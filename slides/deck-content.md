# Deck content — "WIP OpenShift AI - Overview"

Generated reference snapshot of the live Google Slides deck ([open it](https://docs.google.com/presentation/d/1OqZQIPd1monbRLpzaLUcuUegf8xuhn2mwqnyfX7XTho/edit)) after the latest flow rebuild for slides 38–57. Use [`demo-plan.md`](demo-plan.md) for presenter steps and timing; use this file to review exact on-slide text and speaker notes.

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
Token limits

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
- TODO: Agent deployment dazu nehmen
- Consume: safely, from a governed workspace - API keys, MaaS governance and the Playground.
- Observe: which agent answered, which tools, how fast, and what if it is wrong - MLflow.
- Identify: what else is broken - automated red teaming with EvalHub and Garak.
- Mitigate: how do we close it - prompts, guardrails and sandboxing.
- Every demo today hangs on one of these five questions.

---

## Demo 1 — Provide (slides 6–11)

### Slide 6
> Provide  
  
Demos:  
Models as a Service  
Agents  
MCP Servers

### Slide 7
> Model is super large, but you want your engineers to use it anyways?

> AI asset endpoints → Models as a service

### Slide 8
_Contains a full-bleed screenshot image._

> Models  —  Provide AI models by click of a button

> Catalog  
Registry  
MaaS Governance - Token limits

### Slide 9
_Contains a full-bleed screenshot image._

> Playgrounds  —  Test before you consume …

### Slide 10
_Contains a full-bleed screenshot image._

> Agents available based on catalog  
Extend your agent catalog items

> Agents  —  Provide AI agents easily

### Slide 11
_Contains a full-bleed screenshot image._

> MCP Servers  —  Provide an MCP landscape

> Create your application  
Containerize your application  
Push your app to registry  
Create CR in RHOAI  
  
  
  
CR - CustomResource

---

## Demo 2 — Consume (slides 12–15)

### Slide 12
> Consume  
  
Demos:  
API keys  
Playground

### Slide 13
> Can engineers use the model from a safe, governed workspace?

> API keys, MaaS governance and the Playground → safe self-service access with built-in metrics

**Speaker notes:**
- Demo 2 - Consume:
- Open Gen AI studio -> API keys - show an active key tied to the redhat-maas subscription
- Open Gen AI studio -> Playground, pick a model behind an AI asset endpoint
- Send a live chat message, point out token count, time to first token, and tokens per second
- These are the same numbers MaaS governance uses for showback and rate limiting
- No GPU, no SDK, no custom client needed - any engineer with a key can consume the model

### Slide 14
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Screenshot: active API keys under the redhat-maas subscription.

### Slide 15
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Screenshot: Playground chat response with live token/latency metrics.

---

## Demo 3 — Observe (slides 16–36)

### Slide 16
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

### Slide 17
> Observe  
  
Demos:  
MLFlow

### Slide 18
> Which agent processed your question? Was it a single agent, or did multiple agents collaborate?

> MLFlow

**Speaker notes:**
- Solved in the demo: every request lands in MLflow as one trace. The trace breakdown shows the whole LangGraph tree - guardrails, router and every specialist agent as nested spans (e.g. the CEO assistant calling the pipeline-summary tool). In the multi-agent loan-origination experiment you see exactly which agent handled what, and how the agents handed off to each other.

### Slide 19
> Which tools did the agent invoke to gather pipeline data, denial rates, and performance metrics?

> MLFlow

**Speaker notes:**
- Solved in the demo: each tool invocation (get_pipeline_summary, product_info, affordability_calc, ...) is its own span with the exact inputs the agent passed and the outputs the tool returned. You can answer 'which tools were called, with which arguments, and what came back' for every single request.

### Slide 20
> How long did each step take? Was the LLM call fast, or did a tool call add latency?

> MLFlow

### Slide 21
> What if the response was wrong? How would you trace back to the root cause?

> MLFlow

### Slide 22
> What if a tool call failed silently? Would you even know?

> MLFlow

### Slide 23
_Contains a full-bleed screenshot image._

> Why Traditional Monitoring Isn’t Enough

### Slide 24
_Contains a full-bleed screenshot image._

### Slide 25
> What if you don’t want to implement these things by yourself?

> MLflow, managed in Red Hat AI → one line: mlflow.langchain.autolog()

**Speaker notes:**
- Solved in the demo: you don't build this yourself. One line - mlflow.langchain.autolog() - turns on tracing for 40+ LLM frameworks with zero changes to application logic, and the MLflow server runs managed inside Red Hat AI (Experiments page). Built on OpenTelemetry, so traces also flow to Jaeger, Zipkin or Grafana Tempo.

### Slide 26
_Contains a full-bleed screenshot image._

### Slide 27
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Every request becomes exactly one trace, with execution time and state in the list. This is the entry point for 'which agent processed my question?' - pick a trace and open it.

### Slide 28
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Answers: which tools were called
- The trace summary lists each call as it happened (ChatOpenAI, ceo_lo_performance, ...). Answers 'which tools did the agent invoke to gather pipeline data, denial rates and performance metrics?'

### Slide 29
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Answers: which agent handled it — the span tree
- The LangGraph span tree shows guardrails, routing and every agent/tool span with its nesting. Answers 'was it a single agent, or did multiple agents collaborate?'

### Slide 30
_Contains a full-bleed screenshot image._

**Speaker notes:**
- The timeline breaks total latency into per-span bars - LLM call vs. tool chain is immediately visible. Answers 'how long did each step take?'

### Slide 31
_Contains a full-bleed screenshot image._

**Speaker notes:**
- System prompts are registered and versioned in MLflow, with metadata and aliases - prompt changes become auditable and reproducible.

### Slide 32
_Contains a full-bleed screenshot image._

**Speaker notes:**
- A versioned evaluation dataset turns 'wrong' into something measurable.
- Datasets are stored on the MLflow server, not as local files. This means they’re versioned, shareable across team members, and can be reused across evaluation runs. When a new team member joins, they run evaluations against the same test cases—ensuring consistent quality standards across the team.
- Teams without evaluation datasets often discover quality issues only after customer complaints—weeks too late. A structured dataset catches regressions during development, before they reach production.

### Slide 33
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Some assessment columns may show null values. This is expected — at this stage we are only running simple deterministic scorers (contains_expected, has_numeric_result, response_length), not the LLM-as-a-Judge scorers. You’ll enable those in Exercise 6, and the remaining columns will populate.
- If assessment columns are not visible in the Traces view, use the Columns dropdown and enable All Assessments. MLflow doesn’t always show them by default.

### Slide 34
_Contains a full-bleed screenshot image._

**Speaker notes:**
- The additional columns show Pass/Fail for each LLM judge. Notice how tool_call_correctness shows 83% pass rate and safety shows 100%. The agent is safe but occasionally calls the wrong tool.
- Judges score every trace: tool_call_correctness 83%, safety 100% - the agent is safe but occasionally calls the wrong tool.
- The additional columns show Pass/Fail for each LLM judge. Notice how tool_call_correctness shows 83% pass rate and safety shows 100%. The agent is safe but occasionally calls the wrong tool.

### Slide 35
_Contains a full-bleed screenshot image._

**Speaker notes:**
- Drill from a failing score straight into the trace that caused it: judge results next to expectations for that single request.

### Slide 36
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

## Transition (slides 37)

### Slide 37
> Three down, two to go

**Speaker notes:**
- Provide, Consume and Observe are solved, live, on this cluster.
- Two customer questions remain: what is broken, and how do we fix it.
- That is Identify and Mitigate - then we talk about getting to production.

---

## Demo 4 — Identify (slides 38–42)

### Slide 38
> Identify  
  
Demos:  
EvalHub  
Garak (OWASP top 10)

**Speaker notes:**
- - Talk track: We now shift from Observe to Identify: what can go wrong before production.
- - Customer value: Security risk discovery becomes explicit, repeatable, and measurable.
- - Transition: Start with the concrete customer question on the next slide.

### Slide 39
> What security issues does my agent or model have? Are there other known issues?

> Automated red teaming → EvalHub, Garak, benchmarks

**Speaker notes:**
- - Talk track: The question is not whether risk exists; it is how fast we can find it with evidence.
- - Customer value: Automated red teaming reduces manual effort and catches issues earlier.
- - Transition: Before showing the run, align on the safety model and why this loop matters.
- - Fallback: If the live Evaluations status is delayed, use the screenshot and continue the same story.

### Slide 40
> AI Safety on Openshift AI

> A set of tools for:  
Identifying AI/Model risks → automated red teaming  
Rectifying those risks 	→ guardrailing

> AI Safety

**Speaker notes:**
- - Talk track: AI safety here is a loop: identify model risk, then mitigate with controls.
- - Customer value: Teams get one operating model from discovery to remediation, not disconnected tools.
- - Transition: Next, we show a real evaluation run that proves this process on the cluster.

### Slide 41
_Contains a full-bleed screenshot image._

**Speaker notes:**
- - Talk track: This is the seeded evaluation evidence in Develop and train -> Evaluations.
- - Customer value: Security posture is visible in the same place as other model evaluations.
- - Transition: Next slide explains what EvalHub and Garak are doing under the hood.
- - Fallback: If live navigation is slow, stay on this screenshot and call out run name, model, and evaluation type.

### Slide 42
> EvalHub: scheduled red teaming for LLMs

> Managed service in Red Hat AI for scheduled security and quality probes.  
Garak provides OWASP (Open Web Application Security Project) LLM probes such as prompt injection, jailbreak, and data leakage.  
Results appear in Develop & train -> Evaluations alongside other evaluation runs.  
Use as a CI gate before model promotion to catch regressions early.

> garak \  
  --model_type rest \  
  --model_name gpt-oss-120b \  
  --probes owasp.LLM01 \  
  --generations 5

**Speaker notes:**
- - Talk track: EvalHub runs scheduled probes; Garak provides the OWASP (Open Web Application Security Project) vulnerability probes.
- - Customer value: Red teaming shifts left into a repeatable gate before model promotion.
- - Transition: Once we can identify risk consistently, we move to Mitigate and runtime controls.

---

## Demo 5 — Mitigate (slides 43–46)

### Slide 43
> Mitigate  
  
Demos:  
Playground guardrails  
NeMo Guardrails

**Speaker notes:**
- - Talk track: We move from finding issues to closing them in runtime traffic.
- - Customer value: Identify without mitigation is incomplete for production readiness.
- - Transition: The next slide asks the core mitigation question customers raise.

### Slide 44
> How do we close the issues these scans find?

> Prompts, guardrails, sandboxing → secure, observable and scalable by design

**Speaker notes:**
- - Talk track: We close findings with prompts, guardrails, and sandboxing.
- - Customer value: Controls apply before and after model response, not only at offline test time.
- - Transition: First show the guardrails settings in the Playground, then the platform-level resource.
- - Fallback: If UI tabs change, narrate from the screenshot and explain the same control concepts.
- - Acronym note: PII means personally identifiable information.

### Slide 45
_Contains a full-bleed screenshot image._

**Speaker notes:**
- - Talk track: This screenshot shows user-input and model-output guardrail controls in one place.
- - Customer value: AI engineers can enable protection fast while platform teams keep central governance.
- - Transition: Next slide shows the NeMo Guardrails resource that operationalizes this pattern.

### Slide 46
> NeMo Guardrails: request and response protection

> A guardrail model screens every request and response.  
Input guardrails: jailbreak and prompt-attack defense, PII filtering, moderation.  
Output guardrails: PII leak prevention and moderation.  
Enable per agent in Playground or centrally with a NemoGuardrails custom resource.

> apiVersion: trustyai.opendatahub.io/v1alpha1  
kind: NemoGuardrails  
metadata:  
  name: nemoguardrails  
spec:  
  nemoConfigs:  
    - name: default  
      default: true

**Speaker notes:**
- - Talk track: NeMo Guardrails enforces request and response protection as a Kubernetes-native resource.
- - Customer value: The same policy model can be demoed quickly and managed centrally at scale.
- - Transition: With Identify and Mitigate complete, we recap the five-question story.

---

## Takeaways, vision, and close (slides 47–53)

### Slide 47
> Takeaways  
  
→ five questions, answered

**Speaker notes:**
- - Talk track: Recap all five answers: Provide, Consume, Observe, Identify, Mitigate.
- - Customer value: This is a complete path from first access to production controls.
- - Transition: Next, we pivot from what works today to what must mature for production scale.

### Slide 48
> Vision and next steps  
  
Journey to production

**Speaker notes:**
- - Talk track: The next segment is vision and next steps on the journey to production.
- - Customer value: Customers leave with both immediate actions and a forward roadmap view.
- - Transition: Start with the three gaps we still need to close.

### Slide 49
_Contains a full-bleed screenshot image._

> Three critical gaps: Pilot to production

> Ungoverned autonomy

> Unconstrained dynamic code execution creates security risks, requiring isolated environments with deep execution tracing to monitor autonomous actions

> Scalability and performance

> Multi-agent architectures generate unpredictable, concurrent inference spikes that traditional infrastructure cannot handle

> Agent identity

> Agents need secure, cryptographic identities to access sensitive tools under least-privilege principles — hardcoded keys are unacceptable in production

**Speaker notes:**
- - Talk track: The remaining gaps are identity, ungoverned autonomy, and scalability under agentic load.
- - Customer value: This clarifies where pilots fail and where platform investment must focus.
- - Transition: Next slide maps each gap to concrete Red Hat AI capabilities.

### Slide 50
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
- - Talk track: Map each gap to capabilities: identity controls, safety and observability, and inference scalability.
- - Customer value: Production posture is architectural, not a single feature toggle.
- - Transition: Now ground this with OpenShell as the runtime isolation layer.

### Slide 51
_Contains a full-bleed screenshot image._

> Agent Sandboxing with OpenShell

> See OpenShell (and OpenCode) running securely on Red Hat AI: https://youtu.be/tosYZLhtxwE

**Speaker notes:**
- - Talk track: OpenShell provides isolated agent execution with policy-governed access paths.
- - Customer value: Tool execution risk is constrained and auditable, which security teams require.
- - Transition: Final strategy slide summarizes now versus next platform direction.

### Slide 52
> Vision 2026/2027: now and next

> Live now: 5-question journey proven on Red Hat AI 3.5.  
Default path: BYOA + enterprise controls (OpenShell, identity, governance, observability).  
Optional path (targeted): OpenClaw Enterprise control plane.  
API direction: Responses now; broader Messages, A2A, and MCP governance next.

> now (3.5):  
- endpoints + API keys  
- playground + MLflow  
- EvalHub/Garak + guardrails  
  
next (targets):  
- stronger MCP governance  
- expanded control-plane workflows

**Speaker notes:**
- - Talk track: This is directional strategy: now capabilities in 3.5 and next targeted steps.
- - Customer value: Customers can start with bring your own agent now and add enterprise control-plane features as they mature.
- - Transition: Close with thank you and move to Q and A.
- - Acronym note: BYOA means bring your own agent; A2A means agent-to-agent.

### Slide 53
_Contains a full-bleed screenshot image._

> Thank you

> Red Hat is the world’s leading provider of enterprise open source software solutions. Award-winning support, training, and consulting services make Red Hat a trusted adviser to the Fortune 500.

**Speaker notes:**
- - Talk track: Thank the audience and open for questions.
- - Customer value: Reinforce that the deck can be used as a practical post-session reference.
- - Transition: Optional backup slides are available for deeper security discussion if requested.

---

## Backup appendix (optional) (slides 54–57)

### Slide 54
_Contains a full-bleed screenshot image._

> Backup: what could possibly go wrong?

> Source 1  
Source 2  
Source 3

**Speaker notes:**
- - Talk track: Backup context on representative failure modes and attack outcomes.
- - Customer value: Use this when the audience asks for concrete risk examples beyond the main flow.
- - Transition: Move to the red-teaming process slide if they want methodology details.

### Slide 55
_Contains a full-bleed screenshot image._

> Backup: red teaming for GenAI

> The Red Team Loop

> Attack

> Generate diverse adversarial prompts (e.g., using GCG, AutoDAN, or manual creativity).

> Analyze

> Evaluate model responses. Did it refuse? Did it hallucinate? Did it leak data?

> Mitigate

> Update system prompts, fine-tune the model, or patch the guardrails.

> Human Domain Experts

> E.g.Tools like Garak

> Simulating Adversarial Attacks to Build Resilience

> Examples of what can be attacked

> JailbreakingBypassing safety filters

> Prompt InjectionHijacking instructions

> Toxic ContentHate speech, violence

> PII LeakageData extraction

> "The systematic practice of simulating adversarial attacks to identify vulnerabilities, safety flaws, and alignment issues before a model is deployed."

**Speaker notes:**
- - Talk track: Backup deep dive into the red-team loop: attack, analyze, mitigate.
- - Customer value: Shows how adversarial testing becomes a disciplined engineering practice.
- - Transition: If needed, continue with OWASP vulnerability taxonomy on the next backup slide.

### Slide 56
_Contains a full-bleed screenshot image._

> Backup: OWASP top 10 LLM vulnerabilities (2025)

> Slide 2 / 2

> Prompt Injection

> User prompts manipulate LLM behavior (jailbreaks) or output in unintended ways.

> Sensitive Info Disclosure

> Exposure of PII, financial details, or proprietary algorithms via output.

> Supply Chain Risks

> Vulnerabilities in training data, third-party models, and deployment processes.

> Data/Model Poisoning

> Manipulation of training/embedding data to introduce backdoors or biases.

> Improper Output Handling

> Lack of validation/sanitization of outputs before passing to downstream systems.

> Excessive Agency

> Granting the LLM too much autonomy to execute code/functions without oversight.

> System Prompt Leakage

> Risk that internal instructions or proprietary prompts are revealed to users.

> Vector/Embedding Weakness

> Security risks targeting RAG systems, specifically vector databases or embeddings.

> Misinformation (Hallucination)

> Producing false/misleading info that users accept as fact, creating liability.

> Unbounded Consumption

> Resource exhaustion (DoS) via expensive queries or excessive token usage.

> Src: OWASP Top 10 for Large Language Model Applications

> These can be inform probes for Garak

**Speaker notes:**
- - Talk track: Backup OWASP taxonomy for LLM vulnerabilities used to frame probe coverage.
- - Customer value: Connects security language from enterprise governance to concrete model tests.
- - Transition: End with backup AI safety summary if the audience wants a simplified framing.

### Slide 57
> Backup: AI safety on OpenShift AI

> A set of tools for:  
Identifying AI/Model risks → automated red teaming  
Rectifying those risks 	→ guardrailing

> AI Safety

**Speaker notes:**
- - Talk track: Backup summary of AI safety controls across identification and mitigation.
- - Customer value: Useful short recap for security-focused Q and A.
- - Transition: Return to key takeaways or close the discussion.

---
