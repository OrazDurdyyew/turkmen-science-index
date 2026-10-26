# Схема базы данных TSI

## Расширения PostgreSQL

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
```

## ER-диаграмма (связи)

```
profiles ──M2M── publications ──1:N── raw_references
    │              │                       │
    │              │                       │ (matched?)
    │              │                       ▼
    │              └──────── citations ◄────┘
    │                    (source → target)
    │
    └── h_index, i10_index (pre-computed)

journals ──1:N── publications
```

---

## Таблицы

### 1. `profiles` (авторы / учёные)

```sql
CREATE TABLE profiles (
    id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name   TEXT NOT NULL,
    full_name_en TEXT,
    institution TEXT,
    orcid       VARCHAR(19) UNIQUE,  -- формат: 0000-0000-0000-0000
    h_index     INT NOT NULL DEFAULT 0,
    i10_index   INT NOT NULL DEFAULT 0,
    h_index_updated_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Индексы
CREATE INDEX idx_profiles_full_name_trgm ON profiles USING GIN (full_name gin_trgm_ops);
CREATE INDEX idx_profiles_institution ON profiles (institution);
```

**Поля:**
| Поле | Тип | Описание |
|------|-----|----------|
| `id` | UUID | = auth.users.id (автоматическая привязка к авторизации) |
| `full_name` | TEXT | ФИО на основном языке |
| `full_name_en` | TEXT | ФИО латиницей (для международного поиска) |
| `institution` | TEXT | ВУЗ / научная организация |
| `orcid` | VARCHAR(19) | Уникальный идентификатор исследователя |
| `h_index` | INT | Пре-вычисленный индекс Хирша |
| `i10_index` | INT | Кол-во статей с >= 10 цитированиями |
| `h_index_updated_at` | TIMESTAMPTZ | Время последнего пересчёта |

---

### 2. `journals` (научные журналы)

```sql
CREATE TABLE journals (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title       TEXT NOT NULL,
    title_en    TEXT,
    issn        VARCHAR(9) UNIQUE,   -- формат: 1234-5678
    publisher   TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_journals_title_trgm ON journals USING GIN (title gin_trgm_ops);
```

**Поля:**
| Поле | Тип | Описание |
|------|-----|----------|
| `title` | TEXT | Название журнала |
| `issn` | VARCHAR(9) | Международный стандартный серийный номер |
| `publisher` | TEXT | Издатель |

---

### 3. `publications` (статьи)

```sql
CREATE TABLE publications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title           TEXT NOT NULL,
    title_en        TEXT,
    abstract        TEXT,
    journal_id      UUID REFERENCES journals(id) ON DELETE SET NULL,
    published_date  DATE,
    pdf_path        TEXT,           -- путь в Supabase Storage
    doi             VARCHAR(255) UNIQUE,
    language        VARCHAR(2) DEFAULT 'tk',  -- tk, ru, en
    citation_count  INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Полнотекстовый поиск (русский + английский)
CREATE INDEX idx_publications_fts ON publications
    USING GIN (to_tsvector('russian', coalesce(title, '') || ' ' || coalesce(abstract, '')));

-- Fuzzy search по заголовку
CREATE INDEX idx_publications_title_trgm ON publications USING GIN (title gin_trgm_ops);

-- Фильтрация
CREATE INDEX idx_publications_journal ON publications (journal_id);
CREATE INDEX idx_publications_date ON publications (published_date DESC);
```

**Поля:**
| Поле | Тип | Описание |
|------|-----|----------|
| `title` | TEXT | Заголовок статьи |
| `abstract` | TEXT | Аннотация |
| `journal_id` | UUID FK | Ссылка на журнал |
| `pdf_path` | TEXT | Путь к файлу в Storage |
| `doi` | VARCHAR | Digital Object Identifier |
| `citation_count` | INT | Денормализованный счётчик цитирований |

---

### 4. `publication_authors` (M2M: статьи ↔ авторы)

```sql
CREATE TABLE publication_authors (
    publication_id  UUID NOT NULL REFERENCES publications(id) ON DELETE CASCADE,
    profile_id      UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    position        INT NOT NULL DEFAULT 1,        -- порядок авторства
    is_corresponding BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (publication_id, profile_id)
);

CREATE INDEX idx_pub_authors_profile ON publication_authors (profile_id);
```

**Поля:**
| Поле | Тип | Описание |
|------|-----|----------|
| `position` | INT | Порядковый номер автора (1 = первый) |
| `is_corresponding` | BOOLEAN | Автор для корреспонденции |

---

### 5. `citations` (подтверждённые связи цитирования)

```sql
CREATE TABLE citations (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_publication_id   UUID NOT NULL REFERENCES publications(id) ON DELETE CASCADE,
    target_publication_id   UUID NOT NULL REFERENCES publications(id) ON DELETE CASCADE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source_publication_id, target_publication_id),
    CHECK (source_publication_id != target_publication_id)
);

CREATE INDEX idx_citations_target ON citations (target_publication_id);
CREATE INDEX idx_citations_source ON citations (source_publication_id);
```

**Семантика:** `source` цитирует `target`. Статья A ссылается на статью B → source=A, target=B.

---

### 6. `raw_references` (сырые ссылки из PDF)

```sql
CREATE TABLE raw_references (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_publication_id   UUID NOT NULL REFERENCES publications(id) ON DELETE CASCADE,
    raw_text                TEXT NOT NULL,
    parsed_title            TEXT,          -- извлечённый заголовок (для matching)
    parsed_authors          TEXT,          -- извлечённые авторы
    parsed_year             INT,           -- извлечённый год
    matched_publication_id  UUID REFERENCES publications(id) ON DELETE SET NULL,
    match_score             REAL,          -- similarity() score (0.0 - 1.0)
    status                  VARCHAR(10) NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending', 'matched', 'unmatched')),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    matched_at              TIMESTAMPTZ
);

-- Для фоновой обработки
CREATE INDEX idx_raw_refs_status ON raw_references (status) WHERE status = 'pending';
CREATE INDEX idx_raw_refs_source ON raw_references (source_publication_id);
CREATE INDEX idx_raw_refs_matched ON raw_references (matched_publication_id) WHERE matched_publication_id IS NOT NULL;
```

**Жизненный цикл записи:**
```
1. PDF загружен → GROBID парсит список литературы
2. Каждая ссылка → INSERT raw_references (status = 'pending')
3. Cron: fuzzy match parsed_title против publications.title
4. Если match_score > 0.6 → status = 'matched', создаётся citation
5. Если нет совпадений → status = 'unmatched'
6. При загрузке новой статьи → повторная проверка 'unmatched'
```

---

## Триггеры и функции

### Автообновление citation_count

```sql
CREATE OR REPLACE FUNCTION update_citation_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE publications
        SET citation_count = citation_count + 1
        WHERE id = NEW.target_publication_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE publications
        SET citation_count = citation_count - 1
        WHERE id = OLD.target_publication_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_citation_count
AFTER INSERT OR DELETE ON citations
FOR EACH ROW EXECUTE FUNCTION update_citation_count();
```

### Автообновление updated_at

```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_publications_updated_at BEFORE UPDATE ON publications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

### Расчёт индекса Хирша

```sql
CREATE OR REPLACE FUNCTION recalculate_h_index(p_profile_id UUID)
RETURNS void AS $$
DECLARE
    v_h_index INT := 0;
    v_i10_index INT := 0;
BEGIN
    -- h-index: максимальное h, при котором h статей имеют >= h цитирований
    SELECT coalesce(max(rank), 0) INTO v_h_index
    FROM (
        SELECT citation_count,
               ROW_NUMBER() OVER (ORDER BY citation_count DESC) as rank
        FROM publications p
        JOIN publication_authors pa ON pa.publication_id = p.id
        WHERE pa.profile_id = p_profile_id
          AND p.citation_count > 0
    ) ranked
    WHERE citation_count >= rank;

    -- i10-index: кол-во статей с >= 10 цитированиями
    SELECT count(*) INTO v_i10_index
    FROM publications p
    JOIN publication_authors pa ON pa.publication_id = p.id
    WHERE pa.profile_id = p_profile_id
      AND p.citation_count >= 10;

    UPDATE profiles
    SET h_index = v_h_index,
        i10_index = v_i10_index,
        h_index_updated_at = now()
    WHERE id = p_profile_id;
END;
$$ LANGUAGE plpgsql;
```

---

## RLS-политики (Row Level Security)

```sql
-- Включение RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE publications ENABLE ROW LEVEL SECURITY;
ALTER TABLE journals ENABLE ROW LEVEL SECURITY;
ALTER TABLE publication_authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE citations ENABLE ROW LEVEL SECURITY;
ALTER TABLE raw_references ENABLE ROW LEVEL SECURITY;

-- profiles: чтение — все, запись — владелец
CREATE POLICY "profiles_select" ON profiles FOR SELECT USING (true);
CREATE POLICY "profiles_update" ON profiles FOR UPDATE USING (auth.uid() = id);

-- publications: чтение — все, вставка/обновление — авторы
CREATE POLICY "publications_select" ON publications FOR SELECT USING (true);
CREATE POLICY "publications_insert" ON publications FOR INSERT
    WITH CHECK (auth.uid() IN (
        SELECT profile_id FROM publication_authors WHERE publication_id = id
    ));

-- journals: чтение — все (запись — через service_role)
CREATE POLICY "journals_select" ON journals FOR SELECT USING (true);

-- publication_authors: чтение — все
CREATE POLICY "pub_authors_select" ON publication_authors FOR SELECT USING (true);

-- citations: чтение — все (запись — через service_role)
CREATE POLICY "citations_select" ON citations FOR SELECT USING (true);

-- raw_references: чтение — все (запись — через service_role)
CREATE POLICY "raw_refs_select" ON raw_references FOR SELECT USING (true);
```

---

## Полезные запросы

### Поиск статей (полнотекстовый)
```sql
SELECT id, title, ts_rank(to_tsvector('russian', title || ' ' || coalesce(abstract, '')),
    plainto_tsquery('russian', 'квантовая физика')) AS rank
FROM publications
WHERE to_tsvector('russian', title || ' ' || coalesce(abstract, ''))
    @@ plainto_tsquery('russian', 'квантовая физика')
ORDER BY rank DESC
LIMIT 20;
```

### Топ авторов по h-index
```sql
SELECT full_name, institution, h_index, i10_index
FROM profiles
ORDER BY h_index DESC
LIMIT 50;
```

### Статьи автора с цитированиями
```sql
SELECT p.title, p.citation_count, p.published_date
FROM publications p
JOIN publication_authors pa ON pa.publication_id = p.id
WHERE pa.profile_id = :author_id
ORDER BY p.citation_count DESC;
```
