# Движок сопоставления ссылок (Matching Engine)

## Проблема

Когда GROBID извлекает список литературы из PDF, каждая ссылка — это просто текстовая строка:

```
[1] Бердыев А.Г., Мамедов Т.К. Влияние температуры на...
    // Вестник ТГУ. — 2023. — №4. — С. 15-22.
```

Нужно определить, есть ли эта статья уже в нашей базе, и если да — создать связь `citation`.

## Стратегия MVP: pg_trgm + similarity()

### Почему pg_trgm

- Уже встроен в PostgreSQL (расширение)
- Работает с кириллицей
- Не требует внешних сервисов
- Достаточен для тысяч статей (масштаб MVP)

### Алгоритм сопоставления

```
┌─────────────────────────────────┐
│  raw_reference (status=pending) │
│  parsed_title: "Влияние темп..."│
│  parsed_authors: "Бердыев А.Г." │
│  parsed_year: 2023              │
└──────────────┬──────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  Шаг 1: Поиск по заголовку      │
│  SELECT id, title,               │
│    similarity(title, $parsed)    │
│  FROM publications               │
│  WHERE similarity(title, $parsed)│
│    > 0.4                         │
│  ORDER BY similarity DESC        │
│  LIMIT 5;                        │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  Шаг 2: Уточнение по авторам    │
│  Для каждого кандидата:          │
│  - Получить авторов статьи       │
│  - similarity(авторы, parsed)    │
│  - Сравнить год публикации       │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  Шаг 3: Комбинированный скор    │
│  score = 0.6 * title_sim         │
│        + 0.25 * author_sim       │
│        + 0.15 * year_match       │
│                                  │
│  year_match = 1.0 если совпал,   │
│               0.5 если ±1 год,   │
│               0.0 иначе          │
└──────────────┬───────────────────┘
               │
               ▼
┌──────────────────────────────────┐
│  Шаг 4: Решение                  │
│  score >= 0.7 → auto-match       │
│  score 0.5-0.7 → review (manual) │
│  score < 0.5 → unmatched         │
└──────────────────────────────────┘
```

### SQL-функция для matching

```sql
CREATE OR REPLACE FUNCTION match_raw_references(batch_size INT DEFAULT 100)
RETURNS INT AS $$
DECLARE
    ref RECORD;
    best RECORD;
    v_matched INT := 0;
    v_title_sim REAL;
    v_author_sim REAL;
    v_year_score REAL;
    v_combined REAL;
BEGIN
    FOR ref IN
        SELECT id, source_publication_id, parsed_title, parsed_authors, parsed_year
        FROM raw_references
        WHERE status = 'pending' AND parsed_title IS NOT NULL
        LIMIT batch_size
        FOR UPDATE SKIP LOCKED  -- параллельная обработка
    LOOP
        -- Найти лучшего кандидата по заголовку
        SELECT p.id, p.title, p.published_date,
               similarity(p.title, ref.parsed_title) AS title_sim
        INTO best
        FROM publications p
        WHERE p.id != ref.source_publication_id
          AND similarity(p.title, ref.parsed_title) > 0.4
        ORDER BY similarity(p.title, ref.parsed_title) DESC
        LIMIT 1;

        IF best IS NULL THEN
            UPDATE raw_references SET status = 'unmatched' WHERE id = ref.id;
            CONTINUE;
        END IF;

        -- Рассчитать комбинированный скор
        v_title_sim := best.title_sim;

        -- Скор по авторам
        v_author_sim := 0;
        IF ref.parsed_authors IS NOT NULL THEN
            SELECT coalesce(max(similarity(pr.full_name, ref.parsed_authors)), 0)
            INTO v_author_sim
            FROM publication_authors pa
            JOIN profiles pr ON pr.id = pa.profile_id
            WHERE pa.publication_id = best.id;
        END IF;

        -- Скор по году
        v_year_score := 0;
        IF ref.parsed_year IS NOT NULL AND best.published_date IS NOT NULL THEN
            IF EXTRACT(YEAR FROM best.published_date) = ref.parsed_year THEN
                v_year_score := 1.0;
            ELSIF ABS(EXTRACT(YEAR FROM best.published_date) - ref.parsed_year) <= 1 THEN
                v_year_score := 0.5;
            END IF;
        END IF;

        v_combined := 0.6 * v_title_sim + 0.25 * v_author_sim + 0.15 * v_year_score;

        IF v_combined >= 0.7 THEN
            -- Auto-match: создать citation
            UPDATE raw_references
            SET status = 'matched',
                matched_publication_id = best.id,
                match_score = v_combined,
                matched_at = now()
            WHERE id = ref.id;

            INSERT INTO citations (source_publication_id, target_publication_id)
            VALUES (ref.source_publication_id, best.id)
            ON CONFLICT DO NOTHING;

            v_matched := v_matched + 1;
        ELSE
            UPDATE raw_references
            SET status = 'unmatched',
                match_score = v_combined
            WHERE id = ref.id;
        END IF;
    END LOOP;

    RETURN v_matched;
END;
$$ LANGUAGE plpgsql;
```

### Запуск по расписанию

```sql
-- Через pg_cron (если доступен в Supabase)
SELECT cron.schedule('match-references', '*/10 * * * *',
    'SELECT match_raw_references(200)');
```

Альтернатива: Supabase Edge Function с `pg_cron` или внешний cron через GitHub Actions.

## Повторная проверка при загрузке новой статьи

Когда в систему загружается новая статья, нужно проверить, не ссылался ли кто-то на неё ранее:

```sql
CREATE OR REPLACE FUNCTION rematch_on_new_publication()
RETURNS TRIGGER AS $$
BEGIN
    -- Пометить unmatched ссылки как pending для повторной проверки
    UPDATE raw_references
    SET status = 'pending'
    WHERE status = 'unmatched'
      AND similarity(parsed_title, NEW.title) > 0.3;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_rematch_new_publication
AFTER INSERT ON publications
FOR EACH ROW EXECUTE FUNCTION rematch_on_new_publication();
```

## Масштабирование (после MVP)

| Этап | Технология | Когда |
|------|-----------|-------|
| MVP | pg_trgm + similarity() | Сейчас |
| v2 | + Нормализация заголовков (lowercase, удаление стоп-слов) | 5000+ статей |
| v3 | Sentence embeddings (all-MiniLM-L6-v2) + pgvector | 50000+ статей |
| v4 | LLM для сложных случаев (GPT/Claude API) | По необходимости |

## Известные ограничения

1. **Кириллица vs латиница** — similarity() плохо работает при смешении алфавитов. Решение: матчить и `title`, и `title_en` отдельно, брать max.
2. **Сокращения имён** — "Бердыев А." vs "Бердыев Ахмед" дадут низкий similarity. Решение: матчить по фамилии + первой букве.
3. **Однофамильцы** — similarity по имени автора недостаточен. Решение: использовать комбинацию автор + заголовок + год.
