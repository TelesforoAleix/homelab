# Home Lab Model Strategy — September 2026 Refresh

## Executive recommendation

The Home Lab should use a **small model portfolio behind Vercel AI Gateway**, not one model per feature and not one universal “best” model. Routing should depend on four variables:

1. **task type** — utility, general/tool use, hard reasoning, coding, RAG, speech;
2. **difficulty** — routine, hard, frontier;
3. **cache shape** — low-cache one-off request versus long-lived, stable-prefix agent session;
4. **latency tolerance** — interactive versus background work.

This refresh materially changes the previous strategy because several important models arrived in the first ten days of September 2026: **Claude Fable 5.1, Gemini 3.8 Flash, Muse Spark 1.3, GPT-6 Astra, Mercury 2.5, and DeepSeek V4.1 Flash**. DeepSeek V4.1 Flash was officially released on September 10 and is especially relevant because its architecture was explicitly designed to reduce KV-cache cost in agent workloads.[2][8][12][15][17][20]

The most important change is that **DeepSeek V4.1 Flash becomes a Tier-1 workhorse candidate**. On the current Artificial Analysis Intelligence Index v4.3 it scores 40 at max reasoning, produces about 190–200 tokens/s on the first-party API, has a 1M-token context window, and Vercel currently routes it from about $0.15/M input, $0.60/M output and cache reads as low as $0.003/M. That combination is unusually well aligned with the Home Lab’s observed cache-heavy workload.[3][4]

The second important change is that **cache shape should influence frontier routing**. GPT-6 Astra is extraordinarily token-efficient and is the best frontier escalation for difficult one-off work, but its cache reads are $1/M. Claude Fable 5.1 has the same $10/$50 headline input/output pricing but only $0.25/M cache reads, while Muse Spark 1.3 is $1.25/$4.25 with $0.15/M cache reads. Long, highly cached sessions therefore have different economics from one-shot frontier tasks.[9][13][16]

### Recommended v2 model portfolio

| Logical route | Initial configuration | Main challenger / fallback | Why |
|---|---|---|---|
| `utility` | **GPT-5.6 Luna — none/low** | Mercury 2.5 minimal; DeepSeek V4.1 low | Predictable, fast, cheap, concise enough for routing/extraction |
| `general_tools` | **DeepSeek V4.1 Flash — high (provisional)** | Gemini 3.8 Flash medium; GLM-5.3 Flash | Best current cache-aware value; strong speed and 1M context |
| `general_quality` | **Gemini 3.8 Flash — medium** | DeepSeek high; Claude Sonnet 5 | Better-established configurable quality; very high throughput |
| `reasoning_cached` | **GPT-5.6 Sol — high** | Muse Spark 1.3 xhigh; Fable 5.1 medium | Concise hard reasoning; cheap cache reads relative to frontier models |
| `frontier_interactive` | **GPT-6 Astra — low** | Astra medium | Frontier-quality jump with low latency and excellent token efficiency |
| `frontier_cached` | **Claude Fable 5.1 — medium** | Muse Spark 1.3 max/xhigh | Strong long-horizon quality with much cheaper cache reads than Astra |
| `coding_standard` | **Keep subscription Codex / Claude Code for development** | API eval: DeepSeek V4.1 high, Gemini 3.8 high, Muse Spark 1.3 | Harness matters more than base-model leaderboard position |
| `coding_hard` | **Codex + GPT-6 Astra max** | Claude Code + Fable 5.1 max | Current Coding Agent Index leaders |
| `embedding` | **Voyage 4, 1024d** | Voyage 4 Large documents + Voyage 4 Lite queries | Shared embedding space and strong retrieval economics |
| `rerank` | **Cohere Rerank 4 Fast** | Rerank 4 Pro; no-reranker control | Practical multilingual second-stage retrieval |
| `transcribe` | **Benchmark Gemini 3.5 Transcribe vs GPT-4o mini Transcribe** | Gemini 3.5 Transcribe Live later | Public evidence is insufficient to name a universal winner |

The table is intentionally a **starting policy**, not a permanent truth. The Home Lab should eventually promote and demote models using its own task-level evaluation data.

---

## 1. Scope and benchmark method

This analysis is designed for the Home Lab architecture: an orchestration node with Telegram and future interfaces, tool-using agents, RAG/knowledge retrieval, automation, security controls and eventually a local GPU node. The M700 is the control plane, not the inference machine, so hosted models behind a gateway remain the correct near-term architecture.[1]

### Primary quality benchmark

The main independent general-quality reference is **Artificial Analysis Intelligence Index v4.3**, released September 7, 2026. It combines ten evaluations across realistic knowledge work, automation, terminal operation, scientific coding, hard reasoning, document reasoning, hallucination/knowledge reliability and long-context retrieval. Agentic and coding evaluations together account for a substantial share of the score, making it more relevant to Home Lab than older academic-only benchmarks.[2]

Current v4.3 leaders include:

| Model/configuration | AA Intelligence Index v4.3 | Notes |
|---|---:|---|
| Claude Fable 5.1 max with fallback | **53** | Frontier leader, expensive |
| GPT-6 Astra max | **53** | Tied leader, much more token-efficient |
| Claude Opus 5 max | 51 | Strong but increasingly displaced by Fable/Astra |
| Muse Spark 1.3 max | **48** | Strong new mid/frontier option |
| GPT-5.6 Sol max | 47 | Strong, concise, mature |
| GLM-5.3 Flash | **42** | Excellent open-weight value |
| Gemini 3.8 Flash high | **41** | Extremely fast workhorse |
| DeepSeek V4.1 Flash max | **40** | Exceptional speed/cache economics |
| Qwen3.8 Flash-Next | 40 | Useful open-weight challenger |
| GPT-5.6 Luna max | 38 | Cheap configurable OpenAI tier |

Sources: Artificial Analysis v4.3 and current release pages.[2][3][5][7][10][14][16]

### Coding benchmark

Coding is evaluated separately with **Artificial Analysis Coding Agent Index v1.5**, because model + harness performance differs materially from raw model intelligence. The current index combines DeepSWE v1.1, Terminal-Bench 4.0 and SWE-Atlas-QnA.[18][19]

### Speed

Speed should be separated into:

- **TTFT** — network/provider time to first token;
- **time to first answer token** — includes hidden/visible reasoning delay;
- **output throughput** — tokens per second after generation begins;
- **end-to-end task time** — the metric that ultimately matters for agents.

Vercel live metrics and Artificial Analysis standardized measurements can disagree because they observe different providers and workloads. Use both as priors, then log Home Lab measurements.

### Cost

Cost must include:

```text
fresh_input
+ output
+ cache_write
+ cache_read
+ model/provider-specific storage or tool charges
```

For this project, **cost per successful task** matters more than nominal price per million tokens.

---

## 2. New model landscape as of September 11, 2026

### High-relevance recent releases

| Release | Date | Why it matters for Home Lab |
|---|---|---|
| Claude Fable 5.1 | Sep 1 | Frontier long-running agent/coding quality; 98% cache-read discount |
| Gemini 3.8 Flash | Sep 2 | Very high throughput workhorse with configurable reasoning |
| Muse Spark 1.3 | Sep 2 | 45–48 AA score, fast output, moderate pricing, strong coding-agent showing |
| GPT-6 Astra | Sep 3 | Frontier intelligence, coding and terminal strength, unusually token-efficient |
| Mercury 2.5 | Sep 8 | Diffusion reasoning model, very cheap/fast; independent benchmark gap remains |
| DeepSeek V4.1 Flash | Sep 10 official | New cache-efficient architecture; 1M context; open weights; exceptional cost/speed |

Vercel’s current catalogue also contains recent Qwen3.8, GLM-5.3 and Kimi K3 variants. They remain useful challengers, but the six releases above most materially affect the previous strategy.[5][7][8][12][15][17]

### Models screened but not promoted to core defaults

**Qwen3.8 Max** remains capable but is currently hard to justify against cheaper Qwen Flash variants, GLM-5.3 Flash, DeepSeek V4.1 and Gemini 3.8 Flash.

**Kimi K3** is a strong open-weight 1M-context model (AA 44 at max), but its current speed and API economics are less attractive than DeepSeek/GLM for a default Home Lab workhorse. Kimi remains worth testing for coding and multimodal workflows.[26]

**Kimi K2.7 Code** is no longer a default coding recommendation. Newer frontier agents and newer Kimi/DeepSeek generations have overtaken the rationale for centering it.

**GPT-5.6 Terra** remains omitted as a permanent tier. Luna and Sol cover the low-cost and high-capability parts of the OpenAI family more cleanly for this architecture.

**Claude Opus 5** remains excellent but Fable 5.1 is the more relevant Anthropic frontier model where available.

**Mercury 2.5** is deliberately a watchlist model rather than a core default because its Vercel economics are excellent — currently around $0.04/$0.15 and $0.004/M cached read with a 260K context — but there is not yet a comparable independent AA v4.3 result in the source set. It should be evaluated on routing, extraction, JSON adherence and tool use before promotion.[17]

---

## 3. Your observed workload: caching dominates

The observed intensive development week contained:

| Traffic class | Tokens | Share |
|---|---:|---:|
| Fresh input | 4,482,959 | 0.90% |
| Output | 2,424,853 | 0.49% |
| Cache create/write | 6,721,427 | 1.35% |
| Cache read | 485,703,416 | **97.27%** |
| **Total** | **499,332,655** | **100%** |

Claude represented roughly 82% of the processed tokens and Codex roughly 18%. The cache-read ratio was approximately 97.85% for the Claude portion and 94.61% for the Codex portion.

This should **not** be interpreted as “the runtime Home Lab will use 500M tokens per week.” Development agents repeatedly ingest repository instructions, tool definitions, history, files and environment state. But it is a strong signal that the platform will benefit from deliberate stable-prefix engineering.

Modern coding-agent benchmark data supports the direction: Artificial Analysis currently measures roughly **92% cache hits for Claude Code + Fable 5.1 and 93% for Codex + Astra**, while some other coding-agent setups reach around 97%.[19][27]

---

## 4. Cache-aware economics

### Cost equation

```text
effective_cost =
    fresh_input_tokens * input_price
  + output_tokens      * output_price
  + cache_write_tokens * cache_write_price
  + cache_read_tokens  * cache_read_price
```

Where a provider exposes implicit caching without a separate cache-write fee, the sensitivity calculation below models cache creation at normal input price. This is an approximation, not an invoice forecast.

### Synthetic cost using your exact weekly token shape

The following table applies your **same 499.3M-token distribution** to current Vercel-style short-context prices. It is useful for understanding cache sensitivity, but **not for predicting what each model would actually cost**, because models differ in reasoning-token use, output verbosity, number of turns and successful-task rate.

| Model / current route | Fresh input $/M | Output $/M | Cache read $/M | Same-shape weekly cost |
|---|---:|---:|---:|---:|
| Mercury 2.5 promo | 0.04 | 0.15 | 0.004 | **~$2.75** |
| DeepSeek V4.1 Flash — cheapest current route | 0.15 | 0.60 | 0.003 | **~$4.59** |
| GLM-5.3 Flash — low-cost route | 0.07 | 0.24 | 0.01 | **~$6.22** |
| GPT-5.6 Luna | 0.20 | 1.20 | 0.02 | **~$15.20** |
| Gemini 3.8 Flash | 0.75 | 3.75 | 0.08 | **~$56.35** |
| Muse Spark 1.3 | 1.25 | 4.25 | 0.15 | **~$97.17** |
| GPT-5.6 Sol — current Vercel promo route | 2.00 | 10.00 | 0.20 | **~$147.16** |
| Claude Fable 5.1 | 10.00 | 50.00 | 0.25 | **~$371.52** |
| GPT-6 Astra | 10.00 | 50.00 | 1.00 | **~$735.79** |

The key insight is not the dollar number. It is the **ordering**. Fable and Astra have the same headline input/output prices, but under a 97%-cached traffic shape Fable is roughly half the synthetic cost because its cached-read price is four times lower. Conversely, Astra can still be cheaper per *solved task* on difficult one-off benchmarks because it uses far fewer output/reasoning tokens. Both facts can be true simultaneously.[9][13][16]

### What this means for routing

```text
high cache reuse + long session
        -> prioritize cache economics

low cache reuse + hard one-off task
        -> prioritize token efficiency / success per task
```

That distinction is now part of the model policy.

---

## 5. Utility / router model

### Recommendation: GPT-5.6 Luna, `reasoning: none` by default

Use for:

- intent classification;
- agent selection;
- extraction into schemas;
- metadata tagging;
- simple query rewriting;
- risk/destructive-action classification;
- lightweight context summarization.

Luna has 1M+ context, cheap cached reads ($0.02/M on current Gateway routes) and predictable reasoning levels. On AA v4.3, the family moves from 17 non-reasoning to 22 low, 26 medium, 32 high and 38 max. For utility work, those frontier reasoning levels are unnecessary; the point is **low latency and reliable structure**, not composite benchmark intelligence.[10][11]

Recommended configuration:

```yaml
utility:
  model: openai/gpt-5.6-luna
  reasoning: none
  max_output_tokens: 1024
  fallback_reasoning: low
```

### Challenger: Mercury 2.5

Mercury 2.5 is extremely interesting for this role because Vercel currently lists roughly $0.04/M input, $0.15/M output, $0.004/M cache reads, a 260K context and very high live throughput. It supports tool calling and structured outputs. However, the independent benchmark evidence is not yet sufficient to make it a default.[17]

**Action:** build a 200–500 case routing/extraction eval and promote Mercury only if it matches Luna on schema-validity and classification accuracy.

### Why not default DeepSeek V4.1 here?

DeepSeek can certainly do utility work, but the independently tested max configuration is a reasoning model and is very verbose. A router benefits from brevity and determinism. DeepSeek should be tested at `none/minimal/low`, but those exact effort levels do not yet have the same independent benchmark coverage.[3][4]

---

## 6. General / tool-using agent

### Recommendation: DeepSeek V4.1 Flash as the new primary candidate

This is the biggest revision.

DeepSeek V4.1 Flash is now available through Vercel with:

- **1M context**;
- image input;
- tool use;
- structured reasoning controls through AI Gateway;
- prompt caching;
- up to very large output limits depending on provider;
- current Vercel routing from roughly **$0.15/M input, $0.60/M output, $0.003/M cache reads**;
- about **190–200 t/s** on DeepSeek’s API in independent measurement and roughly 250+ t/s on some current Vercel routes.[3][4][8]

Artificial Analysis gives V4.1 Flash max **40** on v4.3 at roughly **$0.27 per benchmark task**. The downside is verbosity: it generated about 250M output tokens across the benchmark suite, materially above the open-model median.[3]

### Reasoning configuration

Public independent v4.3 evidence currently covers the **max** configuration. For Home Lab traffic, running max everywhere is unlikely to be optimal.

My operational starting point would be:

```yaml
general_tools:
  model: deepseek/deepseek-v4.1-flash
  reasoning: high
  max_output_tokens: 8192
```

Then explicitly benchmark `medium` versus `high` versus `xhigh`. The recommendation for `high` is a **starting configuration**, not a benchmark-proven optimum.

Use strict output caps because DeepSeek’s low token price can hide unnecessary verbosity.

### Primary fallback: Gemini 3.8 Flash medium

Gemini remains the stronger “known quantity” workhorse. Its current independent v4.3 scores are:

| Effort | AA v4.3 |
|---|---:|
| Low | 34 |
| **Medium** | **40** |
| High | 41 |

Medium therefore remains the rational default: only one index point separates medium and high, while high uses more reasoning. Google’s first-party output throughput is around 270 t/s in AA testing, while Vercel has observed roughly 380 t/s on live Gateway traffic.[5][6]

```yaml
general_quality:
  model: google/gemini-3.8-flash
  reasoning: medium
```

### Challenger: GLM-5.3 Flash

GLM-5.3 Flash is still one of the strongest value propositions in the market:

- AA v4.3: **42**;
- 1M context;
- open weights / MIT;
- current Vercel routes from about **$0.07/$0.24**, cache read from **$0.01/M**;
- strong AutomationBench and long-context performance.

Its weakness is reasoning delay/verbosity and substantial provider-to-provider latency variation. It should stay in the benchmark suite rather than being ignored.[14][28]

### Selection policy

```text
cheap high-cache general agent
        -> DeepSeek V4.1 high

need validated fast multimodal/tool quality
        -> Gemini 3.8 medium

cost experiment / open-weight portability
        -> GLM-5.3 Flash
```

---

## 7. Hard reasoning

There should no longer be one hard-reasoning route. Split it by cache shape.

### A. Long, cache-heavy reasoning: GPT-5.6 Sol High

Sol High scores **42** on AA v4.3, costs about $0.81 per AA task in the independent evaluation, is relatively concise, and has current Vercel cache reads around $0.20/M. It is not the absolute frontier, but it remains a strong **predictable hard-reasoning tier**.[13][29]

```yaml
reasoning_cached:
  model: openai/gpt-5.6-sol
  reasoning: high
  context_soft_limit: 128000
```

Why keep Sol now that newer models exist? Because benchmark quality is only one axis. Sol is much more concise than GLM/DeepSeek/Muse, cheaper than Fable/Astra at fresh-output generation, and its cache economics are good enough for long stable sessions.

### B. Cache-heavy quality escalation: Muse Spark 1.3 or Fable 5.1

Muse Spark 1.3 is a meaningful new middle/frontier tier:

| Config | AA v4.3 | Output speed | Cost / AA task |
|---|---:|---:|---:|
| xhigh | 45 | ~190–203 t/s | ~$1.37 |
| max | 48 | ~197 t/s | ~$1.60 |

Vercel currently lists $1.25/$4.25 and $0.15/M cached reads. Its weakness is reasoning delay and verbosity. For **background** work, those tradeoffs can be acceptable.[7][16]

Fable 5.1 is the stronger quality escalation. It scores 47 at low, 49 medium, 51 high and 53 at xhigh/max. Its current cache-read price is only $0.25/M despite $10/$50 headline input/output pricing — a 98% discount versus normal input. That makes it much more attractive for persistent agent sessions than headline pricing suggests.[9][30]

Recommended cached-frontier configuration:

```yaml
frontier_cached:
  model: anthropic/claude-fable-5.1
  reasoning: medium
  fallback: meta/muse-spark-1.3
```

Use Fable `high` only where the quality gain is measured to matter. Max should not be a routine default.

---

## 8. Frontier one-off reasoning: GPT-6 Astra

### Recommendation: Astra Low first, then Medium

Astra’s reasoning-effort curve is unusually useful:

| Effort | AA v4.3 | AA cost/task | Operational interpretation |
|---|---:|---:|---|
| None | 45 | — | Already frontier-ish |
| **Low** | **46** | **~$0.82** | Best interactive escalation |
| **Medium** | **50** | **~$1.54** | Main “very hard” tier |
| High | 51 | ~$1.72 | Small gain |
| xhigh | 53 | ~$2.31 | Frontier ceiling |
| Max | 53 | ~$3.26 | Same composite score as xhigh, more compute |

Astra Low is especially striking: it reaches 46 with a time to first token around 2.5 seconds and is extremely concise. Artificial Analysis reports roughly 10M output tokens across the full Intelligence Index evaluation for Astra Low, much lower than most peers. This token efficiency offsets its very expensive $10/$50 nominal price on difficult tasks.[12][13]

Recommended configuration:

```yaml
frontier_interactive:
  model: openai/gpt-6-astra
  reasoning: low

frontier_deep:
  model: openai/gpt-6-astra
  reasoning: medium
```

Do **not** automatically route difficult work to `high`, `xhigh` or `max`. Medium reaches 50; high only gains one point. Xhigh and max both reach 53, so max needs a task-specific reason.

### When not to use Astra

For a long-lived session with hundreds of millions of cached-read tokens, its $1/M cache-read price is expensive. Prefer Sol/Muse/Fable when stable context dominates total traffic, then escalate to Astra for a difficult one-off subproblem.

---

## 9. Coding strategy

### Development: keep Claude Code and Codex subscriptions

Your observed week proves that serious development agents can consume hundreds of millions of cached tokens. Moving the same development workflow to pay-as-you-go Gateway APIs purely for architectural purity would be economically unnecessary while subscription-backed Codex and Claude Code remain available.

The Home Lab should distinguish:

```text
building the Home Lab
    -> Codex / Claude Code subscriptions

Home Lab runtime invokes a coding agent
    -> API/Gateway model route
```

### Current benchmark leaders

Coding Agent Index v1.5 currently shows:

| Harness + model | Index | DeepSWE | Terminal v4 | Repo Q&A | Cost/task | Time/task | Cache hit |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Codex + GPT-6 Astra max** | **62** | 68% | 56% | 62% | ~$7.47 | 29.4m | 93% |
| **Claude Code + Fable 5.1 max** | **62** | 64% | 58% | 65% | ~$12.39 | 34.8m | 92% |
| Claude Code + Opus 5 max | 60 | 63% | 55% | 62% | ~$10.79 | 41.9m | — |
| Codex + GPT-5.6 Sol max | 55 | **72%** | 37% | 54% | ~$6.58 | 20.6m | — |
| Muse Code + Muse Spark 1.3 max | 54 | **72%** | 32% | 59% | ~$3.98 | 18.4m | 97% |
| OpenCode + GLM-5.3 | 54 | 61% | 40% | 59% | ~$4.24 | 48.1m | 97% |

Sources: current Coding Agent Index comparisons.[18][19][27]

### Interpretation

Astra is currently the best **all-round hard coding** choice in Codex, but Sol still wins the DeepSWE patch-oriented subbenchmark. Fable is equally strong overall in Claude Code and slightly stronger on repository Q&A/terminal, but costs more.

Muse Spark is notable because it reaches a 54 coding index at much lower cost and time than frontier Claude/Codex configurations, although the harness is different.

There is **no current Coding Agent Index v1.5 result for DeepSeek V4.1 Flash** in the source set. Do not infer one from older DeepSeek V4 Flash/Pro results. V4.1 should be tested in your own coding harness before being promoted.

### Recommended API coding policy

```yaml
coding_standard_experiment:
  candidates:
    - deepseek/deepseek-v4.1-flash  # high
    - google/gemini-3.8-flash       # high
    - meta/muse-spark-1.3           # xhigh

coding_hard:
  preferred_harness: codex
  model: openai/gpt-6-astra
  reasoning: max

coding_hard_challenger:
  preferred_harness: claude-code
  model: anthropic/claude-fable-5.1
  reasoning: max
```

For hard autonomous coding, `max` is justified because the objective is task completion rather than conversational latency. It is one of the few places in the architecture where max effort should be a normal selectable profile.

---

## 10. RAG architecture

RAG should remain a pipeline, not a “RAG model”:

```text
query
  -> query transformation (optional utility model)
  -> embedding
  -> vector / hybrid retrieval
  -> reranking
  -> deterministic context assembly
  -> general or reasoning generator
```

### Embeddings: Voyage 4 family

The recommendation remains **Voyage 4 at 1024 dimensions** for the first implementation. It costs $0.06/M tokens through Gateway, supports 32K input and multiple Matryoshka dimensions.[21]

A more advanced asymmetric configuration is especially attractive:

```text
document indexing
  -> Voyage 4 Large ($0.12/M)
  -> shared vector space

query embedding
  -> Voyage 4 Lite ($0.02/M)
```

All Voyage 4 family members share an embedding space, so documents can be indexed with the stronger model and queried with the cheaper model without maintaining separate indexes.[21][22]

### Reranking: Cohere Rerank 4 Fast

Use Cohere Rerank 4 Fast as the initial second-stage reranker. It supports 32K per query/document pair, 100+ languages and mixed formats such as JSON/code/tables, and currently costs $2 per 1,000 queries. Rerank 4 Pro is $2.50 per 1,000.[23]

Always benchmark three variants:

```text
A: retrieval -> top 5
B: retrieval -> top 50 -> Rerank 4 Fast -> top 5
C: retrieval -> top 50 -> Rerank 4 Pro  -> top 5
```

At Home Lab scale, the $0.0005/query Fast-versus-Pro difference is tiny. Quality and latency should decide.

### Generator routing after RAG

```text
simple factual synthesis
    -> DeepSeek V4.1 high or Gemini 3.8 medium

complex multi-document synthesis
    -> Sol high

frontier one-off analysis
    -> Astra low/medium

long cache-heavy knowledge session
    -> Fable medium / Muse xhigh experiment
```

Do not fill a 1M context window simply because it exists. Treat it as capacity, not a target.

---

## 11. Prompt and context assembly

Prompt assembly should remain **deterministic application code**. Do not spend another LLM call merely to concatenate messages.

Recommended logical context layers:

```text
C0  global policy / safety / platform rules
C1  agent identity + tool schemas
C2  stable project/session context
---------------------------------- cache boundary
C3  conversation tail / rolling summary
C4  RAG chunks
C5  current tool results
C6  current user request
```

The LLM can help **compress** or **select** context, but it should not own the basic assembly logic.

---

## 12. Cache architecture

### Stable prefix design

The Home Lab should deliberately maximize reuse of the expensive stable prefix:

```text
request
  -> Agent/Model Router
  -> Context Assembler
      -> stable system policy
      -> stable agent prompt
      -> deterministic tool schemas
      -> stable project state
      ---------------------------
      -> dynamic history
      -> RAG results
      -> live tool output
      -> user request
  -> AI Gateway
```

### Rules

1. **Put stable content first.**
2. **Never inject timestamps, request IDs or live values into the stable prefix.**
3. **Serialize tool schemas deterministically** — stable order, names and descriptions.
4. **Version stable prompt components** (`policy_v3`, `tools_v12`, `agent_ops_v5`).
5. **Record cache-read and cache-write tokens** from every response.
6. **Avoid unnecessary provider switching** during cache-sensitive long sessions because caches are provider-specific.
7. **Allow fallback when reliability matters more than the cache hit.**
8. **Measure cache hit rate per route, not globally.** RAG and one-off analysis naturally have lower cache reuse than coding agents.

### Provider pinning

For cache-sensitive sessions, use AI Gateway `order` or `only` provider controls where justified. A useful policy is:

```text
interactive ordinary traffic
    -> automatic gateway routing/failover

long-lived high-cache agent session
    -> prefer pinned provider
       -> fallback only if health/reliability requires it
```

### Cache-aware routing signal

Add an estimate before model selection:

```text
expected_cache_ratio:
  low     < 40%
  medium  40–80%
  high    > 80%
```

These thresholds should ultimately be tuned from observed data rather than treated as universal constants.

---

## 13. Speech-to-text

The public evidence is still less decisive than for text models.

### Candidates

**Gemini 3.5 Transcribe** was released August 26 and is the newer Google path through Gateway. Current Gateway pricing is approximately $2/M input and $12/M output.[24]

**GPT-4o mini Transcribe** is cheaper at $1.25/$5 and OpenAI reports lower WER than Whisper-generation models, particularly for accents/noise. However, Vercel currently marks the OpenAI provider endpoint as going away on February 26, 2027.[25]

**Gemini 3.5 Transcribe Live** costs roughly $0.54/hour and becomes relevant only if the project moves from Telegram voice notes to live speech.[31]

### Recommendation

Do not select by vendor benchmark. Build a small ground-truth set of real Telegram voice notes in the languages/accent conditions you care about and compute:

- WER;
- character error rate;
- punctuation/names accuracy;
- latency;
- cost/minute.

Until then, keep both batch models behind the same `transcribe` interface.

---

## 14. Proposed model registry

This is the configuration I would implement **today as a starting point**, while clearly marking provisional routes.

```yaml
models:

  utility:
    model: openai/gpt-5.6-luna
    reasoning: none
    max_output_tokens: 1024
    challenger: inception/mercury-2.5

  general_tools:
    model: deepseek/deepseek-v4.1-flash
    reasoning: high
    max_output_tokens: 8192
    # Provisional: independently benchmarked result is max effort.
    # A/B medium vs high vs xhigh on Home Lab tasks.

  general_quality:
    model: google/gemini-3.8-flash
    reasoning: medium
    max_output_tokens: 8192

  general_open_challenger:
    model: zai/glm-5.3-flash
    reasoning: provider-default

  reasoning_cached:
    model: openai/gpt-5.6-sol
    reasoning: high
    context_soft_limit: 128000

  reasoning_cached_plus:
    model: meta/muse-spark-1.3
    reasoning: xhigh

  frontier_interactive:
    model: openai/gpt-6-astra
    reasoning: low

  frontier_deep:
    model: openai/gpt-6-astra
    reasoning: medium

  frontier_cached:
    model: anthropic/claude-fable-5.1
    reasoning: medium

  coding_hard:
    model: openai/gpt-6-astra
    reasoning: max
    preferred_harness: codex

  embedding:
    model: voyage/voyage-4
    dimensions: 1024

  embedding_documents_quality:
    model: voyage/voyage-4-large
    dimensions: 1024

  embedding_queries_budget:
    model: voyage/voyage-4-lite
    dimensions: 1024

  reranker:
    model: cohere/rerank-v4-fast

  transcription_primary_candidate:
    model: google/gemini-3.5-transcribe

  transcription_challenger:
    model: openai/gpt-4o-mini-transcribe
```

Model IDs and prices must remain configuration, never architecture.

---

## 15. Routing policy

A practical first router can remain deterministic:

```text
if task == classification/extraction/routing:
    utility

elif task == coding and development_session:
    use subscription Codex or Claude Code

elif task == coding and runtime_agent:
    standard coding eval route
    if difficult/failed -> coding_hard

elif complexity == normal:
    general_tools

elif complexity == hard and expected_cache_ratio > 0.80:
    reasoning_cached

elif complexity == hard and interactive:
    frontier_interactive

elif complexity == frontier and expected_cache_ratio > 0.80:
    frontier_cached

elif complexity == frontier:
    frontier_deep
```

Do not begin with an LLM choosing every model. A deterministic policy is easier to debug and benchmark. Later the utility model can classify task type/difficulty while policy code makes the final route.

---

## 16. Evaluation program

Public benchmarks should choose the shortlist. **Home Lab evaluations should choose the winner.**

### Utility suite

Measure:

- classification accuracy;
- JSON/schema validity;
- tool/agent routing accuracy;
- false-positive destructive-action rate;
- p50/p95 latency;
- cost per 1,000 routes.

Candidates: Luna none/low, Mercury 2.5 minimal/low, DeepSeek V4.1 none/low, GLM Flash.

### General/tool suite

Create 50–100 representative tasks:

- Docker status diagnosis;
- service/log inspection;
- simple multi-tool workflows;
- structured outputs;
- Telegram conversational tasks;
- lightweight document/RAG answers.

Measure:

- task success;
- tool-selection accuracy;
- number of turns/tool calls;
- hallucinated tool arguments;
- total output/reasoning tokens;
- cache hit ratio;
- total cost;
- end-to-end time.

Candidates: DeepSeek V4.1 medium/high/xhigh, Gemini medium/high, GLM Flash, optionally Sonnet 5.

### Reasoning suite

Use architecture/security/diagnostic tasks from the actual Home Lab:

- choose between architecture alternatives;
- diagnose multi-service failures;
- reason across ADRs;
- plan a migration;
- security threat-model decisions.

Compare:

- Sol high;
- Muse xhigh/max;
- Astra low/medium;
- Fable medium/high.

Run the suite twice:

1. **cold / low-cache**;
2. **warm / high-cache**.

This is critical: the winner may change.

### Coding suite

Do not benchmark toy HumanEval snippets. Use repository tasks:

- bug fix;
- feature implementation;
- tests;
- Docker/Compose change;
- refactor across files;
- terminal troubleshooting;
- documentation + code change.

Measure pass/fail, tests, regressions, turns, wall time, tokens and cache hits. Keep the harness fixed when comparing base models.

### RAG suite

Measure retrieval separately from generation:

- Recall@5/10/20;
- nDCG@10;
- MRR;
- answer-groundedness;
- citation accuracy;
- retrieval latency;
- total cost/query.

### STT suite

Use WER/CER against manually corrected Telegram transcripts.

---

## 17. Observability schema

Every model call should eventually log at least:

```text
request_id
session_id
agent_id
task_type
complexity
model_profile
model_id
provider
reasoning_effort

fresh_input_tokens
output_tokens
reasoning_tokens
cache_write_tokens
cache_read_tokens
cache_hit_ratio

input_cost
output_cost
cache_write_cost
cache_read_cost
total_cost

TTFT
time_to_first_answer
total_latency
tool_calls
turns

success
quality_score
error_type
fallback_used
actual_model_served
```

The key derived metrics are:

```text
cost_per_successful_task
latency_per_successful_task
quality_per_dollar
failure_rate_by_model_profile
cache_hit_rate_by_profile
```

That gives the Home Lab a real model-selection loop rather than a static config file.

---

## 18. Final decision matrix

| Decision | Recommendation | Confidence |
|---|---|---|
| Unified managed provider | Vercel AI Gateway | High |
| Utility default | GPT-5.6 Luna none | High |
| Utility experimental challenger | Mercury 2.5 | Medium-low until own eval |
| General/tool default candidate | **DeepSeek V4.1 Flash high** | Medium; very new |
| General quality fallback | Gemini 3.8 Flash medium | High |
| Open-weight general challenger | GLM-5.3 Flash | High |
| High-cache hard reasoning | GPT-5.6 Sol high | Medium-high |
| High-cache stronger escalation | Muse Spark 1.3 xhigh / Fable 5.1 medium | Medium |
| Low-cache interactive frontier | GPT-6 Astra low | High |
| Very hard one-off | GPT-6 Astra medium | High |
| Max frontier reasoning | Astra xhigh before max | High |
| Development coding | Subscription Codex + Claude Code | High |
| Hard API coding | Codex + Astra max | High based on current harness benchmark |
| Anthropic hard coding challenger | Claude Code + Fable max | High |
| Terra permanent tier | Do not add | High |
| DeepSeek V4.1 | **Must benchmark; Tier-1 candidate** | High |
| Embeddings | Voyage 4 1024d | Medium-high |
| Reranker | Cohere Rerank 4 Fast + no-rerank control | Medium-high |
| STT | Own A/B: Gemini 3.5 vs GPT-4o mini | Medium |
| Cache architecture | Stable-prefix + deterministic schemas + provider-aware routing | High |

---

## 19. What changed versus the previous strategy

1. **DeepSeek V4.1 Flash was added and promoted** from “future interesting candidate” to a primary general/tool workhorse candidate.
2. **DeepSeek V4 Flash 0731 is removed** from the active shortlist because V4.1 supersedes it.
3. **Claude Fable 5.1 was added** as the main Anthropic frontier/cache-heavy candidate; Opus 5 becomes secondary.
4. **Muse Spark 1.3 was added** as a strong cache-friendly middle/frontier reasoning and coding challenger.
5. **Mercury 2.5 was added to the watchlist** for utility/high-volume tasks, but not promoted without independent/own eval evidence.
6. **Gemini 3.8 Flash remains important**, but is no longer the uncontested default general model; DeepSeek’s new cache economics justify putting them head-to-head.
7. **GPT-6 Astra remains the best frontier escalation**, especially at low/medium effort and for hard coding, but it should not carry long cache-heavy sessions by default.
8. **Caching is now part of the routing policy**, not simply a provider optimization.

---

## 20. Implementation sequence

1. Implement logical model profiles and a provider-agnostic `ModelService`.
2. Implement the stable-prefix/context assembler and log cache-read/write tokens.
3. Add deterministic route selection using task type, complexity, latency tolerance and estimated cache ratio.
4. Configure Luna, DeepSeek V4.1, Gemini, Sol, Astra and one Anthropic/Meta frontier challenger.
5. Build the utility and general/tool eval suites before allowing automatic use of expensive routes.
6. Benchmark DeepSeek V4.1 `medium/high/xhigh` against Gemini `medium/high` and GLM Flash on real tool tasks.
7. Benchmark Sol/Astra/Muse/Fable twice: cold-context and warm-cache.
8. Keep active Home Lab development on subscription-backed Codex/Claude Code; benchmark Gateway coding separately.
9. Add Voyage + reranking and evaluate retrieval independently.
10. Add transcription and measure on real voice notes.
11. Re-run the market scan periodically; models should be replaceable through config only.

---

## 21. Limitations

- Model releases and provider pricing are moving unusually quickly in September 2026. Vercel routes the same model across providers with different prices and performance; “from” prices can change without the model changing.
- DeepSeek V4.1 is less than two days old at the time of this report. Independent evidence exists for its max reasoning configuration, but its medium/high Gateway effort settings need Home Lab-specific evaluation.
- Mercury 2.5 has compelling Gateway economics but does not yet have comparable independent AA v4.3 evidence in this source set.
- Composite benchmarks are priors, not ground truth. A 40-versus-42 index difference can matter less than tool-call reliability or output verbosity on your workload.
- Coding benchmarks measure **harness + model**. Never attribute all score differences to the base model.
- The synthetic 97%-cache cost table applies the same token mix to every model; real models generate different amounts of reasoning/output and may require different numbers of turns.
- A 1M context window should be treated as capacity, not as a recommendation to send 1M tokens.
- Cache hit rate is not a quality metric. Irrelevant cached context can still degrade answers.

---

## Sources

**[1] Home Lab project handover.** User-supplied project context, September 2026.

**[2] Artificial Analysis.** [Announcing the Artificial Analysis Intelligence Index v4.3](https://artificialanalysis.ai/articles/artificial-analysis-intelligence-index-v4-3), September 7, 2026.

**[3] Artificial Analysis.** [DeepSeek V4.1 Flash — Intelligence, Performance & Price](https://artificialanalysis.ai/models/deepseek-v4-1-flash), September 2026.

**[4] Vercel AI Gateway.** [DeepSeek V4.1 Flash model and current provider pricing](https://vercel.com/ai-gateway/models/deepseek-v4.1-flash).

**[5] Artificial Analysis.** [Gemini 3.8 Flash release comparison](https://artificialanalysis.ai/models/releases/gemini-3-8-flash), September 2026.

**[6] Vercel AI Gateway.** [Gemini 3.8 Flash current Gateway metrics](https://vercel.com/ai-gateway/models/gemini-3-flash).

**[7] Artificial Analysis.** [Muse Spark 1.3 release comparison](https://artificialanalysis.ai/models/releases/muse-spark-1-3), September 2026.

**[8] DeepSeek.** [Introducing DeepSeek-V4.1-Flash](https://www.deepseek.com/en/news/deepseek-v4-1-flash/), September 10, 2026.

**[9] Vercel AI Gateway.** [Claude Fable 5.1 pricing/providers](https://vercel.com/ai-gateway/models/claude-fable-5.1).

**[10] Artificial Analysis.** [GPT-5.6 Luna release comparison](https://artificialanalysis.ai/models/releases/gpt-5-6-luna).

**[11] Vercel AI Gateway.** [GPT-5.6 Luna](https://vercel.com/ai-gateway/models/gpt-5.6-luna).

**[12] Artificial Analysis.** [GPT-6 Astra Low](https://artificialanalysis.ai/models/gpt-6-astra-low) and Astra release comparisons, September 2026.

**[13] Artificial Analysis.** [Benchmarking GPT-6 Astra](https://artificialanalysis.ai/articles/benchmarking-gpt-6-astra), September 9, 2026.

**[14] Artificial Analysis.** [GLM-5.3-Flash](https://artificialanalysis.ai/models/glm-5-3-flash).

**[15] OpenAI.** [Release notes — GPT-6 Astra](https://openai.com/products/release-notes/), September 3, 2026.

**[16] Vercel AI Gateway.** [Muse Spark 1.3](https://vercel.com/ai-gateway/models/muse-spark-1.3).

**[17] Vercel AI Gateway.** [Mercury 2.5](https://vercel.com/ai-gateway/models/mercury-2.5).

**[18] Artificial Analysis.** [Claude Code vs Codex — Coding Agent Index v1.5](https://artificialanalysis.ai/agents/coding-agents/comparisons/claude-code-vs-codex).

**[19] Artificial Analysis.** [Coding Agent benchmarking](https://artificialanalysis.ai/agents/coding-agents).

**[20] Google.** [Introducing Gemini 3.8 Flash](https://blog.google/innovation-and-ai/models-and-research/gemini-models/3-8-flash-and-3-8-flash-cyber/), September 2, 2026.

**[21] Vercel AI Gateway.** [Voyage 4](https://vercel.com/ai-gateway/models/voyage-4).

**[22] Voyage AI.** [Voyage 4 model family and shared embedding space](https://blog.voyageai.com/2026/01/15/voyage-4/).

**[23] Vercel AI Gateway.** [Cohere Rerank 4 Fast](https://vercel.com/ai-gateway/models/rerank-v4-fast).

**[24] Vercel AI Gateway.** [Gemini 3.5 Transcribe](https://vercel.com/ai-gateway/models/gemini-3.5-transcribe).

**[25] Vercel AI Gateway.** [GPT-4o mini Transcribe](https://vercel.com/ai-gateway/models/gpt-4o-mini-transcribe).

**[26] Artificial Analysis.** [Kimi K3](https://artificialanalysis.ai/models/releases/kimi-k3).

**[27] Artificial Analysis.** [Muse Code vs OpenCode coding-agent comparison](https://artificialanalysis.ai/agents/coding-agents/comparisons/muse-code-vs-opencode).

**[28] Vercel AI Gateway.** [GLM-5.3 Flash pricing/providers](https://vercel.com/ai-gateway/models/glm-5.3-flash).

**[29] Vercel AI Gateway.** [GPT-5.6 Sol pricing/providers](https://vercel.com/ai-gateway/models/gpt-5.6-sol).

**[30] Artificial Analysis.** [Claude Fable 5.1 release comparison](https://artificialanalysis.ai/models/releases/claude-fable-5-1).

**[31] Vercel AI Gateway.** [Gemini 3.5 Transcribe Live](https://vercel.com/ai-gateway/models/gemini-3.5-transcribe-live).

**[32] Vercel AI Gateway.** [AI model leaderboards — adoption, requests and spend](https://vercel.com/ai-gateway/leaderboards/models).

---

## Appendix A — Market/adoption signal

Vercel’s anonymized AI Gateway leaderboard is not a quality benchmark, but it is useful as a market signal. As of September 10, DeepSeek V4.1 Flash already represented about **35% of Gateway token volume** and 9.7% of requests in the three-month view; GLM-5.3 Flash led team reach in the Sep 9 snapshot. This unusually fast adoption reinforces the case for benchmarking these models, but it should not be used as evidence that they are intrinsically better.[32]

## Appendix B — Design principle

The durable architecture is:

```text
Home Lab feature
   -> logical capability profile
   -> routing policy
   -> ModelService
   -> Vercel AI Gateway
   -> model + provider
```

Not:

```text
Home Lab feature
   -> hard-coded model name
```

The model landscape will change faster than the rest of the project. The Home Lab should be designed so a benchmark result can change one configuration entry rather than require an application refactor.
