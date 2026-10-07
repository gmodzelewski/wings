# Deck content — "WIP OpenShift AI - Overview"

Generated reference snapshot of the live Google Slides deck ([open it](https://docs.google.com/presentation/d/1OqZQIPd1monbRLpzaLUcuUegf8xuhn2mwqnyfX7XTho/edit)) after the 2026-10-07 restructure to the five-pillar story (Provide → Consume → Observe → Identify → Mitigate). Use [`demo-plan.md`](demo-plan.md) for click-by-click presenter steps; use this file to review exact slide text and speaker notes without opening Slides.

Regenerate by re-fetching the presentation with `gws slides presentations get` and re-running the extraction snippet used to build this file (see git history of this task for the script, or ask the assistant to regenerate it).

---

## Intro, scope, and platform context (slides 1–5)

### Slide 1
_Contains a full-bleed screenshot image._

> OpenShift AI Overview

> Latest and greatest

> Georg Modzelewski  
Specialist Solution Architect, Application Platform  
georg@redhat.com

### Slide 2
_Contains a full-bleed screenshot image._

> Scope of this session  —  what we will and won't cover

> Who this is for

> Platform engineers, AI engineers and architects working with Red Hat AI / OpenShift AI.  
You should be comfortable with basic OpenShift and LLM concepts.  
Format of every block: a customer question → live demo → what it means for you. Questions welcome at any time.

> In scope — live demos

> Red Hat AI 3.5 (Developer/Tech Preview) highlights:  
Models as a service via AI asset endpoints  
API keys, MaaS governance and the Playground, with live metrics  
MLflow tracing and evaluation  
Automated red teaming with EvalHub and Garak  
Guardrails and sandboxing for production readiness

> Not in scope today

> Installation and cluster administration  
Model training, fine-tuning and data pipelines  
Evaluation theory deep dive  
Pricing and licensing  
Happy to take any of these offline afterwards.

> Five short demo blocks — each one answers a question we hear from customers.

**Speaker notes:**
- Before we dive into features, let's set the scope. This session is built for platform engineers, AI engineers and architects. We run five short demo blocks on Red Hat AI 3.5 - Models as a Service, API keys with the Playground, an MLflow tracing and evaluation teaser, automated red teaming with EvalHub and Garak, and guardrails and sandboxing to close the loop. Several features are still Developer or Tech Preview, so treat them as direction, not commitment. We will not cover installation, model training, evaluation theory or pricing today - happy to take those offline. Every block follows the same pattern: a customer question, a live demo, and what it means for you.

### Slide 3
> Red Hat AI’s focus areas

> Accelerate the development and delivery of AI solutions across hybrid-cloud environments

> Area of focus

> Accelerate  Agentic  AI delivery and stay at the forefront of innovation

> Ingrate with MCP, OpenAI Compatible API servers (OGX), Playgrounds, AI Asset Hubs

> Simplified and consistent experience for connecting models to data

> Fine-tuning, Model Customization,  RAG, Private Data, etc

**Speaker notes:**
- [Adel]

### Slide 4
_Contains a full-bleed screenshot image._

> A hands-on workspace to explore and experiment. Includes AI Assets Listing and an AI Playground to interact with models, adjust hyperparameters, and rapidly prototype applications.

> The command center for AI assets. Unifies discovery, deployment, and lifecycle management of LLMs, MCP servers, and more. Backed by performance insights from the Model Validation Program.

> Complementary dashboards in Red Hat AI to power AI agents

> AI Hub & GenAI Studio

> AI Hub (for Platform Engineers)

> GenAI Studio (for AI Engineers)

**Speaker notes:**
- Red Hat AI is designed to handle the full spectrum of generative AI workflows—from standard RAG pipelines all the way to complex, autonomous agentic systems. To make that happen, we’ve unified the experience into two core dashboards: AI Hub and GenAI Studio.
- AI Hub gives Platform Engineers a single, streamlined interface that they need to explore, deploy, and manage critical AI assets — like validated models, inference services, MCP servers and agents. It provides full visibility and control, backed by the insights from Red Hat’s Model Validation Program. AI Hub encompasses the model catalog and registry features we discussed earlier.
- GenAI Studio, on the other hand, gives AI Engineers an integrated space to build and experiment. It’s where they can test the integrations of the components they’ve connected to their llama stack server like models, RAG, and mcp servers. This way they can iterate quickly in a low-friction environment before fully integrating the assets into an agentic app.
- Together, these experiences bring platform and AI engineers into one connected workflow.

### Slide 5
_Contains a full-bleed screenshot image._

> The big picture  —  five questions, one platform

> It's hard to grasp everything Red Hat AI solves. So don't think in features — follow the questions customers ask, from providing models to running agents in production.

> PROVIDE

> “Our model is huge — how do engineers use it anyway?”

> Models as a Service  
AI asset endpoints — one endpoint + API token, no GPU on the laptop

> DEMO 1

> CONSUME

> “Can engineers use it from a safe, governed IDE?”

> API key generation, MaaS Governance, Playground, Metrics  
MaaS credentials for easy consumption

> DEMO 2

> OBSERVE

> “Which agent answered? Which tools? How fast? What if it's wrong?”

> MLflow  
Tracing, per-span timeline, datasets and LLM judges

> DEMO 3

> IDENTIFY

> “What security issues does my agent/model has? Are there other known issues?”

> Automated Red Teaming  
EvalHub, Garak, Benchmarks

> DEMO 4

> MITIGATE

> “How do we close the issues?”

> Prompts, Guardrails, Sandboxing  
Secure, observable and scalable by design

> Demo 5 + OUTLOOK

> One platform — Red Hat AI: from providing models to observing, evaluating and running agents in production.

**Speaker notes:**
- This is the map for today.
- Customers rarely ask for features; they ask questions.
- Provide: the model is huge, how do engineers use it - Models as a Service.
- Consume: safely, from a governed workspace - API keys, MaaS governance and the Playground.
- Observe: which agent answered, which tools, how fast, and what if it is wrong - MLflow.
- Identify: what else is broken - automated red teaming with EvalHub and Garak.
- Mitigate: how do we close it - prompts, guardrails and sandboxing.
- Every demo today hangs on one of these five questions.

---

## Demo 1 — Provide (slides 6–9)

### Slide 6
> Provide  
  
Demos:  
Models as a Service

### Slide 7
> Model is super large, but you want your engineers to use it anyways?

> AI asset endpoints → Models as a service

### Slide 8
_Contains a full-bleed screenshot image._

### Slide 9
_Contains a full-bleed screenshot image._

---

## Demo 2 — Consume (slides 10–13)

### Slide 10
> Consume  
  
Demos:  
API keys  
Playground

### Slide 11
> Can engineers use the model from a safe, governed workspace?

> API keys, MaaS governance and the Playground → safe self-service access with built-in metrics

**Speaker notes:**
- Demo 2 - Consume:
- Open Gen AI studio -> API keys - show an active key tied to the redhat-maas subscription
- Open Gen AI studio -> Playground, pick a model behind an AI asset endpoint
- Send a live chat message, point out token count, time to first token, and tokens per second
- These are the same numbers MaaS governance uses for showback and rate limiting
- No GPU, no SDK, no custom client needed - any engineer with a key can consume the model

### Slide 12
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Screenshot: active API keys under the redhat-maas subscription.

### Slide 13
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Screenshot: Playground chat response with live token/latency metrics.

---

## Demo 3 — Observe (slides 14–34)

### Slide 14
_Contains a full-bleed screenshot image._

> The big picture  —  five questions, one platform

> It's hard to grasp everything Red Hat AI solves. So don't think in features — follow the questions customers ask, from providing models to running agents in production.

> OBSERVE

> “Which agent answered? Which tools? How fast? What if it's wrong?”

> MLflow  
Tracing, per-span timeline, datasets and LLM judges

> DEMO 3

> One platform — Red Hat AI: from providing models to observing, evaluating and running agents in production.

**Speaker notes:**
- This is the map for today - we are now at Observe.
- Provide and Consume are solved; this section answers which agent answered, which tools, how fast, and what if it is wrong - MLflow.
- Identify and Mitigate come right after this section.

### Slide 15
> Observe  
  
Demos:  
MLFlow

### Slide 16
> Which agent processed your question? Was it a single agent, or did multiple agents collaborate?

> MLFlow

**Speaker notes:**
- Solved in the demo: every request lands in MLflow as one trace. The trace breakdown shows the whole LangGraph tree - guardrails, router and every specialist agent as nested spans (e.g. the CEO assistant calling the pipeline-summary tool). In the multi-agent loan-origination experiment you see exactly which agent handled what, and how the agents handed off to each other.

### Slide 17
> Which tools did the agent invoke to gather pipeline data, denial rates, and performance metrics?

> MLFlow

**Speaker notes:**
- Solved in the demo: each tool invocation (get_pipeline_summary, product_info, affordability_calc, ...) is its own span with the exact inputs the agent passed and the outputs the tool returned. You can answer 'which tools were called, with which arguments, and what came back' for every single request.

### Slide 18
> How long did each step take? Was the LLM call fast, or did a tool call add latency?

> MLFlow

### Slide 19
> What if the response was wrong? How would you trace back to the root cause?

> MLFlow

### Slide 20
> What if a tool call failed silently? Would you even know?

> MLFlow

### Slide 21
_Contains a full-bleed screenshot image._

> Why Traditional Monitoring Isn’t Enough

### Slide 22
_Contains a full-bleed screenshot image._

### Slide 23
> What if you don’t want to implement these things by yourself?

> MLflow, managed in Red Hat AI → one line: mlflow.langchain.autolog()

**Speaker notes:**
- Solved in the demo: you don't build this yourself. One line - mlflow.langchain.autolog() - turns on tracing for 40+ LLM frameworks with zero changes to application logic, and the MLflow server runs managed inside Red Hat AI (Experiments page). Built on OpenTelemetry, so traces also flow to Jaeger, Zipkin or Grafana Tempo.

### Slide 24
_Contains a full-bleed screenshot image._

### Slide 25
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Every request becomes exactly one trace, with execution time and state in the list. This is the entry point for 'which agent processed my question?' - pick a trace and open it.

### Slide 26
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Answers: which tools were called
- The trace summary lists each call as it happened (ChatOpenAI, ceo_lo_performance, ...). Answers 'which tools did the agent invoke to gather pipeline data, denial rates and performance metrics?'

### Slide 27
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Answers: which agent handled it — the span tree
- The LangGraph span tree shows guardrails, routing and every agent/tool span with its nesting. Answers 'was it a single agent, or did multiple agents collaborate?'

### Slide 28
_Contains a full-bleed screenshot image._

**Speaker notes:**
- The timeline breaks total latency into per-span bars - LLM call vs. tool chain is immediately visible. Answers 'how long did each step take?'

### Slide 29
_Contains a full-bleed screenshot image._

**Speaker notes:**
- System prompts are registered and versioned in MLflow, with metadata and aliases - prompt changes become auditable and reproducible.

### Slide 30
_Contains a full-bleed screenshot image._

**Speaker notes:**
- A versioned evaluation dataset turns 'wrong' into something measurable.
- Datasets are stored on the MLflow server, not as local files. This means they’re versioned, shareable across team members, and can be reused across evaluation runs. When a new team member joins, they run evaluations against the same test cases—ensuring consistent quality standards across the team.
- Teams without evaluation datasets often discover quality issues only after customer complaints—weeks too late. A structured dataset catches regressions during development, before they reach production.

### Slide 31
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Some assessment columns may show null values. This is expected — at this stage we are only running simple deterministic scorers (contains_expected, has_numeric_result, response_length), not the LLM-as-a-Judge scorers. You’ll enable those in Exercise 6, and the remaining columns will populate.
- If assessment columns are not visible in the Traces view, use the Columns dropdown and enable All Assessments. MLflow doesn’t always show them by default.

### Slide 32
_Contains a full-bleed screenshot image._

**Speaker notes:**
- The additional columns show Pass/Fail for each LLM judge. Notice how tool_call_correctness shows 83% pass rate and safety shows 100%. The agent is safe but occasionally calls the wrong tool.
- Judges score every trace: tool_call_correctness 83%, safety 100% - the agent is safe but occasionally calls the wrong tool.
- The additional columns show Pass/Fail for each LLM judge. Notice how tool_call_correctness shows 83% pass rate and safety shows 100%. The agent is safe but occasionally calls the wrong tool.

### Slide 33
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Drill from a failing score straight into the trace that caused it: judge results next to expectations for that single request.

### Slide 34
> How to use MLFlow

> Provides zero-code observability for over 40 LLM and AI frameworks.  
Enables the capture of LangChain operations—including LLM calls, tool invocations, and agent decisions—using a single autolog() call without modifying application logic.  
Built on OpenTelemetry to support unified tracing, rich metadata, and asynchronous scaling.  
Compatible with standard backends such as Jaeger, Zipkin, and Grafana Tempo.

> import mlflow  
import mlflow.langchain  
  
mlflow.set_tracking_uri(settings.MLFLOW_TRACKING_URI)  
  
mlflow.set_experiment(settings.MLFLOW_EXPERIMENT_NAME)  
  
mlflow.langchain.autolog()

**Speaker notes:**
- This single line enables automatic tracing for all LangChain and LangGraph operations: every LLM call, tool invocation, and agent decision is captured as spans without any code changes to the agents themselves.

---

## Transition (slides 35)

### Slide 35
> Three down, two to go

**Speaker notes:**
- Provide, Consume and Observe are solved, live, on this cluster.
- Two customer questions remain: what is broken, and how do we fix it.
- That is Identify and Mitigate - then we talk about getting to production.

---

## Demo 4 — Identify (slides 36–39)

### Slide 36
> Identify  
  
Demos:  
EvalHub  
Garak (OWASP top 10)

### Slide 37
> What security issues does the agent or model have? Are there other known issues?

> Automated red teaming → EvalHub, Garak, benchmarks

**Speaker notes:**
- Demo 4 - Identify:
- Open Develop & train -> Evaluations
- Show the OWASP (Open Web Application Security Project) LLM Top 10 Garak run against gpt-oss-120b
- Garak is an open-source LLM vulnerability scanner: prompt injection, jailbreak, data leakage probes
- This run was seeded by install.sh - the same scan can run on every model promotion
- Manual red teaming does not scale; a scheduled scan catches regressions before customers do

### Slide 38
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Screenshot: Develop & train -> Evaluations, OWASP LLM Top 10 Garak run.

### Slide 39
> EvalHub: automated red teaming for LLMs

> A managed service in Red Hat AI that runs automated security and quality probes against a model or agent endpoint — no custom test harness required.  
Garak, an open-source LLM vulnerability scanner, provides the probes: prompt injection, jailbreak, data leakage, and the rest of the OWASP (Open Web Application Security Project) LLM top 10.  
Results land in Develop & train → Evaluations, next to every other evaluation run.  
Manual red teaming does not scale; a scheduled scan catches regressions before customers do.

> garak \  
  --model_type rest \  
  --model_name gpt-oss-120b \  
  --probes owasp.LLM01 \  
  --generations 5

**Speaker notes:**
- EvalHub runs Garak against the AI asset endpoint on a schedule, not just once.
- OWASP (Open Web Application Security Project) publishes the LLM top 10 - the probes map directly to those categories.
- The same command that ran on stage can run as a CI gate before every model promotion.

---

## Demo 5 — Mitigate (slides 40–43)

### Slide 40
> Mitigate  
  
Demos:  
Playground guardrails  
NeMo Guardrails

### Slide 41
> How do we close the issues these scans find?

> Prompts, guardrails, sandboxing → secure, observable and scalable by design

**Speaker notes:**
- Demo 5 - Mitigate:
- Back in the Playground, open the Guardrails tab for the same agent
- User input guardrails: jailbreak and prompt-attack protection, PII (personally identifiable information) filtering, content moderation
- Model output guardrails: PII leak prevention, content moderation
- Backed by a NemoGuardrails custom resource - same pattern as any other OpenShift AI resource
- Pair this with agent sandboxing (OpenShell) for isolated, policy-controlled tool execution

### Slide 42
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Screenshot: Playground Guardrails tab, input/output rails.

### Slide 43
> NeMo Guardrails: rails on every request and response

> A guardrail model screens every request and response before it reaches, or leaves, the primary model.  
User input guardrails: jailbreak and prompt-attack protection, personally identifiable information filtering, content moderation.  
Model output guardrails: personally identifiable information leak prevention, content moderation.  
Toggle per agent in the Playground, or enforce centrally with the NemoGuardrails custom resource — the same pattern as any other OpenShift AI resource.

> apiVersion: trustyai.opendatahub.io/v1alpha1  
kind: NemoGuardrails  
metadata:  
  name: nemoguardrails  
spec:  
  nemoConfigs:  
    - name: guardrail-placeholder  
      default: true

**Speaker notes:**
- A red-teaming scan tells you what is broken; guardrails are how you stop it from reaching production traffic.
- Pair this with agent sandboxing (OpenShell) for isolated, policy-controlled tool execution, and per-tool authorization through the MCP (Model Context Protocol) gateway.

---

## Takeaways (slides 44)

### Slide 44
> Takeaways  
  
→ five questions, answered

**Speaker notes:**
- Five customer questions, five answers, all shown live today:
- Provide - Models as a Service through AI asset endpoints, no GPU on the laptop
- Consume - API keys, MaaS governance and the Playground, with live token metrics
- Observe - MLflow tracing, per-span timeline, datasets and LLM judges
- Identify - automated red teaming with EvalHub and Garak against the OWASP LLM Top 10
- Mitigate - prompts, guardrails and sandboxing close the loop
- What is left is operational scale - identity, sandboxing and inference autoscaling - that is next

---

## Closing — production readiness (slides 45–48)

### Slide 45
> Next steps  
  
Journey to production

### Slide 46
_Contains a full-bleed screenshot image._

> Three critical gaps: Pilot to production

> Ungoverned autonomy

> Unconstrained dynamic code execution creates security risks, requiring isolated environments with deep execution tracing to monitor autonomous actions

> Scalability and performance

> Multi-agent architectures generate unpredictable, concurrent inference spikes that traditional infrastructure cannot handle

> Agent identity

> Agents need secure, cryptographic identities to access sensitive tools under least-privilege principles — hardcoded keys are unacceptable in production

**Speaker notes:**
- Agent demos are usually manageable because the environment and external access are tightly controlled. Production is different. Three gaps show up quickly: identity, control over autonomous execution, and scalability.
- First, every agent needs a secure workload identity. The platform needs to know which agent is acting, what tools and data it can access, and whether that access follows least-privilege policies. Hard-coded credentials are not a production solution.
- Second, agents may generate code, call tools, and interact with external systems. Those actions need to run in an isolated environment, with detailed traces showing what the agent did, which tools it called, and what information it used.
- And third, agent workloads can be unpredictable. A single request may trigger planning, retrieval, multiple model and tool calls, retries, and evaluation. Across many users—or multiple agents—that creates inference spikes that the infrastructure has to somehow absorb and handle

### Slide 47
_Contains a full-bleed screenshot image._

> Safety & Observability  
Isolate, trace, evaluate every action

> Agent Sandbox: zero-trust container, microVM isolation.  
MLFlow Tracing: every LLM call, tool use, and decision logged  
EvalHub Real-time Evaluation: continuous scoring, drift detection

> Agent Identity & Security  
Every agent gets its own identity

> Cryptographic Identity (SPIFFE/SPIRE): Short-lived, keyless  
MCP Gateway: per-tool authorization & Audit  
Scoped OAuth2 token exchange: least-privilege access

> Scalability & Performance  
Infrastructure that handles agentic workloads

> vLLM: high-throughput model serving  
Llm-d: dynamic inference routing  
Inference-aware autoscaling: scales on KV cache pressure

> Red Hat AI - Closing the Gaps

> Getting you to production

**Speaker notes:**
- These production gaps map directly to capabilities in Red Hat AI.
- For identity and security, each agent can have its own cryptographic workload identity, using short-lived credentials instead of static secrets. The MCP gateway can then enforce authorization and auditing for individual tools, while scoped OAuth token exchange limits the agent to only the access it needs.
- For safety and observability, the agent can run inside an isolated sandbox that restricts its access to the surrounding environment. MLflow tracing captures the model calls, tool calls, and decisions across the execution path, and evaluation helps teams measure whether the agent continues to behave as expected.
- And for scalability, vLLM provides high-throughput model serving, while llm-d adds dynamic, inference-aware routing. Autoscaling can also respond to signals that are specific to inference workloads, rather than relying only on traditional CPU and memory metrics.
- Together, these capabilities provide the operational layer around the agent framework—so teams can take an agent from a controlled pilot into a secure and scalable production environment.

### Slide 48
_Contains a full-bleed screenshot image._

> Agent Sandboxing with OpenShell

> See OpenShell (and OpenCode) running securely on Red Hat AI: https://youtu.be/tosYZLhtxwE

**Speaker notes:**
- Evaluation tells us whether an agent is behaving as expected. Sandboxing controls what the agent is allowed to do while it runs.
- OpenShell is an open-source project exploring how to secure agent execution at the operating-system and network layers.
- On the left, a shared gateway stores policy, credentials, and inference configuration. Those credentials are kept outside the agent process and are only injected when an approved request is made.
- Each agent runs inside its own sandbox pod. The sandbox supervisor mediates model traffic and outbound network access, while Linux controls restrict the process itself.
- In the example shown here, the agent can call an approved inference endpoint and GitHub, but attempts to read sensitive files or connect to unapproved destinations are blocked.
- This reduces the credentials and system access exposed to the agent and limits the potential impact if it behaves unexpectedly or is compromised.
- The approach is designed to work across different agent frameworks and command-line agents without requiring security controls to be built separately into each one.

---

## Thank you (slides 49)

### Slide 49
_Contains a full-bleed screenshot image._

> Thank you

> Red Hat is the world’s leading provider of enterprise open source software solutions. Award-winning support, training, and consulting services make Red Hat a trusted adviser to the Fortune 500.

---
