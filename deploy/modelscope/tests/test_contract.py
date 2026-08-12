from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_required_files_exist():
    for relative in ("app.py", "inference.py", "studio_config.py", "theme.css", "requirements.txt", "README.md"):
        assert (ROOT / relative).is_file()


def test_no_embedded_secrets():
    text_extensions = {".py", ".md", ".txt", ".css", ".json", ".csv"}
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix not in text_extensions:
            continue
        text = path.read_text(encoding="utf-8")
        assert "".join(("ms", "-bf")) not in text
        assert "".join(("DASHSCOPE", "_API_KEY=")) not in text
