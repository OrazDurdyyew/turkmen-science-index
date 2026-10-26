# Наукометрические показатели TSI

## Обзор метрик

| Метрика | Уровень | Описание | Формула |
|---------|---------|----------|---------|
| **Индекс Хирша (h-index)** | Автор | Максимальное h, при котором h статей процитированы >= h раз | см. ниже |
| **i10-index** | Автор | Количество статей с >= 10 цитированиями | `COUNT(citations >= 10)` |
| **citation_count** | Статья | Сколько раз статью процитировали | `COUNT(citations WHERE target = article)` |
| **Импакт-фактор** | Журнал | Средняя цитируемость статей журнала за 2 года | см. ниже |

---

## 1. Индекс Хирша (h-index)

### Определение
Учёный имеет h-index = **h**, если **h** из его статей процитированы **не менее h раз** каждая.

### Пример

| Статья | Цитирований |
|--------|-------------|
| A | 25 |
| B | 12 |
| C | 8 |
| D | 5 |
| E | 3 |
| F | 1 |

- Статья A: 25 >= 1 (да)
- Статья B: 12 >= 2 (да)
- Статья C: 8 >= 3 (да)
- Статья D: 5 >= 4 (да)
- Статья E: 3 >= 5 (нет) — **стоп**
- **h-index = 4**

### SQL-реализация

```sql
-- Функция находится в DATABASE_SCHEMA.md (recalculate_h_index)
-- Ядро алгоритма:
SELECT coalesce(max(rank), 0)
FROM (
    SELECT citation_count,
           ROW_NUMBER() OVER (ORDER BY citation_count DESC) as rank
    FROM publications p
    JOIN publication_authors pa ON pa.publication_id = p.id
    WHERE pa.profile_id = $1
      AND p.citation_count > 0
) ranked
WHERE citation_count >= rank;
```

### Хранение
- Поле `profiles.h_index` — кэшированное значение
- Поле `profiles.h_index_updated_at` — время последнего пересчёта
- Пересчёт: **раз в час** через cron или по требованию

---

## 2. i10-index

### Определение
Количество статей автора, которые процитированы **10 или более раз**.

### SQL

```sql
SELECT count(*)
FROM publications p
JOIN publication_authors pa ON pa.publication_id = p.id
WHERE pa.profile_id = $1
  AND p.citation_count >= 10;
```

### Хранение
- Поле `profiles.i10_index` — пересчитывается вместе с h-index

---

## 3. citation_count (уровень статьи)

### Определение
Количество статей в системе, которые ссылаются на данную публикацию.

### Обновление
**Синхронное** через триггер на таблице `citations`:
- INSERT → `citation_count += 1`
- DELETE → `citation_count -= 1`

Это единственная метрика, обновляемая в реальном времени (она дешёвая).

---

## 4. Импакт-фактор журнала (будущее)

### Определение
Классический 2-летний импакт-фактор:

```
IF(journal, year) = (цитирования в year на статьи journal за year-1 и year-2)
                     / (кол-во статей journal за year-1 и year-2)
```

### SQL

```sql
CREATE OR REPLACE FUNCTION calculate_journal_impact_factor(
    p_journal_id UUID,
    p_year INT
)
RETURNS NUMERIC AS $$
DECLARE
    v_citations INT;
    v_articles INT;
BEGIN
    -- Кол-во статей журнала за предыдущие 2 года
    SELECT count(*) INTO v_articles
    FROM publications
    WHERE journal_id = p_journal_id
      AND EXTRACT(YEAR FROM published_date) BETWEEN p_year - 2 AND p_year - 1;

    IF v_articles = 0 THEN RETURN 0; END IF;

    -- Цитирования этих статей из статей текущего года
    SELECT count(*) INTO v_citations
    FROM citations c
    JOIN publications target ON target.id = c.target_publication_id
    JOIN publications source ON source.id = c.source_publication_id
    WHERE target.journal_id = p_journal_id
      AND EXTRACT(YEAR FROM target.published_date) BETWEEN p_year - 2 AND p_year - 1
      AND EXTRACT(YEAR FROM source.published_date) = p_year;

    RETURN ROUND(v_citations::NUMERIC / v_articles, 3);
END;
$$ LANGUAGE plpgsql;
```

### Когда добавлять
Не в MVP. Импакт-фактор имеет смысл при достаточном количестве журналов и статей (100+ статей в журнале).

---

## Стратегия пересчёта

```
┌─────────────────────────────────────────────────────────┐
│                    Событие                               │
└──────────┬──────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────┐     ┌────────────────────────────┐
│ INSERT/DELETE citation│────▶│ Триггер: citation_count ±1 │
│ (реальное время)     │     │ (синхронно, мгновенно)     │
└──────────────────────┘     └────────────────────────────┘
           │
           ▼
┌──────────────────────┐     ┌────────────────────────────┐
│ Cron (раз в час)     │────▶│ recalculate_h_index()      │
│                      │     │ для всех авторов, чьи      │
│                      │     │ статьи получили новые       │
│                      │     │ цитирования с последнего    │
│                      │     │ пересчёта                   │
└──────────────────────┘     └────────────────────────────┘
```

### Оптимизация: пересчитывать только затронутых авторов

```sql
-- Найти авторов, чьи метрики устарели
CREATE OR REPLACE FUNCTION recalculate_stale_h_indexes()
RETURNS INT AS $$
DECLARE
    v_count INT := 0;
    v_profile RECORD;
BEGIN
    FOR v_profile IN
        SELECT DISTINCT pa.profile_id
        FROM citations c
        JOIN publication_authors pa ON pa.publication_id = c.target_publication_id
        WHERE c.created_at > (
            SELECT coalesce(h_index_updated_at, '1970-01-01')
            FROM profiles WHERE id = pa.profile_id
        )
    LOOP
        PERFORM recalculate_h_index(v_profile.profile_id);
        v_count := v_count + 1;
    END LOOP;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- Cron: каждый час
-- SELECT cron.schedule('recalc-h-index', '0 * * * *', 'SELECT recalculate_stale_h_indexes()');
```

---

## Отображение на фронтенде

### Профиль автора
```
┌─────────────────────────────────┐
│  Бердыев Ахмед Гурбанович       │
│  ТГУ им. Махтумкули             │
│                                 │
│  h-index: 7    i10-index: 3     │
│  Статей: 24    Цитирований: 142 │
│                                 │
│  Обновлено: 20.03.2026 14:00   │
└─────────────────────────────────┘
```

### Карточка статьи
```
┌─────────────────────────────────┐
│  Влияние температуры на...      │
│  Цитирований: 12                │
│  Цитирует: 8 статей             │
│  (из них 5 в системе TSI)       │
└─────────────────────────────────┘
```
