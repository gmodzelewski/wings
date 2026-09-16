#!/usr/bin/env python3
"""WINGS3 Module 4: golden dataset + hybrid judges — CLI / warmup only.

Stage path is demo/notebooks/03_prod_eval_judges.ipynb (inline SHOW comments).
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")
logging.getLogger("mlflow").setLevel(logging.ERROR)

from dotenv import load_dotenv

load_dotenv()

import mlflow
from mlflow.genai.scorers import Correctness, Guidelines, scorer
from prompts import (
    AGENT_PROMPT_REGISTRY_NAME,
    NUMERIC_AND_CLEAR_GUIDELINES,
    V2_AGENT_PROMPT,
)
from traced_agent import calculator, create_agent_graph, get_config_from_env

GOLDEN_PATH = Path(__file__).resolve().parent.parent / "datasets" / "math_golden.jsonl"
DATASET_NAME = "math_golden"
RUN_NAME = "v2-judged"


def load_golden_records(path: Path = GOLDEN_PATH) -> list[dict]:
    if not path.is_file():
        raise SystemExit(f"golden set not found: {path}")
    records = []
    with path.open() as fh:
        for line in fh:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


DEFAULT_JUDGE_BASE_URL = "https://maas-rhdp.apps.maas.redhatworkshops.io/v1"
DEFAULT_JUDGE_MODEL = "gpt-oss-120b"
JUDGE_SECRET_DIR = Path("/etc/wings3-judge-llm")


def load_judge_secret_env() -> None:
    """Copy Secret files into os.environ.

    RHOAI admission strips ``secretKeyRef`` / ``envFrom`` on the Notebook CR.
    The workbench mounts ``wings3-judge-llm`` at ``JUDGE_SECRET_DIR`` instead.
    """
    if not JUDGE_SECRET_DIR.is_dir():
        return
    for key in ("JUDGE_API_KEY", "JUDGE_BASE_URL", "JUDGE_MODEL"):
        if os.environ.get(key):
            continue
        path = JUDGE_SECRET_DIR / key
        if path.is_file():
            os.environ[key] = path.read_text().strip()


def configure_cluster_judge() -> str:
    """Point MLflow LLM judges at hosted MaaS via LiteLLM hosted_vllm.

    Agent stays on MAAS_* (in-cluster 3B). Judges use JUDGE_* from Secret
    ``wings3-judge-llm``. ``openai:/…`` always calls api.openai.com.
    """
    load_judge_secret_env()
    base = os.environ.get("JUDGE_BASE_URL") or DEFAULT_JUDGE_BASE_URL
    model = os.environ.get("JUDGE_MODEL") or DEFAULT_JUDGE_MODEL
    key = (os.environ.get("JUDGE_API_KEY") or os.environ.get("HOSTED_VLLM_API_KEY") or "").strip()
    if not key or key in {"unused", "REPLACE_ME"}:
        raise RuntimeError(
            "JUDGE_API_KEY is missing. Apply secret-wings3-judge-llm.yaml and "
            "workbench-wings3-demo.yaml (Secret is mounted at /etc/wings3-judge-llm; "
            "RHOAI strips secretKeyRef env). oc set env secret/wings3-judge-llm "
            "-n my-first-model JUDGE_API_KEY='…', then start the workbench."
        )
    os.environ["HOSTED_VLLM_API_BASE"] = base
    os.environ["HOSTED_VLLM_API_KEY"] = key
    print(f"HOSTED_VLLM_API_BASE={base}")
    print(f"JUDGE_MODEL={model}")
    print("JUDGE_API_KEY=set")
    return f"hosted_vllm:/{model}"


@scorer
def contains_expected(inputs: dict, outputs: str, expectations: dict) -> bool:
    if outputs is None or expectations is None:
        return False
    expected = str(expectations.get("expected_answer", ""))
    return expected.lower() in str(outputs).lower()


_agent = None


def get_agent():
    global _agent
    if _agent is None:
        print(f"System prompt (v2):\n{V2_AGENT_PROMPT}\n")
        _agent = create_agent_graph(
            get_config_from_env(), tools=[calculator], system_prompt=V2_AGENT_PROMPT
        )
    return _agent


def predict_fn(user_message: str) -> str:
    try:
        result = get_agent().invoke({"messages": [{"role": "user", "content": user_message}]})
        return result["messages"][-1].content
    except Exception as exc:
        return f"Error: {exc}"


def _drop_existing_records(dataset) -> None:
    """Remove stale rows so merge cannot keep expected_response beside expected_facts."""
    df = dataset.to_df()
    if df is None or df.empty:
        return
    col = "dataset_record_id" if "dataset_record_id" in df.columns else None
    if not col:
        return
    ids = df[col].tolist()
    if ids:
        dataset.delete_records(ids)


def register_golden_dataset(records: list[dict], experiment_id: str):
    """Create math_golden or replace its rows from git. Never silent-reuse stale expectations."""
    try:
        dataset = mlflow.genai.datasets.get_dataset(name=DATASET_NAME)
    except Exception:
        dataset = None

    if dataset is not None:
        delete_ds = getattr(mlflow.genai.datasets, "delete_dataset", None)
        deleted = False
        if delete_ds is not None:
            try:
                delete_ds(dataset_id=dataset.dataset_id)
                deleted = True
            except Exception:
                deleted = False
        if not deleted:
            _drop_existing_records(dataset)
            dataset = dataset.merge_records(records)
            print(
                f"Refreshed evaluation dataset {DATASET_NAME} from git "
                f"({len(records)} records)"
            )
            return dataset
        dataset = None

    dataset = mlflow.genai.datasets.create_dataset(
        name=DATASET_NAME,
        experiment_id=[experiment_id],
        tags={"wings3": "module-4", "kind": "golden"},
    )
    dataset = dataset.merge_records(records)
    print(f"Registered evaluation dataset {DATASET_NAME} ({len(records)} records)")
    return dataset


def register_prompts_and_judges(experiment_id: str, judge_model: str) -> tuple:
    """Register agent prompt + judges for MLflow UI catalogs."""
    mlflow.genai.register_prompt(
        name=AGENT_PROMPT_REGISTRY_NAME,
        template=[{"role": "system", "content": V2_AGENT_PROMPT}],
        commit_message="WINGS3 Module 4 agent system prompt",
        tags={"wings3": "module-4", "kind": "agent-system"},
    )
    print(f"Registered prompt: {AGENT_PROMPT_REGISTRY_NAME} — open MLflow → Prompts")

    correctness = Correctness(model=judge_model).register(
        name="correctness",
        experiment_id=experiment_id,
    )
    numeric_and_clear = Guidelines(
        name="numeric_and_clear",
        guidelines=NUMERIC_AND_CLEAR_GUIDELINES,
        model=judge_model,
    ).register(name="numeric_and_clear", experiment_id=experiment_id)
    print("Registered judges: correctness, numeric_and_clear — open MLflow → Judges")
    print("Eval-only (not in Judges catalog): contains_expected")
    return correctness, numeric_and_clear


def _ensure_mlflow_env() -> str:
    k8s = os.environ.get("MLFLOW_K8S_INTEGRATION", "").lower() == "true"
    if not k8s and not os.environ.get("MLFLOW_TRACKING_TOKEN"):
        raise SystemExit(
            "Set MLFLOW_TRACKING_TOKEN=$(oc whoami --show-token) "
            "or run in a workbench with MLflow integration."
        )
    if not os.environ.get("MLFLOW_WORKSPACE"):
        raise SystemExit("Set MLFLOW_WORKSPACE=my-first-model")

    uri = os.environ.get("MLFLOW_TRACKING_URI")
    if not uri:
        raise SystemExit("MLFLOW_TRACKING_URI is not set")
    mlflow.set_tracking_uri(uri)
    return uri


def register_catalog(register_only: bool = False) -> dict | None:
    """Register dataset, agent prompt, and judges. Optionally skip the full eval."""
    _ensure_mlflow_env()
    experiment_name = os.environ.get("MLFLOW_EXPERIMENT_NAME", "wings3-agent-eval-prod")
    experiment = mlflow.set_experiment(experiment_name)

    records = load_golden_records()
    dataset = register_golden_dataset(records, experiment.experiment_id)

    judge_model = configure_cluster_judge()
    print(f"Judge model: {judge_model}")
    correctness, numeric_and_clear = register_prompts_and_judges(
        experiment.experiment_id, judge_model
    )

    prompt_names = [p.name for p in mlflow.genai.search_prompts()]
    scorer_names = [s.name for s in mlflow.genai.list_scorers(experiment_id=experiment.experiment_id)]
    print(f"Prompts in registry: {prompt_names}")
    print(f"Judges in experiment: {scorer_names}")

    if register_only:
        return None

    scorers = [contains_expected, correctness, numeric_and_clear]
    return _run_eval(dataset, records, scorers)


def _run_eval(dataset, records: list[dict], scorers: list) -> dict:
    os.environ["MLFLOW_GENAI_EVAL_MAX_WORKERS"] = "1"
    from mlflow.utils.databricks_utils import is_in_cluster, is_in_databricks_notebook

    is_in_cluster()
    is_in_databricks_notebook()
    mlflow.langchain.autolog()

    global _agent
    _agent = None
    get_agent()

    print(f"Running evaluation: {RUN_NAME} ({len(records)} examples)")
    with mlflow.start_run(run_name=RUN_NAME):
        result = mlflow.genai.evaluate(
            data=dataset,
            predict_fn=predict_fn,
            scorers=scorers,
        )

    print("\nAggregated metrics:")
    for name, value in result.metrics.items():
        if isinstance(value, float):
            print(f"  {name}: {value:.2%}")
        else:
            print(f"  {name}: {value}")
    return result.metrics


def run_evaluation(register_only: bool = False) -> dict | None:
    return register_catalog(register_only=register_only)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="WINGS3 Module 4 golden set + hybrid judges")
    parser.add_argument(
        "--register-only",
        action="store_true",
        help="Register dataset, prompt, and judges without running v2-judged eval",
    )
    args = parser.parse_args(argv)
    run_evaluation(register_only=args.register_only)
    return 0


if __name__ == "__main__":
    sys.exit(main())
