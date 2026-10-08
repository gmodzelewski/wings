# Demo plan — the five-pillar story

Companion runbook for
["WIP OpenShift AI - Overview"](https://docs.google.com/presentation/d/1OqZQIPd1monbRLpzaLUcuUegf8xuhn2mwqnyfX7XTho/edit).
Total slot: 1 hour. Main story is designed for ~45 minutes plus Q&A.

The red thread remains: a customer question, a live demo, and what it
means for production.

| # | Pillar | Customer question | Capability shown live |
|---|--------|--------------------|------------------------|
| 1 | **Provide** | "Our model is huge — how do engineers use it anyway?" | AI asset endpoints and governed assets |
| 2 | **Consume** | "Can engineers use it from a safe, governed workspace?" | API keys, MaaS governance, Playground metrics |
| 3 | **Observe** | "Which agent answered? Which tools? How fast? What if it's wrong?" | MLflow traces, timeline, evaluations |
| 4 | **Identify** | "What security issues does my agent or model have?" | Safety context + EvalHub and Garak evidence |
| 5 | **Mitigate** | "How do we close the issues?" | Guardrails + NeMo Guardrails runtime pattern |

---

## Pre-stage checklist

1. `oc login`, then run `scripts/check_demo.py`.
2. Keep two tabs open:
   - OpenShift AI dashboard (project `my-first-model`)
   - Slides in presenter mode
3. Confirm `wings-demo` workbench is running.
4. Confirm an active API key under `Gen AI studio -> API keys`.
5. Confirm `wings-demo-garak-owasp` is present in `Develop & train -> Evaluations`.
6. Confirm `oc get nemoguardrails -n my-first-model` reports ready state.

---

## Demo 1 — Provide (slides 6–11, ~6 min)

1. `Gen AI studio -> AI asset endpoints -> Models`.
2. Show models in `Ready` state and one endpoint usage panel.
3. On slides 8–11, keep narration concise:
   - models and governance are centralized,
   - playground supports test-before-consume,
   - agents and MCP assets are discoverable.
4. Message: one endpoint and token path for engineers, with governance.

Fallback: narrate directly from slides 8–11 screenshots.

---

## Demo 2 — Consume (slides 12–15, ~5 min)

1. `Gen AI studio -> API keys`: show active key tied to `redhat-maas`.
2. `Gen AI studio -> Playground`: send a short prompt.
3. Point at latency, token count, time-to-first-token, and throughput.
4. Message: same interaction supports engineering productivity and platform metering.

Fallback: use API key and Playground screenshots in slides 14–15.

---

## Demo 3 — Observe (slides 16–36, ~12 min)

Use the existing Observe sequence as the deep section:
- question slides,
- monitoring-gap framing,
- trace list to span tree to timeline,
- prompt/dataset/judge examples,
- MLflow usage summary on slide 36.

Optional live trace refresh (if time allows):
```bash
cd demo/agent-tracing
MLFLOW_WORKSPACE=my-first-model python run_tracing_demo_autolog.py
```

Fallback: skip live run and stay on screenshot narrative through slide 36.

---

## Transition (slide 37, <1 min)

Slide 37 bridges from solved observability to unresolved safety risk:
"Three down, two to go."

---

## Demo 4 — Identify (slides 38–42, ~5 min)

Flow in this section:
1. Slide 39 customer question.
2. Slide 40 safety context (why identify -> mitigate loop matters).
3. Slide 41 evaluation screenshot evidence.
4. Slide 42 EvalHub/Garak summary + CLI gate framing.

Primary message: automated red teaming is repeatable evidence, not ad hoc testing.

Fallback: if live Evaluations is slow, use slide 41 screenshot and continue.

---

## Demo 5 — Mitigate (slides 43–46, ~4 min)

1. Slide 44 frames mitigation question.
2. Slide 45 shows Playground guardrails controls.
3. Slide 46 shows NeMo Guardrails resource pattern.

Primary message: findings from Identify are converted into enforceable runtime controls.

Fallback: use guardrails screenshot and NeMo summary slide if UI differs.

---

## Close — production and vision (slides 47–53, ~7 min)

1. Slide 47 recap all five answered questions.
2. Slides 48–50: production gaps and capability mapping.
3. Slide 51: OpenShell runtime isolation anchor.
4. Slide 52: now-vs-next strategy framing (targets, not commitments).
5. Slide 53: thank-you and Q&A.

Primary message: start now with the five-pillar path; evolve into broader control-plane capabilities over time.

---

## Backup appendix (slides 54–57, optional)

Use only for security deep-dive questions:
- representative risk scenarios,
- red-team loop methodology,
- OWASP taxonomy refresher,
- condensed AI safety recap.

---

## Timing summary

| Section | Slides | Target time |
|---|---|---|
| Intro, scope, context | 1–5 | 5 min |
| Demo 1 — Provide | 6–11 | 6 min |
| Demo 2 — Consume | 12–15 | 5 min |
| Demo 3 — Observe | 16–36 | 12 min |
| Transition | 37 | <1 min |
| Demo 4 — Identify | 38–42 | 5 min |
| Demo 5 — Mitigate | 43–46 | 4 min |
| Close — production and vision | 47–53 | 7 min |
| **Total main story** | | **~45 min** |
| **Q&A buffer** | | **~15 min** |

If you are running long, cut optional live-refresh steps first, then skip backup appendix slides 54–57.
