# Future Inference Compute Architecture — Home Lab Handover

**Status:** Future-phase architecture note  
**Date:** 2026-09-11  
**Scope:** Long-term model-serving and compute architecture for the Home Lab / AI software factory  
**Reviewed and amended:** 2026-09-11, against the accepted ADRs. Three changes: the harness is
called **Factory** throughout (the original said "Fabric", a transcription artefact rather than a
second name); the Gigabit Ethernet line is restated as a preference rather than a requirement
(§5.1); and the autonomy the end-state assumes is made explicit along with the route to it
(§19.1).  
**Implementation priority:** Deferred. This document captures direction and design intent so the ideas are not lost while the current Home Lab, Factory harness, knowledge layer, and factory architecture are still being built.

---

## 1. Purpose of this document

The Home Lab is evolving toward an AI-native software development system in which a user can eventually request something at the feature level and allow the system to carry that work through multiple stages with limited human intervention.

The current project should **not** attempt to build the complete compute architecture described here yet.

This document exists to preserve the intended future direction:

- keep the Lenovo M700 as the orchestration/control node;
- build the AI operating system and Factory agent harness first;
- keep model access provider-agnostic;
- introduce cloud GPU inference as an interchangeable compute backend;
- retain a future single-GPU local inference node as the canonical local hardware target;
- use persistent model storage independently of ephemeral GPU compute;
- eventually schedule compute at the workflow/session level rather than per individual prompt;
- treat multi-GPU infrastructure only as a possible later experiment if actual workloads justify it.

The objective is to make future implementation deliberate rather than improvising the architecture when local/cloud inference becomes relevant.

---

# 2. Project context

The long-term system is better understood as an **AI software factory** than as a chatbot.

The user should eventually be able to issue a high-level instruction such as:

> Implement feature X.

The system should then coordinate a chain of work such as:

1. Product definition and requirements.
2. Planning and decomposition.
3. Task and sub-task creation.
4. Implementation.
5. Code review.
6. Testing.
7. Corrections and iteration.
8. Pull request creation.
9. Approval/merge logic.
10. Completion reporting.

This implies many model calls across different roles and different quality/cost requirements.

The intended architecture therefore separates:

- orchestration;
- agent behavior;
- memory/context;
- backlog/work state;
- model routing;
- inference infrastructure;
- tools and code execution.

The inference layer should be **replaceable infrastructure**, not the center of the system.

---

# 3. Long-term conceptual architecture

```text
                               USER
                                │
                      "Implement feature X"
                                │
                                ▼
┌──────────────────────────────────────────────────────────────┐
│                       AI OPERATING SYSTEM                    │
│                                                              │
│ lifecycle · scheduling · state · orchestration · backlog     │
│ dependencies · permissions · events · execution management   │
└──────────────────────────────┬───────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                         FACTORY                               │
│                    AI / AGENT HARNESS                       │
│                                                              │
│ Product Manager → Planner → Developer → Reviewer → Tester    │
│            ↘ task decomposition / correction loops ↗        │
└──────────────────────────────┬───────────────────────────────┘
                               │
                   Memory / project context
                               │
                               ▼
┌──────────────────────────────────────────────────────────────┐
│                    MODEL ROUTER / GATEWAY                    │
└───────────────┬──────────────────┬───────────────────────────┘
                │                  │
                ▼                  ▼
        Hosted model APIs     Self-hosted models
        OpenAI / Anthropic           │
        other providers              ▼
                           ┌─────────────────────┐
                           │   COMPUTE MANAGER   │
                           └──────────┬──────────┘
                                      │
                         ┌────────────┴─────────────┐
                         ▼                          ▼
                  Cloud GPU worker          Future local node
                  ephemeral compute         RTX 3090 24 GB
                         │                          │
                         └────────────┬─────────────┘
                                      ▼
                                model response
                                      │
                                      ▼
                           next workflow transition
```

The critical boundary is:

> Agents choose or request capabilities. Infrastructure decides where those capabilities run.

---

# 4. Current control-plane role: Lenovo M700

The Lenovo ThinkCentre M700 remains the Home Lab's primary always-on orchestration node.

Its future responsibilities may include:

- AI operating-system services;
- Factory / agent orchestration;
- backlog and execution state;
- model routing;
- memory and knowledge retrieval;
- project metadata;
- databases;
- queues;
- monitoring;
- interfaces such as Telegram;
- compute-provider management;
- Git and software-factory integrations.

It should **not** become the machine responsible for large-model inference.

This preserves the existing Home Lab principle:

> orchestration and intelligence infrastructure should be separable from expensive model compute.

---

# 5. Canonical future local inference node

Before considering multi-GPU systems, a reference single-GPU machine was defined.

This remains the canonical local inference target unless future measurements show that another design is better.

## Reference specification

| Component | Target |
|---|---|
| Role | Dedicated LLM inference worker |
| GPU | NVIDIA RTX 3090 |
| VRAM | 24 GB GDDR6X |
| System RAM | 64 GB DDR4, ideally 2 × 32 GB |
| CPU | Approximately 6 cores / 12 threads; Ryzen 5 3600/5600-class or comparable |
| Storage | 1 TB NVMe minimum |
| PSU | Quality 750 W minimum; 850 W preferred |
| Network | Gigabit Ethernet **where available** — a preference, not a requirement. See §5.1 |
| OS | Ubuntu Server |
| Initial inference engine | `llama.cpp` / `llama-server` |
| Primary model format | GGUF |
| Typical quantization | Q4 / Q5 |
| Typical model tier | ~30–35B-class quantized models |
| Larger experiments | ~70B-class quantized models with CPU/RAM offload when acceptable |

NVIDIA specifies the RTX 3090 with **24 GB GDDR6X** and a 350 W graphics-card power rating for the Founders Edition; NVIDIA lists a 750 W required system power reference for that configuration.

## 5.1 Networking reality, and why it does not block this

The reference row above says Gigabit Ethernet because that is the right answer when a wired drop
exists. **At the node's current location it does not, and will not** — wired Ethernet is unavailable
there permanently, which ADR-016 records as resolved rather than pending. Any second machine placed
beside the M700 inherits the same constraint: Wi-Fi only.

**This does not make the design unworkable, and the requirement should not be read as absolute.**

The large transfer is model weights — 20 to 30 GB for a quantized 30B-class model. Over Wi-Fi that
is hours rather than minutes. That is acceptable, because it is not a daily operation:

- weights are fetched **once per model**, not once per inference;
- a transfer may simply be left running for several hours, or overnight, or across a day;
- once local, the model is read from disk and the network is irrelevant to inference speed;
- the persistent-volume pattern in §7 exists precisely so weights are not re-fetched.

What Wi-Fi *would* genuinely hurt is a design that streams weights per session, or that treats the
local node as interchangeable with cloud storage on every run. Neither is the design here.

**Upgrade when circumstances allow, do not gate on it.** If the location ever gains a wired drop, or
the machine moves, revisit — but the absence of Ethernet is a slower first load, not a blocker.

The role of this computer is deliberately narrow:

```text
M700
  │
  │ exact inference request
  ▼
Local GPU node
  │
  │ model inference
  ▼
M700 receives response
```

It should not become a second orchestration server.

---

# 6. Cloud GPU compute as an alternative backend

Before buying the local inference computer, the project should strongly consider using rented GPU infrastructure.

This is not a different architecture.

It is another implementation of the same compute-provider interface:

```text
ComputeProvider
├── cloud_gpu
└── local_gpu
```

The AI operating system and Factory should ideally remain unaware of whether a model is physically running:

- inside the Home Lab;
- inside a rented GPU machine;
- behind a managed inference API.

This enables cloud inference to be used first and local hardware to be introduced later without redesigning the system.

---

# 7. Compute and storage must be treated separately

The preferred cloud pattern is:

```text
PERSISTENT
┌───────────────────────────────┐
│ Model weights                 │
│ quantizations                 │
│ configuration                 │
│ startup scripts               │
│ caches where appropriate      │
└───────────────┬───────────────┘
                │ attach
                ▼
EPHEMERAL
┌───────────────────────────────┐
│ Rented GPU worker             │
│                               │
│ CUDA                          │
│ inference runtime             │
│ model loaded into VRAM        │
│ API endpoint                  │
└───────────────────────────────┘
```

The GPU should be disposable.

The model files and required configuration should persist.

This avoids repeatedly downloading tens of gigabytes of model weights every time a worker is provisioned.

Using Runpod as a reference implementation, its network volumes persist independently from Pods and can retain data after the compute resource is terminated. Runpod currently lists standard network storage under 1 TB at $0.07/GB/month.

The provider is only an example. The architecture should not hard-code itself to Runpod.

---

# 8. Cloud execution lifecycle

The future workflow should **not** normally start and stop a GPU for every individual prompt.

A more appropriate unit is a **compute session**.

Example:

```text
Feature execution begins
        │
        ▼
AI OS evaluates queued work
        │
        ▼
Suitable self-hosted model required?
        │
       yes
        ▼
Acquire GPU capacity
        │
        ▼
Attach persistent model volume
        │
        ▼
Start inference container
        │
        ▼
Load model into VRAM
        │
        ▼
Mark worker READY
        │
        ├── PM inference
        ├── planning inference
        ├── coding inference
        ├── review inference
        ├── correction inference
        └── test-analysis inference
        │
        ▼
No runnable jobs remain
        │
        ▼
Idle grace period
        │
        ▼
Release GPU
```

This avoids repeated cold starts during one autonomous workflow.

---

# 9. Why session-level scheduling matters

The software factory may perform many calls while completing one feature.

Starting compute for every call would repeatedly incur:

- worker provisioning;
- container startup;
- model loading;
- health checks;
- network initialization.

Instead, one feature execution may keep the worker alive while there is useful work in the queue.

A future policy might resemble:

```text
IF self-hosted queue contains runnable work:
    keep worker alive

ELSE:
    begin idle timer

IF new job arrives before timeout:
    cancel shutdown

ELSE:
    release compute
```

A small amount of paid idle time may be cheaper and operationally simpler than repeated provisioning.

The exact idle window should be determined experimentally.

---

# 10. Model routing and compute scheduling are different concerns

This separation should be explicit in the architecture.

## Model Router

Question:

> Which model/capability should solve this task?

Inputs may eventually include:

- task type;
- quality requirement;
- context size;
- model benchmark results;
- price;
- latency;
- privacy;
- tool-calling capability;
- historical success rate.

Example outcome:

```text
task = code_review
model = frontier_review_model
```

or:

```text
task = routine_implementation
model = self_hosted_coder_32b
```

## Compute Manager

Question:

> Where and how should that model run?

Example outcomes:

```text
self_hosted_coder_32b
→ existing cloud worker
```

or:

```text
self_hosted_coder_32b
→ provision cloud GPU
```

or eventually:

```text
self_hosted_coder_32b
→ local RTX 3090 node
```

This separation prevents model-selection logic from becoming entangled with infrastructure management.

---

# 11. Future compute-request abstraction

A future internal request might carry requirements rather than provider details.

Example conceptual schema:

```yaml
task:
  type: implementation
  risk: medium

model_requirements:
  capability: coding
  quality_tier: medium
  context_required: 32000
  privacy: self_hosted_preferred

compute_constraints:
  max_cost_dkk: 5
  max_startup_time_seconds: 300
  latency_priority: low
  long_running_allowed: true
```

The model router could choose the model.

The compute manager could then find the cheapest acceptable execution environment.

The precise schema should not be implemented until actual requirements exist.

---

# 12. Provider-neutral inference interface

Self-hosted models should preferably expose a stable interface to the rest of the platform.

A practical target is an OpenAI-style HTTP interface.

Both `llama-server` and vLLM expose OpenAI-compatible/inspired HTTP endpoints. vLLM currently implements APIs including Chat Completions, Completions, Responses, Embeddings, and others. `llama-server` exposes chat/completion endpoints and supports synchronous and streaming inference.

Conceptually:

```text
POST /v1/chat/completions
```

The rest of Home Lab can therefore interact with an abstraction such as:

```text
InferenceProvider
├── openai
├── anthropic
├── ai_gateway
├── cloud_self_hosted
└── local_self_hosted
```

A future migration from cloud GPU to local RTX 3090 should ideally require a configuration change rather than agent rewrites.

---

# 13. Initial cloud implementation: Pod before Serverless

When this phase is eventually implemented, start with an ordinary GPU Pod / VM.

Do not begin with Serverless.

## Learning sequence

### Stage A — manual GPU worker

Manually:

1. Rent GPU.
2. Attach storage.
3. Start container.
4. Load model.
5. Expose inference endpoint.
6. Send requests from the M700.
7. Shut down the worker.
8. Confirm persistent data survives.

Objective:

> Understand the mechanism.

### Stage B — programmatic worker lifecycle

The M700 / AI OS should then learn to:

```text
provision
→ wait
→ health-check
→ route inference
→ monitor
→ terminate
```

Objective:

> Understand compute orchestration.

### Stage C — automatic scheduling

Integrate GPU acquisition with:

- backlog state;
- executable work;
- model demand;
- idle timeouts;
- cost limits.

Objective:

> Treat compute as a resource managed by the AI operating system.

### Stage D — Serverless comparison

Only then compare this manual mechanism against a serverless GPU platform.

Runpod's current Serverless product supports per-second billing and scale-to-zero workers, making it relevant for bursty inference.

Objective:

> Understand what the managed abstraction replaces.

---

# 14. Persistent model library

The persistent inference volume may eventually resemble:

```text
/workspace/
├── models/
│   ├── coding/
│   │   ├── model-a/
│   │   └── model-b/
│   ├── reasoning/
│   └── experimental/
│
├── inference/
│   ├── configs/
│   ├── start.sh
│   ├── healthcheck.sh
│   └── benchmarks/
│
├── cache/
└── logs/
```

Important distinction:

> Persistent cloud storage is not necessarily the authoritative source of the models.

The canonical model definition should still be reproducible from:

- model repository/version;
- quantization;
- hash/checksum where practical;
- inference configuration;
- startup configuration.

Cloud storage is a cache/working layer.

The project should be able to rebuild it.

---

# 15. Containers and reproducibility

The future worker should be reproducible rather than manually configured.

Conceptually:

```text
Container image
├── CUDA-compatible runtime
├── llama.cpp / vLLM / SGLang
├── Python dependencies
├── inference API
├── health checks
└── startup scripts

Persistent volume
├── model weights
└── selected caches/config
```

The exact CUDA version, image, inference-engine version, model revision, and quantization should be recorded.

This aligns with the broader Home Lab objective:

> If a machine or cloud worker disappears, the service should be reconstructable.

---

# 16. `llama.cpp` versus vLLM

No permanent choice should be made yet.

## `llama.cpp`

Strong candidate for:

- GGUF models;
- quantization experimentation;
- consumer GPUs;
- CPU + GPU hybrid inference;
- low-level learning;
- single-user / modest concurrency;
- future multi-GPU experimentation.

`llama.cpp` currently supports configurable GPU-layer offload and multi-GPU split modes including pipeline/layer splitting and experimental tensor parallelism.

## vLLM

Strong candidate for:

- higher-throughput serving;
- concurrency;
- OpenAI-compatible serving;
- GPU-oriented deployments;
- larger serving infrastructure.

vLLM currently exposes an OpenAI-compatible HTTP server covering several model APIs.

## Future experiment

The project should eventually benchmark both rather than choose based purely on reputation.

Measure:

- tokens/sec;
- time to first token;
- cold-start time;
- VRAM use;
- context-size behavior;
- concurrent request throughput;
- stability;
- operational complexity.

---

# 17. Quantization strategy

Quantization is central to the local/self-hosted model strategy.

The canonical RTX 3090 node has 24 GB VRAM, so quantized models are expected.

Likely experimental tiers:

```text
small model
7–14B
→ fast / inexpensive / high-frequency tasks

medium-large model
20–35B quantized
→ primary local/self-hosted intelligence tier

large model
~70B quantized
→ larger GPU rental or CPU/GPU hybrid experiments
```

Do not treat these boundaries as fixed.

Real memory requirements depend on:

- architecture;
- precision/quantization;
- KV cache;
- context length;
- batch/concurrency;
- inference engine.

Model selection should eventually be driven by measured quality/cost/performance.

---

# 18. Backlog as an execution queue

The future backlog is not merely project-management documentation.

It can become the work state consumed by the autonomous factory.

Conceptually:

```text
Feature X
├── specification          DONE
├── architecture           DONE
├── implementation-1      DONE
├── implementation-2      RUNNING
│   ├── code              RUNNING
│   ├── review            WAITING
│   └── test              WAITING
├── implementation-3      READY
└── final review          WAITING
```

The compute manager can use the existence of runnable tasks to decide whether a GPU should remain allocated.

This connects project state to infrastructure utilization.

---

# 19. Example end-state workflow

```text
19:00
User:
"Run Feature X through the factory."

19:00
AI OS creates execution instance.

19:01
Factory PM agent refines feature specification.

19:05
Planning agent decomposes work.

19:10
Model router determines that upcoming implementation tasks
can use a self-hosted coding model.

19:10
Compute Manager requests cloud GPU.

19:12
GPU worker becomes available.

19:13
Persistent model volume attached / model loaded.

19:15
Developer task #1 executes.

19:32
Reviewer evaluates output.

19:38
Correction task executes.

20:05
Developer task #2 executes.

20:44
Tests and review complete.

20:50
PR reaches required state.

20:51
No additional self-hosted inference work is ready.

21:01
Idle timeout expires.

21:01
Compute Manager terminates GPU.

21:02
AI OS sends completion message.
```

The exact workflow may differ significantly after Factory and the factory are implemented. The important architectural idea is the lifecycle.

---

## 19.1 The autonomy this assumes is the point, and the safeguard is the pipeline

The workflow above runs for nearly two hours without a human in it. That is **intended, not an
oversight**, and it is worth stating plainly because it is the whole reason the system is being
built: the owner should be able to say *"implement this feature"* and get a pull request, rather than
approving each step.

**The control is the pipeline, not human presence.** The Factory's roles already encode the
safeguards that a person would otherwise provide:

```text
implement  →  review  →  CI/CD check  →  test  →  commit
     ↑                                      │
     └───────────── correction ←────────────┘
```

Someone writes the code. Someone else reviews it — and by the Factory's own role boundaries, cannot
review their own work. A CI/CD role confirms it builds. A tester confirms it still works. Only then
does it reach a commit. **A human standing at each gate adds latency, not safety, once those gates
genuinely function.** The question is whether they function, and that is answered by evidence, not
by keeping a person in the loop indefinitely.

### What this requires, and the route to it

This end state is **not reachable today**, and the obstacle is deliberate rather than technical.
ADR-025 §10 holds that **model output is never dispatched**, proved in Phase 09 by making a model
emit `/restart ssh.service` and confirming nothing happened. ADR-027 §6 keeps the same lock: the
model gets no tools.

Those locks are not permanent policy. They are closed *until there is a contract for opening them*,
and ADR-027 §6 is that contract:

> Tools open **one agent at a time**, each by adding a declared tool to a specific manifest, with the
> reason recorded. The first agents should be advisory — they read and recommend, the human acts.
> Anything destructive additionally requires approval **at the moment of action**, not merely a
> declared tool.

So the path from here to §19 is: **Phase 19** names the tools, **Phase 20** writes the manifests that
request them, and each grant is then opened individually and recorded. The autonomy arrives one
declared capability at a time, and each step is auditable afterwards.

**The thing to preserve is the order.** Autonomy earned by demonstrating that review, CI and test
actually catch defects is durable. Autonomy granted because the workflow was tedious to supervise is
how a system commits a bad change at 3am with nobody watching. The Factory's own history is the
cautionary note: as of 2026-09-11 its approval levels 2 and 3 had never fired, and its founder inbox
had never been used — specified in detail, never exercised. **A gate that has never fired is
unvalidated**, exactly like a detector that has only ever reported clean.

---

# 20. Cost model

The future system should not assume that self-hosting is cheaper than APIs.

It should measure it.

## Hosted API cost

Typically resembles:

```text
input tokens × input price
+
output tokens × output price
+
other provider charges
```

## Cloud self-hosted cost

Typically resembles:

```text
GPU runtime
+
persistent storage
+
possibly data/network costs
+
idle time during allocated sessions
```

## Local GPU cost

Typically resembles:

```text
hardware amortization
+
electricity
+
maintenance/replacement
```

The system should eventually compare these using actual workload data.

---

# 21. Metrics that should eventually be captured

At the inference-request level:

```text
request_id
workflow_id
task_id
agent_role
model
model_version
quantization
provider
gpu_type
context_tokens
input_tokens
output_tokens
startup_time
inference_time
tokens_per_second
estimated_cost
result_status
```

At the workflow level:

```text
feature_id
total_model_cost
total_cloud_gpu_cost
execution_duration
human_interventions
iterations
review_failures
test_failures
final_acceptance
```

This enables questions such as:

- Is self-hosted coding actually cheaper?
- Does a 32B model produce more review failures than a frontier model?
- Should implementation be local while architecture/review remains frontier?
- Is the rented GPU spending most of its allocation idle?
- Does a larger GPU reduce total workflow cost by completing tasks faster?
- When would purchasing the RTX 3090 node break even?

This is more valuable than optimizing only for cost per token.

---

# 22. Workload routing hypothesis

A likely future model-routing strategy is:

```text
High-value / high-risk / difficult reasoning
→ frontier hosted API

Routine implementation
→ self-hosted medium/large coding model

Simple extraction / classification / formatting
→ small inexpensive model

Embeddings / retrieval
→ dedicated embedding model

Specialized tasks
→ whichever provider/model benchmarks best
```

This is a hypothesis, not a fixed policy.

It should be tested empirically.

---

# 23. Cloud versus future local RTX 3090

Cloud should be used first because it allows the project to learn its actual requirements before buying hardware.

Cloud provides:

- flexible VRAM sizes;
- no large upfront hardware expense;
- easy experiments with GPUs larger than 24 GB;
- measurable utilization;
- measurable cost;
- a realistic distributed architecture.

The future RTX 3090 node provides:

- owned hardware;
- no hourly compute charge;
- predictable availability;
- local control;
- learning around CUDA/Linux/hardware;
- potential value once utilization becomes high enough.

The correct purchase trigger should therefore be evidence.

Example:

```text
Cloud usage history
        │
        ▼
Which GPU sizes are actually used?
How many GPU-hours/month?
Which models matter?
What is the real monthly cost?
How often is capacity needed?
        │
        ▼
Hardware decision
```

Do not buy the local inference node merely because local inference is technically interesting.

---

# 24. Multi-GPU concept — explicitly deferred

A possible 3–4 GPU server was explored.

That architecture could support:

- larger aggregate VRAM;
- very large models;
- multiple concurrent workers;
- model specialization per GPU;
- multi-GPU inference experiments.

However, it requires materially more:

- PCIe lanes;
- power delivery;
- cooling;
- physical chassis capacity;
- system RAM;
- upfront investment.

It should therefore **not** replace the current canonical local-node design.

The current hierarchy is:

```text
CURRENT
M700 control plane

FUTURE EXPERIMENT
cloud GPU inference

POSSIBLE LATER HARDWARE
1 × RTX 3090 24 GB local inference node

ONLY IF JUSTIFIED MUCH LATER
multi-GPU compute server
```

If multi-GPU work becomes justified, reevaluate available GPUs and platforms at that time instead of assuming multiple RTX 3090s will still be the correct choice.

---

# 25. Security considerations

Self-hosted inference endpoints must not simply be exposed openly to the internet.

Future considerations include:

- private networking;
- authenticated API access;
- firewall rules;
- TLS;
- secrets management;
- workload isolation;
- container permissions;
- logging;
- request size limits;
- cost limits;
- automatic termination;
- provider API-key protection.

vLLM documentation currently notes that its built-in API-key option does not protect every exposed endpoint, so deployment should not rely on that mechanism alone. A reverse proxy/private network architecture may be necessary.

The M700 should remain the trusted control point rather than exposing individual GPU workers directly to user interfaces.

---

# 26. Failure handling

Compute management should assume that rented GPU workers can disappear or fail.

Future execution state should distinguish:

```text
TASK STATE
vs.
COMPUTE STATE
```

A failed GPU should not mean a lost workflow.

Potential lifecycle:

```text
worker fails
    ↓
task marked interrupted
    ↓
checkpoint/state preserved
    ↓
new worker provisioned
    ↓
model restored
    ↓
task retried/resumed
```

This is another reason workflow state belongs in the AI operating system rather than on the inference worker.

---

# 27. Cost controls

Autonomous compute introduces financial risk.

Future guardrails should include:

- maximum GPU runtime per workflow;
- maximum cost per task;
- maximum cost per feature;
- idle termination;
- hard global budget;
- alerts for unusually long executions;
- explicit policy for expensive GPU classes;
- prevention of orphaned workers.

A production-quality compute manager should make it difficult for a forgotten process to leave an expensive GPU running indefinitely.

---

# 28. Proposed future development sequence

This roadmap is deliberately deferred until the foundational Home Lab/factory work is mature.

## Phase A — provider abstraction

Ensure model calls are not coupled directly to one provider.

Target concept:

```text
InferenceProvider
```

No GPU orchestration required yet.

---

## Phase B — cloud GPU experiment

Manually provision one GPU worker.

Run one open model.

Connect M700 → worker → response.

Document:

- model;
- GPU;
- VRAM;
- quantization;
- startup time;
- inference speed;
- cost.

---

## Phase C — persistent storage

Create a persistent model volume.

Verify:

```text
create GPU
→ use model
→ destroy GPU
→ create new GPU
→ reattach storage
→ same model available
```

---

## Phase D — reproducible inference container

Build a version-controlled image/environment.

No manual setup should be required on a fresh worker.

---

## Phase E — compute-provider API

Implement M700-side operations such as:

```text
acquire_worker()
worker_status()
wait_until_ready()
release_worker()
```

---

## Phase F — queue/session lifecycle

Keep compute alive while runnable jobs exist.

Introduce an idle timeout.

---

## Phase G — cost telemetry

Measure provider/model/runtime cost per task and workflow.

---

## Phase H — compare engines

Benchmark:

- llama.cpp;
- vLLM;
- potentially SGLang/other engines available at that time.

---

## Phase I — evaluate local hardware

Use accumulated usage data to determine whether the RTX 3090 node is justified.

---

## Phase J — local compute provider

Implement:

```text
cloud_gpu
local_gpu
```

behind the same compute abstraction.

---

## Phase K — only if justified: multi-GPU research

Reassess current-generation hardware and economics before designing a multi-GPU server.

---

# 29. Decision gates before buying local hardware

Do not purchase the local inference node until the project can answer most of these:

1. Which models are actually useful?
2. What VRAM sizes are used most often?
3. What context lengths are typical?
4. How many GPU-hours are consumed per month?
5. What is average cloud spend?
6. What is peak cloud spend?
7. What tasks are good enough on open/self-hosted models?
8. What tasks still require frontier APIs?
9. What inference engine performs best?
10. How important is local availability?
11. How important is privacy?
12. What would the estimated local hardware payback period be?

The earlier RTX 3090 specification is a reference architecture, not a purchase commitment.

---

# 30. Key architectural principles to preserve

### 1. The M700 is the control plane

Compute workers should be disposable.

### 2. Models are infrastructure dependencies

Agents should not directly manage GPU instances.

### 3. Model routing and compute scheduling are separate

Choosing intelligence is different from choosing hardware.

### 4. Storage and compute are separate

Do not make model persistence depend on an active GPU.

### 5. Execution state belongs outside the GPU worker

A worker failure must not destroy the software-factory workflow.

### 6. Start manually, automate later

Understand the mechanism before adding serverless or sophisticated schedulers.

### 7. Measure before buying

Use cloud experimentation to determine the local hardware specification empirically.

### 8. Optimize workflows, not isolated prompts

The relevant unit is eventually a feature/work session, not one chat completion.

### 9. Keep providers interchangeable

Cloud GPUs, APIs, and local GPUs are execution backends.

### 10. This is a future phase

Do not allow this architecture to distract from the current Home Lab, Factory, memory, knowledge, rack, backlog, and factory foundations.

---

# 31. Immediate status / non-goals

As of this handover, **none of the cloud GPU orchestration described above needs to be implemented now**.

Current priorities remain the foundational Home Lab and AI factory architecture.

This document should be revisited when one of these becomes true:

- the model gateway/provider layer is stable;
- Factory is capable of meaningful multi-step software workflows;
- backlog-driven execution exists;
- self-hosted model experimentation becomes a current learning objective;
- hosted API usage/cost becomes large enough to justify comparison;
- the project is ready to introduce a dedicated compute-management phase.

Until then, this document is an architectural direction, not a backlog commitment.

---

# 32. Reference sources

The sources below were verified when this handover was written. Pricing and product behavior can change; re-check current documentation when the phase begins.

1. **NVIDIA — GeForce RTX 3090 specifications**  
   RTX 3090: 24 GB GDDR6X; Founders Edition graphics-card power 350 W; reference required system power 750 W.  
   https://www.nvidia.com/en-eu/geforce/graphics-cards/30-series/rtx-3090/

2. **Runpod — Storage options**  
   Comparison of container disk, volume disk, and network volumes; network volumes persist independently from Pods.  
   https://docs.runpod.io/pods/storage/types

3. **Runpod — Network volumes**  
   Persistent storage independent from compute; current standard pricing under 1 TB listed at $0.07/GB/month.  
   https://docs.runpod.io/storage/network-volumes

4. **Runpod — Pod management**  
   Pod lifecycle, stop/start behavior, and network-volume behavior.  
   https://docs.runpod.io/pods/manage-pods

5. **Runpod — Serverless**  
   Current serverless GPU model: containerized endpoints, per-second billing, autoscaling, and scale-to-zero flex workers.  
   https://www.runpod.io/product/serverless

6. **Runpod — Billing / pricing documentation**  
   Current billing model and storage pricing.  
   https://docs.runpod.io/accounts-billing/billing  
   https://docs.runpod.io/pods/pricing

7. **llama.cpp — `llama-server`**  
   Server functionality, GPU offload controls, multi-GPU split options, and OpenAI-inspired API endpoints.  
   https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md

8. **llama.cpp — Multi-GPU documentation**  
   Layer/pipeline splitting, tensor splitting, GPU selection, and VRAM-fitting behavior.  
   https://github.com/ggml-org/llama.cpp/blob/master/docs/multi-gpu.md

9. **vLLM — OpenAI-Compatible Server**  
   HTTP serving and supported OpenAI-style API endpoints.  
   https://docs.vllm.ai/en/latest/serving/online_serving/openai_compatible_server/

---

# 33. One-sentence future vision

> **The Home Lab should eventually treat model intelligence as a routable service and GPU capacity as an elastic resource: the AI operating system decides what work must happen, Factory executes the agent workflow, the model router selects the appropriate intelligence, and the compute manager transparently acquires cloud or local GPU capacity only for as long as the software factory needs it.**
