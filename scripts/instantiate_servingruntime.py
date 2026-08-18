#!/usr/bin/env python3
"""Instantiate a project ServingRuntime from an OpenShift Template JSON.

Reads `oc get template … -o json` on stdin. Writes a ServingRuntime JSON
document to stdout with metadata.name / namespace set. Substitutes
${PARAM} placeholders from the template parameter list.

Used by scripts/bootstrap.sh so the runtime image matches the
cluster's vllm-cuda-runtime-template (no frozen RHAIIS SHA).
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any


def _params(template: dict[str, Any], name: str, namespace: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for p in template.get("parameters") or []:
        pname = p.get("name")
        if not pname:
            continue
        out[pname] = str(p.get("value") or "")
        key = pname.lower().replace("-", "_")
        if key in {"name", "runtime_name", "servingruntime", "serving_runtime"}:
            out[pname] = name
        if key in {"namespace", "ns"}:
            out[pname] = namespace
    return out


def _subst(value: Any, params: dict[str, str]) -> Any:
    if isinstance(value, str):
        for key, val in params.items():
            value = value.replace("${" + key + "}", val)
        return value
    if isinstance(value, list):
        return [_subst(v, params) for v in value]
    if isinstance(value, dict):
        return {k: _subst(v, params) for k, v in value.items()}
    return value


def servingruntime_from_template(
    template: dict[str, Any], name: str, namespace: str
) -> dict[str, Any]:
    params = _params(template, name, namespace)
    runtime = None
    for obj in template.get("objects") or []:
        if obj.get("kind") == "ServingRuntime":
            runtime = _subst(obj, params)
            break
    if runtime is None:
        raise SystemExit("error: template has no ServingRuntime object")
    md = runtime.setdefault("metadata", {})
    md["name"] = name
    md["namespace"] = namespace
    for drop in (
        "resourceVersion",
        "uid",
        "creationTimestamp",
        "generation",
        "managedFields",
        "selfLink",
    ):
        md.pop(drop, None)
    runtime.pop("status", None)
    return runtime


def main() -> None:
    name = os.environ.get("WINGS3_LLM_MODEL") or os.environ.get("LLM_MODEL")
    namespace = os.environ.get("WINGS3_PROJECT") or os.environ.get("PROJECT")
    if not name or not namespace:
        raise SystemExit("error: set WINGS3_LLM_MODEL and WINGS3_PROJECT")
    template = json.load(sys.stdin)
    json.dump(servingruntime_from_template(template, name, namespace), sys.stdout)


if __name__ == "__main__":
    main()
