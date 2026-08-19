"""Tests for WINGS3 cluster bootstrap and teardown scripts."""

from __future__ import annotations

import subprocess
from pathlib import Path

WINGS3_ROOT = Path(__file__).resolve().parent.parent
BOOTSTRAP = WINGS3_ROOT / "scripts" / "bootstrap.sh"
TEARDOWN = WINGS3_ROOT / "scripts" / "teardown.sh"


def _run(script: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(script), *args],
        check=False,
        capture_output=True,
        text=True,
    )


def test_workbench_clones_public_wings_repo():
    text = (WINGS3_ROOT / "manifests" / "workbench-wings3-demo.yaml").read_text()
    assert "https://github.com/gmodzelewski/wings.git" in text
    assert "--ServerApp.root_dir=/opt/app-root/src/wings" in text
    assert "workingDir: /opt/app-root/src/wings" in text
    assert "initContainers:" in text
    assert BOOTSTRAP.is_file(), "missing scripts/bootstrap.sh"
    assert TEARDOWN.is_file(), "missing scripts/teardown.sh"


def test_scripts_are_valid_bash():
    for script in (BOOTSTRAP, TEARDOWN):
        result = subprocess.run(
            ["bash", "-n", str(script)],
            check=False,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"{script.name}: {result.stderr}"


def test_bootstrap_help_documents_warmup_and_dry_run():
    result = _run(BOOTSTRAP, "--help")
    assert result.returncode == 0, result.stderr
    text = result.stdout.lower()
    assert "--warmup" in text
    assert "--dry-run" in text
    assert "--skip-pip" in text
    assert "--skip-llm" in text
    assert "inferenceservice" in text


def test_teardown_help_documents_shared_cluster_safe_default():
    result = _run(TEARDOWN, "--help")
    assert result.returncode == 0, result.stderr
    text = result.stdout.lower()
    assert "--dry-run" in text
    assert "--purge-mlflow" in text
    assert "--purge-project" in text
    assert "--purge-llm" in text
    assert "operator" in text
    assert "--yes" in text


def test_bootstrap_dry_run_applies_manifests_and_the_llm():
    result = _run(BOOTSTRAP, "--dry-run")
    assert result.returncode == 0, result.stderr
    out = result.stdout
    assert "mlflow-dev.yaml" in out
    assert "namespace-my-first-model.yaml" in out
    assert "workbench-wings3-demo.yaml" in out
    assert "secret-wings3-judge-llm.yaml" in out
    assert "mlflowoperator" in out.lower()
    assert "vllm-cuda-runtime-template" in out
    assert "inferenceservice-llama-32-3b-instruct.yaml" in out
    assert "Recreate" in out
    assert "would not create InferenceService" not in out
    assert "requirements.txt" in out
    assert "--extra-index-url" in out
    assert "git clone" in out
    assert "WINGS3_ONE_QUERY" not in out


def test_bootstrap_dry_run_skip_llm_does_not_instantiate_runtime():
    result = _run(BOOTSTRAP, "--dry-run", "--skip-llm")
    assert result.returncode == 0, result.stderr
    out = result.stdout
    assert "skip llm" in out.lower()
    assert "instantiate ServingRuntime" not in out
    assert "would not create InferenceService" not in out


def test_bootstrap_dry_run_warmup_runs_one_query_and_v1_eval():
    result = _run(BOOTSTRAP, "--dry-run", "--warmup")
    assert result.returncode == 0, result.stderr
    out = result.stdout
    assert "WINGS3_ONE_QUERY" in out
    assert "run_tracing_demo_autolog.py" in out
    assert "WINGS3_PROMPT_VERSION=v1" in out
    assert "evaluate_agent.py" in out


def test_teardown_dry_run_default_deletes_workbench_only():
    result = _run(TEARDOWN, "--dry-run")
    assert result.returncode == 0, result.stderr
    out = result.stdout.lower()
    assert "notebook" in out
    assert "wings3-demo" in out
    assert "pvc" in out
    assert "serviceaccount" in out or " sa " in f" {out} "
    assert "delete mlflow" not in out
    assert "inferenceservice" not in out or "keep" in out
    assert "removed" not in out


def test_teardown_dry_run_purge_mlflow_deletes_cr_not_operator():
    result = _run(TEARDOWN, "--dry-run", "--purge-mlflow")
    assert result.returncode == 0, result.stderr
    out = result.stdout.lower()
    assert "mlflow" in out
    assert "delete" in out
    assert "mlflowoperator" not in out or "would not" in out


def test_teardown_purge_project_requires_yes():
    result = _run(TEARDOWN, "--purge-project")
    assert result.returncode != 0
    assert "--yes" in (result.stdout + result.stderr).lower()


def test_teardown_dry_run_purge_project_deletes_namespace():
    result = _run(TEARDOWN, "--dry-run", "--purge-project", "--yes")
    assert result.returncode == 0, result.stderr
    out = result.stdout.lower()
    assert "my-first-model" in out
    assert "llama-32-3b-instruct" in out


def test_teardown_dry_run_purge_llm_deletes_is_and_runtime():
    result = _run(TEARDOWN, "--dry-run", "--purge-llm")
    assert result.returncode == 0, result.stderr
    out = result.stdout.lower()
    assert "inferenceservice" in out
    assert "servingruntime" in out
    assert "delete" in out


def test_instantiate_servingruntime_sets_name_and_namespace():
    import sys

    sys.path.insert(0, str(WINGS3_ROOT / "scripts"))
    from instantiate_servingruntime import servingruntime_from_template

    template = {
        "parameters": [{"name": "NAME", "value": "placeholder"}],
        "objects": [
            {
                "kind": "ServingRuntime",
                "metadata": {"name": "${NAME}", "namespace": "redhat-ods-applications"},
                "spec": {"containers": [{"image": "registry.example/vllm:${NAME}"}]},
            }
        ],
    }
    runtime = servingruntime_from_template(template, "llama-32-3b-instruct", "my-first-model")
    assert runtime["metadata"]["name"] == "llama-32-3b-instruct"
    assert runtime["metadata"]["namespace"] == "my-first-model"
    assert "llama-32-3b-instruct" in runtime["spec"]["containers"][0]["image"]


def test_inferenceservice_manifest_has_catalog_storage():
    text = (WINGS3_ROOT / "manifests" / "inferenceservice-llama-32-3b-instruct.yaml").read_text()
    assert "oci://quay.io/redhat-ai-services/modelcar-catalog:llama-3.2-3b-instruct" in text
    assert "nvidia.com/gpu" in text
    assert "runtime: llama-32-3b-instruct" in text
    assert "tool-call-parser" in text


def test_judge_secret_is_empty_key_and_workbench_mounts_it():
    secret = (WINGS3_ROOT / "manifests" / "secret-wings3-judge-llm.yaml").read_text()
    workbench = (WINGS3_ROOT / "manifests" / "workbench-wings3-demo.yaml").read_text()
    assert "name: wings3-judge-llm" in secret
    assert "JUDGE_BASE_URL:" in secret
    assert "maas-rhdp.apps.maas.redhatworkshops.io/v1" in secret
    assert "JUDGE_MODEL:" in secret
    assert "gpt-oss-120b" in secret
    assert "deepseek-r1-distill-qwen-14b" in secret
    assert "llama-scout-17b" in secret
    assert 'JUDGE_API_KEY: ""' in secret
    assert "sk-" not in secret
    assert "envFrom:" in workbench
    assert "name: wings3-judge-llm" in workbench
    assert "optional: true" in workbench


def test_presenter_docs_point_at_cluster_scripts():
    setup = (WINGS3_ROOT / "walkthrough" / "00-presenter-setup.md").read_text()
    readme = (WINGS3_ROOT / "README.md").read_text()
    assert "scripts/bootstrap.sh" in setup
    assert "scripts/teardown.sh" in setup
    assert "scripts/bootstrap.sh" in readme
    assert "scripts/teardown.sh" in readme
    assert "vllm-cuda-runtime-template" in setup
    assert "--skip-llm" in setup
    assert "--purge-llm" in setup
