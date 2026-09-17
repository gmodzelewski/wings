"""WINGS3 workbench LLM environment loading (no LangChain dependency)."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Iterable

WINGS3_SECRET_DIR = Path("/etc/wings3-judge-llm")
WINGS3_SECRET_KEYS = (
    "JUDGE_API_KEY",
    "JUDGE_BASE_URL",
    "JUDGE_MODEL",
    "MAAS_API_KEY",
    "MAAS_BASE_URL",
    "MAAS_MODEL",
)
DEFAULT_MAAS_MODEL = "llama-32-3b-instruct"
DEFAULT_MAAS_BASE_URL = (
    "http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1"
)
DEFAULT_MAAS_API_KEY = "unused"
_ENV_FILE = Path(__file__).resolve().parent / ".env"
_REQUIRED_MAAS_KEYS = ("MAAS_MODEL", "MAAS_BASE_URL")


def load_wings3_secret_env() -> None:
    """Load LLM config from the workbench-mounted Secret (RHOAI strips secretKeyRef env)."""
    if not WINGS3_SECRET_DIR.is_dir():
        return
    for key in WINGS3_SECRET_KEYS:
        path = WINGS3_SECRET_DIR / key
        if path.is_file():
            os.environ[key] = path.read_text().strip()


def ensure_maas_env(require_secret: bool = False) -> None:
    """Load agent LLM config from Secret mount, .env (local), then module defaults."""
    load_wings3_secret_env()

    if WINGS3_SECRET_DIR.is_dir():
        missing = [
            key
            for key in _REQUIRED_MAAS_KEYS
            if not os.environ.get(key) and not (WINGS3_SECRET_DIR / key).is_file()
        ]
        if missing:
            keys = ", ".join(missing)
            raise RuntimeError(
                f"{keys} missing from Secret wings3-judge-llm mount at {WINGS3_SECRET_DIR}. "
                "oc apply -f manifests/secret-wings3-judge-llm.yaml (or .example.yaml), "
                "then stop/start workbench wings3-demo."
            )
    elif not require_secret:
        try:
            from dotenv import load_dotenv

            load_dotenv(_ENV_FILE)
        except ImportError:
            pass

    os.environ.setdefault("MAAS_MODEL", DEFAULT_MAAS_MODEL)
    os.environ.setdefault("MAAS_BASE_URL", DEFAULT_MAAS_BASE_URL)
    os.environ.setdefault("MAAS_API_KEY", DEFAULT_MAAS_API_KEY)

    # Partial secret applies often set JUDGE_* only; agent shares the MaaS gateway key.
    judge_key = (os.environ.get("JUDGE_API_KEY") or "").strip()
    maas_key = (os.environ.get("MAAS_API_KEY") or "").strip()
    if judge_key and judge_key not in {"unused", "REPLACE_ME"} and (
        not maas_key or maas_key in {"unused", "REPLACE_ME"}
    ):
        os.environ["MAAS_API_KEY"] = judge_key

    judge_base = (os.environ.get("JUDGE_BASE_URL") or "").strip()
    maas_base = (os.environ.get("MAAS_BASE_URL") or "").strip()
    if judge_base and "REPLACE_AT_INSTALL" not in judge_base and not maas_base:
        os.environ["MAAS_BASE_URL"] = judge_base

    judge_model = (os.environ.get("JUDGE_MODEL") or "").strip()
    maas_model = (os.environ.get("MAAS_MODEL") or "").strip()
    if judge_model and maas_model in {"", DEFAULT_MAAS_MODEL} and judge_model != DEFAULT_MAAS_MODEL:
        os.environ["MAAS_MODEL"] = judge_model


def print_workbench_env(keys: Iterable[str]) -> None:
    """Print selected environment variables for notebook env cells."""
    for key in keys:
        print(f"{key}={os.environ.get(key)}")


def print_secret_key_status(key: str, label: str | None = None) -> None:
    """Print whether a secret API key is set without leaking the value."""
    value = (os.environ.get(key) or "").strip()
    name = label or key
    if value and value not in {"unused", "REPLACE_ME"}:
        print(f"{name}=set")
    elif value == "unused":
        print(f"{name}=unused")
    else:
        print(f"{name}=MISSING")
