from app.community import repository as repository_module


def test_repository_environment_strips_bom_and_whitespace(monkeypatch):
    captured: dict[str, str] = {}
    sentinel = object()

    def fake_repository(database_url: str):
        captured["database_url"] = database_url
        return sentinel

    monkeypatch.setenv("DATABASE_URL", "\ufeff  postgresql://example.test/db  \n")
    monkeypatch.setattr(repository_module, "NeonCommunityRepository", fake_repository)

    repository = repository_module.repository_from_environment()

    assert repository is sentinel
    assert captured["database_url"] == "postgresql://example.test/db"
