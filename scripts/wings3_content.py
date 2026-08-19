"""Slide content for a plain WINGS3 MLflow on OpenShift AI deck.

Live-demo spine: teach on slides → PAUSE to the cluster → RETURN wrap.
Walkthrough modules remain the source of truth for live clicks.

No branded layouts. Each slide is title + bullets + speaker notes.
"""

from __future__ import annotations

SLIDES: list[dict] = [
    {
        "key": "title",
        "layout": "title",
        "title": "MLflow on OpenShift AI",
        "subtitle": "WINGS 3 deep dive — see the agent, debug it, prove it got better",
        "notes": (
            "One-hour deep dive plus an optional follow-on lab.\n"
            "Red thread, say it now and before every act: without a tracking server you cannot see "
            "the agent; without traces you cannot debug it; without eval you cannot prove it got better.\n"
            "Native on OpenShift AI: workspace equals the project for RBAC. The workbench injects "
            "the tracking URI. You do not paste a laptop token on stage.\n"
            "Code runs in JupyterLab workbench wings3-demo, project my-first-model.\n"
            "Follow walkthrough/00-presenter-setup.md for what is pre-staged vs live."
        ),
    },
    {
        "key": "red_thread",
        "layout": "content",
        "title": "Red thread — say this three times",
        "bullets": [
            "Without a tracking server you cannot see the agent",
            "Without traces you cannot debug it",
            "Without eval you cannot prove it got better",
            "Act 1 = see. Act 2 = debug. Act 3 = prove (toy gate). Module 4 = reviewable gate.",
        ],
        "notes": (
            "This is the only sentence that must land. Repeat it before each PAUSE.\n"
            "Act 1 proves the tracking server exists. Act 2 proves you can read a tool-call span. "
            "Act 3 proves a prompt change moved a metric. Module 4 is optional: same agent, "
            "a registered dataset, and LLM judges with rationales."
        ),
    },
    {
        "key": "why_native",
        "layout": "content",
        "title": "Why native MLflow, not an external tracer",
        "bullets": [
            "Workspace is the OpenShift project — RBAC is already there",
            "Workbench injects MLFLOW_TRACKING_URI and Kubernetes auth",
            "No laptop token on stage",
            "Act 1 is a verify of something already on the cluster, not a SaaS signup",
        ],
        "notes": (
            "Sixty seconds. Contrast an external tracer: extra identity, extra URL, a token on the laptop.\n"
            "Here the workspace is the project, the URI is injected, and you stay inside OpenShift AI.\n"
            "That is why Act 1 is oc get plus the standalone /mlflow UI, not a signup flow."
        ),
    },
    {
        "key": "three_terms",
        "layout": "content",
        "title": "Three words you will reuse all hour",
        "bullets": [
            "Project — OpenShift namespace my-first-model",
            "Workspace — MLflow name for that project (MLFLOW_WORKSPACE). The RBAC boundary.",
            "Experiment — named bucket inside the workspace",
            "wings3-agent-tracing · wings3-agent-eval · wings3-agent-eval-prod",
        ],
        "notes": (
            "Say the three words once and reuse them.\n"
            "Project is the namespace. Workspace is MLFLOW_WORKSPACE=my-first-model. "
            "Experiments: tracing for Act 2, eval for Act 3, eval-prod for Module 4.\n"
            "Workbench injects the URI; you still set the workspace. "
            "oc whoami --show-token is rehearsal-only, never on camera."
        ),
    },
    {
        "key": "personas",
        "layout": "content",
        "title": "Three hats, one thread",
        "bullets": [
            "Platform engineer — Act 1: operator, CR, standalone /mlflow. You can see the agent.",
            "AI developer — Act 2: notebook 01_agent_tracing_autolog.ipynb. You can debug it.",
            "Data scientist — Act 3: notebook 02_eval_improvement.ipynb. You can prove a prompt moved.",
            "Follow-on: same data scientist, notebook 03_prod_eval_judges.ipynb. A reviewable gate.",
        ],
        "notes": (
            "Name the hats before the agenda. Hand the hat at each wrap slide.\n"
            "Platform owns Act 1. Developer owns Act 2. Data scientist owns Act 3 and Module 4.\n"
            "Repeat the red thread before each act."
        ),
    },
    {
        "key": "agenda",
        "layout": "content",
        "title": "Sixty minutes, three PAUSE marks",
        "bullets": [
            "Intro + why native — 6 min (slides)",
            "PAUSE 1 — Act 1 install verify — 8 min (oc get, then /mlflow)",
            "PAUSE 2 — Act 2 autolog traces — 22 min (workbench notebook)",
            "PAUSE 3 — Act 3 evaluation — 15 min (same workbench)",
            "Production CR + Q&A — 9 min (slides)",
            "Not in this hour: Module 4 datasets + judges — 20–25 min follow-on",
        ],
        "notes": (
            "6 intro, 8 install, 22 tracing, 15 evaluation, 9 production and Q&A.\n"
            "The MLflow operator is pre-enabled. Live install is verify, not wait-for-Ready.\n"
            "Act 2: one query in 01_agent_tracing_autolog.ipynb. Act 3: skip live v1 if already logged.\n"
            "Module 4 is after the hour if they want the promote-gate story. Do not squeeze it in."
        ),
    },
    {
        "key": "where",
        "layout": "content",
        "title": "Where the demo actually runs",
        "bullets": [
            "OpenShift AI dashboard — project my-first-model. Do not Create workbench from the UI.",
            "Workbench wings3-demo — YAML only, ServiceAccount wings3-demo",
            "Standalone /mlflow — Traces, Details & Timeline, Evaluation, Datasets. Not the embedded Experiments view.",
            "LLM — in-cluster vLLM Llama 3.2 3B (KServe). No port-forward on stage.",
        ],
        "notes": (
            "Dashboard Create workbench uses ServiceAccount default and gets PERMISSION_DENIED. "
            "The YAML Notebook uses wings3-demo; the MLflow webhook binds RBAC to that name.\n"
            "Paste mlflow_ui from walkthrough/partials/_attributes.md. Do not type a placeholder host.\n"
            "Laptop plus oc port-forward is an appendix for rehearsal only."
        ),
    },
    {
        "key": "prestage",
        "layout": "content",
        "title": "Pre-stage (off camera)",
        "bullets": [
            "mlflowoperator is Managed; MLflow CR already applied (do not oc apply on camera)",
            "InferenceService llama-32-3b-instruct is Ready",
            "Workbench Running from workbench-wings3-demo.yaml; demo folder on the PVC; pip already done",
            "Optional: v1 eval run in wings3-agent-eval",
        ],
        "notes": (
            "If something in this list is missing, that is a pre-stage miss. Do not debug it on camera.\n"
            "Pip lives in the notebook venv, not the PVC — re-run after a workbench restart.\n"
            "RHOAI 3.4 RHAI index has langgraph 1.x only: pip install -r requirements.txt "
            "--extra-index-url https://pypi.org/simple.\n"
            "Checklist: walkthrough/00-presenter-setup.md."
        ),
    },
    {
        "key": "act1_section",
        "layout": "section",
        "title": "Act 1 — Install (verify)",
        "subtitle": "Platform · 8 minutes · you can see the agent",
        "notes": (
            "Hand the platform hat. Red thread: without a tracking server you cannot see the agent.\n"
            "Live is oc get only. The CR was applied in presenter setup."
        ),
    },
    {
        "key": "install_steps",
        "layout": "content",
        "title": "Act 1 — what you verify",
        "bullets": [
            "oc get datasciencecluster — mlflowoperator is Managed",
            "oc get mlflow / oc get pods -l app=mlflow — server Running",
            "Namespace my-first-model has opendatahub.io/dashboard=true",
            "Dev CR is SQLite plus PVC. Production is Postgres plus S3 — tease, not this hour.",
        ],
        "notes": (
            "SWITCH TO TERMINAL only to show oc get. Do not oc apply on camera.\n"
            "Expected: mlflowoperator Managed; a mlflow pod Ready 2/2.\n"
            "First start can take several minutes. If READY is not 2/2, skip to the wrap and keep talking. "
            "Do not watch CrashLoop on camera.\n"
            "Next click is standalone /mlflow, not the Projects list."
        ),
    },
    {
        "key": "architecture",
        "layout": "content",
        "title": "What you are looking at",
        "bullets": [
            "Gateway exposes standalone /mlflow",
            "Operator runs the tracking server in redhat-ods-applications",
            "Workbench annotation opendatahub.io/mlflow-instance=mlflow injects URI and Kubernetes auth",
            "You still set MLFLOW_WORKSPACE=my-first-model",
        ],
        "notes": (
            "Gateway is the UI. Operator is the server. Injection is how the notebook talks to MLflow "
            "without a token.\n"
            "KServe vLLM in my-first-model is the in-cluster model. Token auth is the laptop path."
        ),
    },
    {
        "key": "demo_install",
        "layout": "section",
        "title": "PAUSE — terminal + /mlflow",
        "subtitle": "oc get, then workspace my-first-model",
        "notes": (
            "PAUSE. Terminal: oc get mlflow -n redhat-ods-applications and oc get pods -l app=mlflow. "
            "Do not oc apply.\n"
            "Then open the standalone /mlflow URL from _attributes.md. "
            "Workspace dropdown → my-first-model.\n"
            "Do not wait for a cold start. If the pod is not Ready, narrate and move on."
        ),
    },
    {
        "key": "wrap_see",
        "layout": "content",
        "title": "Wrap — you can see the agent",
        "bullets": [
            "Tracking server is on the cluster",
            "Workspace is the project",
            "Without this UI the next notebook is a black box",
        ],
        "notes": (
            "Close Act 1 on the red thread: you can see the agent now.\n"
            "Traces and Evaluation live in this standalone UI, not the embedded Experiments view.\n"
            "Hand the hat to the developer."
        ),
    },
    {
        "key": "act2_section",
        "layout": "section",
        "title": "Act 2 — Autolog traces",
        "subtitle": "Developer · 22 minutes · you can debug it",
        "notes": (
            "Hand the developer hat. Red thread: without traces you cannot debug it.\n"
            "Open JupyterLab workbench wings3-demo. Notebook 01_agent_tracing_autolog.ipynb. "
            "Do not open traced_agent.py or the CLI script on stage."
        ),
    },
    {
        "key": "autolog",
        "layout": "content",
        "title": "One line, full traces",
        "bullets": [
            "mlflow.langchain.autolog() before the agent runs",
            "No manual spans. Without it you miss the calculator span.",
            "Agent: LangGraph ReAct + calculator tool + Llama 3.2 3B on cluster vLLM",
            "Live query: Calculate 256 divided by 16 → 16.0",
        ],
        "notes": (
            "The SHOW cell is the whole teaching object: one autolog line before invoke.\n"
            "Llama 3.2 3B: one tool call per turn; keep max_tokens at 256; calculator-only. "
            "Extra queries often Error — that is the debug beat, then the OK tree.\n"
            "If the clock is tight, run only that one query."
        ),
    },
    {
        "key": "contrast_manual",
        "layout": "content",
        "title": "Manual spans vs autolog",
        "bullets": [
            "Manual: a custom span per node — easy to miss the tool, high maintenance",
            "Autolog: LangGraph, ChatOpenAI, calculator — one line",
            "Autolog is the RHOAI on-ramp. Custom spans still exist if you need them later.",
        ],
        "notes": (
            "Sixty seconds of contrast, then PAUSE to the notebook.\n"
            "Say: without autolog you would miss the calculator span. That is why Act 2 exists."
        ),
    },
    {
        "key": "act2_show",
        "layout": "content",
        "title": "Notebook SHOW cells (top to bottom)",
        "bullets": [
            "Env — injected MLFLOW_*. Workspace must be my-first-model.",
            "SHOW: calculator tool — the span autolog will capture",
            "SHOW: mlflow.langchain.autolog() — before the agent runs",
            "SHOW: one query — Calculate 256 divided by 16",
        ],
        "notes": (
            "Stop at each SHOW comment. Do not scroll past autolog without pointing at it.\n"
            "Expected success path: The result of 256 divided by 16 is 16.0. "
            "Then: MLflow UI → Traces → Details & Timeline."
        ),
    },
    {
        "key": "demo_trace",
        "layout": "section",
        "title": "PAUSE — notebook, then Traces",
        "subtitle": "Error row, then OK 256 ÷ 16 Details & Timeline",
        "notes": (
            "PAUSE. JupyterLab wings3-demo. Open 01_agent_tracing_autolog.ipynb.\n"
            "Scroll SHOW cells: calculator, autolog, one query.\n"
            "Then standalone /mlflow → workspace my-first-model → experiment wings3-agent-tracing → Traces.\n"
            "Do not click the latest row. Open an Error and say where it failed (timeout, empty response, "
            "or missing tool). Do not linger.\n"
            "Then open the OK Calculate 256 divided by 16 row. Drawer: Details & Timeline. "
            "Point at LangGraph → ChatOpenAI → calculator → ChatOpenAI."
        ),
    },
    {
        "key": "wrap_debug",
        "layout": "content",
        "title": "Wrap — you can debug it",
        "bullets": [
            "Error row is the failure",
            "OK tree shows the calculator span",
            "Without traces you cannot debug the agent",
        ],
        "notes": (
            "Close Act 2 on the red thread: you can debug it now.\n"
            "The Error row taught the failure; the OK tree taught the tool call.\n"
            "Hand the hat to the data scientist."
        ),
    },
    {
        "key": "act3_section",
        "layout": "section",
        "title": "Act 3 — Evaluation",
        "subtitle": "Data scientist · 15 minutes · you can prove a prompt moved",
        "notes": (
            "Hand the data scientist hat. Red thread: without eval you cannot prove it got better.\n"
            "SAME workbench. Notebook 02_eval_improvement.ipynb.\n"
            "SAY THE CAVEAT BEFORE ANY CELL: contains_expected is a substring check on four math rows. "
            "It is not an LLM-as-judge and not a production SLO."
        ),
    },
    {
        "key": "eval_loop",
        "layout": "content",
        "title": "Substring, n=4, not an SLO",
        "bullets": [
            "contains_expected — True if expected_answer appears in the output (e.g. 16)",
            "v1: You are a helper. Answer briefly. — may skip the tool or omit the number",
            "v2: Precise math assistant. Always use the calculator. State the numeric result.",
            "Rehearsal: contains_expected 25% → 50%. has_numeric_result was already 100% on both.",
        ],
        "notes": (
            "Say this BEFORE the notebook: contains_expected is a substring check on four math rows. "
            "It is not an LLM-as-judge and not a production SLO.\n"
            "v2 is only a system-prompt change. Same model, same calculator, same four rows, same scorers.\n"
            "Celebrate direction of improvement, then say you would add judges and a larger dataset "
            "before a real promote gate — that is Module 4.\n"
            "If v1 already exists from rehearsal, run v2 only."
        ),
    },
    {
        "key": "act3_show",
        "layout": "content",
        "title": "Notebook SHOW cells (Act 3)",
        "bullets": [
            "SHOW: prompts — v1 vs v2 on screen",
            "SHOW: four-row dataset",
            "SHOW: substring scorer contains_expected",
            "SHOW: mlflow.genai.evaluate() — define run_eval, then run v1 (optional) and v2",
        ],
        "notes": (
            "Do not open evaluate_agent.py on stage. That file is CLI / bootstrap --warmup only.\n"
            "run_eval define cell does not call the LLM yet. The next cells do."
        ),
    },
    {
        "key": "demo_eval",
        "layout": "section",
        "title": "PAUSE — eval notebook, then Evaluation",
        "subtitle": "Caveat first, then v2, then a False row",
        "notes": (
            "PAUSE. First sentence out loud: substring scorer, four rows, direction not a production gate.\n"
            "Scroll SHOW cells. Run v1 if needed, then v2. If behind, skip v1 live.\n"
            "Show the printed metrics table, then Evaluation tab, experiment wings3-agent-eval, "
            "v1-baseline vs v2-improved-prompt.\n"
            "Pick a False contains_expected row and read the output. Contrast a True row that includes the number."
        ),
    },
    {
        "key": "wrap_prove",
        "layout": "content",
        "title": "Wrap — direction, not an SLO",
        "bullets": [
            "A prompt change moved a toy scorer",
            "n=4 is a demo, not a gate",
            "Judges come before you promote",
        ],
        "notes": (
            "Close Act 3 on the red thread: you can prove a prompt moved — that is direction, not an SLO.\n"
            "The False contains_expected row is the toy gate. Do not promote on a substring.\n"
            "If this is the 60-minute hour, go to production CR then Q&A. "
            "If they stay for the follow-on, Module 4 is next."
        ),
    },
    {
        "key": "production",
        "layout": "content",
        "title": "Production CR — two fields, then a real gate",
        "bullets": [
            "Demo CR: SQLite plus PVC, replicas 1",
            "Prod example: backendStoreUriFrom (Postgres secret)",
            "Prod example: artifactsDestination s3://…",
            "replicas > 1 needs remote storage, not SQLite",
        ],
        "notes": (
            "Open manifests/mlflow-prod.example.yaml if you have it on screen, or stay on this slide.\n"
            "Point at backendStoreUriFrom and artifactsDestination. Do not apply the prod CR in this hour.\n"
            "The False contains_expected row is still the toy gate — do not promote on a substring."
        ),
    },
    {
        "key": "act4_section",
        "layout": "section",
        "title": "Module 4 — Datasets + judges (follow-on)",
        "subtitle": "Data scientist · 20–25 min · not in the 60-minute hour",
        "notes": (
            "Only if they stayed. Act 3 already promised judges before you promote.\n"
            "Same workbench. Notebook 03_prod_eval_judges.ipynb. Experiment wings3-agent-eval-prod "
            "so Act 3 numbers stay clean.\n"
            "SAY THIS BEFORE CELLS: 3B is the agent; judges use hosted gpt-oss-120b from Secret wings3-judge-llm."
        ),
    },
    {
        "key": "judges",
        "layout": "content",
        "title": "A reviewable gate, not a substring",
        "bullets": [
            "Golden set: demo/datasets/math_golden.jsonl — 8 calculator-only rows (first four = Act 3)",
            "Register it: create_dataset + merge_records → MLflow Datasets tab (math_golden)",
            "Hybrid scorers: contains_expected + Correctness + Guidelines (numeric_and_clear)",
            "Judge model: hosted_vllm:/gpt-oss-120b via hosted MaaS (Secret wings3-judge-llm) — not openai:/ and not gpt-4o-mini",
            "Live run: v2 prompt only. Run name v2-judged.",
        ],
        "notes": (
            "v2 prompt is already proven in Act 3. Module 4 does not re-run v1 vs v2.\n"
            "expected_answer feeds the substring scorer. expected_facts feeds Correctness.\n"
            "Keep contains_expected so a flaky judge row still has a cheap metric.\n"
            "Do not use trace-based make_judge on stage — 3B already blows context on extra queries.\n"
            "Eight rows times one agent plus two judges is about 24 LLM calls. If vLLM is cold, "
            "walk SHOW cells and open a pre-logged v2-judged run."
        ),
    },
    {
        "key": "act4_show",
        "layout": "content",
        "title": "Notebook SHOW cells (Module 4)",
        "bullets": [
            "SHOW: golden JSONL — expected_answer vs expected_facts",
            "SHOW: register dataset",
            "SHOW: hybrid scorers — print judge_model hosted_vllm:/gpt-oss-120b",
            "SHOW: mlflow.genai.evaluate() — then run v2-judged",
        ],
        "notes": (
            "Do not open evaluate_agent_judges.py on stage.\n"
            "If the judge cell did not print hosted_vllm:/gpt-oss-120b, openai:/ will "
            "call api.openai.com with key unused and 401. Fix HOSTED_VLLM_API_BASE = JUDGE_BASE_URL."
        ),
    },
    {
        "key": "demo_judges",
        "layout": "section",
        "title": "PAUSE — judges notebook, then Datasets + Evaluation",
        "subtitle": "Read a rationale. That is the beat Act 3 cannot do.",
        "notes": (
            "PAUSE. Caveat first: 3B is the agent; gpt-oss-120b is the judge.\n"
            "Walk SHOW cells. Run v2 if warm.\n"
            "Standalone /mlflow → workspace my-first-model → experiment wings3-agent-eval-prod.\n"
            "Datasets → math_golden, 8 records.\n"
            "Evaluation → v2-judged. Open a row where substring and judge disagree, or a Fail with "
            "rationale, and read the judge text out loud."
        ),
    },
    {
        "key": "wrap_gate",
        "layout": "content",
        "title": "Wrap — a gate you can argue with",
        "bullets": [
            "Named golden set in MLflow, not a Python list",
            "Scores with rationales, plus a cheap substring safety net",
            "Agent is in-cluster 3B; judges are hosted gpt-oss-120b",
        ],
        "notes": (
            "Close Module 4 honestly: the agent/judge split is production-shaped; eight math rows are not a production SLO.\n"
            "SQLite is enough for Evaluation Datasets on this cluster. Postgres plus S3 is still "
            "the tracking-server production CR from the previous slide — do not mix the two stories."
        ),
    },
    {
        "key": "closing",
        "layout": "content",
        "title": "See → debug → prove",
        "bullets": [
            "Act 1 — tracking server on the cluster",
            "Act 2 — autolog traces, Error then OK tree",
            "Act 3 — prompt change moved a toy scorer",
            "Module 4 — dataset + judges before you promote",
            "Walkthrough: 00-presenter-setup.md. Q&A.",
        ],
        "notes": (
            "Recap the red thread one last time.\n"
            "Production next step for the server: backendStoreUriFrom (Postgres) and "
            "artifactsDestination (S3).\n"
            "Production next step for the agent: grow the golden set — "
            "do not promote on a substring gate or eight calculator rows.\n"
            "Q&A. Next step for them: run walkthrough/00-presenter-setup.md on their cluster."
        ),
    },
]

EXPECTED_SLIDE_COUNT = len(SLIDES)
