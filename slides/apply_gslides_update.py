#!/usr/bin/env python3
"""Apply the 5-pillar story restructure to the live "WIP OpenShift AI - Overview"
Google Slides deck via the `gws` CLI (Google Workspace CLI, must already be
authenticated: `gws auth status`).

This is a one-shot, idempotent-ish migration script written for a single
restructuring pass (old 4-pillar Provide/Consume(DevSpaces)/Connect(MCP)/Observe
agenda -> new 5-pillar Provide/Consume(API keys)/Observe/Identify/Mitigate
agenda). It is kept in slides/ as a record of how the deck was built and as a
starting point if the deck needs another structural pass later. It is NOT a
general-purpose tool - the hardcoded object IDs are specific to the
2026-10-07 state of presentation 1OqZQIPd1monbRLpzaLUcuUegf8xuhn2mwqnyfX7XTho.

Usage:
    python3 slides/apply_gslides_update.py --phase delete
    python3 slides/apply_gslides_update.py --phase duplicate
    python3 slides/apply_gslides_update.py --phase reorder
    python3 slides/apply_gslides_update.py --phase content
    python3 slides/apply_gslides_update.py --phase dump   # sanity-check current state
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys

PRESENTATION_ID = "1OqZQIPd1monbRLpzaLUcuUegf8xuhn2mwqnyfX7XTho"
RAW_BASE = "https://raw.githubusercontent.com/gmodzelewski/wings/main/slides/screenshots"


def gws(*args: str, json_body: dict | None = None) -> dict:
    cmd = ["gws", *args]
    if json_body is not None:
        cmd += ["--json", json.dumps(json_body)]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        print("CMD:", " ".join(cmd[:3]), file=sys.stderr)
        print(proc.stdout, file=sys.stderr)
        print(proc.stderr, file=sys.stderr)
        raise SystemExit(f"gws call failed (exit {proc.returncode})")
    out = proc.stdout
    # gws may print a "Using keyring backend: keyring" diagnostic to stdout.
    lines = out.splitlines()
    if lines and lines[0].strip().startswith("Using keyring backend"):
        out = "\n".join(lines[1:])
    return json.loads(out) if out.strip() else {}


def batch_update(requests: list[dict]) -> dict:
    return gws(
        "slides",
        "presentations",
        "batchUpdate",
        "--params",
        json.dumps({"presentationId": PRESENTATION_ID}),
        json_body={"requests": requests},
    )


def get_presentation() -> dict:
    return gws(
        "slides",
        "presentations",
        "get",
        "--params",
        json.dumps({"presentationId": PRESENTATION_ID}),
    )


# ---------------------------------------------------------------------------
# PHASE 1: delete obsolete slides (old Consume=DevSpaces, old Connect=MCP,
# the stale condensed appendix block, and the stale duplicate "big picture"
# recap near the end).
# ---------------------------------------------------------------------------

DELETE_IDS = [
    # old Consume (Dev Spaces + Continue) section, slides 10-17
    "g3fb9b1791db_11_0",
    "g3f6cafff019_0_5790",
    "g3f6cafff019_0_5811",
    "g3f6cafff019_0_5808",
    "g3f6cafff019_0_5819",
    "g3f6cafff019_0_5815",
    "g3f6cafff019_0_7241",
    "g3f6cafff019_0_7244",
    # old Connect (MCP + Playground) recap/divider/QA/feature/demos, slides 18-25
    "g3fb9b1791db_0_70",
    "g3fb9b1791db_0_7",
    "g3f6cafff019_0_5858",
    "g3f6cafff019_0_5581",
    "g3f6cafff019_0_5833",
    "g3f6cafff019_0_5840",
    "g3f6cafff019_0_5843",
    "g3f6cafff019_0_5846",
    # stale condensed appendix duplicate block, slides 48-57
    "g3fb9b1791db_0_219",
    "g3fb9b1791db_0_226",
    "g3fb9b1791db_0_232",
    "g3fb9b1791db_0_274",
    "g3fb9b1791db_0_250",
    "g3fb9b1791db_0_279",
    "g3fb9b1791db_0_262",
    "g3fb9b1791db_0_284",
    "g3fb9b1791db_0_268",
    "g3fb9b1791db_0_289",
    # stale duplicate "big picture" recap (old 4-pillar order), slide 60
    "g3fb9b1791db_0_158",
]


def phase_delete() -> None:
    reqs = [{"deleteObject": {"objectId": oid}} for oid in DELETE_IDS]
    print(f"Deleting {len(reqs)} slides...")
    resp = batch_update(reqs)
    print("OK, revision:", resp.get("writeControl"))


# ---------------------------------------------------------------------------
# PHASE 2: duplicate template slides for the new Consume / Identify /
# Mitigate sections and the final Takeaways slide, pinning deterministic new
# objectIds so we can target them precisely without re-fetching.
# ---------------------------------------------------------------------------

# NOTE: deleteObject note - g3f6cafff019_0_5581 (MCP Management Ecosystem) was
# deleted above but we still want its *layout* (title+4-block body) as a
# content template. We duplicate from it *before* phase_delete in practice by
# running duplicate requests against the ORIGINAL id in the same early pass -
# but since phase_delete already removed it, we instead template Identify and
# Mitigate feature slides off slide 61 pattern is not 4-block, so instead this
# script duplicates them off the still-alive QA slide for text layout and
# relies on manual placement for the 4-block feature slides (see
# IDENTIFY_FEATURE_TEXT / MITIGATE_FEATURE_TEXT handling in content phase,
# which inserts a fresh text box rather than duplicating the deleted slide).

TEMPLATES = {
    # divider pattern (title/section slide)
    "divider": {
        "src_page": "g3fb9b1791db_0_0",
        "text_shape": "g3fb9b1791db_0_6",
        "notes_body": "g3fb9b1791db_0_5",
    },
    # Q&A pattern (question + answer)
    "qa": {
        "src_page": "g3f6cafff019_0_5794",
        "question_shape": "g3f6cafff019_0_5795",
        "answer_shape": "g3f6cafff019_0_5796",
        "notes_body": "g3f6cafff019_0_5799",
    },
    # full-bleed single image demo slide
    "demo": {
        "src_page": "g3f6cafff019_0_5782",
        "image_shape": "g3f6cafff019_0_5793",
        "notes_body": "g3f6cafff019_0_5787",
    },
    # takeaways/transition pattern (single big statement + arrow line)
    "takeaway": {
        "src_page": "g3f6cafff019_0_5672",
        "notes_body": "g3f6cafff019_0_5677",
    },
    # title + bullet list + code sample ("How to use MLflow" pattern)
    "feature": {
        "src_page": "g3f6cafff019_0_7200",
        "title_shape": "g3f6cafff019_0_7203",
        "bullets_shape": "g3f6cafff019_0_7210",
        "code_shape": "g3f6cafff019_0_7211",
        "notes_body": "g3f6cafff019_0_7205",
    },
}


def _pin(prefix: str, src_page: str, child_ids: list[str]) -> tuple[str, dict]:
    """Build a deterministic new page id + objectIds pin map for one duplicate."""
    new_page = f"wi_{prefix}"
    mapping = {src_page: new_page}
    for cid in child_ids:
        # keep a short, stable, readable suffix per child
        suffix = cid.split("_")[-1]
        mapping[cid] = f"wi_{prefix}_{suffix}"
    # also pin notes page + its BODY placeholder (consistent ":notes" suffix
    # pattern observed on every inspected template slide in this deck)
    mapping[f"{src_page}:notes"] = f"{new_page}:notes"
    return new_page, mapping


def _duplicate_request(prefix: str, template: str) -> tuple[str, dict, dict]:
    t = TEMPLATES[template]
    child_ids = [v for k, v in t.items() if k != "src_page"]
    new_page, mapping = _pin(prefix, t["src_page"], child_ids)
    req = {"duplicateObject": {"objectId": t["src_page"], "objectIds": mapping}}
    return new_page, mapping, req


# sections to create: (prefix, template)
NEW_SLIDES_PLAN = [
    ("consume_divider", "divider"),
    ("consume_qa", "qa"),
    ("consume_demo1", "demo"),
    ("consume_demo2", "demo"),
    ("identify_divider", "divider"),
    ("identify_qa", "qa"),
    ("identify_demo", "demo"),
    ("mitigate_divider", "divider"),
    ("mitigate_qa", "qa"),
    ("mitigate_demo", "demo"),
    ("final_takeaways", "takeaway"),
]


def phase_duplicate() -> None:
    reqs = []
    mappings = {}
    for prefix, template in NEW_SLIDES_PLAN:
        new_page, mapping, req = _duplicate_request(prefix, template)
        reqs.append(req)
        mappings[prefix] = mapping
    print(f"Duplicating {len(reqs)} template slides...")
    resp = batch_update(reqs)
    print("OK, revision:", resp.get("writeControl"))
    with open("/tmp/gslides/new_slide_mappings.json", "w") as fh:
        json.dump(mappings, fh, indent=2)
    print("Wrote /tmp/gslides/new_slide_mappings.json")


# ---------------------------------------------------------------------------
# PHASE 3: reorder - move the new slides to their correct final positions.
# ---------------------------------------------------------------------------


def _move_one(slide_id: str, after_id: str) -> None:
    """Move a single slide to immediately after `after_id`, re-resolving the
    current index each time (single-id moves are always "in order")."""
    pres = get_presentation()
    order = [s["objectId"] for s in pres["slides"]]
    idx = {oid: i for i, oid in enumerate(order)}
    insertion_index = idx[after_id] + 1
    print(f"Moving {slide_id} to index {insertion_index} (after {after_id})")
    resp = batch_update([
        {"updateSlidesPosition": {"slideObjectIds": [slide_id], "insertionIndex": insertion_index}}
    ])
    print("  OK", resp.get("writeControl"))


def phase_reorder() -> None:
    # Consume section goes right after Provide's last demo slide, in order.
    anchor = "g3fb9b1791db_0_201"
    for sid in ["wi_consume_divider", "wi_consume_qa", "wi_consume_demo1", "wi_consume_demo2"]:
        _move_one(sid, anchor)
        anchor = sid

    # Identify + Mitigate + final takeaways go right after the repurposed
    # transition slide (old "Takeaways", objectId g3f6cafff019_0_5672), in order.
    anchor = "g3f6cafff019_0_5672"
    tail_ids = [
        "wi_identify_divider", "wi_identify_qa", "wi_identify_demo",
        "wi_mitigate_divider", "wi_mitigate_qa", "wi_mitigate_demo",
        "wi_final_takeaways",
    ]
    for sid in tail_ids:
        _move_one(sid, anchor)
        anchor = sid


# ---------------------------------------------------------------------------
# PHASE 4: content - text replacement, image swap, notes, and fixes to
# existing slides (Scope bullets, Observe recap demo number).
# ---------------------------------------------------------------------------

def replace_text(page_id: str, pairs: list[tuple[str, str]]) -> dict:
    reqs = []
    for old, new in pairs:
        reqs.append({
            "replaceAllText": {
                "containsText": {"text": old, "matchCase": True},
                "replaceText": new,
                "pageObjectIds": [page_id],
            }
        })
    return batch_update(reqs)


def set_notes(page_notes_body_id: str, text: str, had_existing_text: bool = False) -> dict:
    reqs = []
    if had_existing_text:
        reqs.append({"deleteText": {"objectId": page_notes_body_id, "textRange": {"type": "ALL"}}})
    reqs.append({"insertText": {"objectId": page_notes_body_id, "text": text, "insertionIndex": 0}})
    return batch_update(reqs)


def replace_image(image_object_id: str, url: str) -> dict:
    return batch_update([
        {"replaceImage": {"imageObjectId": image_object_id, "url": url, "imageReplaceMethod": "CENTER_CROP"}}
    ])


def phase_content() -> None:
    # --- CONSUME ---
    replace_text("wi_consume_divider", [
        ("Provide\n\nDemos:\nModels as a Service", "Consume\n\nDemos:\nAPI keys\nPlayground"),
    ])
    replace_text("wi_consume_qa", [
        ("Model is super large, but you want your engineers to use it anyways? ",
         "Can engineers use the model from a safe, governed workspace?"),
        ("AI asset endpoints → Models as a service",
         "API keys, MaaS governance and the Playground → safe self-service access with built-in metrics"),
    ])
    replace_image("wi_consume_demo1_5793", f"{RAW_BASE}/02-consume-api-keys.png")
    replace_image("wi_consume_demo2_5793", f"{RAW_BASE}/03-consume-playground-chat.png")
    set_notes("wi_consume_qa_5799", (
        "Demo 2 - Consume:\n"
        "Open Gen AI studio -> API keys - show an active key tied to the redhat-maas subscription\n"
        "Open Gen AI studio -> Playground, pick a model behind an AI asset endpoint\n"
        "Send a live chat message, point out token count, time to first token, and tokens per second\n"
        "These are the same numbers MaaS governance uses for showback and rate limiting\n"
        "No GPU, no SDK, no custom client needed - any engineer with a key can consume the model"
    ))
    set_notes("wi_consume_demo1_5787", "Screenshot: active API keys under the redhat-maas subscription.")
    set_notes("wi_consume_demo2_5787", "Screenshot: Playground chat response with live token/latency metrics.")

    # --- IDENTIFY ---
    replace_text("wi_identify_divider", [
        ("Provide\n\nDemos:\nModels as a Service", "Identify\n\nDemos:\nEvalHub\nGarak (OWASP top 10)"),
    ])
    replace_text("wi_identify_qa", [
        ("Model is super large, but you want your engineers to use it anyways? ",
         "What security issues does the agent or model have? Are there other known issues?"),
        ("AI asset endpoints → Models as a service",
         "Automated red teaming → EvalHub, Garak, benchmarks"),
    ])
    replace_image("wi_identify_demo_5793", f"{RAW_BASE}/06-identify-garak-owasp-eval.png")
    set_notes("wi_identify_qa_5799", (
        "Demo 4 - Identify:\n"
        "Open Develop & train -> Evaluations\n"
        "Show the OWASP (Open Web Application Security Project) LLM Top 10 Garak run against gpt-oss-120b\n"
        "Garak is an open-source LLM vulnerability scanner: prompt injection, jailbreak, data leakage probes\n"
        "This run was seeded by install.sh - the same scan can run on every model promotion\n"
        "Manual red teaming does not scale; a scheduled scan catches regressions before customers do"
    ))
    set_notes("wi_identify_demo_5787", "Screenshot: Develop & train -> Evaluations, OWASP LLM Top 10 Garak run.")

    # --- MITIGATE ---
    replace_text("wi_mitigate_divider", [
        ("Provide\n\nDemos:\nModels as a Service", "Mitigate\n\nDemos:\nPlayground guardrails\nNeMo Guardrails"),
    ])
    replace_text("wi_mitigate_qa", [
        ("Model is super large, but you want your engineers to use it anyways? ",
         "How do we close the issues these scans find?"),
        ("AI asset endpoints → Models as a service",
         "Prompts, guardrails, sandboxing → secure, observable and scalable by design"),
    ])
    replace_image("wi_mitigate_demo_5793", f"{RAW_BASE}/07-mitigate-guardrails-tab.png")
    set_notes("wi_mitigate_qa_5799", (
        "Demo 5 - Mitigate:\n"
        "Back in the Playground, open the Guardrails tab for the same agent\n"
        "User input guardrails: jailbreak and prompt-attack protection, PII (personally identifiable "
        "information) filtering, content moderation\n"
        "Model output guardrails: PII leak prevention, content moderation\n"
        "Backed by a NemoGuardrails custom resource - same pattern as any other OpenShift AI resource\n"
        "Pair this with agent sandboxing (OpenShell) for isolated, policy-controlled tool execution"
    ))
    set_notes("wi_mitigate_demo_5787", "Screenshot: Playground Guardrails tab, input/output rails.")

    # --- final Takeaways slide ---
    replace_text("wi_final_takeaways", [
        ("Takeaways\n\n→ five questions, answered",
         "Takeaways\n\n→ five questions, answered"),
    ])
    set_notes("wi_final_takeaways_5677", (
        "Five customer questions, five answers, all shown live today:\n"
        "Provide - Models as a Service through AI asset endpoints, no GPU on the laptop\n"
        "Consume - API keys, MaaS governance and the Playground, with live token metrics\n"
        "Observe - MLflow tracing, per-span timeline, datasets and LLM judges\n"
        "Identify - automated red teaming with EvalHub and Garak against the OWASP LLM Top 10\n"
        "Mitigate - prompts, guardrails and sandboxing close the loop\n"
        "What is left is operational scale - identity, sandboxing and inference autoscaling - "
        "that is next"
    ), had_existing_text=True)

    # --- fix existing slide 2 (Scope) ---
    replace_text("g3f6e5b86ae9_2_0", [
        (
            "Red Hat AI 3.5 (Developer/Tech Preview) Highlights:\nModels as a Service via AI asset endpoints\nDev Spaces with the Continue code assistant\nMCP servers and the Playground\nMLflow tracing and evaluation (teaser)\nWhat's next: Prompt Registry, AutoRAG, Eval Hub",
            "Red Hat AI 3.5 (Developer/Tech Preview) highlights:\nModels as a service via AI asset endpoints\nAPI keys, MaaS governance and the Playground, with live metrics\nMLflow tracing and evaluation\nAutomated red teaming with EvalHub and Garak\nGuardrails and sandboxing for production readiness",
        ),
        (
            "Five short demo blocks — each one answers a question we hear from customers.",
            "Five short demo blocks — each one answers a question we hear from customers.",
        ),
    ])

    # --- fix existing slide 26 (Observe recap) demo number ---
    replace_text("g3fb9b1791db_0_114", [
        ("DEMO 5", "DEMO 3"),
    ])

    # --- repurpose existing slide 47 into a mid-deck transition ---
    replace_text("g3f6cafff019_0_5672", [
        ("Takeaways\n\n→ five questions, answered",
         "Three down, two to go"),
    ])
    set_notes("g3f6cafff019_0_5677", (
        "Provide, Consume and Observe are solved, live, on this cluster.\n"
        "Two customer questions remain: what is broken, and how do we fix it.\n"
        "That is Identify and Mitigate - then we talk about getting to production."
    ), had_existing_text=True)

    print("Content phase done.")


FEATURE_SLIDES_PLAN = [
    ("identify_feature", "feature"),
    ("mitigate_feature", "feature"),
]


def phase_add_features() -> None:
    # 1) duplicate
    reqs = []
    for prefix, template in FEATURE_SLIDES_PLAN:
        _, _, req = _duplicate_request(prefix, template)
        reqs.append(req)
    print(f"Duplicating {len(reqs)} feature-slide templates...")
    resp = batch_update(reqs)
    print("OK", resp.get("writeControl"))

    # 2) reorder: identify_feature right after wi_identify_demo (before
    # wi_mitigate_divider); mitigate_feature right after wi_mitigate_demo
    # (before wi_final_takeaways)
    _move_one("wi_identify_feature", "wi_identify_demo")
    _move_one("wi_mitigate_feature", "wi_mitigate_demo")

    # 3) content
    replace_text("wi_identify_feature", [
        ("How to use MLFlow", "EvalHub: automated red teaming for LLMs"),
        (
            "Provides zero-code observability for over 40 LLM and AI frameworks.\nEnables the capture of LangChain operations—including LLM calls, tool invocations, and agent decisions—using a single autolog() call without modifying application logic.\nBuilt on OpenTelemetry to support unified tracing, rich metadata, and asynchronous scaling.\nCompatible with standard backends such as Jaeger, Zipkin, and Grafana Tempo.",
            "A managed service in Red Hat AI that runs automated security and quality probes against a model or agent endpoint — no custom test harness required.\nGarak, an open-source LLM vulnerability scanner, provides the probes: prompt injection, jailbreak, data leakage, and the rest of the OWASP (Open Web Application Security Project) LLM top 10.\nResults land in Develop & train → Evaluations, next to every other evaluation run.\nManual red teaming does not scale — new jailbreak techniques appear every week; a scheduled scan catches regressions before customers do.",
        ),
        (
            'import mlflow\nimport mlflow.langchain\n\nmlflow.set_tracking_uri(\x0bsettings.MLFLOW_TRACKING_URI)\n\nmlflow.set_experiment(\x0bsettings.MLFLOW_EXPERIMENT_NAME)\n\nmlflow.langchain.autolog()',
            "garak \\\n  --model_type rest \\\n  --model_name gpt-oss-120b \\\n  --probes owasp.LLM01 \\\n  --generations 5",
        ),
    ])
    set_notes("wi_identify_feature_7205", (
        "EvalHub runs Garak against the AI asset endpoint on a schedule, not just once.\n"
        "OWASP (Open Web Application Security Project) publishes the LLM top 10 - the "
        "probes map directly to those categories.\n"
        "The same command that ran on stage can run as a CI gate before every model promotion."
    ))

    replace_text("wi_mitigate_feature", [
        ("How to use MLFlow", "NeMo Guardrails: rails on every request and response"),
        (
            "Provides zero-code observability for over 40 LLM and AI frameworks.\nEnables the capture of LangChain operations—including LLM calls, tool invocations, and agent decisions—using a single autolog() call without modifying application logic.\nBuilt on OpenTelemetry to support unified tracing, rich metadata, and asynchronous scaling.\nCompatible with standard backends such as Jaeger, Zipkin, and Grafana Tempo.",
            "A guardrail model screens every request and response before it reaches, or leaves, the primary model.\nUser input guardrails: jailbreak and prompt-attack protection, personally identifiable information filtering, content moderation.\nModel output guardrails: personally identifiable information leak prevention, content moderation.\nToggle per agent in the Playground, or enforce centrally with the NemoGuardrails custom resource — the same pattern as any other OpenShift AI resource.",
        ),
        (
            'import mlflow\nimport mlflow.langchain\n\nmlflow.set_tracking_uri(\x0bsettings.MLFLOW_TRACKING_URI)\n\nmlflow.set_experiment(\x0bsettings.MLFLOW_EXPERIMENT_NAME)\n\nmlflow.langchain.autolog()',
            "apiVersion: trustyai.opendatahub.io/v1alpha1\nkind: NemoGuardrails\nmetadata:\n  name: nemoguardrails\nspec:\n  nemoConfigs:\n    - name: guardrail-placeholder\n      default: true",
        ),
    ])
    set_notes("wi_mitigate_feature_7205", (
        "A red-teaming scan tells you what is broken; guardrails are how you stop it from "
        "reaching production traffic.\n"
        "Pair this with agent sandboxing (OpenShell) for isolated, policy-controlled tool "
        "execution, and per-tool authorization through the MCP (Model Context Protocol) "
        "gateway."
    ))
    print("Feature slides added.")


def phase_dump() -> None:
    pres = get_presentation()
    for i, s in enumerate(pres["slides"], 1):
        texts = []
        for el in s.get("pageElements", []):
            if "shape" in el and el["shape"].get("text"):
                t = "".join(
                    te.get("textRun", {}).get("content", "")
                    for te in el["shape"]["text"].get("textElements", [])
                ).strip()
                if t:
                    texts.append(t.replace("\n", " / ")[:70])
        print(f"{i:3d}  {s['objectId']:30s}  {' | '.join(texts)[:140]}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--phase",
        required=True,
        choices=["delete", "duplicate", "reorder", "content", "add_features", "dump"],
    )
    args = ap.parse_args()
    {
        "delete": phase_delete,
        "duplicate": phase_duplicate,
        "reorder": phase_reorder,
        "content": phase_content,
        "add_features": phase_add_features,
        "dump": phase_dump,
    }[args.phase]()


if __name__ == "__main__":
    main()
