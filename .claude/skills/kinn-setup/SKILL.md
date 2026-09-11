---
name: kinn-setup
description: Conventions for editing the .kinn_setup provisioning repo — the installer module contract, TUI rules, plan-state semantics, and the gfx1151 pins that must not drift. Use when adding or changing anything under installers/, install.sh, bin/ai, or files/.
---

# Working on .kinn_setup

Provisions an HP ZBook Ultra G1a (Strix Halo, **gfx1151**) with a local AI
stack and a gaming stack. Structure deliberately mirrors
[kinncj/statusline](https://github.com/kinncj/statusline).

## Module contract

Every `installers/<name>.sh` is a **standalone executable**, not a sourced
library. It must:

1. `set -euo pipefail`
2. `source "$(dirname "$0")/_lib.sh"`
3. Handle `UNINSTALL=1` early and `exit 0`
4. Use `_lib.sh` verbs — never call `pacman`/`systemctl`/`ln` directly
5. Be idempotent: safe to re-run

Register it in `KNOWN_MODULES` in `install.sh`. Order is load-bearing:
`packages` first (installs `uv` + ROCm), `environment` before `unsloth`
(bitsandbytes shells out to `rocminfo`).

## Layering — do not cross these seams

| File | Owns | Must NOT |
|---|---|---|
| `installers/_tui.sh` | colors, logo, boxes, spinner, plan/summary rows | know about pacman or systemd |
| `installers/_lib.sh` | `run`, pkg/unit/file/link verbs, guards | print raw ANSI |
| `installers/<name>.sh` | one concern | reimplement a `_lib.sh` verb |
| `install.sh` | flags, sequencing, tallies | know how any module works |
| `bin/ai` | one registry → status/list/help | hardcode a unit into help text |

## Plan semantics

Every state-changing verb reports through `plan <state> <item> [detail]`:
`new` `+` · `update` `~` · `same` `=` · `remove` `-`. This is what makes
`--dry-run` answer *what actually changes*. A new verb that mutates state
without a `plan` call is a bug — it will silently vanish from the plan tally.

## Rules that bite

- **Never `exit` inside `awk` in a pipeline.** Under `set -o pipefail` the
  SIGPIPE fails the whole command substitution. Use `&& !seen {...; seen=1}`.
- **Never `grep -c ... || echo 0`.** grep exits 1 on zero matches *and* prints
  `0`, so the variable becomes `"0\n0"`. Use `awk '$0==k{n++} END{print n+0}'`.
- **Do not touch `~/.local/bin/unsloth`.** Unsloth Studio owns it. The venv CLI
  is linked as `unsloth-venv`. The `unsloth-studio` user unit runs Studio's
  binary; `ai start unsloth` drives that unit, never the venv.
- **User units use `user_unit_install`, not `unit_install`.** The latter writes
  with `sudo` and would prompt for a password to touch your own `~/.config`.
- **Never relax the torch pin.** `torch==2.12.1+rocm7.2`. Not 2.13 (unsloth_zoo
  requires `<2.13.0`), not the rocm6.4 index (contains no gfx1151 code).
- Honor `NO_COLOR`, `TUI_NO_ANIM`, and non-TTY stdout.

## Before committing

```sh
bash -n install.sh installers/*.sh bin/ai     # syntax
./install.sh --dry-run --all                  # plan must be clean
TUI_NO_ANIM=1 NO_COLOR=1 ./install.sh --dry-run --all   # degrades cleanly
```

If you changed a pin or added a workaround, add an entry to
`docs/decisions.md` explaining **why** — that file is the point of this repo.
