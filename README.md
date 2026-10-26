# TSI — TurkmenScience Index

Национальная система научного цитирования Туркменистана. Статьи загружаются в виде PDF: система сама извлекает название, авторов, аннотацию и список литературы, сопоставляет ссылки со статьями в базе, считает цитирования, h-index и i10-index авторов.

## Возможности

**Для всех (без входа):**
- каталог публикаций, авторов и журналов с фильтрами, сортировкой и пагинацией;
- поиск по названию, аннотации и ФИО авторов (полнотекстовый + нечёткий, с подсказками);
- карточка статьи: авторы, аннотация, «цитируется в», список литературы со ссылками на найденные статьи;
- профиль автора: h-index, i10-index, цитирования, публикации, соавторы.

**Для зарегистрированных:**
- загрузка PDF с предпросмотром и правкой распознанных данных;
- ручное добавление и редактирование статей, выбор соавторов;
- личный кабинет с метриками;
- «Это я» — заявка на привязку профиля, созданного автоматически по загруженным статьям.

**Для администраторов (`/admin`):**
- обзор: счётчики, состояние сопоставления, запуск сопоставления и пересчёта h-index вручную;
- публикации: поиск, редактирование, удаление;
- ссылки: ручная привязка не найденных ссылок, отвязка ошибочных, отклонение;
- авторы и пользователи: роли, объединение дублей, удаление пустых профилей;
- заявки на профили: одобрение / отклонение;
- журналы: добавление, редактирование, удаление.

## Архитектура

| Слой | Технология |
|------|-----------|
| Фронтенд | Nuxt 4 (SPA), Vue 3, Tailwind CSS 4, компоненты shadcn — `frontend/` |
| Парсер PDF | FastAPI (Python 3.12) + GROBID 0.8.1 + pypdf — `services/parser/` |
| База данных, авторизация, файлы | Supabase: PostgreSQL 17, Auth, Storage, pg_cron, pg_trgm — `supabase/` |

```
Браузер ──► Supabase (REST + RLS)          публичное чтение, правки владельцев и админов
   │
   └──► Parser ──► GROBID                  PDF → TEI XML → метаданные
           └──► Supabase (service role)    запись статьи, авторов, ссылок, PDF
pg_cron: сопоставление ссылок каждые 10 мин, h-index каждый час, очистка пустых профилей раз в сутки
```

Ключевые решения:
- **Профили без аккаунта.** Каждый автор из PDF получает профиль сразу (`profiles.user_id IS NULL`), с h-index и местом в поиске. Зарегистрированный пользователь «забирает» свой профиль через заявку. У зарегистрированных `profiles.id = auth.uid()`.
- **Сопоставление ссылок** — `pg_trgm`, порог сходства 0.6, отсев кандидатов с годом, отличающимся больше чем на 1. При совпадении h-index цитируемых авторов пересчитывается сразу. Спорные случаи решает администратор.
- **Разбор PDF**: GROBID + эвристика первой страницы для формата постсоветских журналов (УДК → НАЗВАНИЕ → ФИО → аффилиация → «Аннотация»). Русское название основное, английское — в `title_en`.
- **Безопасность**: всё проверяется на стороне БД (RLS + триггеры, которые не дают пользователю менять h-index, цитирования, роль). Парсер принимает только запросы с токеном пользователя.

Подробнее — в [docs/](docs/): [архитектура](docs/ARCHITECTURE.md), [схема БД](docs/DATABASE_SCHEMA.md), [сопоставление ссылок](docs/MATCHING_ENGINE.md), [метрики](docs/METRICS.md), [дорожная карта](docs/ROADMAP.md).

## Требования

- Node.js ≥ 18 и pnpm 10 (`npx pnpm@10.31.0 …`, если глобально стоит другая версия)
- Docker и Docker Compose
- [Supabase CLI](https://supabase.com/docs/guides/cli)
- Python 3.10+ (только для скрипта массового импорта)

## Запуск локально

```bash
# 1. Зависимости фронтенда
pnpm --dir frontend install

# 2. Переменные окружения
cp .env.example .env
cp frontend/.env.example frontend/.env

# 3. Supabase (миграции применятся автоматически)
supabase start
supabase status -o env      # ключи для .env
```

В `.env` и `frontend/.env` впишите ключи из `supabase status`:

```
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_KEY=<ANON_KEY / publishable key>
SUPABASE_SERVICE_KEY=<SERVICE_ROLE_KEY>
SUPABASE_SERVICE_KEY_JWT=<SERVICE_ROLE_KEY в формате JWT>   # Python SDK не принимает ключи sb_…
```

```bash
# 4. GROBID + парсер (GROBID стартует ~60 секунд)
pnpm services:up

# 5. Фронтенд
pnpm dev                    # http://localhost:3050
```

### Первый администратор

Зарегистрируйтесь на сайте, затем в Supabase Studio → SQL Editor:

```sql
update profiles set role = 'admin'
where user_id = (select id from auth.users where email = 'you@example.com');
```

Дальше роли назначаются в админке: «Авторы и пользователи» → «Сделать админом».

### Демо-данные

```bash
pnpm import "/путь/к/выпуску" --journal "Горизонты науки" --date 2026-04-15
```

Скрипт загружает все PDF папки (рекурсивно, кроме `umumy.pdf` — полного выпуска) от имени администратора (`TSI_EMAIL` / `TSI_PASSWORD`), пропускает уже загруженные статьи и в конце запускает сопоставление и пересчёт h-index.

## Адреса (dev)

| Сервис | URL |
|--------|-----|
| Сайт | http://localhost:3050 |
| Админка | http://localhost:3050/admin |
| Parser API (Swagger) | http://localhost:8000/docs |
| GROBID | http://localhost:8070 |
| Supabase Studio | http://localhost:54323 |
| Почта (Mailpit) | http://localhost:54324 |

## Тесты и проверки

```bash
pnpm test:db        # RLS и права: 26 сценариев, всё в транзакции с откатом
pnpm test:parser    # pytest: разбор TEI, эвристика первой страницы, валидация, авторизация
pnpm typecheck      # nuxi typecheck
pnpm build          # статическая сборка фронтенда
```

## Продакшен

1. Создайте проект Supabase, примените миграции: `supabase link --project-ref … && supabase db push`. Расширения `pg_cron` и `pg_trgm` включаются миграциями.
2. Заполните `.env` (см. `.env.example`): `PARSER_SUPABASE_URL`, `SUPABASE_SERVICE_KEY_JWT`, `CORS_ORIGINS`, `PUBLIC_SUPABASE_URL`, `SUPABASE_KEY`, `PUBLIC_PARSER_URL`, `RESTART_POLICY=unless-stopped`.
3. `docker compose --profile prod up -d --build` — GROBID, парсер и фронтенд (nginx, порт `FRONTEND_PORT`, по умолчанию 8080).
4. Поставьте перед фронтендом и парсером обратный прокси с HTTPS. В настройках Auth проекта Supabase укажите адрес сайта (Site URL).

## Полезные команды

```bash
pnpm db:migrate     # применить новые миграции к локальной БД
pnpm db:types       # перегенерировать frontend/types/database.types.ts
pnpm db:stop        # остановить Supabase (данные сохраняются)
pnpm services:down  # остановить GROBID и парсер
```

## Структура

```
frontend/              Nuxt-приложение
  pages/               страницы (admin/ — администрирование)
  components/          общие компоненты (ui/ — базовые shadcn)
  composables/         useAuth, useSupabase, useToast, usePublicationAuthors
services/parser/       FastAPI: main.py, tei_parser.py, first_page.py, tests/
supabase/migrations/   схема БД, RLS, функции, cron (001–011)
supabase/tests/        SQL-тест прав доступа
scripts/bulk_import.py массовый импорт PDF
```

## Лицензия

[MIT](LICENSE)
