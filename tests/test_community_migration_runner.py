from pathlib import Path

import pytest

from app.community.migration_runner import (
    MigrationSafetyError,
    SchemaSnapshot,
    classify_migrations,
    database_target,
    discover_migrations,
    migration_body,
    validate_apply_confirmation,
)
from scripts.community_migrate import main


ROOT = Path(__file__).resolve().parents[1]


def _v1_snapshot(*, recorded=None) -> SchemaSnapshot:
    return SchemaSnapshot(
        relations=frozenset(
            {
                "community_posts",
                "community_consents",
                "community_responses",
                "community_public_posts",
                "community_area_summaries",
            }
        ),
        post_columns=frozenset(),
        public_view_columns=frozenset(),
        community_site_count=0,
        recorded_checksums=recorded or {},
    )


def test_discovers_ordered_migrations_and_strips_nested_transactions():
    migrations = discover_migrations(ROOT / "migrations")
    assert [item.version for item in migrations] == [1, 2]
    assert all(len(item.checksum) == 64 for item in migrations)
    body = migration_body(migrations[1].path)
    assert not body.lower().startswith("begin;")
    assert not body.lower().endswith("commit;")
    assert "create table if not exists community_media_assets" in body


def test_classifies_existing_mvp_as_baseline_and_v2_as_pending():
    migrations = discover_migrations(ROOT / "migrations")
    statuses = classify_migrations(migrations, _v1_snapshot())
    assert [item.state for item in statuses] == ["baseline_required", "pending"]


def test_detects_changed_applied_migration_checksum():
    migrations = discover_migrations(ROOT / "migrations")
    statuses = classify_migrations(
        migrations,
        _v1_snapshot(recorded={1: "not-the-current-checksum"}),
    )
    assert statuses[0].state == "checksum_mismatch"


def test_apply_requires_exact_database_hostname():
    url = "postgresql://user:secret@db.example.test:5432/community"
    assert database_target(url) == ("db.example.test", "community")
    assert validate_apply_confirmation(url, "DB.EXAMPLE.TEST") == "db.example.test"
    with pytest.raises(MigrationSafetyError, match="目标确认不匹配"):
        validate_apply_confirmation(url, "other.example.test")


def test_cli_stops_before_connecting_when_confirmation_is_wrong(tmp_path, capsys):
    env_file = tmp_path / ".env"
    env_file.write_text(
        "DATABASE_URL=postgresql://user:secret@db.example.test/community\n",
        encoding="utf-8",
    )
    exit_code = main(
        [
            "--env-file",
            str(env_file),
            "--migrations-dir",
            str(ROOT / "migrations"),
            "--apply",
            "--confirm-host",
            "wrong.example.test",
        ]
    )
    assert exit_code == 2
    output = capsys.readouterr().out
    assert "迁移已停止" in output
    assert "secret" not in output
