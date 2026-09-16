#!/usr/bin/env python3
"""Report RHOAI DSC component and EvalHub API discovery for WINGS3 install."""

from __future__ import annotations

import json
import subprocess
import sys
from typing import Any


def _oc_json(args: list[str]) -> dict[str, Any] | None:
    try:
        raw = subprocess.check_output(["oc", *args], stderr=subprocess.DEVNULL, text=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    return json.loads(raw)


def rhoai_version(dsc: dict[str, Any]) -> str:
    status = dsc.get("status", {}) or {}
    for rel in status.get("installedComponents", {}).get("releases") or []:
        if rel.get("name") == "platform":
            return str(rel.get("version") or "")
    for rel in status.get("releases") or []:
        if rel.get("name") == "platform":
            return str(rel.get("version") or "")
    for comp in (status.get("components") or {}).values():
        if not isinstance(comp, dict):
            continue
        for rel in comp.get("releases") or []:
            if rel.get("name") == "platform":
                return str(rel.get("version") or "")
    return ""


def component_state(components: dict[str, Any], name: str) -> str:
    entry = components.get(name)
    if not isinstance(entry, dict):
        return ""
    return str(entry.get("managementState") or "")


def crd_registered(suffix: str) -> bool:
    try:
        lines = subprocess.check_output(
            ["oc", "api-resources", "-o", "name"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False
    return any(suffix in line for line in lines.splitlines())


def discover_evalhub_component(components: dict[str, Any]) -> str:
    prefs = ["evalhuboperator", "evalhub", "evaluationoperator", "rhaievaluationoperator"]
    for name in prefs:
        if name in components:
            return name
    for name in sorted(components):
        lower = name.lower()
        if "evalhub" in lower or lower.endswith("evaluationoperator"):
            return name
    if "trustyai" in components and crd_registered("evalhubs.trustyai.opendatahub.io"):
        return "trustyai"
    return ""


def discover_garak_component(components: dict[str, Any]) -> str:
    prefs = ["garakoperator", "garakpipelineoperator", "garak", "garakpipeline"]
    for name in prefs:
        if name in components:
            return name
    for name in sorted(components):
        if "garak" in name.lower():
            return name
    return ""


def matching_components(components: dict[str, Any]) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for name in sorted(components):
        lower = name.lower()
        if any(k in lower for k in ("evalhub", "garak", "evaluation", "trustyai", "mlflow")):
            state = component_state(components, name)
            out.append((name, state))
    return out


def main() -> int:
    dsc_name = sys.argv[1] if len(sys.argv) > 1 else "default-dsc"
    data = _oc_json(["get", "datasciencecluster", dsc_name, "-o", "json"])
    if data is None:
        print(f"error: could not read DataScienceCluster {dsc_name}", file=sys.stderr)
        return 1

    components = data.get("spec", {}).get("components", {}) or {}
    version = rhoai_version(data)
    evalhub = discover_evalhub_component(components)
    garak = discover_garak_component(components)
    mlflow_state = component_state(components, "mlflowoperator")

    print(f"DataScienceCluster: {dsc_name}")
    if version:
        print(f"RHOAI version: {version}")
    print()
    print("Components matching evalhub|garak|evaluation|mlflow|trustyai:")
    for name, state in matching_components(components):
        print(f"  {name}: {state or '(unset)'}")
    if not matching_components(components):
        print("  (none in stored spec)")
    print()
    print(f"MLflow (mlflowoperator): {mlflow_state or 'not in stored spec (patch to enable)'}")
    print(f"EvalHub DSC component: {evalhub or '(not found — set WINGS3_EVALHUB_DSC_COMPONENT)'}")
    print(f"Garak DSC component: {garak or '(none — Garak may be EvalHub provider only)'}")
    print()
    print("Evaluation-related API resources:")
    try:
        resources = subprocess.check_output(
            ["oc", "api-resources"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
        for line in resources.splitlines():
            if "eval" in line.lower() or "garak" in line.lower() or "lmeval" in line.lower():
                print(f"  {line.strip()}")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("  (oc api-resources failed)")
    print()
    mlflow_ns = "redhat-ods-applications"
    print(f"Pods in {mlflow_ns} (mlflow/evalhub/garak):")
    try:
        pods = subprocess.check_output(
            ["oc", "get", "pods", "-n", mlflow_ns, "--no-headers"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
        matched = [
            line for line in pods.splitlines() if any(k in line.lower() for k in ("mlflow", "evalhub", "eval-hub", "garak", "trustyai"))
        ]
        if matched:
            for line in matched:
                print(f"  {line.strip()}")
        else:
            print("  (none found)")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("  (oc get pods failed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
