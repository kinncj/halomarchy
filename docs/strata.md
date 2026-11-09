<!--
SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
SPDX-License-Identifier: MIT
-->
# Strata — a sparse MoE on Strix Halo

[Strata](https://github.com/Niko1221/Strata) (MIT) serves
**Qwen3.8-Flash-Next** — 10 of 512 experts per token — where Lemonade serves the
dense 27B. It exposes OpenAI **and** Anthropic APIs on `127.0.0.1:13306`.

**Why it exists here.** A dense model on this laptop is pinned by memory
bandwidth: ~256 GB/s against 17.5 GB of weights, and two independent engines land
within 2.6% of each other, which is what a wall looks like. A **sparse** model
reads a fraction of its weights per token, so it is the only thing that goes
faster. Time-to-first-token is not bandwidth-bound at all, and on this machine it
was the real cost of working locally — 163.8 s before the first token at 32k.

## Measured here

HP ZBook Ultra G1a, Radeon 8060S (gfx1151), 128 GB LPDDR5X, 70 W package limit,
Qwen3.8-Flash-Next UD-IQ4_XS, prompts of llama.cpp's own C++ sources, 256
generated tokens, **warm medians of 3 fresh processes per length**:

| prompt | decode | prefill | time to first token |
|---|---|---|---|
| 8k | **49.6 tok/s** | 1,116 tok/s | **7.9 s** |
| 32k | **55.4 tok/s** | 1,083 tok/s | **31.0 s** |
| 131k | **47.7 tok/s** | 1,135 tok/s | **116.0 s** |

Against Lemonade's dense 27B on the same machine (24.6 tok/s and 32.4 s at 8k;
20.8 and 163.8 s at 32k; 131k does not run):

- **2.0x decode and 4.1x TTFT at 8k; 2.7x and 5.3x at 32k.**
- **Prefill does not decay with depth** — ~1,100 tok/s from 8k to 131k. That is
  the structural win, and it is **lossless**: unlike `--backend=strix`, no part of
  the prompt is dropped to get it.
- 131k is a context the dense path cannot serve at all.

**Decode is not monotonic**: 32k (55.4) measures faster than 8k (49.6). It
reproduced across runs; it is not noise.

**Run 1 at any new length is 30-36% slower** (32k: 38.3 cold vs 55.4 warm). The
experts live in page cache, so the first prompt at a new depth faults them in from
SSD. Real for day-to-day use, not just for benchmarks.

Through the `halo` harness instead of the engine directly — same instrument and
same prompts as the dense path, so this is the comparable pair — decode reads
**34.9-39.0 tok/s against Lemonade's 24.6**. Lower than the engine-level figure
because the prompts differ; never compare across the two.

## Install

```bash
ai                      # or: ~/.kinn_setup/installers/strata.sh
ai start strata         # NOT enabled at boot: it holds 55 GiB of experts resident
ai status strata
```

From the fleet front-end, as a third engine beside `lemond` and `strix`:

```bash
halo --backend=strata status
halo --backend=strata pi
```

## What it needs, and what it must not have

The service is ~96 GB of locally built artefacts: the packaged engine, a model
pack, and an MTP draft layer. `installers/strata.sh` names any missing piece
rather than failing at start.

The **run config** is the one piece the installer can produce: it renders
`files/strata/flash-next.json.in` — the configuration everything above was
measured with — into `~/strata/profiles/flash-next.json`, substituting the home
and the two GGUF shard paths it finds at the pinned revision. An existing
profile is **never** overwritten, so a tuned one survives a re-run. Three of
its entries are not tuning — the two flags immediately below and the reasoning
fuse further down — and `tests/run.sh` fails if the template loses any of them.

**Two flags are the difference between running and an out-of-memory kill** on a
128 GB machine, and they live in the run config:

- **`--mmap-experts`** — without it the engine keeps a pinned host arena *and* a
  GPU-resident cache, **55.43 GiB each**. On an APU the GPU's memory is the same
  system RAM, so that is 110.9 GiB of 121.6 GiB and the kernel kills it. The
  upstream benchmark used `--resident-budget-gib 55`, which **no longer exists**
  (it was engine v0.1.41); this is its replacement.
- **`--ple-io direct`** — keeps the 26.8 GiB n-gram table on SSD. The engine's
  own residency policy promotes it to RAM when RAM looks free, so *freeing*
  memory makes it greedier and can cause the very OOM it was meant to avoid.

**Do not reserve hugepages for it.** The expert arena is registered with
`cudaHostRegister`, which cannot draw from `hugetlbfs`, so a `vm.nr_hugepages`
reservation is memory this process can never use — it only starves the machine.
The engine's `MAP_HUGETLB unavailable` line is informational; transparent huge
pages already cover it. Reserving 56 GiB here once drove the box into OOM and the
kernel killed the desktop session.

**`"reasoning_effort": "none"` in the run config.** Flash-Next is a reasoning
model and thinks by default, so a client that sends no `reasoning_effort` gets
its whole token budget spent on `reasoning_content` and comes back with
`content: null` and `finish_reason: length` — an empty answer, not an error.
Measured: a 32-token request returned nothing; with the config key it answers in
2 tokens and stops. This is the **server-side fuse**, the same place the dense
path puts `--reasoning-effort low`: putting it in the client means every client
has to remember.

**`LimitMEMLOCK=infinity`** (the unit sets it) lets the engine lock the n-gram
table: measured up to 6% of decode, and it roughly doubled the arena load rate.

**Pin the model revision.** `unsloth/Qwen3.8-Flash-Next-GGUF` re-uploaded
`UD-IQ4_XS` with a different expert mix — same name, same path, 4 shards instead
of 3 — and the newer one carries `Q5_0` expert down-projections that **the engine
refuses to start on**. Strata ships `data/gguf_fingerprints.json`, which is how
that is visible before an 87 GiB download.

## Caveats

- The gfx1151 path is **experimental** upstream.
- Quality is **not** verified here. The fast switches change rounding, and
  8-bit hyper-connection weights are on by default ("answers can differ in
  near-tie tokens"). Run `tools/needle-retrieval.py` before trusting it for
  retrieval work — the `strix` backend is the cautionary tale: every timing
  improved and 2 of 5 needles silently vanished.
- It serves **one request at a time** by default (`parallel` raises it, to a
  handful of slots). This is a single-user engine, not a household server.
