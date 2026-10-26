from pathlib import Path

import pytest

from tei_parser import (
    PUBLISHER_TAIL_RE,
    _person_name,
    _valid_year,
    detect_language,
    parse_tei_xml,
)
from lxml import etree

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture(scope="module")
def ru():
    return parse_tei_xml((FIXTURES / "ru_article.tei.xml").read_bytes())


@pytest.fixture(scope="module")
def en():
    return parse_tei_xml((FIXTURES / "en_article.tei.xml").read_bytes())


def test_russian_fio_order_is_fixed(ru):
    assert ru["authors"][0]["full_name"] == "Антонов Игорь Михайлович"
    assert ru["authors"][0]["last_name"] == "Антонов"


def test_latin_duplicate_merged_into_full_name_en(ru):
    names = [a["full_name"] for a in ru["authors"]]
    assert "Antonov Igor" not in names
    assert ru["authors"][0]["full_name_en"] == "Antonov Igor"


def test_lone_patronymic_fragments_dropped(ru):
    names = [a["full_name"] for a in ru["authors"]]
    assert "Mikhailovich" not in names
    assert "Sergeyevich" not in names


def test_page_count_is_not_a_year(ru):
    years = [r["year"] for r in ru["references"]]
    assert 1136 not in years
    assert 1120 not in years
    assert all(y is None or 1800 <= y <= 2100 for y in years)
    stroustrup = next(r for r in ru["references"] if r["raw_text"].startswith("Страуструп"))
    assert stroustrup["year"] == 2011


def test_raw_text_is_original_citation(ru):
    assert ru["references"][0]["raw_text"] == (
        "Керниган Б.В., Ритчи Д.М. Язык программирования Си. М.: Вильямс, 2015. 304 с."
    )


def test_empty_analytic_title_falls_back_to_monogr(ru):
    assert ru["references"][0]["title"] == "Язык программирования Си"


def test_language_detection(ru, en):
    assert ru["language"] == "ru"
    assert en["language"] == "en"
    assert detect_language("Türkmenistanyň ylymlar akademiýasy") == "tk"
    assert detect_language("") == "tk"


def test_english_article(en):
    assert en["authors"][0]["last_name"] == "Winkler"
    assert len(en["references"]) == 44
    assert en["references"][0]["year"] == 1992


def test_date_is_iso_or_empty(ru, en):
    import re
    for d in (ru["date"], en["date"]):
        assert d == "" or re.fullmatch(r"\d{4}-\d{2}-\d{2}", d)


@pytest.mark.parametrize("title, expected", [
    ("Язык программирования Си. М.: Вильямс", "Язык программирования Си"),
    ("Современные операционные системы. СПб.: Питер", "Современные операционные системы"),
    ("Error Rate Estimation for Record Linkage: Some Recent Developments",
     "Error Rate Estimation for Record Linkage: Some Recent Developments"),
])
def test_publisher_tail_stripped(title, expected):
    assert PUBLISHER_TAIL_RE.sub("", title) == expected


def test_valid_year():
    assert _valid_year("2011") == 2011
    assert _valid_year("1136") is None
    assert _valid_year("abcd") is None
    assert _valid_year("") is None


def test_person_name_without_patronymic_untouched():
    xml = (
        '<persName xmlns="http://www.tei-c.org/ns/1.0">'
        '<forename type="first">Igor</forename><surname>Antonov</surname></persName>'
    )
    assert _person_name(etree.fromstring(xml)) == {"last": "Antonov", "first": "Igor", "middle": ""}
