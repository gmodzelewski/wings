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
    from check_demo import (
        check_evalhub_instance,
        check_evalhub_pod,
        check_evaluations_nav,
        run_checks,
    )

    assert callable(run_checks)
    assert callable(check_evalhub_pod)
    assert callable(check_evalhub_instance)
    assert callable(check_evaluations_nav)


def test_evalhub_instance_manifest_and_install_wiring():
    manifest = (WINGS3_ROOT / "manifests" / "evalhub-instance.yaml").read_text()
    lib = (WINGS3_ROOT / "scripts" / "wings3_lib.sh").read_text()
    check_py = (WINGS3_ROOT / "scripts" / "check_demo.py").read_text()

    assert "kind: EvalHub" in manifest
    assert "database:" in manifest
    assert "type: sqlite" in manifest
    assert "lm-evaluation-harness" in manifest
    assert "tenancy: single" in manifest
    assert "/mlflow" in manifest
    assert "evalhub-instance.yaml" in lib
    assert "evalhub.trustyai.opendatahub.io/tenant-" in lib
    assert "check_evalhub_instance" in check_py
    assert "check_evaluations_nav" in check_py
    assert "check_evalhub_model_auth" in check_py
    assert "check_evalhub_endpoint_url" in check_py
    assert "check_evalhub_endpoint_url" in check_py
    assert "evalhub_cr_is_single_tenant" in check_py
    assert "disableLMEval" in lib
    assert "ensure_evalhub_model_auth_secret" in lib
    assert "resolve_evalhub_openai_base_url" in lib


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


def test_submit_evalhub_eval_run_supports_garak_and_v1_endpoint():
    script = WINGS3_ROOT / "scripts" / "submit_evalhub_eval_run.sh"
    text = script.read_text()
    assert "GARAK_BENCHMARKS=" in text
    assert "quick" in text
    assert 'provider_id": "garak"' in text
    assert "normalize_openai_endpoint" in text
    assert "*/v1" in text
    assert "wings3-maas-upstream-api-key" in text
    assert "secret_ref" in text
    assert "MODEL_AUTH_SECRET" in text
    result = _run(script, "--help")
    assert result.returncode == 0, result.stderr
    assert "quick" in result.stdout
    assert "--provider" in result.stdout


def test_garak_demo_json_uses_evalhub_api_format():
    import json

    data = json.loads((WINGS3_ROOT / "demo" / "evalhub" / "jobs" / "garak-demo.json").read_text())
    assert data["benchmarks"][0]["provider_id"] == "garak"
    assert data["benchmarks"][0]["id"] == "quick"
    assert data["model"]["url"].endswith("/v1")


def test_evalhub_garak_walkthrough_documents_v1_endpoint():
    text = (WINGS3_ROOT / "walkthrough" / "05-evalhub-garak.md").read_text()
    assert "404 Not Found" in text
    assert "/v1" in text
    assert "submit_evalhub_eval_run.sh --benchmark quick" in text
    assert "List view vs detail" in text
    assert "**Completed**" in text and "attack success rate" in text.lower()


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
    secret = (WINGS3_ROOT / "manifests" / "secret-wings3-judge-llm.example.yaml").read_text()
    workbench = (WINGS3_ROOT / "manifests" / "workbench-wings3-demo.yaml").read_text()
    assert "name: wings3-judge-llm" in secret
    assert "JUDGE_BASE_URL:" in secret
    assert "/gpt-oss-120b/v1" in secret
    assert "maas.redhatworkshops.io" not in secret
    assert "JUDGE_MODEL:" in secret
    assert "gpt-oss-120b" in secret
    assert "MAAS_MODEL:" in secret
    assert "llama-32-3b-instruct" in secret
    assert "MAAS_BASE_URL:" in secret
    assert "MAAS_API_KEY:" in secret
    assert 'JUDGE_API_KEY: ""' in secret
    assert "sk-" not in secret
    assert "mountPath: /etc/wings3-judge-llm" in workbench
    assert "secretName: wings3-judge-llm" in workbench
    assert "mountPath: /etc/wings3-maas-upstream-api-key" in workbench
    assert "secretName: wings3-maas-upstream-api-key" in workbench
    assert "secretKeyRef:" not in workbench
    assert "envFrom:" not in workbench


def test_maas_external_model_manifests():
    external = (WINGS3_ROOT / "manifests" / "maas-external-model-gpt-oss-120b.yaml").read_text()
    modelref = (WINGS3_ROOT / "manifests" / "maas-modelref-gpt-oss-120b.yaml").read_text()
    auth_sub = (WINGS3_ROOT / "manifests" / "maas-auth-subscription-gpt-oss-120b.yaml").read_text()
    lib = (WINGS3_ROOT / "scripts" / "wings3_lib.sh").read_text()
    install = INSTALL.read_text()
    uninstall = UNINSTALL.read_text()
    check_py = CHECK_PY.read_text()
    assert "kind: ExternalModel" in external
    assert "maas-rhdp.apps.maas.redhatworkshops.io" in external
    assert "targetModel: gpt-oss-120b" in external
    assert "credentialRef:" in external
    assert "wings3-maas-upstream-api-key" in external
    assert "opendatahub.io/genai-asset" in external
    assert "opendatahub.io/dashboard" in external
    assert "kind: MaaSModelRef" in modelref
    assert "kind: ExternalModel" in modelref
    assert "kind: MaaSSubscription" in auth_sub
    assert "kind: MaaSAuthPolicy" in auth_sub
    assert "wings3-gpt-oss-120b" in auth_sub
    assert "gpt-oss-20b" in auth_sub
    assert "llama-scout-17b" in auth_sub
    for model in ("gpt-oss-120b", "gpt-oss-20b", "llama-scout-17b"):
        em = (WINGS3_ROOT / "manifests" / f"maas-external-model-{model}.yaml").read_text()
        mr = (WINGS3_ROOT / "manifests" / f"maas-modelref-{model}.yaml").read_text()
        assert f"name: {model}" in em
        assert f"targetModel: {model}" in em
        assert "credentialRef:" in em
        assert "name: wings3-maas-upstream-api-key" in em
        assert f"name: {model}" in mr
    assert "MAAS_CATALOG_MODELS" in lib
    assert "maas-external-model-${model}.yaml" in lib or 'maas-external-model-${model}.yaml' in lib
    assert "WINGS3_MAAS_CATALOG_MODELS" in check_py
    assert "gpt-oss-20b" in check_py
    assert "llama-scout-17b" in check_py
    assert "enable_maas" in install
    assert "purge_maas_resources" in uninstall
    assert "check_maas_external_model" in check_py
    assert "check_maas_modelref" in check_py
    kuadrant = (WINGS3_ROOT / "manifests" / "kuadrant-dev.yaml").read_text()
    gateway = (WINGS3_ROOT / "manifests" / "maas-default-gateway.yaml").read_text()
    assert "kind: Kuadrant" in kuadrant
    assert "redhat-ai-gateway-infra" in gateway
    assert "enable_maas()" in lib
    assert "enable_genai_studio" in lib
    assert "enable_ogx_dsc" in lib
    assert "deploy_ogx_server" in lib
    assert "enable_mcplifecycle" in lib
    assert "ensure_servicemesh" in lib
    assert "ensure_genai_dashboard_prereqs" in lib
    assert "ensure_maas_dashboard_prereqs" in lib
    assert "purge_ogx_resources" in lib
    ogx_server = (WINGS3_ROOT / "manifests" / "ogx-server-wings3.yaml").read_text()
    ogx_pg = (WINGS3_ROOT / "manifests" / "ogx-postgres-dev.yaml").read_text()
    sm3 = (WINGS3_ROOT / "manifests" / "servicemesh3-operator.yaml").read_text()
    sm3_istio = (WINGS3_ROOT / "manifests" / "servicemesh3-istio.yaml").read_text()
    assert "kind: OGXServer" in ogx_server
    assert "wings3-ogx" in ogx_server
    assert "wings3-ogx-postgres" in ogx_pg
    assert "servicemeshoperator3" in sm3
    assert "kind: OperatorGroup" not in sm3
    assert "kind: Istio" in sm3_istio
    assert "ensure_kuadrant" in lib
    assert "ensure_authorino_tls" in lib
    assert "reconcile_maas_subscription" in lib
    assert "sync_llm_endpoint_configmap" in lib
    assert "purge_maas_resources()" in lib
    assert "enable_maas" in install
    assert "enable_genai_studio" in install
    assert "purge_maas_resources" in uninstall
    assert "purge_ogx_resources" in uninstall
    assert "check_secret_data_key" in check_py
    assert "agent secret MAAS_MODEL" in check_py
    assert "check_maas_crds" in check_py
    assert "check_ogx_managed" in check_py
    assert "check_ogx_server" in check_py
    assert "check_mcp_catalog" in check_py
    assert "check_evaluations_nav" in check_py
    assert "check_maas_ui" in check_py
    assert "check_kuadrant_ready" in check_py
    assert "maas.redhatworkshops.io" in check_py


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
