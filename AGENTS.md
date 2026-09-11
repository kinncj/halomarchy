# AGENTS.md

`.kinn_setup` provisions a Strix Halo (**gfx1151**) laptop with a local AI
stack and a gaming stack.

## Orientation

```
install.sh              flags, sequencing, plan tally, summary
installers/_tui.sh      presentation only (logo, boxes, spinner, rows)
installers/_lib.sh      run + pacman/systemd/file/link verbs + guards
installers/<name>.sh    one concern each, standalone executables
bin/ai                  service control — one registry drives status/list/help
docs/decisions.md       WHY every pin and workaround exists — read this first
```

## Ground rules

- Modules go through `_lib.sh` verbs, never `pacman`/`systemctl`/`ln` directly.
- Every mutating verb reports via `plan` so `--dry-run` stays truthful.
- The GPU is `gfx1151`. Pins in `installers/unsloth.sh` are load-bearing:
  `torch==2.12.1+rocm7.2`, `triton-rocm==3.7.1`, bitsandbytes preview.
  Upstream Unsloth docs are **wrong** for this GPU; see `docs/decisions.md`.
- Validate with `./install.sh --dry-run --all` before proposing changes.

## Don't

- Don't "simplify" the triton uninstall/rm/reinstall dance — it fixes real
  package shadowing.
- Don't repoint `~/.local/bin/unsloth`; that belongs to Unsloth Studio. The
  `unsloth-studio` unit *executes* it — the venv CLI stays `unsloth-venv`.
- Don't add a module without an entry in `KNOWN_MODULES`.
- Don't hardcode a unit into `ai help`; add it to the registry at the top of
  `bin/ai` and every view picks it up. (The group array is `AI_GROUPS` —
  `GROUPS` is bash's own read-only array.)
