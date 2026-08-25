from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from dotenv import load_dotenv


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from app.community.migration_runner import (
    MigrationSafetyError,
    apply_migrations,
    database_target,
    discover_migrations,
    read_status,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="只读检查或安全执行社区数据库迁移"
    )
    parser.add_argument("--env-file", type=Path, default=ROOT / ".env")
    parser.add_argument("--migrations-dir", type=Path, default=ROOT / "migrations")
    parser.add_argument("--apply", action="store_true", help="执行待应用迁移")
    parser.add_argument("--confirm-host", help="必须与DATABASE_URL主机完全一致")
    parser.add_argument("--require-current", action="store_true")
    parser.add_argument("--json", action="store_true", dest="as_json")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    load_dotenv(args.env_file, override=True)
    database_url = os.getenv("DATABASE_URL", "").strip().lstrip("\ufeff").strip()
    try:
        hostname, database = database_target(database_url)
        migrations = discover_migrations(args.migrations_dir)
        if args.apply:
            statuses = apply_migrations(
                database_url,
                migrations,
                confirm_host=args.confirm_host,
            )
        else:
            _, statuses = read_status(database_url, migrations)
        payload = {
            "target": {"host": hostname, "database": database},
            "mode": "apply" if args.apply else "status",
            "migrations": [
                {
                    "version": item.migration.version,
                    "file": item.migration.path.name,
                    "checksum": item.migration.checksum,
                    "state": item.state,
                }
                for item in statuses
            ],
        }
        if args.as_json:
            print(json.dumps(payload, ensure_ascii=False, indent=2))
        else:
            print(f"目标：{hostname}/{database}")
            print(f"模式：{'执行迁移' if args.apply else '只读检查'}")
            for item in payload["migrations"]:
                print(
                    f"{item['version']:03d} {item['file']}: {item['state']} "
                    f"({item['checksum'][:12]})"
                )
        if args.require_current and any(
            item.state != "applied" for item in statuses
        ):
            return 3
        return 0
    except MigrationSafetyError as error:
        if args.as_json:
            print(json.dumps({"error": str(error)}, ensure_ascii=False))
        else:
            print(f"迁移已停止：{error}")
        return 2
    except Exception as error:
        try:
            import psycopg

            is_database_error = isinstance(error, psycopg.Error)
        except ImportError:
            is_database_error = False
        if not is_database_error:
            raise
        message = f"数据库连接或查询失败（{type(error).__name__}）"
        if args.as_json:
            print(json.dumps({"error": message}, ensure_ascii=False))
        else:
            print(f"迁移已停止：{message}")
        return 4


if __name__ == "__main__":
    raise SystemExit(main())
