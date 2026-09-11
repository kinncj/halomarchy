---
description: Verify the whole AI + gaming stack end-to-end and report what is broken
---

Verify this machine's stack and report a concise table. Run the checks; do not
assume any of them pass.

1. **Plan drift** — `./install.sh --dry-run --all`. Anything under "to change"
   means the machine has drifted from the repo. Say what and why.
2. **GPU** — `/opt/rocm/bin/rocminfo | awk '/Name:.*gfx/'` must show `gfx1151`.
3. **Services** — `ai status`. Note anything inactive or disabled.
4. **Torch** — the venv must report `2.12.1+rocm7.2` and have `gfx1151` in
   `torch.cuda.get_arch_list()`:
   `~/ai/unsloth/bin/python -c "import torch;print(torch.__version__, 'gfx1151' in ' '.join(torch.cuda.get_arch_list()))"`
5. **Triton** — exactly one triton distribution: `~/ai/unsloth/bin/pip list | grep -i triton`
   should show only `triton-rocm 3.7.1`. Two means shadowing has returned.
6. **Inference** — if ollama is active, one real generation and its tok/s.
7. **Gaming** — `vulkaninfo --summary` must name the device with `radv`.

Report a table of check → pass/fail → detail. For each failure, name the fix
and cite the relevant section of `docs/decisions.md`. Do not fix anything
unless asked.
