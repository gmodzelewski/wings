#!/usr/bin/env python3
"""WINGS3: GenAI evaluation — CLI / bootstrap --warmup only.

Stage path is demo/notebooks/02_eval_improvement.ipynb (inline SHOW comments).
"""

from __future__ import annotations

import logging
import os
import warnings

warnings.filterwarnings("ignore")
logging.getLogger("mlflow").setLevel(logging.ERROR)

from dotenv import load_dotenv

load_dotenv(override=True)

import mlflow
from mlflow.genai.scorers import scorer
from traced_agent import calculator, create_agent_graph, get_config_from_env

PROMPTS = {
    "v1": "You are a helper. Answer briefly.",
    "v2": (
        "You are a precise math assistant. Always use the calculator tool for arithmetic. "
        "State the numeric result clearly in your answer."
    ),
}

EVAL_DATASET = [
    {"inputs": {"user_message": "What is 25 * 17 + 89?"}, "expectations": {"expected_answer": "514"}},
    {"inputs": {"user_message": "Calculate 256 divided by 16"}, "expectations": {"expected_answer": "16"}},
    {"inputs": {"user_message": "What is the square root of 144?"}, "expectations": {"expected_answer": "12"}},
    {"inputs": {"user_message": "Multiply 33 by 3 and add 1"}, "expectations": {"expected_answer": "100"}},
]


@scorer
def contains_expected(inputs: dict, outputs: str, expectations: dict) -> bool:
    if outputs is None or expectations is None:
        return False
    expected = str(expectations.get("expected_answer", ""))
    return expected.lower() in str(outputs).lower()


@scorer
def has_numeric_result(outputs: str) -> bool:
    if outputs is None:
        return False
    return any(c.isdigit() for c in str(outputs))


_agent = None


def prompt_version() -> str:
    version = os.environ.get("WINGS3_PROMPT_VERSION", "v1")
    if version not in PROMPTS:
        raise ValueError(f"Unknown WINGS3_PROMPT_VERSION={version!r}; use v1 or v2")
    return version


def get_agent():
    global _agent
    if _agent is None:
        version = prompt_version()
        prompt = PROMPTS[version]
        print(f"System prompt ({version}):\n{prompt}\n")
        config = get_config_from_env()
        _agent = create_agent_graph(config, tools=[calculator], system_prompt=prompt)
    return _agent


def predict_fn(user_message: str) -> str:
    agent = get_agent()
    try:
        result = agent.invoke({"messages": [{"role": "user", "content": user_message}]})
        return result["messages"][-1].content
    except Exception as exc:
        return f"Error: {exc}"


def run_evaluation() -> dict:
    k8s = os.environ.get("MLFLOW_K8S_INTEGRATION", "").lower() == "true"
    if not k8s and not os.environ.get("MLFLOW_TRACKING_TOKEN"):
        raise SystemExit(
            "Set MLFLOW_TRACKING_TOKEN=$(oc whoami --show-token) "
            "or run in a workbench with MLflow integration."
        )
    if not os.environ.get("MLFLOW_WORKSPACE"):
        raise SystemExit("Set MLFLOW_WORKSPACE=my-first-model")

    version = prompt_version()
    run_name = f"{version}-{'baseline' if version == 'v1' else 'improved-prompt'}"

    uri = os.environ.get("MLFLOW_TRACKING_URI")
    if not uri:
        raise SystemExit("MLFLOW_TRACKING_URI is not set")
    mlflow.set_tracking_uri(uri)
    experiment = os.environ.get("MLFLOW_EXPERIMENT_NAME", "wings3-agent-eval")
    mlflow.set_experiment(experiment)
    os.environ["MLFLOW_GENAI_EVAL_MAX_WORKERS"] = "1"
    from mlflow.utils.databricks_utils import is_in_cluster, is_in_databricks_notebook

    is_in_cluster()
    is_in_databricks_notebook()
    mlflow.langchain.autolog()

    global _agent
    _agent = None
    get_agent()

    print(f"Running evaluation: {run_name} ({len(EVAL_DATASET)} examples)")
    with mlflow.start_run(run_name=run_name):
        result = mlflow.genai.evaluate(
            data=EVAL_DATASET,
            predict_fn=predict_fn,
            scorers=[contains_expected, has_numeric_result],
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
