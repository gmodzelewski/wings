#!/usr/bin/env python3
"""WINGS3: LangGraph agent with mlflow.langchain.autolog() — CLI / bootstrap --warmup only.

Stage path is demo/notebooks/01_agent_tracing_autolog.ipynb (inline SHOW comments).
"""

from __future__ import annotations

import logging
import os
import sys
import warnings

warnings.filterwarnings("ignore")
logging.getLogger("mlflow").setLevel(logging.ERROR)

from dotenv import load_dotenv

load_dotenv(override=True)

import urllib3

urllib3.disable_warnings()

if not os.environ.get("MLFLOW_WORKSPACE"):
    print("ERROR: set MLFLOW_WORKSPACE=my-first-model")
    sys.exit(1)
k8s = os.environ.get("MLFLOW_K8S_INTEGRATION", "").lower() == "true"
if not k8s and not os.environ.get("MLFLOW_TRACKING_TOKEN"):
    print("ERROR: set MLFLOW_TRACKING_TOKEN=$(oc whoami --show-token) or use a workbench")
    sys.exit(1)

import mlflow
from traced_agent import calculator, create_agent_graph, get_config_from_env


QUERIES = [
    "Calculate 256 divided by 16",
    "What is 25 times 17?",
    "What is the square root of 144?",
]


def main() -> None:
    uri = os.environ.get("MLFLOW_TRACKING_URI")
    if not uri:
        print("ERROR: MLFLOW_TRACKING_URI is not set")
        sys.exit(1)
    experiment = os.environ.get("MLFLOW_EXPERIMENT_NAME", "wings3-agent-tracing")
    mlflow.set_tracking_uri(uri)
    mlflow.set_experiment(experiment)
    mlflow.langchain.autolog()

    config = get_config_from_env()
    agent = create_agent_graph(config, tools=[calculator])
    print(f"MLflow: {uri}")
    print(f"Workspace: {os.environ['MLFLOW_WORKSPACE']}")
    print(f"Experiment: {experiment}")
    print(f"Model: {config.model}")

    queries = QUERIES[:1] if os.environ.get("WINGS3_ONE_QUERY") else QUERIES
    for i, query in enumerate(queries, 1):
        print(f"\n--- Query {i}: {query}")
        try:
            result = agent.invoke({"messages": [{"role": "user", "content": query}]})
            print(result["messages"][-1].content)
        except Exception as exc:
            print(f"Error: {exc}")

    print("\nDone → MLflow UI → Traces tab")


if __name__ == "__main__":
    main()
