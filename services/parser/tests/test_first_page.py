from first_page import merge_header, parse_header, sentence_case

PAGE = """- 1 -
                                   УДК- 004.42:519.1
ОПТИМИЗАЦИЯ ПАРАЛЛЕЛЬНЫХ ВЫЧИСЛЕНИЙ В
ГЕТЕРОГЕННЫХ СИСТЕМАХ С ИСПОЛЬЗОВАНИЕМ ГРАФОВЫХ
МОДЕЛЕЙ ЗАВИСИМОСТЕЙ ДАННЫХ
Антонов Игорь Михайлович
Преподаватель кафедры высокопроизводительных вычислений,
Санкт-Петербургский национальный исследовательский университет
информационных технологий, механики и оптики (ИТМО)
г. Санкт-Петербург, Россия
Павлов Артем Сергеевич
Студент факультета информационных технологий и программирования,
Санкт-Петербургский национальный исследовательский университет
информационных технологий, механики и оптики (ИТМО)
г. Санкт-Петербург, Россия
Аннотация
В данной научной статье ...
"""


def test_parse_header_title_and_authors():
    h = parse_header(PAGE)
    assert h["title"] == (
        "ОПТИМИЗАЦИЯ ПАРАЛЛЕЛЬНЫХ ВЫЧИСЛЕНИЙ В ГЕТЕРОГЕННЫХ СИСТЕМАХ "
        "С ИСПОЛЬЗОВАНИЕМ ГРАФОВЫХ МОДЕЛЕЙ ЗАВИСИМОСТЕЙ ДАННЫХ"
    )
    assert [a["full_name"] for a in h["authors"]] == ["Антонов Игорь Михайлович", "Павлов Артем Сергеевич"]
    assert h["authors"][0]["affiliation"].startswith("Санкт-Петербургский национальный исследовательский университет")


def test_parse_header_without_abstract_marker_is_empty():
    assert parse_header("Some random text\nwithout structure") == {}


def test_sentence_case_keeps_latin_acronyms_in_cyrillic_title():
    assert sentence_case("МОДЕЛИРОВАНИЕ СТОЛКНОВЕНИЙ ГАЛАКТИК: N-BODY СИМУЛЯЦИИ") == "Моделирование столкновений галактик: N-BODY симуляции"
    assert sentence_case("Already Normal Title") == "Already Normal Title"


def test_merge_prefers_cyrillic_header_and_keeps_english_as_title_en():
    grobid = {
        "title": "OPTIMIZATION OF PARALLEL COMPUTING IN HETEROGENEOUS SYSTEMS",
        "abstract": "Преподаватель кафедры ... Аннотация В данной научной статье проводится анализ",
        "authors": [
            {"full_name": "Antonov Igor", "full_name_en": "", "affiliation": ""},
            {"full_name": "Pavlov Artem", "full_name_en": "", "affiliation": ""},
        ],
    }
    m = merge_header(grobid, parse_header(PAGE))
    assert m["title"].startswith("Оптимизация параллельных вычислений")
    assert m["title_en"] == "Optimization of parallel computing in heterogeneous systems"
    assert [(a["full_name"], a["full_name_en"]) for a in m["authors"]] == [
        ("Антонов Игорь Михайлович", "Antonov Igor"),
        ("Павлов Артем Сергеевич", "Pavlov Artem"),
    ]
    assert m["abstract"] == "В данной научной статье проводится анализ"


def test_merge_drops_keywords_as_title():
    m = merge_header({"title": "Ключевые слова: виртуальная реальность", "abstract": "", "authors": []}, {})
    assert m["title"] == ""


def test_merge_without_header_keeps_grobid():
    grobid = {"title": "Advanced Methods for Record Linkage", "abstract": "x", "authors": [{"full_name": "Winkler William"}]}
    m = merge_header(grobid, {})
    assert m["title"] == "Advanced Methods for Record Linkage"
    assert m["authors"] == grobid["authors"]


def test_merge_replaces_english_abstract_for_cyrillic_article():
    grobid = {"title": "MODELS", "abstract": "This article studies models of spaces.", "authors": []}
    header = {"title": "МОДЕЛИ ПРОСТРАНСТВ", "authors": []}
    m = merge_header(grobid, header, "В данной статье исследуются модели пространств.")
    assert m["abstract"] == "В данной статье исследуются модели пространств."


def test_merge_keeps_cyrillic_grobid_abstract():
    grobid = {"title": "", "abstract": "Аннотация. Исследуются модели.", "authors": []}
    m = merge_header(grobid, {"title": "МОДЕЛИ", "authors": []}, "Другой текст аннотации")
    assert m["abstract"] == "Исследуются модели."


def test_header_title_wins_over_grobid_cyrillic_title_with_udc():
    grobid = {"title": "УДК-621.833 МАТЕМАТИЧЕСКОЕ МОДЕЛИРОВАНИЕ ПРОЦЕССОВ", "abstract": "", "authors": []}
    m = merge_header(grobid, {"title": "МАТЕМАТИЧЕСКОЕ МОДЕЛИРОВАНИЕ ПРОЦЕССОВ", "authors": []})
    assert m["title"] == "Математическое моделирование процессов"
    assert m["title_en"] == ""


def test_udc_prefix_stripped_without_header():
    m = merge_header({"title": "УДК-621.833 МАТЕМАТИЧЕСКОЕ МОДЕЛИРОВАНИЕ", "abstract": "", "authors": []}, {})
    assert m["title"] == "Математическое моделирование"


def test_title_length_capped():
    m = merge_header({"title": "x" * 5000, "abstract": "", "authors": []}, {})
    assert len(m["title"]) <= 600
