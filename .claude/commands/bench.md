---
description: Re-run the hardware benchmarks and update docs/benchmarks.md
argument-hint: [model-tag]
---

Re-measure this machine and update `docs/benchmarks.md` with real numbers.
Use `${1:-qwen3.8:27b}`.

1. Ensure ollama is active (`ai status`; `ai start ollama` if needed).
2. Generation: POST to `http://127.0.0.1:11434/api/generate` with
   `stream:false` and a fixed prompt. Compute tok/s from `eval_count` and
   `eval_duration` — do **not** time the wall clock, it includes model load.
   Run twice; the first is cold.
3. Confirm placement with `ollama ps` — it must say `100% GPU`.
4. If lemonade is active, benchmark it too via
   `http://127.0.0.1:13305/api/v1/chat/completions` and note that its figure
   includes HTTP overhead, so it is not directly comparable.
5. LoRA: run the training check with and without
   `TORCH_ROCM_AOTRITON_ENABLE_EXPERIMENTAL=1` and report both.

Update the tables in `docs/benchmarks.md` with what you measured. Keep the
existing conclusions only if the numbers still support them — generation is
expected to be memory-bandwidth-bound at ~18 tok/s for a dense 27B. If a
result contradicts that, say so plainly rather than massaging it.
