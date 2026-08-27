from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_required_files_exist():
    for relative in ("app.py", "inference.py", "studio_config.py", "theme.css", "instrument.css", "requirements.txt", "README.md"):
        assert (ROOT / relative).is_file()


def test_no_embedded_secrets():
    text_extensions = {".py", ".md", ".txt", ".css", ".json", ".csv"}
    for path in ROOT.rglob("*"):
        if not path.is_file() or path.suffix not in text_extensions:
            continue
        text = path.read_text(encoding="utf-8")
        assert "".join(("ms", "-bf")) not in text  # noqa: FLY002 - keep scanners from matching the token prefix
        assert "".join(("DASHSCOPE", "_API_KEY=")) not in text  # noqa: FLY002 - do not embed the secret name


def test_studio_has_task_first_entry_and_mobile_escape_hatch():
    app_source = (ROOT / "app.py").read_text(encoding="utf-8")
    config_source = (ROOT / "studio_config.py").read_text(encoding="utf-8")

    assert 'href="#investigation"' in app_source
    assert 'elem_id="investigation"' in app_source
    assert "STUDIO_DIRECT_URL" in app_source
    assert "STUDIO_DIRECT_URL" in config_source


def test_default_experience_is_a_single_viewport_workspace():
    app_source = (ROOT / "app.py").read_text(encoding="utf-8")
    css = (ROOT / "theme.css").read_text(encoding="utf-8")

    assert 'elem_id="investigation"' in app_source
    assert 'elem_id="result-content"' in app_source
    assert "with gr.Tabs" not in app_source
    assert 'class="hero"' not in app_source
    assert "height: 100dvh" in css
    assert "overflow: hidden" in css
    assert "#result-content" in css
    assert "overflow: auto" in css


def test_web_theme_reuses_android_material_tokens():
    css = (ROOT / "theme.css").read_text(encoding="utf-8").lower()
    app_source = (ROOT / "app.py").read_text(encoding="utf-8")

    for token in ("#174936", "#17251f", "#f8f5ec", "#66716b", "#b9b7ab"):
        assert token in css
    assert 'font=[gr.themes.Font("PingFang SC"), "Microsoft YaHei"' in app_source
    assert "APP_THEME" in app_source


def test_mobile_workspace_switches_views_instead_of_stacking_panels():
    app_source = (ROOT / "app.py").read_text(encoding="utf-8")
    css = (ROOT / "theme.css").read_text(encoding="utf-8")

    assert 'data-workspace-view="capture"' in app_source
    assert 'data-workspace-view="results"' in app_source
    assert 'setWorkspaceView("results")' in app_source
    assert 'style.setProperty(' in app_source
    assert ".workspace-show-results #investigation > #audio-input-panel.workspace-panel" in css
    assert ".workspace-show-results #investigation > #analysis-result-panel.workspace-panel" in css


def test_mobile_audio_uploader_stays_in_flow_on_short_viewports():
    css = (ROOT / "theme.css").read_text(encoding="utf-8")

    assert "flex-wrap: nowrap !important" in css
    assert ".workspace-panel > .block" in css
    assert "#source-audio .source-selection" in css
    assert "@media (max-width: 760px) and (max-height: 540px)" in css
    assert "max-height: min(36dvh, 250px)" in css


def test_audio_capture_unifies_android_style_recording_and_file_drop():
    app_source = (ROOT / "app.py").read_text(encoding="utf-8")
    css = (ROOT / "theme.css").read_text(encoding="utf-8")

    assert 'document.addEventListener("dragenter"' in app_source
    assert 'button[aria-label="Upload file"]' in app_source
    assert "audio-file-dragging" in app_source
    assert "deliverDroppedAudio" in app_source
    assert 'input.dispatchEvent(new Event("change"' in app_source
    assert "#source-audio .record-button.record" in css
    assert 'content: "开始聆听"' in css
    assert "拖入音频，或点右侧选择文件" in css
    assert "#source-audio .source-selection button.selected" in css


def test_field_instrument_layout_uses_selected_visual_direction():
    app_source = (ROOT / "app.py").read_text(encoding="utf-8")
    css = (ROOT / "instrument.css").read_text(encoding="utf-8")

    assert "听见此刻的自然" in app_source
    assert 'id="drop-audio-surface"' in app_source
    assert "观测册" in app_source
    assert ".live-waveform" in css
    assert "field-bird.png" in css
    assert "field-context" in app_source
    assert "rail-process" in app_source
    assert "live-waveform" in app_source
    assert "createAnalyser" in app_source
    assert "getByteTimeDomainData" in app_source
    assert "left: calc(50% - 10px)" in css


def test_studio_preflights_audio_before_enabling_analysis():
    app_source = (ROOT / "app.py").read_text(encoding="utf-8")
    config_source = (ROOT / "studio_config.py").read_text(encoding="utf-8")

    assert "_audio_preflight" in app_source
    assert "MAX_UPLOAD_BYTES" in app_source
    assert "SUPPORTED_AUDIO_SUFFIXES" in config_source
    assert 'interactive=False' in app_source
    assert "audio.change(" in app_source
    assert "inspect_audio," in app_source
    assert "outputs=[quality, submit, result_html, observation]" in app_source
    assert "不会自动公开或进入训练集" in app_source
    assert "max_file_size=MAX_UPLOAD_BYTES" in app_source
    assert 'buttons=["download"]' in app_source


def test_user_facing_errors_do_not_include_internal_exception_text():
    app_source = (ROOT / "app.py").read_text(encoding="utf-8")

    assert 'LOGGER.exception("ModelScope Studio analysis failed")' in app_source
    assert "{exc}" not in app_source


def test_theme_covers_accessibility_and_narrow_candidate_cards():
    app_source = (ROOT / "app.py").read_text(encoding="utf-8")
    css = (ROOT / "theme.css").read_text(encoding="utf-8")

    assert ":focus-visible" in css
    assert "prefers-reduced-motion" in css
    assert "@media (max-width: 760px)" in css
    assert ".interval-chip" in css
    assert ".candidate-details" in css
    assert 'class="interval-chip" data-start=' in app_source
    assert "event.composedPath()" in app_source
    assert 'node.shadowRoot?.querySelector("audio")' in app_source
    assert "js=APP_JS" in app_source
    assert "})();" in app_source
    assert "#reset-investigation" in css


def test_studio_serializes_shared_tflite_interpreters():
    app_source = (ROOT / "app.py").read_text(encoding="utf-8")
    inference_source = (ROOT / "inference.py").read_text(encoding="utf-8")

    assert "self._inference_lock = threading.Lock()" in inference_source
    assert "with self._inference_lock:" in inference_source
    assert "default_concurrency_limit=1" in app_source


def test_weak_bird_species_are_not_presented_as_specific_answers():
    app_source = (ROOT / "app.py").read_text(encoding="utf-8")
    inference_source = (ROOT / "inference.py").read_text(encoding="utf-8")
    config_source = (ROOT / "studio_config.py").read_text(encoding="utf-8")

    assert "BIRD_SPECIES_DISPLAY_THRESHOLD = 0.42" in config_source
    assert "bird.confidence >= BIRD_SPECIES_DISPLAY_THRESHOLD" in inference_source
    assert "possibly" not in app_source.lower()
    assert "可能的物种线索" in app_source
    assert "技术详情" in app_source


def test_checked_in_bird_catalog_has_no_english_name_fallbacks():
    import json

    catalog_path = ROOT.parents[1] / "mobile" / "assets" / "labels" / "birdnet_hz.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))

    assert all(item["name_zh"] != item["name_en"] for item in catalog["species"])
