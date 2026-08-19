#!/usr/bin/env python3
"""WINGS3 Module 4: golden dataset + hybrid judges — CLI / warmup only.

Stage path is demo/notebooks/03_prod_eval_judges.ipynb (inline SHOW comments).
"""

from __future__ import annotations

import json
import logging
import os
import warnings
from pathlib import Path

warnings.filterwarnings("ignore")
logging.getLogger("mlflow").setLevel(logging.ERROR)

from dotenv import load_dotenv

load_dotenv(override=True)

import mlflow
from mlflow.genai.scorers import Correctness, Guidelines, scorer
from traced_agent import calculator, create_agent_graph, get_config_from_env

V2_PROMPT = (
    "You are a precise math assistant. Always use the calculator tool for arithmetic. "
    "State the numeric result clearly in your answer."
)

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


def configure_cluster_judge() -> str:
    """Point MLflow LLM judges at the in-cluster OpenAI-compatible vLLM."""
    base = os.environ.get(
        "MAAS_BASE_URL",
        "http://llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local:8080/v1",
    )
    os.environ["OPENAI_API_KEY"] = os.environ.get("MAAS_API_KEY", "unused")
    os.environ["OPENAI_BASE_URL"] = base
    os.environ["OPENAI_API_BASE"] = base
    model = os.environ.get("MAAS_MODEL", "llama-32-3b-instruct")
    return f"openai:/{model}"


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
        print(f"System prompt (v2):\n{V2_PROMPT}\n")
        _agent = create_agent_graph(
            get_config_from_env(), tools=[calculator], system_prompt=V2_PROMPT
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


def run_evaluation() -> dict:
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
    experiment_name = os.environ.get("MLFLOW_EXPERIMENT_NAME", "wings3-agent-eval-prod")
    experiment = mlflow.set_experiment(experiment_name)
    mlflow.langchain.autolog()

    records = load_golden_records()
    dataset = register_golden_dataset(records, experiment.experiment_id)

    judge_model = configure_cluster_judge()
    print(f"Judge model: {judge_model}")
    scorers = [
        contains_expected,
        Correctness(model=judge_model),
        Guidelines(
            name="numeric_and_clear",
            guidelines=[
                "The numeric result must appear as digits in the response.",
                "The response must state a single clear arithmetic result.",
            ],
            model=judge_model,
        ),
    ]

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


if __name__ == "__main__":
    run_evaluation()
