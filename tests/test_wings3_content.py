"""Unit tests for the WINGS3 content module (plain deck)."""

from __future__ import annotations

import sys
from pathlib import Path

WINGS3_ROOT = Path(__file__).resolve().parent.parent
WINGS3_SCRIPTS = WINGS3_ROOT / "scripts"
sys.path.insert(0, str(WINGS3_SCRIPTS))

from wings3_content import EXPECTED_SLIDE_COUNT, SLIDES  # noqa: E402

VALID_LAYOUTS = ("title", "section", "content")
DEMO_KEYS = ("demo_install", "demo_trace", "demo_eval")


def test_slide_count():
    assert len(SLIDES) == EXPECTED_SLIDE_COUNT
    assert EXPECTED_SLIDE_COUNT >= 23


def test_required_keys():
    for slide in SLIDES:
        assert slide["layout"] in VALID_LAYOUTS
        assert slide["title"].strip()
        assert slide["notes"].strip()
        assert "key" in slide
        if slide["layout"] == "content":
            assert isinstance(slide.get("bullets"), list)


def test_keys_unique():
    keys = [s["key"] for s in SLIDES]
    assert len(set(keys)) == len(keys)


def test_has_three_acts():
    blob = " ".join(s["title"] + " " + s["notes"] for s in SLIDES).lower()
    assert "install" in blob
    assert "trace" in blob
    assert "evaluat" in blob


def test_has_autolog():
    autolog = next(s for s in SLIDES if s["key"] == "autolog")
    assert "autolog" in autolog["notes"].lower() or "autolog" in autolog["title"].lower()


def test_has_demo_cues():
    demo_keys = [s["key"] for s in SLIDES if s["key"] in DEMO_KEYS]
    assert demo_keys == list(DEMO_KEYS)
    for slide in SLIDES:
        if slide["key"] in DEMO_KEYS:
            assert "PAUSE" in slide["notes"]
            assert "PAUSE" in slide["title"]


def test_has_mlflow_and_rhoai():
    blob = " ".join(s["title"] + " " + s["notes"] for s in SLIDES).lower()
    assert "mlflow" in blob
    assert "openshift ai" in blob or "rhoai" in blob


def test_personas_before_act1():
    keys = [s["key"] for s in SLIDES]
    assert keys.index("personas") < keys.index("install_steps")


def test_contrast_before_trace_demo():
    keys = [s["key"] for s in SLIDES]
    assert keys.index("contrast_manual") < keys.index("demo_trace")


def test_run_of_show_times_in_agenda_notes():
    agenda = next(s for s in SLIDES if s["key"] == "agenda")
    notes = agenda["notes"]
    assert "6 intro" in notes
    assert "8 install" in notes
    assert "22 tracing" in notes
    assert "15 evaluation" in notes
    assert "9 production" in notes


def test_walkthrough_index_matches_run_of_show():
    index = (WINGS3_ROOT / "walkthrough" / "index.md").read_text()
    assert "| Intro + personas | 6 |" in index
    assert "| 1 — Install | 8 |" in index
    assert "| 2 — Autolog tracing | 22 |" in index
    assert "| 3 — Evaluation | 15 |" in index
    assert "| Production + Q&A | 9 |" in index
    setup = (WINGS3_ROOT / "walkthrough" / "00-presenter-setup.md").read_text()
    assert "6" in setup and "22" in setup and "15" in setup and "9" in setup


def test_eval_notes_state_substring_scorer():
    eval_loop = next(s for s in SLIDES if s["key"] == "eval_loop")
    notes = eval_loop["notes"].lower()
    assert "substring" in notes
    demo_eval = next(s for s in SLIDES if s["key"] == "demo_eval")
    assert "substring" in demo_eval["notes"].lower()


def test_demo_trace_notes_error_then_details():
    demo = next(s for s in SLIDES if s["key"] == "demo_trace")
    notes = demo["notes"].lower()
    assert "error" in notes
    assert "details" in notes and "timeline" in notes
    assert "calculator" in notes


def test_walkthrough_docs_point_at_rhoai_34():
    index = (WINGS3_ROOT / "walkthrough" / "index.md").read_text()
    install = (WINGS3_ROOT / "walkthrough" / "01-install-mlflow.md").read_text()
    assert "self-managed/3.4/" in index
    assert "self-managed/3.4/" in install
    assert "self-managed/3.5/" not in index
    assert "self-managed/3.5/" not in install


def test_module2_single_workbench_path_and_trace_beat():
    mod2 = (WINGS3_ROOT / "walkthrough" / "02-agent-tracing-autolog.md").read_text()
    setup = (WINGS3_ROOT / "walkthrough" / "00-presenter-setup.md").read_text()
    assert "Create workbench" not in mod2
    assert "workbench-wings3-demo.yaml" in mod2
    assert "workbench-wings3-demo.yaml" in setup
    assert "Details & Timeline" in mod2
    assert "click the latest row" not in mod2.lower()


def test_module1_live_is_oc_get_not_apply():
    mod1 = (WINGS3_ROOT / "walkthrough" / "01-install-mlflow.md").read_text()
    setup = (WINGS3_ROOT / "walkthrough" / "00-presenter-setup.md").read_text()
    assert "oc apply -f manifests/mlflow-dev.yaml" not in mod1
    assert "oc apply -f manifests/mlflow-dev.yaml" in setup
    assert "08-dashboard-verify.png" in mod1
    assert "MLflow home" in mod1


def _notebook_source(name: str) -> str:
    import json

    nb = json.loads((WINGS3_ROOT / "demo" / "notebooks" / name).read_text())
    return "\n".join("".join(cell.get("source", [])) for cell in nb["cells"])


def test_eval_notebook_inlines_show_beats():
    blob = _notebook_source("02_eval_improvement.ipynb")
    assert "from evaluate_agent import" not in blob
    assert "# SHOW:" in blob
    assert "You are a helper. Answer briefly." in blob
    assert "Calculate 256 divided by 16" in blob
    assert "def contains_expected" in blob
    assert "mlflow.genai.evaluate" in blob
    mod3 = (WINGS3_ROOT / "walkthrough" / "03-workbench-evaluation.md").read_text()
    assert "SHOW:" in mod3


def test_tracing_notebook_inlines_show_beats():
    blob = _notebook_source("01_agent_tracing_autolog.ipynb")
    assert "from run_tracing_demo_autolog import" not in blob
    assert "# SHOW:" in blob
    assert "mlflow.langchain.autolog()" in blob
    assert "Calculate 256 divided by 16" in blob
    assert "def calculator" in blob
    mod2 = (WINGS3_ROOT / "walkthrough" / "02-agent-tracing-autolog.md").read_text()
    assert "01_agent_tracing_autolog.ipynb" in mod2
    assert "SHOW:" in mod2


def test_remaining_gaps_teaching_beats():
    title = next(s for s in SLIDES if s["key"] == "title")
    personas = next(s for s in SLIDES if s["key"] == "personas")
    hook = (title["notes"] + personas["notes"]).lower()
    assert "inject" in hook or "injected" in hook
    assert "workspace" in hook
    assert "native" in hook or "external" in hook

    mod1 = (WINGS3_ROOT / "walkthrough" / "01-install-mlflow.md").read_text()
    assert "Project" in mod1 and "Workspace" in mod1 and "Experiment" in mod1
    show, sep, appendix = mod1.partition("## Appendix")
    assert sep, "Module 1 must move laptop exports to an appendix"
    assert "oc whoami --show-token" not in show
    assert "oc whoami --show-token" in appendix
    assert "sandbox3159" not in show
    assert "<gateway_host>" not in show
    assert "partials/_attributes.md" in show

    attrs = (WINGS3_ROOT / "walkthrough" / "partials" / "_attributes.md").read_text()
    assert "`gateway_host`" in attrs
    assert "`mlflow_ui`" in attrs
    assert "/mlflow/health" in attrs
    assert "sandbox956" in attrs or "rh-ai.apps" in attrs
    env_example = (WINGS3_ROOT / "demo" / "agent-tracing" / ".env.example").read_text()
    assert "<gateway_host>" not in env_example

    mod2 = (WINGS3_ROOT / "walkthrough" / "02-agent-tracing-autolog.md").read_text()
    know = mod2.split("## Show")[0]
    assert "opendatahub.io/mlflow-instance" in know
    assert "extra-index-url" in know

    tracing_nb = _notebook_source("01_agent_tracing_autolog.ipynb")
    assert "traced_agent.py" in tracing_nb

    closing = next(s for s in SLIDES if s["key"] == "closing")
    notes = closing["notes"].lower()
    assert "backendstoreuri" in notes or "postgres" in notes
    assert "contains_expected" in notes or "gate" in notes

    agenda = next(s for s in SLIDES if s["key"] == "agenda")
    assert "WINGS3_ONE_QUERY" not in agenda["notes"]

    prod = WINGS3_ROOT / "manifests" / "mlflow-prod.example.yaml"
    assert prod.is_file()
    prod_text = prod.read_text()
    assert "postgresql" in prod_text.lower() or "backendStoreUriFrom" in prod_text
    assert "s3://" in prod_text


def test_traced_agent_is_calculator_only():
    text = (WINGS3_ROOT / "demo" / "agent-tracing" / "traced_agent.py").read_text()
    assert "DuckDuckGo" not in text
    assert "MCP_SERVER" not in text
    assert "create_agent_with_mcp" not in text
    assert "def calculator" in text
    assert "def create_agent_graph" in text
    assert "def get_config_from_env" in text


def test_screenshot_captions_are_this_cluster():
    mod1 = (WINGS3_ROOT / "walkthrough" / "01-install-mlflow.md").read_text()
    mod2 = (WINGS3_ROOT / "walkthrough" / "02-agent-tracing-autolog.md").read_text()
    mod3 = (WINGS3_ROOT / "walkthrough" / "03-workbench-evaluation.md").read_text()
    index = (WINGS3_ROOT / "walkthrough" / "index.md").read_text()
    assert "this cluster" in mod1
    assert "this cluster" in mod2
    assert "this cluster" in mod3
    assert "this cluster" in index
    assert "until recapture" not in mod1
    assert "until recapture" not in mod2
    assert "until recapture" not in mod3
    assert "until recapture" not in index
    for slide in SLIDES:
        for bullet in slide.get("bullets") or []:
            assert "until recapture" not in bullet
        notes = slide.get("notes") or ""
        assert "previous cluster" not in notes.lower()
        assert "until recapture" not in notes


def test_module4_in_deck():
    keys = [s["key"] for s in SLIDES]
    assert "judges" in keys
    assert "demo_judges" in keys
    judges = next(s for s in SLIDES if s["key"] == "judges")
    blob = (judges["title"] + judges["notes"] + " ".join(judges["bullets"])).lower()
    assert "math_golden" in blob
    assert "correctness" in blob
    demo = next(s for s in SLIDES if s["key"] == "demo_judges")
    assert "PAUSE" in demo["title"]
    assert "rationale" in demo["notes"].lower()
