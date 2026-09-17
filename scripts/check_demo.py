#!/usr/bin/env python3
"""Health checks for the WINGS3 demo cluster install."""

from __future__ import annotations

import base64
import os
import subprocess
import sys
from dataclasses import dataclass


@dataclass
class CheckResult:
    name: str
    ok: bool
    detail: str = ""


NOTEBOOK_API = os.environ.get("WINGS3_NOTEBOOK_API", "notebook.kubeflow.org")


def _oc(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["oc", *args],
        capture_output=True,
        text=True,
        check=False,
    )


def check_oc_login() -> CheckResult:
    result = _oc(["whoami"])
    if result.returncode == 0 and result.stdout.strip():
        return CheckResult("oc login", True, result.stdout.strip())
    return CheckResult("oc login", False, result.stderr.strip() or "not logged in")


def check_mlflow_cr(mlflow_ns: str) -> CheckResult:
    for args in ([], ["-n", mlflow_ns]):
        result = _oc(["get", "mlflow", "mlflow", *args])
        if result.returncode == 0:
            return CheckResult("mlflow cr", True)
    return CheckResult("mlflow cr", False, "mlflow/mlflow not found")


def check_pod_ready(ns: str, pattern: str, label: str) -> CheckResult:
    result = _oc(["get", "pods", "-n", ns, "--no-headers"])
    if result.returncode != 0:
        return CheckResult(label, False, f"cannot list pods in {ns}")
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        name, ready, status = parts[0], parts[1], parts[2]
        if pattern in name and status == "Running" and ready.split("/")[0] == ready.split("/")[-1]:
            wait = _oc(["wait", "--for=condition=Ready", f"pod/{name}", "-n", ns, "--timeout=10s"])
            if wait.returncode == 0:
                return CheckResult(label, True, name)
    return CheckResult(label, False, f"no Ready pod matching {pattern}")


def check_notebook_ready(project: str, workbench: str) -> CheckResult:
    result = _oc(
        [
            "get",
            NOTEBOOK_API,
            workbench,
            "-n",
            project,
            "-o",
            "jsonpath={.status.conditions[?(@.type==\"Ready\")].status}",
        ]
    )
    if result.returncode == 0 and result.stdout.strip() == "True":
        return CheckResult(f"workbench {workbench}", True)
    pod = check_pod_ready(project, workbench, f"workbench {workbench}")
    return pod


def check_inferenceservice(project: str, model: str) -> CheckResult:
    result = _oc(
        [
            "get",
            "inferenceservice",
            model,
            "-n",
            project,
            "-o",
            "jsonpath={.status.conditions[?(@.type==\"Ready\")].status}",
        ]
    )
    if result.returncode == 0 and result.stdout.strip() == "True":
        return CheckResult(f"inferenceservice {model}", True)
    if result.returncode != 0:
        return CheckResult(f"inferenceservice {model}", False, "not found")
    return CheckResult(f"inferenceservice {model}", False, "not Ready")


def check_evalhub_pod(mlflow_ns: str) -> CheckResult:
    for pattern in ("eval-hub", "evalhub", "evaluation"):
        result = check_pod_ready(mlflow_ns, pattern, "evalhub ui pod")
        if result.ok:
            return result
    return CheckResult("evalhub ui pod", False, "no Ready pod matching eval-hub/evalhub/evaluation")


def namespace_has_evalhub_tenant_label(labels: str) -> bool:
    return "evalhub.trustyai.opendatahub.io/tenant" in labels


def evalhub_cr_is_single_tenant(project: str) -> bool:
    result = _oc(
        [
            "get",
            "evalhub",
            "evalhub",
            "-n",
            project,
            "-o",
            "jsonpath={.spec.tenancy}",
        ]
    )
    return result.returncode == 0 and result.stdout.strip() == "single"


def check_evalhub_instance(project: str) -> CheckResult:
    cr = _oc(["get", "evalhub", "evalhub", "-n", project])
    if cr.returncode != 0:
        return CheckResult(
            "evalhub instance",
            False,
            f"evalhub/evalhub missing in {project} — oc apply -f manifests/evalhub-instance.yaml",
        )

    if not evalhub_cr_is_single_tenant(project):
        return CheckResult(
            "evalhub instance",
            False,
            f"evalhub/evalhub in {project} must have spec.tenancy: single",
        )

    label_result = _oc(["get", "namespace", project, "--show-labels"])
    if label_result.returncode == 0 and namespace_has_evalhub_tenant_label(label_result.stdout):
        return CheckResult(
            "evalhub instance",
            False,
            f"remove tenant label: oc label namespace {project} evalhub.trustyai.opendatahub.io/tenant-",
        )

    phase = _oc(
        [
            "get",
            "evalhub",
            "evalhub",
            "-n",
            project,
            "-o",
            "jsonpath={.status.phase}",
        ]
    )
    phase_value = phase.stdout.strip() if phase.returncode == 0 else ""
    if phase_value and phase_value not in ("Running", "Ready"):
        return CheckResult(
            "evalhub instance",
            False,
            f"evalhub/evalhub phase={phase_value}",
        )

    pod = check_pod_ready(project, "evalhub", "evalhub server pod")
    if not pod.ok:
        return CheckResult(
            "evalhub server pod",
            False,
            f"no Ready evalhub pod in {project}",
        )
    return CheckResult("evalhub instance", True, pod.detail or "evalhub")


def servingruntime_version_current(template_version: str, sr_version: str) -> bool:
    if not template_version:
        return False
    return bool(sr_version) and sr_version == template_version


def check_servingruntime_version(
    project: str,
    model: str,
    mlflow_ns: str,
    template: str,
) -> CheckResult:
    template_result = _oc(
        [
            "get",
            "template",
            template,
            "-n",
            mlflow_ns,
            "-o",
            "jsonpath={.objects[0].metadata.annotations.opendatahub\\.io/runtime-version}",
        ]
    )
    template_version = template_result.stdout.strip()
    if template_result.returncode != 0 or not template_version:
        return CheckResult(
            f"servingruntime {model}",
            False,
            f"template {template} version not found",
        )

    sr_result = _oc(
        [
            "get",
            "servingruntime",
            model,
            "-n",
            project,
            "-o",
            "jsonpath={.metadata.annotations.opendatahub\\.io/runtime-version}",
        ]
    )
    sr_version = sr_result.stdout.strip()
    if sr_result.returncode != 0 or not sr_version:
        return CheckResult(
            f"servingruntime {model}",
            False,
            f"missing; template is {template_version}",
        )
    if servingruntime_version_current(template_version, sr_version):
        return CheckResult(f"servingruntime {model}", True, sr_version)
    return CheckResult(
        f"servingruntime {model}",
        False,
        f"{sr_version} != template {template_version}",
    )


def check_resource(kind: str, name: str, ns: str, label: str) -> CheckResult:
    result = _oc(["get", kind, name, "-n", ns])
    if result.returncode == 0:
        return CheckResult(label, True)
    return CheckResult(label, False, f"{kind}/{name} missing in {ns}")


def judge_api_key_populated(key_b64: str) -> bool:
    return bool(key_b64.strip())


def workbench_has_judge_mount(mount_paths: list[str], volume_secret_names: list[str]) -> bool:
    return "/etc/wings3-judge-llm" in mount_paths and "wings3-judge-llm" in volume_secret_names


def decode_secret_value(b64: str) -> str | None:
    if not b64.strip():
        return None
    try:
        return base64.b64decode(b64).decode()
    except (ValueError, UnicodeDecodeError):
        return None


def check_secret_data_key(project: str, key: str, label: str) -> CheckResult:
    result = _oc(
        [
            "get",
            "secret",
            "wings3-judge-llm",
            "-n",
            project,
            "-o",
            f"jsonpath={{.data.{key}}}",
        ]
    )
    if result.returncode != 0:
        return CheckResult(label, False, "secret/wings3-judge-llm missing")
    value = decode_secret_value(result.stdout)
    if not value:
        return CheckResult(label, False, f"empty {key}")
    return CheckResult(label, True, value)


def check_judge_secret_key(project: str) -> CheckResult:
    result = _oc(
        [
            "get",
            "secret",
            "wings3-judge-llm",
            "-n",
            project,
            "-o",
            "jsonpath={.data.JUDGE_API_KEY}",
        ]
    )
    if result.returncode != 0:
        return CheckResult(
            "judge secret JUDGE_API_KEY",
            False,
            "secret/wings3-judge-llm missing",
        )
    if judge_api_key_populated(result.stdout):
        return CheckResult("judge secret JUDGE_API_KEY", True)
    return CheckResult(
        "judge secret JUDGE_API_KEY",
        False,
        "empty — oc set env secret/wings3-judge-llm -n "
        f"{project} JUDGE_API_KEY='<token>'",
    )


def crd_exists(suffix: str) -> bool:
    result = _oc(["api-resources", "-o", "name"])
    if result.returncode != 0:
        return False
    return any(suffix in line for line in result.stdout.splitlines())


def check_maas_crds() -> CheckResult:
    has_external = crd_exists("externalmodels.maas.opendatahub.io")
    has_modelref = crd_exists("maasmodelrefs.maas.opendatahub.io") or crd_exists(
        "maasmodelrefs.models.opendatahub.io"
    )
    if has_external and has_modelref:
        return CheckResult("maas crds", True)
    return CheckResult(
        "maas crds",
        False,
        "externalmodels/maasmodelrefs CRDs missing — enable modelsAsService on DSC",
    )


def maas_resource_ready(kind: str, name: str, ns: str) -> bool:
    phase = _oc(
        [
            "get",
            kind,
            name,
            "-n",
            ns,
            "-o",
            "jsonpath={.status.phase}",
        ]
    )
    if phase.returncode == 0 and phase.stdout.strip() == "Ready":
        return True
    ready = _oc(
        [
            "get",
            kind,
            name,
            "-n",
            ns,
            "-o",
            "jsonpath={.status.conditions[?(@.type==\"Ready\")].status}",
        ]
    )
    return ready.returncode == 0 and ready.stdout.strip() == "True"


def check_maas_external_model(project: str, model: str) -> CheckResult:
    if not crd_exists("externalmodels.maas.opendatahub.io"):
        return CheckResult(
            f"externalmodel {model}",
            False,
            "MaaS CRDs not installed",
        )
    exists = _oc(["get", "externalmodels.maas.opendatahub.io", model, "-n", project])
    if exists.returncode != 0:
        return CheckResult(
            f"externalmodel {model}",
            False,
            f"externalmodel/{model} missing in {project}",
        )
    phase = _oc(
        [
            "get",
            "externalmodels.maas.opendatahub.io",
            model,
            "-n",
            project,
            "-o",
            "jsonpath={.metadata.name}",
        ]
    )
    if phase.returncode == 0 and phase.stdout.strip() == model:
        return CheckResult(f"externalmodel {model}", True)
    return CheckResult(f"externalmodel {model}", False, "not found")


def genai_studio_optional() -> bool:
    return os.environ.get("WINGS3_SKIP_OGX", "0") == "1"


def mcp_catalog_optional() -> bool:
    return os.environ.get("WINGS3_SKIP_MCP", "0") == "1"


def check_ogx_managed() -> CheckResult:
    dsc = os.environ.get("WINGS3_DSC_NAME", "default-dsc")
    has_crd = crd_exists("ogxservers.ogx.io")
    state = _oc(
        [
            "get",
            "datasciencecluster",
            dsc,
            "-o",
            "jsonpath={.spec.components.ogx.managementState}",
        ]
    )
    ogx_ready = _oc(
        [
            "get",
            "datasciencecluster",
            dsc,
            "-o",
            "jsonpath={.status.conditions[?(@.type==\"OGXReady\")].status}",
        ]
    )
    mgmt = state.stdout.strip() if state.returncode == 0 else "missing"
    ready = ogx_ready.stdout.strip() if ogx_ready.returncode == 0 else ""
    if not has_crd:
        if mgmt == "Managed":
            return CheckResult(
                "ogx",
                False,
                "Managed but ogx.io CRDs missing — run install.sh (Service Mesh + OGX)",
            )
        if genai_studio_optional():
            return CheckResult(
                "ogx",
                True,
                "skipped (WINGS3_SKIP_OGX=1)",
            )
        return CheckResult(
            "ogx",
            False,
            "operator not on cluster — install.sh enables Service Mesh + OGX for Playground",
        )
    if mgmt == "Managed" and ready == "True":
        return CheckResult("ogx", True)
    if mgmt == "Managed":
        return CheckResult("ogx", False, f"OGXReady={ready or 'False'}")
    if genai_studio_optional():
        return CheckResult("ogx", True, "skipped (WINGS3_SKIP_OGX=1)")
    return CheckResult(
        "ogx",
        False,
        f"managementState={mgmt} — run install.sh to enable OGX",
    )


def check_ogx_server(project: str) -> CheckResult:
    name = os.environ.get("WINGS3_OGX_SERVER_NAME", "wings3-ogx")
    if genai_studio_optional():
        return CheckResult("ogxserver", True, "skipped (WINGS3_SKIP_OGX=1)")
    if not crd_exists("ogxservers.ogx.io"):
        return CheckResult("ogxserver", False, "ogx.io CRDs missing")
    exists = _oc(["get", "ogxserver", name, "-n", project])
    if exists.returncode != 0:
        return CheckResult("ogxserver", False, f"ogxserver/{name} missing in {project}")
    ready = _oc(
        [
            "get",
            "ogxserver",
            name,
            "-n",
            project,
            "-o",
            "jsonpath={.status.conditions[?(@.type==\"Ready\")].status}",
        ]
    )
    phase = _oc(
        [
            "get",
            "ogxserver",
            name,
            "-n",
            project,
            "-o",
            "jsonpath={.status.phase}",
        ]
    )
    if ready.returncode == 0 and ready.stdout.strip() == "True":
        return CheckResult("ogxserver", True)
    if phase.returncode == 0 and phase.stdout.strip() == "Ready":
        return CheckResult("ogxserver", True)
    detail = ready.stdout.strip() or phase.stdout.strip() or "not Ready"
    return CheckResult("ogxserver", False, detail)


def check_evaluations_nav() -> CheckResult:
    mlflow_ns = os.environ.get("WINGS3_MLFLOW_NAMESPACE", "redhat-ods-applications")
    flag = _oc(
        [
            "get",
            "odhdashboardconfig",
            "odh-dashboard-config",
            "-n",
            mlflow_ns,
            "-o",
            "jsonpath={.spec.dashboardConfig.disableLMEval}",
        ]
    )
    if flag.returncode != 0:
        return CheckResult("evaluations nav", False, "OdhDashboardConfig odh-dashboard-config missing")
    value = flag.stdout.strip().lower()
    if value == "false":
        return CheckResult("evaluations nav", True)
    if value == "true":
        detail = "dashboardConfig.disableLMEval is true — hides Develop & train → Evaluations"
    else:
        detail = (
            "dashboardConfig.disableLMEval not false (default hides Evaluations) — "
            "oc patch odhdashboardconfig odh-dashboard-config -n "
            f"{mlflow_ns} --type=merge -p "
            '\'{"spec":{"dashboardConfig":{"disableLMEval":false}}}\''
        )
    return CheckResult("evaluations nav", False, detail)


def check_mcp_catalog() -> CheckResult:
    mlflow_ns = os.environ.get("WINGS3_MLFLOW_NAMESPACE", "redhat-ods-applications")
    if mcp_catalog_optional():
        return CheckResult("mcp catalog", True, "skipped (WINGS3_SKIP_MCP=1)")
    flag = _oc(
        [
            "get",
            "odhdashboardconfig",
            "odh-dashboard-config",
            "-n",
            mlflow_ns,
            "-o",
            "jsonpath={.spec.dashboardConfig.mcpCatalog}",
        ]
    )
    enabled = flag.returncode == 0 and flag.stdout.strip() == "true"
    has_crd = crd_exists("mcpservers.mcp.x-k8s.io")
    if enabled and has_crd:
        return CheckResult("mcp catalog", True)
    if not enabled:
        return CheckResult("mcp catalog", False, "dashboardConfig.mcpCatalog not true")
    return CheckResult(
        "mcp catalog",
        False,
        "mcpservers.mcp.x-k8s.io CRD missing — run install.sh",
    )


def check_maas_ui() -> CheckResult:
    mlflow_ns = os.environ.get("WINGS3_MLFLOW_NAMESPACE", "redhat-ods-applications")
    dep = _oc(["get", "deployment", "maas-ui", "-n", mlflow_ns])
    if dep.returncode != 0:
        return CheckResult("maas-ui", False, "deployment missing in redhat-ods-applications")
    ready = _oc(
        [
            "get",
            "deployment",
            "maas-ui",
            "-n",
            mlflow_ns,
            "-o",
            "jsonpath={.status.readyReplicas}",
        ]
    )
    if ready.returncode != 0 or ready.stdout.strip() != "1":
        return CheckResult("maas-ui", False, "deployment not Ready")
    logs = _oc(["logs", "-n", mlflow_ns, "deployment/maas-ui", "--tail=30"])
    if logs.returncode == 0 and "SERVER_UNAVAILABLE" in logs.stdout:
        return CheckResult(
            "maas-ui",
            False,
            "recent SERVER_UNAVAILABLE in logs — oc rollout restart deployment/maas-ui -n "
            f"{mlflow_ns}",
        )
    return CheckResult("maas-ui", True)


def check_kuadrant_ready() -> CheckResult:
    kuadrant_ns = os.environ.get("WINGS3_KUADRANT_NAMESPACE", "kuadrant-system")
    if not crd_exists("kuadrants.kuadrant.io"):
        return CheckResult("kuadrant", False, "kuadrants.kuadrant.io CRD missing")
    exists = _oc(["get", "kuadrant", "kuadrant", "-n", kuadrant_ns])
    if exists.returncode != 0:
        return CheckResult(
            "kuadrant",
            False,
            f"kuadrant/kuadrant missing in {kuadrant_ns}",
        )
    ready = _oc(
        [
            "get",
            "kuadrant",
            "kuadrant",
            "-n",
            kuadrant_ns,
            "-o",
            "jsonpath={.status.conditions[?(@.type==\"Ready\")].status}",
        ]
    )
    if ready.returncode == 0 and ready.stdout.strip() == "True":
        return CheckResult("kuadrant", True)
    return CheckResult("kuadrant", False, "not Ready")


def check_maas_modelref(project: str, model: str) -> CheckResult:
    if not (
        crd_exists("maasmodelrefs.maas.opendatahub.io")
        or crd_exists("maasmodelrefs.models.opendatahub.io")
    ):
        return CheckResult(f"maasmodelref {model}", False, "MaaS CRDs not installed")
    exists = _oc(["get", "maasmodelref", model, "-n", project])
    if exists.returncode != 0:
        return CheckResult(
            f"maasmodelref {model}",
            False,
            f"maasmodelref/{model} missing in {project}",
        )
    if maas_resource_ready("maasmodelref", model, project):
        return CheckResult(f"maasmodelref {model}", True)
    return CheckResult(f"maasmodelref {model}", False, "not Ready")


def check_judge_base_url_routed_via_local_maas(project: str) -> CheckResult:
    result = _oc(
        [
            "get",
            "secret",
            "wings3-judge-llm",
            "-n",
            project,
            "-o",
            "jsonpath={.data.JUDGE_BASE_URL}",
        ]
    )
    if result.returncode != 0:
        return CheckResult(
            "judge JUDGE_BASE_URL",
            False,
            "secret/wings3-judge-llm missing",
        )
    base_url = decode_secret_value(result.stdout)
    if base_url is None:
        return CheckResult("judge JUDGE_BASE_URL", False, "empty or invalid JUDGE_BASE_URL")
    if "maas.redhatworkshops.io" in base_url:
        return CheckResult(
            "judge JUDGE_BASE_URL",
            False,
            "still points at workshop MaaS — re-run install.sh",
        )
    if "REPLACE_AT_INSTALL" in base_url:
        return CheckResult(
            "judge JUDGE_BASE_URL",
            False,
            "placeholder URL — re-run install.sh",
        )
    if "/llm/" not in base_url and f"/{project}/" not in base_url:
        return CheckResult(
            "judge JUDGE_BASE_URL",
            False,
            f"expected in-cluster MaaS path, got {base_url}",
        )
    return CheckResult("judge JUDGE_BASE_URL", True, base_url)


def check_workbench_judge_mount(project: str, workbench: str) -> CheckResult:
    mount_result = _oc(
        [
            "get",
            NOTEBOOK_API,
            workbench,
            "-n",
            project,
            "-o",
            "jsonpath={.spec.template.spec.containers[0].volumeMounts[*].mountPath}",
        ]
    )
    volume_result = _oc(
        [
            "get",
            NOTEBOOK_API,
            workbench,
            "-n",
            project,
            "-o",
            "jsonpath={.spec.template.spec.volumes[*].secret.secretName}",
        ]
    )
    if mount_result.returncode != 0 or volume_result.returncode != 0:
        return CheckResult(
            "workbench judge mount",
            False,
            f"notebook/{workbench} not found in {project}",
        )
    mount_paths = [p for p in mount_result.stdout.split() if p]
    volume_secrets = [v for v in volume_result.stdout.split() if v]
    if workbench_has_judge_mount(mount_paths, volume_secrets):
        return CheckResult("workbench judge mount", True)
    return CheckResult(
        "workbench judge mount",
        False,
        "missing /etc/wings3-judge-llm — oc apply -f manifests/workbench-wings3-demo.yaml "
        "then stop/start workbench (dashboard reconcile can strip custom mounts)",
    )


def run_checks(skip_llm: bool = False) -> list[CheckResult]:
    project = os.environ.get("WINGS3_PROJECT", "my-first-model")
    mlflow_ns = os.environ.get("WINGS3_MLFLOW_NAMESPACE", "redhat-ods-applications")
    workbench = os.environ.get("WINGS3_WORKBENCH", "wings3-demo")
    llm_model = os.environ.get("WINGS3_LLM_MODEL", "llama-32-3b-instruct")
    sr_template = os.environ.get("WINGS3_SR_TEMPLATE", "vllm-cuda-runtime-template")

    maas_model = os.environ.get("WINGS3_MAAS_MODEL", "gpt-oss-120b")

    results = [
        check_oc_login(),
        check_mlflow_cr(mlflow_ns),
        check_pod_ready(mlflow_ns, "mlflow", "mlflow pod"),
        check_evalhub_pod(mlflow_ns),
        check_evalhub_instance(project),
        check_evaluations_nav(),
        check_maas_crds(),
        check_ogx_managed(),
        check_ogx_server(project),
        check_mcp_catalog(),
        check_kuadrant_ready(),
        check_maas_ui(),
        check_maas_external_model(project, maas_model),
        check_maas_modelref(project, maas_model),
        check_notebook_ready(project, workbench),
        check_resource("configmap", "wings3-llm-endpoint", project, "configmap wings3-llm-endpoint"),
        check_resource("secret", "wings3-judge-llm", project, "secret wings3-judge-llm"),
        check_judge_secret_key(project),
        check_secret_data_key(project, "MAAS_MODEL", "agent secret MAAS_MODEL"),
        check_secret_data_key(project, "MAAS_BASE_URL", "agent secret MAAS_BASE_URL"),
        check_judge_base_url_routed_via_local_maas(project),
        check_workbench_judge_mount(project, workbench),
    ]
    if not skip_llm:
        results.append(
            check_servingruntime_version(project, llm_model, mlflow_ns, sr_template)
        )
        results.append(check_inferenceservice(project, llm_model))
    return results


def usage() -> None:
    print(
        "Usage: check_demo.py [--skip-llm]\n\n"
        "Verify WINGS3 demo health; exit 1 if any check fails."
    )


def main() -> int:
    if "-h" in sys.argv or "--help" in sys.argv:
        usage()
        return 0
    skip_llm = "--skip-llm" in sys.argv
    verbose = os.environ.get("WINGS3_VERBOSE", "0") == "1"
    results = run_checks(skip_llm=skip_llm)
    passed = sum(1 for r in results if r.ok)
    for r in results:
        status = "ok " if r.ok else "FAIL"
        line = f"{status}  {r.name}"
        if r.detail and (not r.ok or verbose):
            line = f"{line} ({r.detail})"
        print(line)
    total = len(results)
    if passed == total:
        print(f"check passed ({passed}/{total})")
        return 0
    print(f"check failed ({passed}/{total})", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
