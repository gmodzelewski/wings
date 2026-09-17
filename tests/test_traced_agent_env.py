"""Unit tests for wings3_env secret/env loading."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

WINGS3_ROOT = Path(__file__).resolve().parent.parent
AGENT_TRACING = WINGS3_ROOT / "demo" / "agent-tracing"
sys.path.insert(0, str(AGENT_TRACING))

import wings3_env  # noqa: E402


@pytest.fixture(autouse=True)
def clear_maas_env(monkeypatch):
    for key in wings3_env.WINGS3_SECRET_KEYS:
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setattr(wings3_env, "WINGS3_SECRET_DIR", Path("/nonexistent-wings3-secret"))


def test_ensure_maas_env_uses_module_defaults_without_mount(monkeypatch):
    wings3_env.ensure_maas_env()
    assert os.environ["MAAS_MODEL"] == wings3_env.DEFAULT_MAAS_MODEL
    assert os.environ["MAAS_BASE_URL"] == wings3_env.DEFAULT_MAAS_BASE_URL
    assert os.environ["MAAS_API_KEY"] == wings3_env.DEFAULT_MAAS_API_KEY


def test_ensure_maas_env_loads_from_secret_mount(tmp_path, monkeypatch):
    monkeypatch.setattr(wings3_env, "WINGS3_SECRET_DIR", tmp_path)
    (tmp_path / "MAAS_MODEL").write_text("gpt-oss-120b\n")
    (tmp_path / "MAAS_BASE_URL").write_text("https://example.test/v1\n")
    (tmp_path / "MAAS_API_KEY").write_text("sk-test\n")

    wings3_env.ensure_maas_env()

    assert os.environ["MAAS_MODEL"] == "gpt-oss-120b"
    assert os.environ["MAAS_BASE_URL"] == "https://example.test/v1"
    assert os.environ["MAAS_API_KEY"] == "sk-test"


def test_ensure_maas_env_fails_when_mount_missing_required_keys(tmp_path, monkeypatch):
    monkeypatch.setattr(wings3_env, "WINGS3_SECRET_DIR", tmp_path)
    (tmp_path / "JUDGE_MODEL").write_text("gpt-oss-120b\n")

    with pytest.raises(RuntimeError, match="MAAS_MODEL"):
        wings3_env.ensure_maas_env()


def test_ensure_maas_env_falls_back_to_judge_api_key(tmp_path, monkeypatch):
    monkeypatch.setattr(wings3_env, "WINGS3_SECRET_DIR", tmp_path)
    (tmp_path / "MAAS_MODEL").write_text("gpt-oss-120b\n")
    (tmp_path / "MAAS_BASE_URL").write_text("https://example.test/v1\n")
    (tmp_path / "JUDGE_API_KEY").write_text("sk-oai-test-key\n")

    wings3_env.ensure_maas_env()

    assert os.environ["MAAS_API_KEY"] == "sk-oai-test-key"


def test_print_secret_key_status_masks_values(capsys, monkeypatch):
    monkeypatch.setenv("MAAS_API_KEY", "sk-secret")
    wings3_env.print_secret_key_status("MAAS_API_KEY")
    assert capsys.readouterr().out.strip() == "MAAS_API_KEY=set"

    monkeypatch.setenv("MAAS_API_KEY", "unused")
    wings3_env.print_secret_key_status("MAAS_API_KEY")
    assert capsys.readouterr().out.strip() == "MAAS_API_KEY=unused"
