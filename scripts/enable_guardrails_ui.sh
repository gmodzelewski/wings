#!/usr/bin/env bash
# Enable Gen AI Studio Playground Guardrails tab (NeMo-backed, Technology Preview).
# Requires cluster-admin (or patch on OdhDashboardConfig in redhat-ods-applications).
# Usage: ./scripts/enable_guardrails_ui.sh
set -euo pipefail

NS="${MLFLOW_NS:-redhat-ods-applications}"
CFG="${ODH_DASHBOARD_CONFIG:-odh-dashboard-config}"

if ! oc get odhdashboardconfig "$CFG" -n "$NS" >/dev/null 2>&1; then
  echo "error: cannot get odhdashboardconfig/$CFG in $NS (need read access)" >&2
  exit 1
fi

echo "before: genAiStudio=$(oc get odhdashboardconfig "$CFG" -n "$NS" -o jsonpath='{.spec.dashboardConfig.genAiStudio}') guardrails=$(oc get odhdashboardconfig "$CFG" -n "$NS" -o jsonpath='{.spec.dashboardConfig.guardrails}')"

if ! oc patch odhdashboardconfig "$CFG" -n "$NS" --type=merge \
  -p '{"spec":{"dashboardConfig":{"genAiStudio":true,"guardrails":true}}}'; then
  echo "error: patch forbidden — re-run as cluster-admin (or grant patch on odhdashboardconfigs in $NS)" >&2
  exit 1
fi

echo "after:  genAiStudio=$(oc get odhdashboardconfig "$CFG" -n "$NS" -o jsonpath='{.spec.dashboardConfig.genAiStudio}') guardrails=$(oc get odhdashboardconfig "$CFG" -n "$NS" -o jsonpath='{.spec.dashboardConfig.guardrails}')"

if oc get dsc -A >/dev/null 2>&1; then
  oc get dsc -A -o jsonpath='{range .items[*]}{.metadata.name} ogx={.spec.components.ogx.managementState}{"\n"}{end}'
else
  echo "note: cannot list DataScienceCluster (need cluster-scoped get); Playground also needs OGX Managed"
fi

echo
echo "Next: hard-refresh OpenShift AI → Gen AI studio → Playground → Configure → Guardrails"
echo "Note: OdhDashboardConfig may be Argo CD–managed; if the flag reverts, set guardrails in the GitOps source."
