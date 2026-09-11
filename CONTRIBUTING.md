# Contributing

Thanks for looking. This repo provisions a specific class of machine — AMD
Strix Halo (gfx1151) on Arch/Omarchy — so the most valuable contributions are
usually **"this failed on my Ryzen AI MAX box, here's why"**.

## Before you open a PR

```bash
./tests/run.sh                 # must pass
./install.sh --dry-run --all   # plan must be clean and exit 0
```

Read [docs/guidelines/module-contract.md](docs/guidelines/module-contract.md)
and [docs/guidelines/shell-style.md](docs/guidelines/shell-style.md) first.
The short version:

- Modules are standalone executables in `installers/`, sourcing `_lib.sh`.
- Never call `pacman`/`systemctl`/`ln`/`pip` directly — use a `_lib.sh` verb, so
  `--dry-run` and `--uninstall` keep working.
- Every mutating verb must report through `plan`, or it silently vanishes from
  the plan tally.
- Honor `NO_COLOR`, `TUI_NO_ANIM`, and non-TTY stdout.

## If you change a pin or add a workaround

Add an entry to [docs/decisions.md](docs/decisions.md) explaining **why**, and
include the failing symptom — the exact error string. That file exists so the
next person can paste their error into a search box and land on the answer.
A workaround without a recorded reason will be asked to justify itself.

## Reporting a problem

Open an issue: <https://github.com/kinncj/halomarchy/issues>. Include:

- `uname -r`, and the output of `rocminfo | grep gfx`
- your machine (ZBook G1a, Framework Desktop, GMKtec EVO-X2, …)
- `./install.sh --dry-run --all` output
- the exact error text, not a paraphrase

## Other hardware

Non-ZBook Ryzen AI MAX machines are welcome — open an issue with what worked
and what didn't, even if you don't have a patch. The ROCm, inference and gaming
modules should apply unchanged; `webcam` is ZBook-specific. If a module needs
to branch on hardware, branch explicitly and say so in `module_describe`-level
comments rather than silently degrading.

## Commit messages

Explain **why**, not what — the diff already says what. Reference the decision
entry when relevant.
