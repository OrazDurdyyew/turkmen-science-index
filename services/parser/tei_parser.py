"""Parse GROBID TEI XML output into structured metadata."""

import re
from datetime import date

from lxml import etree

TEI_NS = "http://www.tei-c.org/ns/1.0"
NS = {"tei": TEI_NS}

MIN_YEAR = 1800
YEAR_RE = re.compile(r"\b(1[89]\d\d|20\d\d)\b")

# ". М.: Вильямс", ". СПб.: Питер, 2011" — city and publisher glued to a book title
PUBLISHER_TAIL_RE = re.compile(r"\.\s+[A-ZА-ЯÄŇÖÜÝÇŞŽ][^\s.:]{0,12}\.?\s*:\s.*$")

# Russian-style patronymics: Михайлович, Сергеевна, Ильич, Mikhailovich, Sergeyevna...
PATRONYMIC_RE = re.compile(
    r"(вич|вна|ична|инична|ич|ovich|evich|ovna|evna|ichna)$", re.IGNORECASE
)

TURKMEN_CHARS = set("äňöüýçşžÄŇÖÜÝÇŞŽ")

CYR_TO_LAT = {
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e",
    "ж": "zh", "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m",
    "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
    "ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
    "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
}


def parse_tei_xml(xml_bytes: bytes) -> dict:
    """Extract metadata and references from GROBID TEI XML."""
    root = etree.fromstring(xml_bytes)

    title = _extract_title(root)
    abstract = _extract_abstract(root)

    return {
        "title": title,
        "abstract": abstract,
        "authors": _extract_authors(root),
        "references": _extract_references(root),
        "doi": _extract_doi(root),
        "date": _extract_date(root),
        "language": detect_language(f"{title} {abstract}"),
    }


def detect_language(text: str) -> str:
    """Rough language guess: 'tk' (Turkmen Latin), 'ru' (Cyrillic) or 'en'."""
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return "tk"
    cyrillic = sum(1 for c in letters if "Ѐ" <= c <= "ӿ")
    if cyrillic / len(letters) > 0.3:
        return "ru"
    if any(c in TURKMEN_CHARS for c in letters):
        return "tk"
    return "en"


def _extract_title(root: etree._Element) -> str:
    el = root.find(".//tei:titleStmt/tei:title[@type='main']", NS)
    if el is None:
        el = root.find(".//tei:titleStmt/tei:title", NS)
    return _text(el)


def _extract_abstract(root: etree._Element) -> str:
    el = root.find(".//tei:profileDesc/tei:abstract", NS)
    if el is None:
        return ""
    paragraphs = el.findall(".//tei:p", NS)
    if paragraphs:
        return "\n".join(_text(p) for p in paragraphs if _text(p))
    return _text(el)


def _person_name(persname: etree._Element) -> dict | None:
    """Turn <persName> into {last, first, middle}, fixing GROBID's shift on Russian FIO.

    For "Антонов Игорь Михайлович" GROBID returns first=Антонов, middle=Игорь,
    surname=Михайлович — the patronymic ends up as the surname.
    """
    first = _text(persname.find("tei:forename[@type='first']", NS)) or _text(
        persname.find("tei:forename", NS)
    )
    middle = _text(persname.find("tei:forename[@type='middle']", NS))
    last = _text(persname.find("tei:surname", NS))

    if not last:
        return None

    if first and middle and PATRONYMIC_RE.search(last) and not PATRONYMIC_RE.search(first):
        first, middle, last = middle, last, first

    return {"last": last, "first": first, "middle": middle}


def _format_name(name: dict) -> str:
    return " ".join(p for p in (name["last"], name["first"], name["middle"]) if p)


def _is_cyrillic(s: str) -> bool:
    return any("Ѐ" <= c <= "ӿ" for c in s)


def _translit(s: str) -> str:
    return "".join(CYR_TO_LAT.get(c, c) for c in s.lower())


def _same_person(cyr: dict, lat: dict) -> bool:
    """Cyrillic and Latin spellings of one author (GROBID often emits both)."""
    if _translit(cyr["last"]) != lat["last"].lower():
        return False
    if cyr["first"] and lat["first"]:
        return _translit(cyr["first"])[:1] == lat["first"].lower()[:1]
    return True


def _extract_authors(root: etree._Element) -> list[dict]:
    names = []
    for author_el in root.findall(
        ".//tei:fileDesc/tei:sourceDesc/tei:biblStruct/tei:analytic/tei:author", NS
    ):
        persname = author_el.find("tei:persName", NS)
        if persname is None:
            continue
        name = _person_name(persname)
        if name is None:
            continue
        # A lone patronymic ("Mikhailovich") is a fragment of the previous author's name
        if not name["first"] and PATRONYMIC_RE.search(name["last"]):
            continue

        affiliation = ""
        aff_el = author_el.find(".//tei:affiliation/tei:orgName[@type='institution']", NS)
        if aff_el is None:
            aff_el = author_el.find(".//tei:affiliation/tei:orgName", NS)
        if aff_el is not None:
            affiliation = _text(aff_el)

        names.append((name, affiliation))

    # Merge Latin duplicates of Cyrillic authors into full_name_en
    authors: list[dict] = []
    for name, affiliation in names:
        full = _format_name(name)
        if not _is_cyrillic(full):
            twin = next(
                (a for a in authors
                 if a["_cyr"] and not a["full_name_en"] and _same_person(a["_name"], name)),
                None,
            )
            if twin:
                twin["full_name_en"] = full
                twin["affiliation"] = twin["affiliation"] or affiliation
                continue

        authors.append({
            "full_name": full,
            "full_name_en": "",
            "first_name": name["first"],
            "last_name": name["last"],
            "affiliation": affiliation,
            "_name": name,
            "_cyr": _is_cyrillic(full),
        })

    for a in authors:
        del a["_name"], a["_cyr"]
    return authors


def _extract_references(root: etree._Element) -> list[dict]:
    refs = []
    for bib in root.findall(".//tei:listBibl/tei:biblStruct", NS):
        ref = _parse_bib_entry(bib)
        if ref.get("raw_text") or ref.get("title"):
            refs.append(ref)
    return refs


def _parse_bib_entry(bib: etree._Element) -> dict:
    """Parse a single <biblStruct> into reference metadata."""
    # Title from analytic (article), falling back to monogr (book/journal);
    # GROBID emits an empty <title/> in analytic for books
    title = _text(bib.find(".//tei:analytic/tei:title", NS)) or _text(
        bib.find(".//tei:monogr/tei:title", NS)
    )
    title = PUBLISHER_TAIL_RE.sub("", title)

    author_names = []
    for path in (".//tei:analytic/tei:author/tei:persName", ".//tei:monogr/tei:author/tei:persName"):
        for a in bib.findall(path, NS):
            name = _person_name(a)
            if name:
                author_names.append(_format_name(name))
        if author_names:
            break

    raw_note = _text(bib.find("tei:note[@type='raw_reference']", NS))

    year = None
    date_el = bib.find(".//tei:monogr/tei:imprint/tei:date[@type='published']", NS)
    if date_el is not None:
        year = _valid_year(date_el.get("when", "")[:4])
    # GROBID sometimes puts the page count ("1136 с.") into the date
    if year is None and raw_note:
        m = YEAR_RE.search(raw_note)
        if m:
            year = _valid_year(m.group(1))

    doi = _text(bib.find(".//tei:idno[@type='DOI']", NS))

    raw_text = raw_note
    if not raw_text:
        parts = [p for p in (", ".join(author_names), title, str(year) if year else "") if p]
        raw_text = ". ".join(parts)

    return {
        "title": title,
        "authors": ", ".join(author_names),
        "year": year,
        "doi": doi,
        "raw_text": raw_text,
    }


def _valid_year(s: str) -> int | None:
    try:
        year = int(s)
    except (TypeError, ValueError):
        return None
    return year if MIN_YEAR <= year <= date.today().year + 1 else None


def _extract_doi(root: etree._Element) -> str:
    el = root.find(".//tei:sourceDesc//tei:idno[@type='DOI']", NS)
    return _text(el)


def _extract_date(root: etree._Element) -> str:
    el = root.find(
        ".//tei:fileDesc/tei:sourceDesc/tei:biblStruct/tei:monogr/tei:imprint/tei:date[@type='published']",
        NS,
    )
    if el is None:
        return ""
    when = el.get("when", "")
    # publications.published_date is DATE; GROBID may give "2015" or "2015-03"
    if re.fullmatch(r"\d{4}", when):
        return f"{when}-01-01" if _valid_year(when) else ""
    if re.fullmatch(r"\d{4}-\d{2}", when):
        return f"{when}-01" if _valid_year(when[:4]) else ""
    return when if re.fullmatch(r"\d{4}-\d{2}-\d{2}", when) and _valid_year(when[:4]) else ""


def _text(el: etree._Element | None) -> str:
    if el is None:
        return ""
    return " ".join("".join(el.itertext()).split())
