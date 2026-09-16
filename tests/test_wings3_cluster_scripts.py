"""Tests for WINGS3 cluster install, uninstall, and check scripts."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

WINGS3_ROOT = Path(__file__).resolve().parent.parent
INSTALL = WINGS3_ROOT / "scripts" / "install.sh"
UNINSTALL = WINGS3_ROOT / "scripts" / "uninstall.sh"
CHECK = WINGS3_ROOT / "scripts" / "check.sh"
CHECK_PY = WINGS3_ROOT / "scripts" / "check_demo.py"


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
    assert "--ServerApp.root_dir=/opt/app-root/src/wings" not in text
    assert "workingDir: /opt/app-root/src/wings" in text
    assert "initContainers:" in text
    assert INSTALL.is_file(), "missing scripts/install.sh"
    assert UNINSTALL.is_file(), "missing scripts/uninstall.sh"
    assert CHECK.is_file(), "missing scripts/check.sh"
    assert (WINGS3_ROOT / "check.sh").is_file(), "missing check.sh"


def test_scripts_are_valid_bash():
    for script in (INSTALL, UNINSTALL, CHECK):
        result = subprocess.run(
            ["bash", "-n", str(script)],
            check=False,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, f"{script.name}: {result.stderr}"


def test_install_help_documents_skip_llm_only():
    result = _run(INSTALL, "--help")
    assert result.returncode == 0, result.stderr
    text = result.stdout.lower()
    assert "--skip-llm" in text
    assert "wings3_llm_storage_uri" in text
    assert "--warmup" not in text
    assert "--dry-run" not in text
    assert "--force-llm" not in text
    assert "--prestage-evalhub" not in text


def test_uninstall_help_documents_all_only():
    result = _run(UNINSTALL, "--help")
    assert result.returncode == 0, result.stderr
    text = result.stdout.lower()
    assert "--all" in text
    assert "inferenceservice" in text or "llm" in text
    assert "--dry-run" not in text
    assert "--purge-llm" not in text
    assert "--purge-evalhub" not in text
    assert "--yes" not in text


def test_check_help_documents_skip_llm():
    result = _run(CHECK, "--help")
    assert result.returncode == 0, result.stderr
    text = result.stdout.lower()
    assert "--skip-llm" in text or "skip" in text


def test_check_demo_py_imports_and_evalhub_logic():
    sys.path.insert(0, str(WINGS3_ROOT / "scripts"))
    from check_demo import check_evalhub_instance, check_evalhub_pod, run_checks

    assert callable(run_checks)
    assert callable(check_evalhub_pod)
    assert callable(check_evalhub_instance)


def test_evalhub_instance_manifest_and_install_wiring():
    manifest = (WINGS3_ROOT / "manifests" / "evalhub-instance.yaml").read_text()
    lib = (WINGS3_ROOT / "scripts" / "wings3_lib.sh").read_text()
    check_py = (WINGS3_ROOT / "scripts" / "check_demo.py").read_text()

    assert "kind: EvalHub" in manifest
    assert "database:" in manifest
    assert "type: sqlite" in manifest
    assert "lm-evaluation-harness" in manifest
    assert "tenancy: single" in manifest
    assert "evalhub-instance.yaml" in lib
    assert "evalhub.trustyai.opendatahub.io/tenant-" in lib
    assert "check_evalhub_instance" in check_py
    assert "evalhub_cr_is_single_tenant" in check_py


def test_evalhub_tenant_label_helper():
    sys.path.insert(0, str(WINGS3_ROOT / "scripts"))
    from check_demo import namespace_has_evalhub_tenant_label

    assert namespace_has_evalhub_tenant_label(
        "kubernetes.io/metadata.name=my-first-model evalhub.trustyai.opendatahub.io/tenant="
    )
    assert not namespace_has_evalhub_tenant_label("kubernetes.io/metadata.name=my-first-model")


def test_judge_secret_and_mount_helpers():
    sys.path.insert(0, str(WINGS3_ROOT / "scripts"))
    from check_demo import judge_api_key_populated, workbench_has_judge_mount

    assert judge_api_key_populated("dGVzdA==")
    assert not judge_api_key_populated("")
    assert not judge_api_key_populated("   ")
    assert workbench_has_judge_mount(
        ["/opt/app-root/src", "/etc/wings3-judge-llm"],
        ["wings3-judge-llm"],
    )
    assert not workbench_has_judge_mount(
        ["/opt/app-root/src"],
        ["wings3-judge-llm"],
    )


def test_servingruntime_version_current_logic():
    sys.path.insert(0, str(WINGS3_ROOT / "scripts"))
    from check_demo import servingruntime_version_current

    assert servingruntime_version_current("v0.24.0", "v0.24.0")
    assert not servingruntime_version_current("v0.24.0", "v0.9.1.0")
    assert not servingruntime_version_current("v0.24.0", "")
    assert not servingruntime_version_current("", "v0.24.0")


def test_discover_dsc_components_py_imports():
    sys.path.insert(0, str(WINGS3_ROOT / "scripts"))
    from discover_dsc_components import discover_evalhub_component, discover_garak_component

    components = {
        "trustyai": {"managementState": "Managed"},
        "dashboard": {"managementState": "Managed"},
    }
    assert discover_evalhub_component(components) == "trustyai"
    assert discover_garak_component(components) == ""


def test_lmevaljob_manifest_targets_openai_endpoint():
    text = (WINGS3_ROOT / "manifests" / "evalhub-demo-lmevaljob.yaml").read_text()
    assert "trustyai.opendatahub.io/v1alpha1" in text
    assert "kind: LMEvalJob" in text
    assert "openai-chat-completions" in text
    assert "llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local" in text
    assert "gsm8k" in text


def test_submit_evalhub_dry_run_mentions_lmevaljob():
    script = WINGS3_ROOT / "scripts" / "submit_evalhub_demo_jobs.sh"
    result = _run(script, "--dry-run")
    assert result.returncode == 0, result.stderr
    out = result.stdout.lower()
    assert "evalhub-demo-lmevaljob.yaml" in out
    assert "lmevaljob" in out


def test_configmap_manifest_has_endpoint_hostname():
    text = (WINGS3_ROOT / "manifests" / "configmap-wings3-llm-endpoint.yaml").read_text()
    assert "llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local" in text
    assert "openai_base_url" in text


def test_instantiate_servingruntime_sets_name_and_namespace():
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
    assert "mountPath: /etc/wings3-judge-llm" in workbench
    assert "secretName: wings3-judge-llm" in workbench
    assert "secretKeyRef:" not in workbench
    assert "envFrom:" not in workbench


def test_presenter_docs_point_at_cluster_scripts():
    setup = (WINGS3_ROOT / "walkthrough" / "00-presenter-setup.md").read_text()
    readme = (WINGS3_ROOT / "README.md").read_text()
    assert "./install.sh" in setup
    assert "./uninstall.sh" in setup
    assert "./check.sh" in setup
    assert "./install.sh" in readme
    assert "./uninstall.sh" in readme
    assert "./check.sh" in readme
    assert "--skip-llm" in setup
    assert "--all" in setup
    assert "bootstrap.sh" not in setup
    assert "teardown.sh" not in setup
    assert "discover_evalhub.sh" not in setup
    assert "05-evalhub-garak.md" in readme
