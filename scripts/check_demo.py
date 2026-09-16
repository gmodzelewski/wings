#!/usr/bin/env python3
"""Health checks for the WINGS3 demo cluster install."""

from __future__ import annotations

import os
import subprocess
import sys
from dataclasses import dataclass


@dataclass
class CheckResult:
    name: str
    ok: bool
    detail: str = ""


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
            "notebook",
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


def check_workbench_judge_mount(project: str, workbench: str) -> CheckResult:
    mount_result = _oc(
        [
            "get",
            "notebook",
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
            "notebook",
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

    results = [
        check_oc_login(),
        check_mlflow_cr(mlflow_ns),
        check_pod_ready(mlflow_ns, "mlflow", "mlflow pod"),
        check_evalhub_pod(mlflow_ns),
        check_evalhub_instance(project),
        check_notebook_ready(project, workbench),
        check_resource("configmap", "wings3-llm-endpoint", project, "configmap wings3-llm-endpoint"),
        check_resource("secret", "wings3-judge-llm", project, "secret wings3-judge-llm"),
        check_judge_secret_key(project),
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
