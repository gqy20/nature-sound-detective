from __future__ import annotations

import subprocess
import sys

import pytest

from app.generated_prompts import (
    PROMPT_CATALOG_DIGEST,
    PROMPT_VERSIONS,
    prompt_generation,
    render_prompt,
)


def test_generated_prompt_catalog_is_current():
    completed = subprocess.run(
        [sys.executable, "scripts/generate_prompt_catalog.py", "--check"],
        capture_output=True,
        text=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stdout + completed.stderr


def test_prompt_catalog_versions_and_generation_profiles_are_available():
    assert len(PROMPT_CATALOG_DIGEST) == 16
    assert PROMPT_VERSIONS["story"] == "animal-story-v5"
    assert PROMPT_VERSIONS["parent_guidance"] == "parent-guidance-v4"
    assert PROMPT_VERSIONS["creation"] == "creation-v3"
    assert prompt_generation("story")["max_completion_tokens"] == 500


def test_prompt_rendering_requires_exact_variables():
    rendered = render_prompt(
        "creation.mobile_video_bird",
        location="杭州",
        subject="树麻雀",
    )
    assert "树麻雀" in rendered
    assert "生成一支5秒" in rendered
    assert "单镜头" in rendered
    assert "杭州" in rendered
    assert "{{" not in rendered

    with pytest.raises(ValueError, match="missing"):
        render_prompt(
            "creation.mobile_video_bird",
            location="杭州",
        )


def test_experiment_prompts_also_come_from_the_catalog():
    assert "树麻雀" in render_prompt("wan3_experiments.structured_sparrow")
    assert "额外肢体" in render_prompt("wan3_experiments.negative")
