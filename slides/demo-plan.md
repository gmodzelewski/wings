# Demo plan — the five-pillar story

Companion runbook for the Google Slides deck
["WIP OpenShift AI - Overview"](https://docs.google.com/presentation/d/1OqZQIPd1monbRLpzaLUcuUegf8xuhn2mwqnyfX7XTho/edit).
Use this when presenting at a customer event. Total slot: 1 hour.
Slides and live demos together: ~45 minutes, leaving ~15 minutes for
questions.

The whole session follows one red thread: a customer question, a live
demo that answers it, and what it means for them. The five questions map
to five platform capabilities:

| # | Pillar | Customer question | Capability shown live |
|---|--------|--------------------|------------------------|
| 1 | **Provide** | "Our model is huge — how do engineers use it anyway?" | Models as a Service via AI asset endpoints |
| 2 | **Consume** | "Can engineers use it from a safe, governed workspace?" | API keys, MaaS governance, Playground |
| 3 | **Observe** | "Which agent answered? Which tools? How fast? What if it's wrong?" | MLflow tracing, span timeline, datasets, judges |
| 4 | **Identify** | "What security issues does my agent/model have?" | Automated red teaming — EvalHub, Garak |
| 5 | **Mitigate** | "How do we close the issues?" | Prompts, guardrails, sandboxing |

All demos below run against a live `wings`-installed OpenShift AI cluster
(see the repo [`README.md`](../README.md) and `scripts/install.sh`). Run
`scripts/check_demo.py` the morning of the event to confirm every piece is
up before you present — it checks every item referenced here.

---

## Pre-stage (do this before the audience arrives)

1. `oc login` to the demo cluster; confirm `scripts/check_demo.py` is green.
2. Open two browser tabs, logged in as the cluster admin / demo user:
   - Tab A: the OpenShift AI dashboard (`rhods-dashboard` route), landed on
     **Projects → my-first-model → Overview**.
   - Tab B: the slide deck, presenter view, on slide 1.
3. Confirm the `wings-demo` workbench (JupyterLab) is **Running** —
   Project `my-first-model` → Workbenches. If stopped, start it now; it
   takes a few minutes.
4. Confirm an **API key** named `wings-judge` (or similar) with an
   **Active** status exists under **Gen AI studio → API keys**, tied to
   the `redhat-maas` subscription. If missing, click **Create API key**
   live during Demo 2 instead of pre-staging it — either works.
5. Confirm **Develop & train → Evaluations** shows the seeded
   `wings-demo-garak-owasp` run (installed by `scripts/install.sh` via
   `submit_demo_garak_owasp_run()`). It is fine if the status is still
   **Running** — read on in Demo 4 for what to say either way.
6. Confirm `oc get nemoguardrails -n my-first-model` shows `phase: Ready`.

---

## Demo 1 — Provide (slides 6–11, ~6 min)

**Question:** "Our model is huge — how do engineers use it anyway?"
**Answer:** Models as a Service through AI asset endpoints — plus the
catalog context (models, agents, MCP servers) that teams consume from.

1. In Tab A: **Gen AI studio → AI asset endpoints → Models**.
2. Point out the model list is all **Ready** (not "Unknown") — these are
   the models the platform team published for consumption.
3. Click one model to show its endpoint URL and the "Use this model"
   panel (OpenAI-compatible base URL).
4. On slides 8–11, keep the narration high-level (do not deep-dive every
   card):
   - models and governance are published centrally,
   - playgrounds support test-before-consume behavior,
   - agents and MCP servers are discoverable assets in the same story.
5. Say: "Any engineer, any IDE, any script — same endpoint, same token,
   and governed assets around it."

**If it breaks:** the Provide section already has screenshot-backed slides
(8–11), so narrate from the deck and move on.

---

## Demo 2 — Consume (slides 12–15, ~5 min)

**Question:** "Can engineers use it from a safe, governed workspace?"
**Answer:** API keys, MaaS governance and the Playground — safe
self-service access with built-in metrics.

1. In Tab A: **Gen AI studio → API keys**.
2. Show the active key(s) tied to the `redhat-maas` subscription. If none
   exist, click **Create API key** live — takes a few seconds.
3. Go to **Gen AI studio → Playground**, project `my-first-model`.
4. In the chat box, send: *"What is Red Hat OpenShift AI in one
   sentence?"*
5. After the response streams in, point at the badges under the message:
   latency (e.g. `1.22 s`), token count (`T: 107`), time-to-first-token
   (`TTFT: 153ms`), and tokens/sec (`88 T/s`).
6. Say: "These are the same numbers MaaS governance uses for showback and
   rate limiting — the engineer gets a chat UI, the platform team gets
   metering, for free."

**If it breaks:** fall back to the two screenshots already in the deck
(API keys list, Playground chat with metrics).

---

## Demo 3 — Observe (slides 16–36, ~13 min)

This is the deepest section of the deck — most of its content (the five
customer-question slides, the monitoring-gap slide, and the nine
screenshot slides covering trace list → span tree → timeline → prompts →
datasets → judges → drill-down) already carries real screenshots from a
richer multi-agent demo. Narrate from those slides at your own pace; the
live portion below is optional and only needed if you want to show a
*fresh* trace generated on this exact cluster.

**Optional live portion** (adds ~3 min):

1. In Tab A: **Projects → my-first-model → Workbenches → wings-demo**
   (must be Running) → **Open**.
2. In JupyterLab, open a terminal:
   ```bash
   cd demo/agent-tracing
   MLFLOW_WORKSPACE=my-first-model python run_tracing_demo_autolog.py
   ```
   This runs a small LangGraph calculator agent with
   `mlflow.langchain.autolog()` turned on and asks it three questions.
   Takes roughly 2–3 minutes (small model, GPU-constrained).
3. Open the standalone MLflow UI (`<dashboard-route>/mlflow`) → select
   workspace `my-first-model` → **Experiments → wings-agent-tracing →
   Traces**.
4. Click the **"Calculate 256 divided by 16"** trace → **Details &
   Timeline** tab → **Graph** view.
5. Walk the span tree: `LangGraph → agent → call_model → ChatOpenAI`,
   then `tools → calculator`, then back to `agent` for the final answer.
   Say: "One line of code — `mlflow.langchain.autolog()` — and every LLM
   call and every tool call is a span, nested exactly as the agent called
   them."

**If it breaks:** the deck's own screenshots already tell this story end
to end; skip straight to slide 36 ("How to use MLflow") and move on.

---

## Demo 4 — Identify (slides 38–41, ~4 min)

**Question:** "What security issues does my agent or model have? Are
there other known issues?"
**Answer:** Automated red teaming — EvalHub, Garak, benchmarks.

1. In Tab A: **Develop & train → Evaluations**.
2. Point at `wings-demo-garak-owasp` — evaluation `Owasp Llm Top10`
   against `gpt-oss-120b`.
   - If status is **Running**: say "This was seeded automatically by the
     install script and is still scanning — Garak throws dozens of
     adversarial probes at the model, so a full run takes a while. Here
     is what finishes earlier today," and move to the slide's screenshot
     for a completed example if you have one, or simply narrate what the
     scan covers (see slide 41).
   - If status is **Succeeded**: open it and show the pass/fail counts
     per probe category.
3. On slide 41 (the EvalHub/Garak explainer), point at the one-liner CLI
   invocation and say: "This is literally the command the install script
   runs — the exact same thing can run as a CI gate before every model
   promotion."

**If it breaks:** the deck's screenshot shows a real run against this
cluster regardless of what the live Evaluations page shows at demo time.

---

## Demo 5 — Mitigate (slides 42–45, ~4 min)

**Question:** "How do we close the issues these scans find?"
**Answer:** Prompts, guardrails, sandboxing — secure, observable and
scalable by design.

1. Stay in the Playground from Demo 2 (or reopen it).
2. Open **Settings → Guardrails** tab for the same agent/model.
3. Point out the two toggles and their descriptions:
   - **User input guardrails** — jailbreak and prompt-attack protection,
     PII (personally identifiable information) filtering, content
     moderation.
   - **Model output guardrails** — PII leak prevention, content
     moderation.
4. Say: "This is the same guardrail model pattern Demo 4 just tested
   against — a red-teaming scan tells you what is broken, guardrails are
   how you stop it from reaching production traffic."
5. Optional: in a terminal, run
   `oc get nemoguardrails -n my-first-model -o yaml` to show the
   `NemoGuardrails` custom resource backing the toggle — "just another
   OpenShift AI resource, GitOps-friendly like everything else today."
6. On slide 45 (the NeMo Guardrails explainer), point at the YAML
   snippet and mention agent sandboxing (OpenShell, shown later) as the
   next layer of defense for tool execution itself.

**If it breaks:** the deck's screenshot shows the Guardrails tab exactly
as captured on this cluster.

---

## Closing — vision and production readiness (slides 46–51, ~6 min)

1. Slide 46, **Takeaways**: recap all five questions and answers in one
   breath — Provide, Consume, Observe, Identify, Mitigate.
2. Slide 48, **Three critical gaps**: pivot to "what's left between a
   pilot and production" — agent identity, scalability, ungoverned
   autonomy.
3. Slide 49, **Closing the Gaps**: map each gap to a capability
   (cryptographic workload identity, vLLM/llm-d autoscaling, agent
   sandboxing) — these are the same sandboxing and MCP-gateway concepts
   already teased in Demo 5.
4. Slide 50, **OpenShell video**: play or link the short video if time
   allows; otherwise mention it as a leave-behind resource.
5. Slide 51, **Vision 2026/2027: now and next**:
   - Clearly label this as direction, not commitment.
   - Message: BYOA remains the default path; optional control-plane path
     matures over time.
   - Tie to API sovereignty and MCP/A2A governance trajectory.
6. Slide 52, **Thank you**: close, open the floor for questions.

---

## Timing summary

| Section | Slides | Target time |
|---|---|---|
| Intro, scope, context | 1–5 | 5 min |
| Demo 1 — Provide | 6–11 | 6 min |
| Demo 2 — Consume | 12–15 | 5 min |
| Demo 3 — Observe | 16–36 | 13 min |
| Transition | 37 | <1 min |
| Demo 4 — Identify | 38–41 | 4 min |
| Demo 5 — Mitigate | 42–45 | 4 min |
| Takeaways + vision + production | 46–51 | 6 min |
| Thank you | 52 | <1 min |
| **Total slides/demo** | | **~45 min** |
| **Q&A buffer** | | **~15 min** |

If you are running long, the first thing to cut is the optional *live*
portion of Demo 3 (it already has a full screenshot narrative) — never
cut Demo 4 or Demo 5, they are the newest and least-familiar material for
most customer audiences.
