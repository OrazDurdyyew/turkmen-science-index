import json

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

import main


def test_safe_filename():
    assert main._safe_filename("Статья 1.pdf") == "1.pdf"
    assert main._safe_filename("Статья.pdf") == "paper.pdf"
    assert main._safe_filename("my paper (v2).PDF") == "my_paper_v2.pdf"


def test_same_author_by_last_name_and_initial():
    profile = {"full_name": "Антонов Игорь Михайлович", "full_name_en": None}
    assert main._same_author(profile, {"full_name": "Антонов Игорь", "full_name_en": ""})
    assert main._same_author(profile, {"full_name": "Antonov I", "full_name_en": "Антонов И."})
    assert not main._same_author(profile, {"full_name": "Антонов Пётр", "full_name_en": ""})
    # same initial, different first name
    assert not main._same_author(profile, {"full_name": "Антонов Иван", "full_name_en": ""})
    assert not main._same_author({"full_name": "", "full_name_en": None},
                                 {"full_name": "Антонов Игорь", "full_name_en": ""})


def test_same_author_first_last_order_and_affiliation():
    profile = {"full_name": "Annanazar Mamiyev, Turkmen State Institute", "full_name_en": None}
    assert main._same_author(profile, {"full_name": "Mamiyev Annanazar", "full_name_en": ""})
    assert main._same_author(profile, {"full_name": "Mamiyev A.", "full_name_en": ""})
    assert not main._same_author(profile, {"full_name": "Mamiyev Batyr", "full_name_en": ""})


def test_metadata_from_form_sanitizes():
    meta = main._metadata_from_form(json.dumps({
        "title": "  Заголовок  ",
        "authors": [{"full_name": "Иванов Иван"}, {"full_name": "   "}],
        "references": [{"raw_text": "Ref 1", "year": "2011"}, {"raw_text": ""}],
        "date": "2015",
        "language": "xx",
    }))
    assert meta["title"] == "Заголовок"
    assert [a["full_name"] for a in meta["authors"]] == ["Иванов Иван"]
    assert len(meta["references"]) == 1
    assert meta["references"][0]["year"] is None  # non-int year rejected
    assert meta["date"] == "2015-01-01"
    assert meta["language"] == "ru"


def test_metadata_from_form_rejects_bad_journal_id():
    with pytest.raises(HTTPException) as e:
        main._metadata_from_form(json.dumps({"title": "T", "journal_id": "'; drop table"}))
    assert e.value.status_code == 400


def test_metadata_from_form_rejects_bad_json():
    with pytest.raises(HTTPException) as e:
        main._metadata_from_form("{not json")
    assert e.value.status_code == 400


def test_parse_requires_auth(monkeypatch):
    monkeypatch.setattr(main, "SUPABASE_SERVICE_KEY", "dummy")
    monkeypatch.setattr(main, "create_client", lambda *a: object())
    client = TestClient(main.app)
    resp = client.post("/parse", files={"file": ("a.pdf", b"%PDF-1.4", "application/pdf")})
    assert resp.status_code == 401


def test_metadata_limits_and_validation():
    with pytest.raises(HTTPException):
        main._metadata_from_form(json.dumps({"title": "T", "authors": [{"full_name": "A B"}] * 101}))
    with pytest.raises(HTTPException):
        main._metadata_from_form(json.dumps({"title": "T", "doi": "x" * 300}))
    meta = main._metadata_from_form(json.dumps({"title": "T", "doi": "https://doi.org/10.1000/xyz", "date": "2020-13-45"}))
    assert meta["doi"] == "10.1000/xyz"
    assert meta["date"] == ""


def test_normalize_date():
    assert main._normalize_date("2015") == "2015-01-01"
    assert main._normalize_date("2015-03") == "2015-03-01"
    assert main._normalize_date("2015-03-07") == "2015-03-07"
    assert main._normalize_date("1136") == ""


def test_oversized_request_rejected_before_parsing():
    client = TestClient(main.app)
    resp = client.post("/parse", content=b"x", headers={"content-length": str(main.MAX_REQUEST_BYTES + 1), "content-type": "multipart/form-data; boundary=x"})
    assert resp.status_code == 413
