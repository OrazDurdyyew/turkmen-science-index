#!/usr/bin/env python3
"""Bulk-import a folder of PDFs into TSI through the parser service.

Every *.pdf under the folder (recursively) is parsed by GROBID and saved as a publication
of the given journal. Already imported articles (same DOI or title) are skipped.
Afterwards reference matching and the h-index recalculation are run once.

    python3 scripts/bulk_import.py "/path/to/issue" --journal "Горизонты науки" --date 2026-04-15

Credentials of an admin account are read from the environment (or .env / .env.example):
    SUPABASE_URL, SUPABASE_KEY, PARSER_URL, TSI_EMAIL / TSI_PASSWORD
    (TEST_USER_EMAIL / TEST_USER_PASSWORD are used as a fallback for local development)

Only the standard library is used, so it runs anywhere Python 3.10+ is available.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_env() -> dict[str, str]:
    env: dict[str, str] = {}
    for name in (".env.example", ".env"):  # .env wins
        path = ROOT / name
        if path.exists():
            for line in path.read_text(encoding="utf8").splitlines():
                if "=" in line and not line.lstrip().startswith("#"):
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip().strip('"')
    env.update(os.environ)
    return env


class Api:
    def __init__(self, env: dict[str, str]):
        self.supabase = env.get("SUPABASE_URL", "http://127.0.0.1:54321").rstrip("/")
        self.anon = env["SUPABASE_KEY"]
        self.parser = env.get("PARSER_URL", "http://localhost:8000").rstrip("/")
        self.token = ""

    def request(self, method: str, url: str, body: bytes | None = None, headers: dict | None = None, timeout: int = 300):
        req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read()
                return resp.status, json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except json.JSONDecodeError:
                return e.code, raw.decode(errors="replace")

    def sign_in(self, email: str, password: str) -> None:
        status, data = self.request(
            "POST",
            f"{self.supabase}/auth/v1/token?grant_type=password",
            json.dumps({"email": email, "password": password}).encode(),
            {"apikey": self.anon, "Content-Type": "application/json"},
        )
        if status != 200:
            sys.exit(f"Не удалось войти как {email}: {data}")
        self.token = data["access_token"]

    def rest(self, method: str, path: str, payload=None, prefer: str = ""):
        headers = {
            "apikey": self.anon,
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
        }
        if prefer:
            headers["Prefer"] = prefer
        body = json.dumps(payload).encode() if payload is not None else None
        return self.request(method, f"{self.supabase}/rest/v1/{path}", body, headers)

    def parser_post(self, path: str, pdf: Path, metadata: dict | None = None):
        boundary = uuid.uuid4().hex
        parts = [
            f"--{boundary}\r\n".encode(),
            f'Content-Disposition: form-data; name="file"; filename="{pdf.parent.name}-{pdf.name}"\r\n'.encode(),
            b"Content-Type: application/pdf\r\n\r\n",
            pdf.read_bytes(),
            b"\r\n",
        ]
        if metadata is not None:
            parts += [
                f"--{boundary}\r\n".encode(),
                b'Content-Disposition: form-data; name="metadata"\r\n',
                b"Content-Type: application/json; charset=utf-8\r\n\r\n",
                json.dumps(metadata, ensure_ascii=False).encode(),
                b"\r\n",
            ]
        parts.append(f"--{boundary}--\r\n".encode())
        return self.request(
            "POST",
            f"{self.parser}{path}",
            b"".join(parts),
            {"Authorization": f"Bearer {self.token}", "Content-Type": f"multipart/form-data; boundary={boundary}"},
        )


def ensure_journal(api: Api, title: str) -> str:
    status, rows = api.rest("GET", f"journals?select=id&title=eq.{urllib.parse.quote(title)}")
    if status == 200 and rows:
        return rows[0]["id"]
    status, rows = api.rest("POST", "journals", {"title": title}, prefer="return=representation")
    if status not in (200, 201):
        sys.exit(f"Не удалось создать журнал «{title}» (нужны права администратора): {rows}")
    print(f"Создан журнал «{title}»")
    return rows[0]["id"]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", type=Path, help="папка с PDF (ищется рекурсивно)")
    ap.add_argument("--journal", help="название журнала (создаётся, если нет)")
    ap.add_argument("--date", help="дата публикации YYYY-MM-DD, если в PDF её нет")
    ap.add_argument("--skip", action="append", default=["umumy.pdf"],
                    help="имя файла, который не импортировать (по умолчанию umumy.pdf — полный выпуск)")
    args = ap.parse_args()

    env = load_env()
    email = env.get("TSI_EMAIL") or env.get("TEST_USER_EMAIL")
    password = env.get("TSI_PASSWORD") or env.get("TEST_USER_PASSWORD")
    if not email or not password:
        sys.exit("Укажите TSI_EMAIL и TSI_PASSWORD")

    api = Api(env)
    api.sign_in(email, password)
    journal_id = ensure_journal(api, args.journal) if args.journal else None

    pdfs = sorted(p for p in args.folder.rglob("*.pdf") if p.name not in args.skip)
    if not pdfs:
        sys.exit(f"В {args.folder} нет PDF")

    imported = skipped = failed = 0
    for i, pdf in enumerate(pdfs, 1):
        label = f"[{i}/{len(pdfs)}] {pdf.relative_to(args.folder)}"
        status, meta = api.parser_post("/parse", pdf)
        if status != 200:
            failed += 1
            print(f"{label}: ошибка распознавания {status}: {meta}")
            continue
        meta["journal_id"] = journal_id
        if not meta.get("date") and args.date:
            meta["date"] = args.date
        status, res = api.parser_post("/parse-and-save", pdf, meta)
        if status == 200:
            imported += 1
            print(f"{label}: {res['title'][:70]} — авторов {len(res['authors'])}, ссылок {res['reference_count']}")
        elif status == 409:
            skipped += 1
            print(f"{label}: уже в базе")
        else:
            failed += 1
            print(f"{label}: ошибка сохранения {status}: {res}")

    print(f"\nИмпортировано: {imported}, пропущено: {skipped}, ошибок: {failed}")

    for fn, title in (("run_matching", "Сопоставление ссылок"), ("run_h_index_update", "Пересчёт h-index")):
        status, res = api.rest("POST", f"rpc/{fn}", {})
        print(f"{title}: {res if status == 200 else f'ошибка {status}: {res}'}")


if __name__ == "__main__":
    main()
