"""TSI PDF Parsing Service — FastAPI + GROBID integration."""

import json
import logging
import os
import re
from datetime import date as date_cls

import httpx
from fastapi import FastAPI, Form, Header, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from supabase import Client, create_client

from first_page import first_page_text, leading_abstract, merge_header, parse_header
from tei_parser import detect_language, parse_tei_xml

log = logging.getLogger("tsi.parser")

app = FastAPI(title="TSI Parser", version="0.2.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_methods=["*"],
    allow_headers=["*"],
)



@app.middleware("http")
async def limit_body_size(request: Request, call_next):
    """Reject oversized uploads before multipart parsing spools them to disk."""
    length = request.headers.get("content-length")
    if length and length.isdigit() and int(length) > MAX_REQUEST_BYTES:
        return JSONResponse({"detail": "Файл слишком большой (максимум 50 МБ)"}, status_code=413)
    return await call_next(request)


GROBID_URL = os.getenv("GROBID_URL", "http://localhost:8070")
SUPABASE_URL = os.getenv("SUPABASE_URL", "http://localhost:54321")
SUPABASE_SERVICE_KEY = os.getenv("SUPABASE_SERVICE_KEY", "")
MAX_PDF_BYTES = 50 * 1024 * 1024
# Request body = PDF + metadata JSON + multipart overhead
MAX_REQUEST_BYTES = MAX_PDF_BYTES + 5 * 1024 * 1024
MAX_AUTHORS = 100
MAX_REFERENCES = 1000
DOI_RE = re.compile(r"10\.\d{4,9}/\S{1,200}")
UUID_RE = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")


def _supabase() -> Client:
    if not SUPABASE_SERVICE_KEY:
        raise HTTPException(500, "SUPABASE_SERVICE_KEY not configured")
    return create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)


def _current_user_id(sb: Client, authorization: str | None) -> str:
    """Resolve the caller from their Supabase access token (Authorization: Bearer ...)."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Требуется вход в систему")
    token = authorization.split(" ", 1)[1].strip()
    try:
        resp = sb.auth.get_user(token)
    except Exception:
        raise HTTPException(401, "Сессия недействительна, войдите заново")
    if not resp or not resp.user:
        raise HTTPException(401, "Сессия недействительна, войдите заново")
    return resp.user.id


async def _read_pdf(file: UploadFile) -> bytes:
    if not file.filename or not file.filename.lower().endswith(".pdf"):
        raise HTTPException(400, "Принимаются только PDF-файлы")
    pdf_bytes = await file.read()
    if len(pdf_bytes) > MAX_PDF_BYTES:
        raise HTTPException(413, "Файл слишком большой (максимум 50 МБ)")
    if not pdf_bytes.startswith(b"%PDF"):
        raise HTTPException(400, "Файл не похож на PDF")
    return pdf_bytes


async def _grobid_parse(filename: str, pdf_bytes: bytes) -> dict:
    async with httpx.AsyncClient(timeout=180) as client:
        try:
            resp = await client.post(
                f"{GROBID_URL}/api/processFulltextDocument",
                files={"input": (filename, pdf_bytes, "application/pdf")},
                data={
                    "consolidateHeader": "1",
                    "consolidateCitations": "0",
                    "includeRawCitations": "1",
                },
            )
        except httpx.RequestError as e:
            raise HTTPException(502, f"GROBID недоступен: {e}")

    if resp.status_code != 200:
        raise HTTPException(502, f"GROBID вернул ошибку {resp.status_code}")

    try:
        meta = parse_tei_xml(resp.content)
    except Exception as e:
        raise HTTPException(500, f"Ошибка разбора TEI: {e}")

    # GROBID often takes the English duplicate of a Russian/Turkmen header — prefer the first page
    meta = merge_header(meta, parse_header(first_page_text(pdf_bytes)), leading_abstract(pdf_bytes))
    # The title is the most reliable signal: the abstract may be the English duplicate
    meta["language"] = detect_language(meta["title"] or meta["abstract"])
    return meta


def _metadata_from_form(raw: str) -> dict:
    """Metadata reviewed (and possibly edited) by the user on the preview step."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise HTTPException(400, "metadata: некорректный JSON")

    title = str(data.get("title") or "").strip()[:1000]
    title_en = str(data.get("title_en") or "").strip()[:1000]
    abstract = str(data.get("abstract") or "").strip()[:20000]
    raw_authors = data.get("authors") or []
    raw_refs = data.get("references") or []
    if not isinstance(raw_authors, list) or not isinstance(raw_refs, list):
        raise HTTPException(400, "metadata: authors и references должны быть списками")
    if len(raw_authors) > MAX_AUTHORS or len(raw_refs) > MAX_REFERENCES:
        raise HTTPException(400, f"metadata: не больше {MAX_AUTHORS} авторов и {MAX_REFERENCES} ссылок")

    authors = []
    for a in raw_authors:
        if not isinstance(a, dict):
            continue
        full_name = " ".join(str(a.get("full_name") or "").split())[:200]
        if full_name:
            authors.append({
                "full_name": full_name,
                "full_name_en": " ".join(str(a.get("full_name_en") or "").split())[:200],
                "affiliation": str(a.get("affiliation") or "").strip()[:300],
            })
    references = []
    for r in raw_refs:
        if not isinstance(r, dict):
            continue
        raw_text = str(r.get("raw_text") or "").strip()[:2000]
        if raw_text:
            year = r.get("year")
            references.append({
                "raw_text": raw_text,
                "title": str(r.get("title") or "").strip()[:1000],
                "authors": str(r.get("authors") or "").strip()[:1000],
                "year": year if isinstance(year, int) and 1800 <= year <= 2100 else None,
            })

    language = data.get("language")
    if language not in ("tk", "ru", "en"):
        language = detect_language(f"{title} {abstract}")

    journal_id = str(data.get("journal_id") or "").strip()
    if journal_id and not UUID_RE.fullmatch(journal_id):
        raise HTTPException(400, "metadata: некорректный journal_id")

    date = _normalize_date(str(data.get("date") or "").strip())

    doi = str(data.get("doi") or "").strip()
    if doi.lower().startswith("https://doi.org/"):
        doi = doi[16:]
    if doi and not DOI_RE.fullmatch(doi):
        raise HTTPException(400, "metadata: некорректный DOI (ожидается 10.xxxx/...)")

    return {
        "title": title,
        "title_en": title_en,
        "abstract": abstract,
        "authors": authors,
        "references": references,
        "doi": doi,
        "date": date,
        "language": language,
        "journal_id": journal_id or None,
    }


def _normalize_date(value: str) -> str:
    """'2015' → '2015-01-01'; invalid dates (2020-13-45) → '' instead of a database error."""
    if not value:
        return ""
    if re.fullmatch(r"\d{4}", value):
        value = f"{value}-01-01"
    elif re.fullmatch(r"\d{4}-\d{2}", value):
        value = f"{value}-01"
    try:
        d = date_cls.fromisoformat(value[:10])
    except ValueError:
        return ""
    return d.isoformat() if 1800 <= d.year <= date_cls.today().year + 1 else ""


def _safe_filename(filename: str) -> str:
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", filename.rsplit(".", 1)[0]).strip("._")
    return f"{stem or 'paper'}.pdf"


def _find_duplicate(sb: Client, title: str, doi: str) -> str | None:
    # RPC: titles go in the request body (a long title in the query string hits "URI too long")
    res = sb.rpc("find_duplicate_publication", {"p_title": title, "p_doi": doi or None}).execute()
    return res.data or None


def _same_author(profile: dict, author: dict) -> bool:
    """Uploader profile vs extracted author: same last name and same first name.

    An initial matches a full first name ("Антонов И." ~ "Антонов Игорь"),
    but two different full names do not ("Иванов Иван" ≠ "Иванов Игорь").
    Users often register as "First Last" or append their affiliation after a comma,
    so the profile name is also tried with the first two words swapped.
    """
    def split(name: str) -> tuple[str, str]:
        parts = name.split(",")[0].lower().replace(".", " ").split()
        return (parts[0], parts[1]) if len(parts) > 1 else (parts[0] if parts else "", "")

    def compatible(a: tuple[str, str], b: tuple[str, str]) -> bool:
        if not a[0] or not a[1] or not b[1] or a[0] != b[0]:
            return False
        if len(a[1]) == 1 or len(b[1]) == 1:
            return a[1][0] == b[1][0]
        return a[1] == b[1]

    mine = [split(n) for n in (profile.get("full_name"), profile.get("full_name_en")) if n]
    mine += [(first, last) for last, first in mine]
    theirs = [split(n) for n in (author["full_name"], author.get("full_name_en")) if n]
    return any(compatible(m, t) for m in mine for t in theirs)


@app.get("/health")
async def health():
    """Health check — also pings GROBID."""
    async with httpx.AsyncClient(timeout=5) as client:
        try:
            resp = await client.get(f"{GROBID_URL}/api/isalive")
            grobid_ok = resp.status_code == 200
        except httpx.RequestError:
            grobid_ok = False

    return {"status": "ok", "grobid": grobid_ok}


@app.post("/parse")
async def parse_pdf(file: UploadFile, authorization: str | None = Header(None)):
    """Send PDF to GROBID, parse TEI XML, return structured metadata (nothing is saved)."""
    _current_user_id(_supabase(), authorization)
    pdf_bytes = await _read_pdf(file)
    metadata = await _grobid_parse(file.filename, pdf_bytes)
    return {**metadata, "reference_count": len(metadata["references"])}


@app.post("/parse-and-save")
async def parse_and_save(
    file: UploadFile,
    metadata: str | None = Form(None),
    authorization: str | None = Header(None),
):
    """Save a PDF as a publication.

    `metadata` — JSON from the /parse preview, possibly edited by the user.
    Without it the PDF is parsed by GROBID here.

    1. Creates the publication  2. Uploads the PDF  3. Links authors
    (unclaimed profiles for unregistered ones)  4. Saves raw references for matching
    """
    sb = _supabase()
    user_id = _current_user_id(sb, authorization)
    pdf_bytes = await _read_pdf(file)

    meta = _metadata_from_form(metadata) if metadata else await _grobid_parse(file.filename, pdf_bytes)

    title = meta["title"] or file.filename.rsplit(".", 1)[0]
    duplicate = _find_duplicate(sb, title, meta["doi"])
    if duplicate:
        raise HTTPException(409, {"message": "Эта статья уже есть в базе", "publication_id": duplicate})

    try:
        pub_result = sb.table("publications").insert({
            "title": title,
            "title_en": meta.get("title_en") or None,
            "abstract": meta["abstract"] or None,
            "doi": meta["doi"] or None,
            "published_date": meta["date"] or None,
            "language": meta["language"],
            "journal_id": meta.get("journal_id"),
            "created_by": user_id,
        }).execute()
    except Exception as e:
        log.warning("publication insert rejected: %s", e)
        raise HTTPException(400, "Не удалось создать статью: проверьте журнал, DOI и дату")
    pub_id = pub_result.data[0]["id"]
    storage_path = f"papers/{pub_id}/{_safe_filename(file.filename)}"

    try:
        sb.storage.from_("papers").upload(
            storage_path, pdf_bytes, {"content-type": "application/pdf"}
        )
        sb.table("publications").update({"pdf_path": storage_path}).eq("id", pub_id).execute()

        uploader_linked = _link_authors(sb, pub_id, user_id, meta["authors"])

        refs_to_insert = [
            {
                "source_publication_id": pub_id,
                "raw_text": ref["raw_text"],
                "parsed_title": ref.get("title") or None,
                "parsed_authors": ref.get("authors") or None,
                "parsed_year": ref.get("year"),
                "status": "pending",
            }
            for ref in meta["references"]
            if ref.get("raw_text")
        ]
        if refs_to_insert:
            sb.table("raw_references").insert(refs_to_insert).execute()
    except Exception:
        log.exception("saving publication %s failed, rolling back", pub_id)
        # publication_authors / raw_references cascade
        sb.table("publications").delete().eq("id", pub_id).execute()
        try:
            sb.storage.from_("papers").remove([storage_path])
        except Exception:
            pass
        raise HTTPException(500, "Не удалось сохранить статью")

    return {
        "publication_id": pub_id,
        "title": title,
        "authors": meta["authors"],
        "uploader_is_author": uploader_linked,
        "language": meta["language"],
        "reference_count": len(refs_to_insert),
        "pdf_path": storage_path,
    }


def _link_authors(sb: Client, pub_id: str, user_id: str, authors: list[dict]) -> bool:
    """Each extracted author gets a profile (unclaimed if not registered).

    The uploader takes the place of the extracted author whose name matches theirs.
    Returns whether the uploader ended up among the authors.
    """
    res = sb.table("profiles").select("id, full_name, full_name_en").eq("user_id", user_id).execute()
    uploader = res.data[0] if res.data else None

    rows = []
    linked: set[str] = set()
    uploader_linked = False
    for author in authors:
        if uploader and not uploader_linked and _same_author(uploader, author):
            profile_id = uploader["id"]
            uploader_linked = True
        else:
            profile_id = sb.rpc("resolve_author_profile", {
                "p_full_name": author["full_name"],
                "p_full_name_en": author.get("full_name_en") or None,
                "p_institution": author.get("affiliation") or None,
            }).execute().data
        if profile_id and profile_id not in linked:
            linked.add(profile_id)
            rows.append({"publication_id": pub_id, "profile_id": profile_id, "position": len(rows) + 1})

    # No authors extracted: the uploader is the only author we know of
    if uploader and not rows:
        rows.append({"publication_id": pub_id, "profile_id": uploader["id"], "position": 1})
        uploader_linked = True

    if rows:
        sb.table("publication_authors").insert(rows).execute()
    return uploader_linked
