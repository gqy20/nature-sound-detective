from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable, Literal
from urllib.parse import urlparse


MigrationState = Literal[
    "applied",
    "baseline_required",
    "pending",
    "checksum_mismatch",
]


@dataclass(frozen=True)
class Migration:
    version: int
    name: str
    path: Path
    checksum: str


@dataclass(frozen=True)
class SchemaSnapshot:
    relations: frozenset[str]
    post_columns: frozenset[str]
    public_view_columns: frozenset[str]
    community_site_count: int
    recorded_checksums: dict[int, str]


@dataclass(frozen=True)
class MigrationStatus:
    migration: Migration
    state: MigrationState


class MigrationSafetyError(RuntimeError):
    pass


def discover_migrations(directory: Path) -> list[Migration]:
    migrations: list[Migration] = []
    for path in sorted(directory.glob("[0-9][0-9][0-9]_*.sql")):
        match = re.fullmatch(r"(?P<version>\d{3})_(?P<name>.+)\.sql", path.name)
        if match is None:
            continue
        payload = path.read_bytes()
        migrations.append(
            Migration(
                version=int(match.group("version")),
                name=match.group("name"),
                path=path,
                checksum=hashlib.sha256(payload).hexdigest(),
            )
        )
    versions = [item.version for item in migrations]
    if not migrations:
        raise MigrationSafetyError(f"没有在 {directory} 找到迁移文件")
    if len(versions) != len(set(versions)):
        raise MigrationSafetyError("迁移版本号重复")
    if versions != sorted(versions):
        raise MigrationSafetyError("迁移版本顺序无效")
    return migrations


def migration_body(path: Path) -> str:
    sql = path.read_text(encoding="utf-8-sig").strip()
    sql = re.sub(r"^begin\s*;", "", sql, count=1, flags=re.IGNORECASE).strip()
    sql = re.sub(r"commit\s*;$", "", sql, count=1, flags=re.IGNORECASE).strip()
    if not sql:
        raise MigrationSafetyError(f"迁移文件为空：{path.name}")
    return sql


def database_target(database_url: str) -> tuple[str, str]:
    parsed = urlparse(database_url.strip().lstrip("\ufeff").strip())
    if parsed.scheme not in {"postgres", "postgresql"} or not parsed.hostname:
        raise MigrationSafetyError("DATABASE_URL 不是有效的 PostgreSQL 连接地址")
    return parsed.hostname.lower(), parsed.path.lstrip("/") or "postgres"


def validate_apply_confirmation(database_url: str, confirmation: str | None) -> str:
    hostname, _ = database_target(database_url)
    if not confirmation:
        raise MigrationSafetyError(
            f"写入操作必须提供 --confirm-host {hostname}"
        )
    if confirmation.strip().lower() != hostname:
        raise MigrationSafetyError(
            f"目标确认不匹配；期望 {hostname}，收到 {confirmation.strip().lower()}"
        )
    return hostname


def migration_detected(version: int, snapshot: SchemaSnapshot) -> bool:
    if version == 1:
        return {
            "community_posts",
            "community_consents",
            "community_responses",
            "community_public_posts",
            "community_area_summaries",
        }.issubset(snapshot.relations)
    if version == 2:
        return (
            {
                "park_id",
                "zone_id",
                "site_id",
                "sampling_mode",
                "sampling_effort",
                "audio_quality",
                "ecology_eligible",
            }.issubset(snapshot.post_columns)
            and {
                "community_sites",
                "community_media_assets",
            }.issubset(snapshot.relations)
            and {
                "park_id",
                "zone_id",
                "site_id",
                "ecology_eligible",
            }.issubset(snapshot.public_view_columns)
            and snapshot.community_site_count >= 9
        )
    if version == 3:
        return "community_parent_guidance_quotas" in snapshot.relations
    if version == 4:
        return "community_parent_guidance_cache" in snapshot.relations
    if version == 5:
        return {
            "family_exploration_sessions",
            "family_exploration_events",
            "family_session_commands",
        }.issubset(snapshot.relations)
    return False


def classify_migrations(
    migrations: Iterable[Migration], snapshot: SchemaSnapshot
) -> list[MigrationStatus]:
    statuses = []
    for migration in migrations:
        recorded = snapshot.recorded_checksums.get(migration.version)
        if recorded is not None:
            state: MigrationState = (
                "applied" if recorded == migration.checksum else "checksum_mismatch"
            )
        elif migration_detected(migration.version, snapshot):
            state = "baseline_required"
        else:
            state = "pending"
        statuses.append(MigrationStatus(migration=migration, state=state))
    return statuses


def _relation_names(connection) -> frozenset[str]:
    rows = connection.execute(
        """select c.relname
           from pg_class c
           join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and c.relkind in ('r','v','m')"""
    ).fetchall()
    return frozenset(row[0] for row in rows)


def _column_names(connection, relation: str) -> frozenset[str]:
    rows = connection.execute(
        """select column_name from information_schema.columns
           where table_schema='public' and table_name=%s""",
        (relation,),
    ).fetchall()
    return frozenset(row[0] for row in rows)


def inspect_schema(connection) -> SchemaSnapshot:
    relations = _relation_names(connection)
    site_count = 0
    if "community_sites" in relations:
        site_count = int(
            connection.execute("select count(*) from community_sites").fetchone()[0]
        )
    recorded: dict[int, str] = {}
    if "community_schema_migrations" in relations:
        recorded = {
            int(row[0]): str(row[1])
            for row in connection.execute(
                "select version, checksum from community_schema_migrations"
            ).fetchall()
        }
    return SchemaSnapshot(
        relations=relations,
        post_columns=_column_names(connection, "community_posts"),
        public_view_columns=_column_names(connection, "community_public_posts"),
        community_site_count=site_count,
        recorded_checksums=recorded,
    )


def read_status(database_url: str, migrations: list[Migration]):
    import psycopg

    with psycopg.connect(database_url) as connection:
        with connection.transaction():
            connection.execute("set transaction read only")
            snapshot = inspect_schema(connection)
    return snapshot, classify_migrations(migrations, snapshot)


def apply_migrations(
    database_url: str,
    migrations: list[Migration],
    *,
    confirm_host: str | None,
    connect: Callable[..., Any] | None = None,
) -> list[MigrationStatus]:
    validate_apply_confirmation(database_url, confirm_host)
    if connect is None:
        import psycopg

        connect = psycopg.connect
    with connect(database_url) as connection:
        with connection.transaction():
            connection.execute("set local lock_timeout = '5s'")
            connection.execute("set local statement_timeout = '60s'")
            locked = connection.execute(
                "select pg_try_advisory_xact_lock(hashtext(%s))",
                ("xykw-community-schema-migrations",),
            ).fetchone()[0]
            if not locked:
                raise MigrationSafetyError("另一个迁移进程正在运行，请稍后重试")
            connection.execute(
                """create table if not exists community_schema_migrations (
                       version integer primary key,
                       name text not null,
                       checksum text not null,
                       applied_at timestamptz not null default now()
                   )"""
            )
            snapshot = inspect_schema(connection)
            statuses = classify_migrations(migrations, snapshot)
            mismatch = [item for item in statuses if item.state == "checksum_mismatch"]
            if mismatch:
                names = ", ".join(item.migration.path.name for item in mismatch)
                raise MigrationSafetyError(f"已应用迁移的校验和发生变化：{names}")
            for status in statuses:
                migration = status.migration
                if status.state == "applied":
                    continue
                if status.state == "pending":
                    connection.execute(migration_body(migration.path))
                    if not migration_detected(
                        migration.version, inspect_schema(connection)
                    ):
                        raise MigrationSafetyError(
                            f"迁移执行后验收失败：{migration.path.name}"
                        )
                connection.execute(
                    """insert into community_schema_migrations
                       (version, name, checksum) values (%s,%s,%s)
                       on conflict (version) do nothing""",
                    (migration.version, migration.name, migration.checksum),
                )
            final_snapshot = inspect_schema(connection)
            final_statuses = classify_migrations(migrations, final_snapshot)
            if any(item.state != "applied" for item in final_statuses):
                raise MigrationSafetyError("迁移完成后仍存在未应用版本")
    return final_statuses
