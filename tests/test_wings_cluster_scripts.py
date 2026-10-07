"""Tests for WINGS cluster install, uninstall, and check scripts."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

WINGS_ROOT = Path(__file__).resolve().parent.parent
INSTALL = WINGS_ROOT / "scripts" / "install.sh"
UNINSTALL = WINGS_ROOT / "scripts" / "uninstall.sh"
CHECK = WINGS_ROOT / "scripts" / "check.sh"
CHECK_PY = WINGS_ROOT / "scripts" / "check_demo.py"


def _run(script: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(script), *args],
        check=False,
        capture_output=True,
        text=True,
    )


def test_workbench_clones_public_wings_repo():
    text = (WINGS_ROOT / "manifests" / "workbench-wings-demo.yaml").read_text()
    assert "https://github.com/gmodzelewski/wings.git" in text
    assert "--ServerApp.root_dir=/opt/app-root/src/wings" not in text
    assert "workingDir: /opt/app-root/src/wings" in text
    assert "initContainers:" in text
    assert INSTALL.is_file(), "missing scripts/install.sh"
    assert UNINSTALL.is_file(), "missing scripts/uninstall.sh"
    assert CHECK.is_file(), "missing scripts/check.sh"
    assert (WINGS_ROOT / "check.sh").is_file(), "missing check.sh"


def test_scripts_are_valid_bash():
    scripts = (
        INSTALL,
        UNINSTALL,
        CHECK,
        WINGS_ROOT / "scripts" / "submit_evalhub_eval_run.sh",
        WINGS_ROOT / "scripts" / "prestage_garak_before_after.sh",
        WINGS_ROOT / "scripts" / "rotate_maas_upstream_key.sh",
        WINGS_ROOT / "scripts" / "verify_hf_gated_access.sh",
    )
    for script in scripts:
        assert script.is_file(), f"missing {script}"
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
    assert "wings_llm_storage_uri" in text
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
    sys.path.insert(0, str(WINGS_ROOT / "scripts"))
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
    manifest = (WINGS_ROOT / "manifests" / "evalhub-instance.yaml").read_text()
    lib = (WINGS_ROOT / "scripts" / "wings_lib.sh").read_text()
    check_py = (WINGS_ROOT / "scripts" / "check_demo.py").read_text()

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
    assert "ensure_maas_gateway_api_key_secret" in lib
    assert "wings-maas-gateway-api-key" in lib
    assert "resolve_evalhub_openai_base_url" in lib
    assert "maas-gateway." in lib


def test_evalhub_tenant_label_helper():
    sys.path.insert(0, str(WINGS_ROOT / "scripts"))
    from check_demo import namespace_has_evalhub_tenant_label

    assert namespace_has_evalhub_tenant_label(
        "kubernetes.io/metadata.name=my-first-model evalhub.trustyai.opendatahub.io/tenant="
    )
    assert not namespace_has_evalhub_tenant_label("kubernetes.io/metadata.name=my-first-model")


def test_judge_secret_and_mount_helpers():
    sys.path.insert(0, str(WINGS_ROOT / "scripts"))
    from check_demo import judge_api_key_populated, workbench_has_judge_mount

    assert judge_api_key_populated("dGVzdA==")
    assert not judge_api_key_populated("")
    assert not judge_api_key_populated("   ")
    assert workbench_has_judge_mount(
        ["/opt/app-root/src", "/etc/wings-judge-llm"],
        ["wings-judge-llm"],
    )
    assert not workbench_has_judge_mount(
        ["/opt/app-root/src"],
        ["wings-judge-llm"],
    )


def test_servingruntime_version_current_logic():
    sys.path.insert(0, str(WINGS_ROOT / "scripts"))
    from check_demo import servingruntime_version_current

    assert servingruntime_version_current("v0.24.0", "v0.24.0")
    assert not servingruntime_version_current("v0.24.0", "v0.9.1.0")
    assert not servingruntime_version_current("v0.24.0", "")
    assert not servingruntime_version_current("", "v0.24.0")


def test_mlflow_workspace_proxy_wired_into_install_and_check():
    manifest = (WINGS_ROOT / "manifests" / "mlflow-workspace-proxy.yaml").read_text()
    lib = (WINGS_ROOT / "scripts" / "wings_lib.sh").read_text()
    check_py = (WINGS_ROOT / "scripts" / "check_demo.py").read_text()
    evalhub = (WINGS_ROOT / "manifests" / "evalhub-instance.yaml").read_text()

    assert "kind: Service" in manifest
    assert "name: wings-mlflow-ws-proxy" in manifest
    assert "X-MLflow-Workspace" in manifest
    # evalhub-instance.yaml routes MLFLOW_TRACKING_URI through this Service, so
    # install must create it and uninstall --all must remove it.
    assert "wings-mlflow-ws-proxy" in evalhub
    assert "mlflow-workspace-proxy.yaml" in lib
    assert "mlflow workspace proxy" in check_py


def test_submit_evalhub_eval_run_supports_garak_and_v1_endpoint():
    script = WINGS_ROOT / "scripts" / "submit_evalhub_eval_run.sh"
    text = script.read_text()
    assert "GARAK_BENCHMARKS=" in text
    assert "quick" in text
    assert 'provider_id": "garak"' in text
    assert "normalize_openai_endpoint" in text
    assert "*/v1" in text
    assert "wings-maas-upstream-api-key" in text
    assert "secret_ref" in text
    assert "MODEL_AUTH_SECRET" in text
    assert '"experiment"' in text
    assert "wings-evalhub-garak" in text
    assert "--experiment" in text
    assert "lower_is_better" in text
    assert "attack_success_rate" in text
    assert "infer_endpoint_kind" in text
    assert '"description"' in text
    assert "target:%s" in text
    assert "wait_and_log_mlflow_endpoint_params" in text
    assert "model_url" in text
    assert "target_endpoint_kind" in text
    assert "log-parameter" in text
    # Post-run MLflow param logging is script-side (curl from EvalHub pod; no python3 there).
    assert "runs/log-parameter" in text
    assert "base64" in text
    result = _run(script, "--help")
    assert result.returncode == 0, result.stderr
    assert "quick" in result.stdout
    assert "--provider" in result.stdout
    assert "--experiment" in result.stdout
    assert "--wait" in result.stdout
    assert "model_url" in result.stdout


def test_garak_demo_json_uses_evalhub_api_format():
    import json

    data = json.loads((WINGS_ROOT / "demo" / "evalhub" / "jobs" / "garak-demo.json").read_text())
    assert data["benchmarks"][0]["provider_id"] == "garak"
    assert data["benchmarks"][0]["id"] == "quick"
    assert data["model"]["url"].endswith("/v1")
    assert data["experiment"]["name"] == "wings-evalhub-garak"
    assert data["benchmarks"][0]["primary_score"]["lower_is_better"] is True
    assert data["benchmarks"][0]["primary_score"]["metric"] == "attack_success_rate"
    assert data["pass_criteria"]["threshold"] == 0.3
    assert "description" in data
    assert "tags" in data
    assert "garak" in data["tags"]
    assert any(t.startswith("target:") for t in data["tags"])
    assert "model_url" in data["notes"]
    assert "target_endpoint_kind" in data["notes"]


def test_evalhub_garak_walkthrough_documents_v1_endpoint():
    text = (WINGS_ROOT / "walkthrough" / "05-evalhub-garak.md").read_text()
    assert "404 Not Found" in text
    assert "/v1" in text
    assert "submit_evalhub_eval_run.sh --benchmark quick" in text
    assert "List view vs detail" in text
    assert "**Completed**" in text and "attack success rate" in text.lower()
    assert "run ID: None" in text
    assert "GenAI → Traces" in text
    assert "wings-evalhub-garak" in text
    assert "lower_is_better" in text
    assert "target:unguarded" in text
    assert "model_url" in text
    assert "target_endpoint_kind" in text


def test_configmap_manifest_has_endpoint_hostname():
    text = (WINGS_ROOT / "manifests" / "configmap-wings-llm-endpoint.yaml").read_text()
    assert "llama-32-3b-instruct-predictor.my-first-model.svc.cluster.local" in text
    assert "openai_base_url" in text


def test_instantiate_servingruntime_sets_name_and_namespace():
    sys.path.insert(0, str(WINGS_ROOT / "scripts"))
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
    text = (WINGS_ROOT / "manifests" / "inferenceservice-llama-32-3b-instruct.yaml").read_text()
    assert "oci://quay.io/redhat-ai-services/modelcar-catalog:llama-3.2-3b-instruct" in text
    assert "nvidia.com/gpu" in text
    assert "runtime: llama-32-3b-instruct" in text
    assert "tool-call-parser" in text


def test_judge_secret_is_empty_key_and_workbench_mounts_it():
    secret = (WINGS_ROOT / "manifests" / "secret-wings-judge-llm.example.yaml").read_text()
    workbench = (WINGS_ROOT / "manifests" / "workbench-wings-demo.yaml").read_text()
    assert "name: wings-judge-llm" in secret
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
    assert "mountPath: /etc/wings-judge-llm" in workbench
    assert "secretName: wings-judge-llm" in workbench
    assert "mountPath: /etc/wings-maas-upstream-api-key" in workbench
    assert "secretName: wings-maas-upstream-api-key" in workbench
    assert "secretKeyRef:" not in workbench
    assert "envFrom:" not in workbench


def test_maas_external_model_manifests():
    external = (WINGS_ROOT / "manifests" / "maas-external-model-gpt-oss-120b.yaml").read_text()
    modelref = (WINGS_ROOT / "manifests" / "maas-modelref-gpt-oss-120b.yaml").read_text()
    auth_sub = (WINGS_ROOT / "manifests" / "maas-auth-subscription-redhat-maas.yaml").read_text()
    lib = (WINGS_ROOT / "scripts" / "wings_lib.sh").read_text()
    install = INSTALL.read_text()
    uninstall = UNINSTALL.read_text()
    check_py = CHECK_PY.read_text()
    assert "kind: ExternalModel" in external
    assert "maas-rhdp.apps.maas.redhatworkshops.io" in external
    assert "targetModel: gpt-oss-120b" in external
    assert "credentialRef:" in external
    assert "wings-maas-upstream-api-key" in external
    assert "opendatahub.io/genai-asset" in external
    assert "opendatahub.io/dashboard" in external
    assert "label_maas_external_model_assets" in lib
    assert "externalproviders.inference.opendatahub.io" in lib
    # gen-ai-aa-custom-model-endpoints was an earlier workaround ConfigMap that
    # duplicated these models in Gen AI Studio -> AI asset endpoints with a
    # "(workshop)" suffix stuck in "Unknown" status (it referenced a secret,
    # endpoint-api-key-1, that was never created). Native CR labelling via
    # label_maas_external_model_assets now covers this -- the manifest file is
    # gone and install.sh actively deletes the ConfigMap on clusters that still
    # have it from an earlier run.
    assert not (WINGS_ROOT / "manifests" / "gen-ai-aa-custom-model-endpoints.yaml").exists()
    assert "delete configmap gen-ai-aa-custom-model-endpoints" in lib
    assert "kind: MaaSModelRef" in modelref
    assert "kind: ExternalModel" in modelref
    assert "kind: MaaSSubscription" in auth_sub
    assert "kind: MaaSAuthPolicy" in auth_sub
    assert "redhat-maas" in auth_sub
    assert "gpt-oss-20b" in auth_sub
    assert "llama-scout-17b" in auth_sub
    assert "qwen36-35b-a3b" in auth_sub
    for model in ("gpt-oss-120b", "gpt-oss-20b", "llama-scout-17b", "qwen36-35b-a3b"):
        em = (WINGS_ROOT / "manifests" / f"maas-external-model-{model}.yaml").read_text()
        mr = (WINGS_ROOT / "manifests" / f"maas-modelref-{model}.yaml").read_text()
        assert f"name: {model}" in em
        assert f"targetModel: {model}" in em
        assert "credentialRef:" in em
        assert "name: wings-maas-upstream-api-key" in em
        assert f"name: {model}" in mr
    assert "MAAS_CATALOG_MODELS" in lib
    assert "maas-external-model-${model}.yaml" in lib or 'maas-external-model-${model}.yaml' in lib
    assert "inference.llm-d.ai/ipp-managed" in lib
    upstream_example = (
        WINGS_ROOT / "manifests" / "secret-wings-maas-upstream-api-key.example.yaml"
    ).read_text()
    assert "inference.llm-d.ai/ipp-managed" in upstream_example
    assert "inference.networking.k8s.io/bbr-managed" in upstream_example
    assert "WINGS_MAAS_CATALOG_MODELS" in check_py
    assert "gpt-oss-20b" in check_py
    assert "llama-scout-17b" in check_py
    assert "qwen36-35b-a3b" in check_py
    assert "qwen36-35b-a3b" in lib
    assert "enable_maas" in install
    assert "purge_maas_resources" in uninstall
    assert "check_maas_external_model" in check_py
    assert "check_maas_modelref" in check_py
    kuadrant = (WINGS_ROOT / "manifests" / "kuadrant-dev.yaml").read_text()
    gateway = (WINGS_ROOT / "manifests" / "maas-default-gateway.yaml").read_text()
    gw_cfg = (WINGS_ROOT / "manifests" / "maas-default-gateway-config.yaml").read_text()
    assert "kind: Kuadrant" in kuadrant
    assert "redhat-ai-gateway-infra" in gateway
    assert "maas-default-gateway-config" in gateway
    assert "parametersRef" in gateway
    assert "type: ClusterIP" in gw_cfg
    assert "maas-default-gateway-config.yaml" in lib
    assert "maas-default-gateway-route.yaml" in lib
    assert "ensure_maas_gateway_route" in lib
    assert "LoadBalancer address pending" in lib
    gw_route = (WINGS_ROOT / "manifests" / "maas-default-gateway-route.yaml").read_text()
    assert "kind: Route" in gw_route
    assert "maas-default-gateway" in gw_route
    assert "reencrypt" in gw_route
    assert "enable_maas()" in lib
    assert "enable_genai_studio" in lib
    assert "enable_ogx_dsc" in lib
    assert "deploy_ogx_server" in lib
    assert "enable_mcplifecycle" in lib
    assert "ensure_servicemesh" in lib
    assert "ensure_genai_dashboard_prereqs" in lib
    assert "ensure_maas_dashboard_prereqs" not in lib
    assert '"guardrails":true' in lib
    assert "guardrails" in lib
    assert '"agentsCatalog":true' in lib
    assert '"agentOps":true' in lib
    assert '"agentConfigManagement":true' in lib
    assert '"aiAssetCustomEndpoints":true' in lib
    assert "purge_ogx_resources" in lib
    ogx_server = (WINGS_ROOT / "manifests" / "ogx-server-wings.yaml").read_text()
    ogx_pg = (WINGS_ROOT / "manifests" / "ogx-postgres-dev.yaml").read_text()
    sm3 = (WINGS_ROOT / "manifests" / "servicemesh3-operator.yaml").read_text()
    sm3_istio = (WINGS_ROOT / "manifests" / "servicemesh3-istio.yaml").read_text()
    assert "kind: OGXServer" in ogx_server
    assert "wings-ogx" in ogx_server
    assert "wings-ogx-postgres" in ogx_pg
    assert "servicemeshoperator3" in sm3
    assert "kind: OperatorGroup" not in sm3
    assert "kind: Istio" in sm3_istio
    assert "ensure_kuadrant" in lib
    assert "ensure_connectivity_link_operator" in lib
    assert "wait_for_connectivity_link" in lib
    assert "connectivity-link-operator.yaml" in lib
    rhcl = (WINGS_ROOT / "manifests" / "connectivity-link-operator.yaml").read_text()
    assert "name: rhcl-operator" in rhcl
    assert "source: redhat-operators" in rhcl
    assert "kind: OperatorGroup" not in rhcl
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
    assert "check_agents_catalog" in check_py
    assert "check_evaluations_nav" in check_py
    assert "check_maas_ui" in check_py
    assert "check_kuadrant_ready" in check_py
    assert "maas.redhatworkshops.io" in check_py


def test_observability_check_demo_pure_logic():
    sys.path.insert(0, str(WINGS_ROOT / "scripts"))
    from check_demo import (
        dsci_metrics_storage_configured,
        limitador_uses_redis_storage,
        maas_telemetry_enabled,
        maas_usage_logging_enabled,
        uwm_config_enables_workload,
    )

    assert dsci_metrics_storage_configured('{"retention":"15d","size":"5Gi"}')
    assert not dsci_metrics_storage_configured("{}")
    assert not dsci_metrics_storage_configured("")

    assert uwm_config_enables_workload("enableUserWorkload: true\n")
    assert not uwm_config_enables_workload("enableUserWorkload: false\n")
    assert not uwm_config_enables_workload("")

    assert maas_telemetry_enabled('{"enabled":true,"metrics":{"captureUser":false}}')
    assert not maas_telemetry_enabled('{"enabled":false}')
    assert not maas_telemetry_enabled("")

    assert maas_usage_logging_enabled('{"usageLogging":true,"limitadorScrapeInterval":"30s"}')
    assert not maas_usage_logging_enabled('{"usageLogging":false}')
    assert not maas_usage_logging_enabled("")

    assert limitador_uses_redis_storage('{"redis":{"configSecretRef":{"name":"redis-config"}}}')
    assert not limitador_uses_redis_storage("{}")
    assert not limitador_uses_redis_storage("")


def test_observability_stack_manifests_and_wiring():
    lib = (WINGS_ROOT / "scripts" / "wings_lib.sh").read_text()
    install = INSTALL.read_text()
    uninstall = UNINSTALL.read_text()
    check_py = CHECK_PY.read_text()

    coo = (WINGS_ROOT / "manifests" / "cluster-observability-operator.yaml").read_text()
    otel = (WINGS_ROOT / "manifests" / "opentelemetry-operator.yaml").read_text()
    tempo = (WINGS_ROOT / "manifests" / "tempo-operator.yaml").read_text()
    loki = (WINGS_ROOT / "manifests" / "loki-operator.yaml").read_text()
    uwm_ref = (WINGS_ROOT / "manifests" / "cluster-monitoring-config.yaml").read_text()
    minio = (WINGS_ROOT / "manifests" / "maas-usage-logging-minio.yaml").read_text()
    minio_secret = (
        WINGS_ROOT / "manifests" / "maas-usage-logging-minio-secret.yaml"
    ).read_text()
    lokistack = (
        WINGS_ROOT / "manifests" / "maas-usage-logging-lokistack.yaml"
    ).read_text()
    redis = (WINGS_ROOT / "manifests" / "limitador-redis.yaml").read_text()
    redis_secret = (WINGS_ROOT / "manifests" / "limitador-redis-secret.yaml").read_text()

    # Operator manifests: dedicated namespace + OperatorGroup + Subscription.
    assert "openshift-cluster-observability-operator" in coo
    assert "kind: Subscription" in coo
    assert "kind: OperatorGroup" in coo
    assert "openshift-opentelemetry-operator" in otel
    assert "opentelemetry-product" in otel
    assert "openshift-tempo-operator" in tempo
    assert "tempo-product" in tempo
    assert "openshift-operators-redhat" in loki
    assert "REPLACE_LOKI_CHANNEL" in loki
    assert "enableUserWorkload: true" in uwm_ref

    # Usage-logging backend (MinIO + LokiStack) and Redis-backed Limitador.
    assert "kind: Deployment" in minio
    assert "kind: Secret" in minio_secret
    assert "kind: LokiStack" in lokistack
    assert "gp3-csi" in lokistack or "storageClassName" in lokistack
    assert "redis-limitador" in redis
    assert "kind: Secret" in redis_secret
    assert "redis-config" in redis_secret

    # wings_lib.sh orchestration + namespace vars.
    for var in (
        "DSCI_NAME",
        "MONITORING_NS",
        "COO_NS",
        "OTEL_NS",
        "TEMPO_NS",
        "LOKI_OPERATOR_NS",
        "REDIS_LIMITADOR_NS",
    ):
        assert var in lib
    assert "ensure_cluster_observability_operator" in lib
    assert "ensure_opentelemetry_operator" in lib
    assert "ensure_tempo_operator" in lib
    assert "ensure_loki_operator" in lib
    assert "discover_loki_channel" in lib
    assert "catalogSource" in lib  # avoid ambiguous community/redhat packagemanifest
    assert "ensure_user_workload_monitoring" in lib
    assert "merge_uwm_enabled_flag" in lib
    assert "patch_dsci_observability_metrics" in lib
    assert "wait_for_dsci_monitoring_ready" in lib
    assert "ensure_observability_operators" in lib
    assert "deploy_usage_logging_backend" in lib
    assert "wait_for_lokistack_ready" in lib
    assert "enable_observability" in lib
    assert '"observabilityDashboard":true' in lib
    assert "enable_maas_tenant_telemetry" in lib
    assert "enable_maas_usage_logging" in lib
    assert "ensure_limitador_redis" in lib
    assert "enable_maas_observability" in lib
    assert "discover_maastenantconfig_name" in lib
    assert "discover_maas_config_name" in lib

    # Uninstall symmetry: every new install step has a purge counterpart.
    assert "purge_maas_tenant_telemetry" in lib
    assert "purge_maas_usage_logging" in lib
    assert "purge_usage_logging_backend" in lib
    assert "purge_limitador_redis" in lib
    assert "revert_dsci_observability_metrics" in lib
    assert "purge_observability_operators" in lib
    assert "revert_user_workload_monitoring" in lib
    assert "purge_observability_resources" in lib

    # install.sh / uninstall.sh wiring.
    assert "enable_observability" in install
    assert "WINGS_SKIP_OBSERVABILITY" in install
    assert "purge_observability_resources" in uninstall

    # check_demo.py coverage for the new stack.
    assert "check_coo_operator" in check_py
    assert "check_otel_operator" in check_py
    assert "check_tempo_operator" in check_py
    assert "check_loki_operator" in check_py
    assert "check_dsci_observability_metrics" in check_py
    assert "check_observability_dashboard_flag" in check_py
    assert "check_user_workload_monitoring" in check_py
    assert "check_lokistack_ready" in check_py
    assert "check_maas_tenant_telemetry" in check_py
    assert "check_maas_usage_logging" in check_py
    assert "check_limitador_redis" in check_py

    # Shared-namespace safety: openshift-operators-redhat (loki-operator.yaml)
    # is a Red Hat-conventional namespace other operators may already use.
    # Install/uninstall must never take ownership of (or delete) a namespace
    # WINGS didn't create -- see apply_operator_manifest_ns_aware /
    # purge_operator_manifest_ns_aware below.
    assert "manifest_minus_namespace_doc" in lib
    assert "namespace_owned_by_wings" in lib
    assert "apply_operator_manifest_ns_aware" in lib
    assert "purge_operator_manifest_ns_aware" in lib
    assert lib.count("apply_operator_manifest_ns_aware") >= 5  # def + 4 call sites
    assert lib.count("purge_operator_manifest_ns_aware") >= 5  # def + 4 call sites


def test_reinstall_restarts_pods_with_stale_watch_caches_or_db_connections():
    """Regression test for two real bugs found while testing a full
    `uninstall.sh --all` + `install.sh` cycle live:

    1. `maas-api` (redhat-ai-gateway-infra) runs its DB schema migration on
       startup. After `uninstall.sh --all` wipes `wings-maas-postgres` and
       install.sh recreates it empty, the long-running maas-api pod (never
       restarted by RHOAI's modelsAsAService component) kept serving against
       a connection pool with no migrated schema -- API key minting failed
       with "relation \"api_keys\" does not exist".
    2. `payload-processing`/`payload-pre-processing` (openshift-ingress) keep
       an in-memory ExternalModel/ExternalProvider watch cache used to
       resolve the gateway inference path to a provider + injected upstream
       credential. After the ExternalModel CRs are deleted and recreated
       with new UIDs, the long-running pods kept serving a stale cache --
       inference calls 404'd (path never resolved) or 401'd ("no api key
       passed in", credential never injected) even though the CRs reported
       Ready.

    Both were fixed by detecting a fresh (re)create in `ensure_maas_postgres`
    / `apply_maas_manifests` and issuing `oc rollout restart` for the
    corresponding long-running deployment. Verify the wiring exists.
    """
    lib = (WINGS_ROOT / "scripts" / "wings_lib.sh").read_text()
    assert "fresh_db" in lib
    assert "rollout restart deployment/maas-api" in lib
    assert "restart_payload_processing_stack" in lib
    assert "rollout restart deployment/payload-processing deployment/payload-pre-processing" in lib
    assert "created_any" in lib


def test_purge_operator_manifest_ns_aware_never_deletes_foreign_namespace():
    """Regression test for a real bug found while testing uninstall.sh --all live:
    purge_observability_operators used to unconditionally `oc delete -f
    loki-operator.yaml`, which includes a Namespace doc for
    openshift-operators-redhat -- a namespace other, unrelated operators
    commonly share. Verify the ns-aware helpers only ever touch resources
    WINGS itself owns, using fake kubectl-shaped manifests and a stub `oc`
    (no live cluster required).
    """
    lib = (WINGS_ROOT / "scripts" / "wings_lib.sh").read_text()
    assert "apply_operator_manifest_ns_aware" in lib

    manifest = """apiVersion: v1
kind: Namespace
metadata:
  name: shared-ns
  labels:
    app.kubernetes.io/part-of: wings-demo
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: og
  namespace: shared-ns
spec: {}
"""
    # manifest_minus_namespace_doc must drop only the Namespace document.
    script = f"source {WINGS_ROOT / 'scripts' / 'wings_lib.sh'}; manifest_minus_namespace_doc"
    proc = subprocess.run(
        ["bash", "-c", script],
        input=manifest,
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr
    assert "kind: Namespace" not in proc.stdout
    assert "kind: OperatorGroup" in proc.stdout


def test_presenter_docs_point_at_cluster_scripts():
    setup = (WINGS_ROOT / "walkthrough" / "00-presenter-setup.md").read_text()
    readme = (WINGS_ROOT / "README.md").read_text()
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
    assert "walkthrough/00-presenter-setup.md" in readme
    assert "walkthrough/customer-ui-click-script.md" in readme
