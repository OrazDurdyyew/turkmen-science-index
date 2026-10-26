# Архитектура TSI (TurkmenScience Index)

## Обзор системы

```
┌─────────────────────────────────────────────────────────┐
│                      Frontend                           │
│              Nuxt 4 + Vite + Pinia + Tailwind            │
│         (SPA: поиск, профили, загрузка PDF)             │
└──────────────────────┬──────────────────────────────────┘
                       │ REST / Realtime
┌──────────────────────▼──────────────────────────────────┐
│                   Supabase (BaaS)                       │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌───────┐  │
│  │PostgreSQL│  │   Auth   │  │  Storage  │  │ Edge  │  │
│  │  (БД)    │  │  (JWT)   │  │  (PDF)    │  │ Func  │  │
│  └──────────┘  └──────────┘  └───────────┘  └───────┘  │
└──────────────────────┬──────────────────────────────────┘
                       │ HTTP (внутренняя сеть)
┌──────────────────────▼──────────────────────────────────┐
│              AI/Parsing Service (Docker)                 │
│  ┌──────────────────┐  ┌──────────────────────────────┐ │
│  │   FastAPI (Python)│  │   GROBID (Java, контейнер)  │ │
│  │  - PDF upload     │  │   - Извлечение метаданных   │ │
│  │  - Парсинг ответа │  │   - Список литературы       │ │
│  │  - Fuzzy matching │  │   - Структура статьи        │ │
│  └──────────────────┘  └──────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Компоненты

### 1. Frontend (Nuxt 4)
- **Фреймворк:** Nuxt 4 Composition API
- **Сборщик:** Vite
- **Стейт:** Pinia
- **UI-kit:** shadcn-vue (Radix Vue + Tailwind CSS)
- **Роутинг:** Nuxt file-based routing
- **Клиент БД:** @supabase/supabase-js

**Основные страницы:**
| Страница | Описание |
|----------|----------|
| `/` | Главная + поиск |
| `/search` | Результаты поиска (статьи, авторы) |
| `/publication/:id` | Карточка статьи (метаданные, цитирования) |
| `/author/:id` | Профиль автора (h-index, список статей) |
| `/upload` | Загрузка PDF (авторизованные пользователи) |
| `/journal/:id` | Карточка журнала |
| `/dashboard` | Личный кабинет автора |

### 2. Supabase

**PostgreSQL** — основная БД со всеми таблицами, индексами, RLS.
- Расширения: `pg_trgm`, `uuid-ossp`
- Полнотекстовый поиск: `tsvector` + GIN-индексы
- Cron: `pg_cron` для пересчёта метрик

**Auth** — регистрация/вход учёных.
- Email + password (основной)
- Привязка ORCID (будущее)

**Storage** — хранение PDF-файлов.
- Бакет `publications` (приватный, доступ через RLS)
- Лимит: 50 МБ на файл

**Edge Functions** — серверная логика.
- Триггер на загрузку PDF → вызов Parsing Service
- Webhook для пересчёта метрик

### 3. Parsing Service (Python + GROBID)

**FastAPI** принимает PDF, отправляет в GROBID, парсит XML-ответ:

```
PDF → GROBID → TEI XML → FastAPI парсит → Supabase
                                │
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
              publications  raw_references  publication_authors
```

**Эндпоинты:**
| Метод | Путь | Описание |
|-------|------|----------|
| POST | `/parse` | Принять PDF, вернуть метаданные |
| POST | `/match` | Запустить fuzzy matching для raw_references |
| GET  | `/health` | Проверка GROBID |

### 4. Docker Compose (Dev Environment)

```yaml
services:
  grobid:        # GROBID сервер (порт 8070)
  parsing:       # FastAPI (порт 8000)
  # Supabase запускается отдельно через supabase CLI
```

## Поток данных: загрузка статьи

```
1. Автор загружает PDF через /upload
2. Frontend → Supabase Storage (сохранение файла)
3. Supabase Edge Function → POST /parse (Parsing Service)
4. GROBID извлекает: заголовок, авторы, аннотация, список литературы
5. FastAPI записывает в Supabase:
   - publications (метаданные статьи)
   - publication_authors (связь с профилями)
   - raw_references (сырые ссылки)
6. Фоновый процесс (cron): fuzzy matching raw_references → citations
7. Cron (раз в час): пересчёт h-index затронутых авторов
```

## Безопасность

- **RLS** на всех таблицах — пользователь может редактировать только свои данные
- **Service Role Key** — только на бэкенде (Parsing Service)
- **Anon Key** — только на фронтенде (ограниченный доступ)
- **CORS** — разрешён только домен фронтенда
- **Rate Limiting** — на Edge Functions (защита от спама загрузок)
