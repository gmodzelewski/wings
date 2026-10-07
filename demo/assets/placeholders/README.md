# Demo screenshot placeholders — Act 5 (EvalHub + Garak)

Captured on the demo cluster for the customer event / guardrails coda.

| File | Content |
|------|---------|
| `demo1-evalhub-submit.png` | Evaluations → Select evaluation type (Benchmark / Benchmark suite) |
| `demo2-evalhub-results.png` | Evaluations list — unguarded + guarded Garak runs |
| `demo3-garak-pipeline.png` | Unguarded Garak detail — **100%** ASR / **Fail** (before) |
| `demo4-garak-html-report.png` | Guarded Garak detail — **0%** ASR / **Pass** (after) |
| `demo4-garak-html-report.html` | Companion before/after probe summary table |

**Fallback rule:** if live jobs fail or run long, narrate from these screenshots. Do not debug provider install on stage.

**Lab endpoints (workshop MaaS key 401):** unguarded `wings-unguarded-llm`; Garak guarded target `wings-guarded-llm` (refuse stub). NeMo Route is the live Playground/curl guarded URL. Rotate a real workshop token with `./scripts/rotate_maas_upstream_key.sh`.
