"""Header heuristics for post-Soviet journal layouts, applied on top of GROBID.

Typical first page:

    УДК 514.74
    МАТЕМАТИЧЕСКИЕ МОДЕЛИ МНОГОМЕРНЫХ ПРОСТРАНСТВ      ← title, upper case, may wrap
    Овчинников Станислав Дмитриевич                     ← author: Фамилия Имя Отчество
    Старший преподаватель кафедры …, МГТУ им. Баумана   ← affiliation lines
    г. Москва, Россия
    Аннотация

GROBID tends to pick the English duplicate of the header (printed later in the article)
and splits Russian ФИО oddly, so for such layouts this module is the primary source and
GROBID's English values become title_en / full_name_en.
"""

import io
import re

from pypdf import PdfReader

ABSTRACT_MARKERS = re.compile(r"^\s*(аннотация|annotation|abstract|резюме|annotasiýa|gysgaça\s+mazmuny)\b", re.IGNORECASE)
SKIP_LINE = re.compile(r"^\s*(-\s*\d+\s*-|\d+|удк|udc|ббк|doi|issn|https?://)", re.IGNORECASE)
CITY_LINE = re.compile(r"^\s*(г\.|город|ş\.|şäheri|city)\s", re.IGNORECASE)
NAME_WORD = r"[A-ZА-ЯЁÄŇÖÜÝÇŞŽ][a-zа-яёäňöüýçşž]+(?:-[A-ZА-ЯЁÄŇÖÜÝÇŞŽ][a-zа-яёäňöüýçşž]+)?"
# 2–3 capitalised words, optionally initials: "Овчинников Станислав Дмитриевич", "Durdyýew Oraz", "Иванов И.И."
AUTHOR_LINE = re.compile(rf"^\s*{NAME_WORD}(?:\s+{NAME_WORD}){{1,2}}\s*$|^\s*{NAME_WORD}\s+[A-ZА-ЯЁ]\.\s?[A-ZА-ЯЁ]\.\s*$")
INSTITUTION_HINT = re.compile(
    r"университет|институт|академи|колледж|школ|центр|лаборатори|министерств|"
    r"university|institute|academy|college|uniwersitet|institut|akademiýa|mekdep",
    re.IGNORECASE,
)


def first_page_text(pdf_bytes: bytes) -> str:
    try:
        reader = PdfReader(io.BytesIO(pdf_bytes))
        if not reader.pages:
            return ""
        return reader.pages[0].extract_text() or ""
    except Exception:
        return ""


# Where the leading abstract ends: keywords, or the start of the English duplicate block
ABSTRACT_END = re.compile(
    r"(ключевые\s+слова|key\s*words|açar\s+sözler)\s*[:.—-]?|^\s*(abstract|annotation)\b",
    re.IGNORECASE | re.MULTILINE,
)
ENGLISH_TITLE_LINE = re.compile(r"^\s*[A-Z][A-Z ,:;\-]{25,}$", re.MULTILINE)
PAGE_NUMBER = re.compile(r"^\s*-\s*\d+\s*-\s*$", re.MULTILINE)


def leading_abstract(pdf_bytes: bytes) -> str:
    """Abstract printed right after the header ("Аннотация … Ключевые слова:"), first two pages.

    Layout mode keeps words intact better than the default extraction.
    """
    try:
        reader = PdfReader(io.BytesIO(pdf_bytes))
        text = "\n".join(p.extract_text(extraction_mode="layout") or "" for p in reader.pages[:2])
    except Exception:
        return ""
    text = PAGE_NUMBER.sub("", text)
    start = re.search(r"^\s*(аннотация|annotation|abstract|annotasiýa)\b[\s.:—-]*", text, re.IGNORECASE | re.MULTILINE)
    if not start:
        return ""
    rest = text[start.end():]
    stops = [m.start() for m in (ABSTRACT_END.search(rest), ENGLISH_TITLE_LINE.search(rest)) if m]
    body = rest[: min(stops)] if stops else rest[:5000]
    return re.sub(r"\s+", " ", body).strip()[:5000]


def _is_upper(line: str) -> bool:
    letters = [c for c in line if c.isalpha()]
    return len(letters) >= 3 and sum(c.isupper() for c in letters) / len(letters) > 0.8


def _is_cyrillic(s: str) -> bool:
    return any("Ѐ" <= c <= "ӿ" for c in s)


def sentence_case(title: str) -> str:
    """ВОСПРИЯТИЕ ГЛУБИНЫ В VR-СРЕДЕ → Восприятие глубины в VR-среде.

    Only for all-caps titles. In Cyrillic titles Latin words (GPU, N-BODY, DAG) keep their case.
    """
    if not _is_upper(title):
        return title
    cyr = _is_cyrillic(title)
    words = []
    for w in title.split():
        latin_only = not _is_cyrillic(w) and any(c.isalpha() for c in w)
        words.append(w if cyr and latin_only else w.lower())
    out = " ".join(words)
    return out[:1].upper() + out[1:]


def parse_header(text: str) -> dict:
    """Extract title / authors / affiliations from first-page text. Empty dict if the layout doesn't fit."""
    lines = [re.sub(r"\s+", " ", l).strip() for l in text.splitlines()]
    lines = [l for l in lines if l]

    end = next((i for i, l in enumerate(lines) if ABSTRACT_MARKERS.match(l)), None)
    if end is None or end < 2:
        return {}
    head = [l for l in lines[:end] if not SKIP_LINE.match(l)]

    # Title: the first run of upper-case lines
    i = 0
    while i < len(head) and not _is_upper(head[i]):
        i += 1
    title_lines = []
    while i < len(head) and _is_upper(head[i]) and not AUTHOR_LINE.match(head[i]):
        title_lines.append(head[i])
        i += 1
    if not title_lines:
        return {}
    title = " ".join(title_lines)

    authors: list[dict] = []
    for line in head[i:]:
        if AUTHOR_LINE.match(line):
            authors.append({"full_name": line, "affiliation_lines": []})
        elif authors and not CITY_LINE.match(line):
            authors[-1]["affiliation_lines"].append(line)

    for a in authors:
        aff = " ".join(a.pop("affiliation_lines"))
        a["affiliation"] = _institution(aff)

    return {"title": title, "authors": authors}


def _institution(aff: str) -> str:
    """"Старший преподаватель кафедры X, Московский ... университет" → the university part."""
    parts = [p.strip() for p in aff.split(",") if p.strip()]
    for k, p in enumerate(parts):
        if INSTITUTION_HINT.search(p):
            return ", ".join(parts[k:])
    return aff


MAX_TITLE = 600
UDC_PREFIX = re.compile(r"^\s*(удк|udc)[\s:-]*[\d.:()/+-]+\s*", re.IGNORECASE)
KEYWORDS_PREFIX = re.compile(r"^\s*(ключевые слова|keywords|key words|açar sözler)\s*:", re.IGNORECASE)
ABSTRACT_PREFIX = re.compile(r"^.*?\b(аннотация|abstract|annotation)\b[\s.:—-]*", re.IGNORECASE | re.DOTALL)


def _latin_key(name: str) -> tuple[str, str]:
    from tei_parser import _translit

    parts = _translit(name).replace("'", "").split()
    return (parts[0], parts[1][:1]) if len(parts) > 1 else (parts[0] if parts else "", "")


def _similar_names(cyr: str, lat: str) -> bool:
    from difflib import SequenceMatcher

    (c_last, c_init), (l_last, l_init) = _latin_key(cyr), _latin_key(lat)
    if c_init and l_init and c_init != l_init:
        return False
    return SequenceMatcher(None, c_last, l_last).ratio() >= 0.75


def merge_header(meta: dict, header: dict, leading: str = "") -> dict:
    """Combine GROBID metadata with first-page heuristics (see module docstring)."""
    out = dict(meta)
    grobid_title = (meta.get("title") or "").strip()
    if KEYWORDS_PREFIX.match(grobid_title):
        grobid_title = ""

    header_title = (header.get("title") or "").strip()[:MAX_TITLE]
    grobid_title = grobid_title[:MAX_TITLE]
    if header_title:
        # The header layout matched: its title is the article's own. GROBID's is either the same
        # (possibly with "УДК …" glued on) or the English duplicate.
        out["title"] = sentence_case(header_title)
        out["title_en"] = sentence_case(grobid_title) if grobid_title and not _is_cyrillic(grobid_title) else ""
    else:
        out["title"] = sentence_case(UDC_PREFIX.sub("", grobid_title))
        out["title_en"] = ""

    header_authors = header.get("authors") or []
    if header_authors:
        grobid_authors = list(meta.get("authors") or [])
        authors = []
        for h in header_authors:
            twin = next((g for g in grobid_authors if _similar_names(h["full_name"], g["full_name"])), None)
            if twin:
                grobid_authors.remove(twin)
            en = ""
            if twin and not _is_cyrillic(twin["full_name"]):
                en = twin["full_name"]
            elif twin:
                en = twin.get("full_name_en") or ""
            authors.append({
                "full_name": h["full_name"],
                "full_name_en": en,
                "affiliation": h.get("affiliation") or (twin or {}).get("affiliation", ""),
            })
        out["authors"] = authors

    abstract = (meta.get("abstract") or "").strip()
    if re.search(r"\b(аннотация|abstract|annotation)\b", abstract[:2000], re.IGNORECASE):
        abstract = ABSTRACT_PREFIX.sub("", abstract, count=1).strip()
    # Cyrillic article but GROBID took the English abstract: use the one printed under the header
    if leading and _is_cyrillic(out["title"]) and _cyrillic_share(leading) > 0.5 and _cyrillic_share(abstract) < 0.3:
        abstract = leading
    elif not abstract and leading:
        abstract = leading
    out["abstract"] = abstract
    return out


def _cyrillic_share(text: str) -> float:
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return 0.0
    return sum(1 for c in letters if "\u0400" <= c <= "\u04ff") / len(letters)
