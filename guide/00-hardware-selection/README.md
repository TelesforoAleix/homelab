# 00 — Hardware Selection

## Goal

Choose affordable hardware that matches the kind of AI experimentation you actually want to do.

The reference Home Lab deliberately separates **orchestration/infrastructure** from **GPU-heavy local inference**.

## Hardware tiers

### Tier 1 — Minimum orchestration node

Suitable for learning Linux, Docker, hosted-model access, simple agents, Telegram, lightweight services, and basic automation.

Look for:

- x86-64 CPU with multiple cores
- SSD storage
- reliable networking
- enough RAM for the services you intend to run
- good Linux compatibility
- low idle power and acceptable noise if always-on

Older business mini PCs can be strong candidates because they are inexpensive on the used market, compact, replaceable, and usually well understood by Linux.

### Tier 2 — Recommended Home Lab node

For running more concurrent containers, databases, indexing/RAG services, monitoring, and development workloads, prioritize additional RAM and storage capacity rather than spending heavily on CPU alone.

For this project, **16 GB RAM is a sensible working target**, while the exact minimum depends on the services introduced. The reference build begins with 8 GB and may be upgraded after actual usage is measured.

### Tier 3 — Local AI / GPU node

If local LLM inference, CUDA experiments, quantization, model serving, or fine-tuning are primary goals, the orchestration-node approach is not enough by itself.

Prioritize:

- an NVIDIA GPU supported by the software you want to test;
- enough VRAM for the target model sizes/quantization levels;
- adequate system RAM;
- storage for model files;
- adequate cooling and power supply;
- a chassis that physically supports the GPU.

A Tiny/Mini/Micro business PC is generally better treated as an orchestration node than forced into this role. Home Lab may later add a separate CUDA node.

## Reference examples

The canonical build uses a **Lenovo ThinkCentre M700 Tiny**. Similar used business mini PCs can also be appropriate if they satisfy the same functional requirements. Specific model recommendations and market price ranges should be updated from actual research rather than treated as permanent facts.

## Budget philosophy

The reference project favors used hardware and records actual spending. Market prices vary by country and date, so distinguish:

- actual reference-build price;
- typical used-market range at the time of research;
- optional upgrade cost;
- local-AI hardware as a separate budget category.

Do not over-upgrade an orchestration machine to solve a future GPU problem.
