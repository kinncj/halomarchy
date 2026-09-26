# Changelog

Notable changes to this project. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `strix-llama` installer: builds `halo-box/strix-llama.cpp` for gfx1151 with
  speculative prefill. Measured on a 395 laptop at 70 W, 27B Q4 at 32k context,
  TTFT falls 163.8s -> 49.6s (3.3x) with decode unchanged. It is lossy — at
  `p=0.15` retrieval dropped to 3/5 planted facts, losing the middle of the
  document while keeping both ends, so 0.30 is the documented floor and the
  installer wires nothing up for you. Vendors Vulkan/SPIRV headers (no root),
  builds at `-j8` because this is a sustained all-core load, and installs a
  self-contained launcher — a copied `llama-server` otherwise keeps resolving
  against the build tree and exits 127 under a clean environment.

### Changed
- `lemonade` installer no longer enables `lemond` at boot. A coding-grade model
  holds ~17 GB resident and this is a laptop before it is a server; Lemonade
  loads lazily, so `ai start lemonade` on demand costs only the daemon. Opt back
  in with `LEMOND_AUTOSTART=1`. The installer never disables a unit you enabled
  yourself. Documented in `docs/services.md`.

### Added
- `playwright` module: every Playwright-managed Chromium on the machine renders
  WebGL through ANGLE → Vulkan → RADV instead of SwiftShader. `bin/playwright-gpu`
  wraps the cached binaries; a `playwright-gpu.path` user unit re-wraps after
  any `playwright install`. `PLAYWRIGHT_GPU=0` bypasses per run.
  Motivation and mechanics in `docs/decisions.md` §15.
- `power` module: `kinn-cpu-cap` caps `scaling_max_freq` on every CPU (default
  3000 MHz, `KINN_CPU_CAP_MHZ`), re-applied at boot and after resume, and holds
  power-profiles-daemon on `balanced` (`KINN_POWER_PROFILE`). Stops the ZBook
  Ultra G1a's instant power-offs under boost bursts; evidence in
  `docs/decisions.md` §16.

## [1.0.0] — 2026-08-29

### Added
- Modular installer (`install.sh` + `installers/`) with animated TUI, flags for
  `--dry-run`, `--all`, `--target`, `--uninstall`, `--no-animation`, `--quiet`.
- Plan-aware dry-run: reports `new` / `update` / `same` / `remove` per item by
  comparing package versions, file content, unit state and symlink targets.
- `ai` command for service control across user and system systemd scopes.
- Modules: `packages`, `environment`, `webcam`, `gaming`, `heimdall`, `ollama`,
  `lemonade`, `unsloth`, `commands`.
- `unsloth-studio` user unit, so Unsloth Studio starts, stops and logs through
  `ai` like every other service: `ai start unsloth`, `ai logs unsloth`. The
  `ai` group target now covers `lemond` + `ollama` + `unsloth-studio`.
- `user_unit_install` / `user_unit_dir` verbs in `_lib.sh` for units that live
  under `$HOME` and need no root.
- `ai list [targets|groups|units]` — every group and unit with its live state,
  marking units whose unit file is not installed.
- `ai help` is now rendered from the same registry as `status` and `list`, so
  a new service appears in all three by adding one row to `bin/ai`.
- `KINN_STUDIO_BIN` override for Unsloth Studio's CLI, alongside `KINN_VENV`.
- Test suite (`tests/run.sh`), including a check that `--dry-run` leaves every
  installer target byte-identical.
- Docs: architecture, services, decisions, benchmarks, troubleshooting,
  guidelines — diagrams in Mermaid.
- Claude Code integration: `/stack-check`, `/new-module`, `/bench`, a
  `stack-doctor` agent and a `kinn-setup` skill.

### Fixed
- `awk`'s early `exit` in a pipeline SIGPIPE'd `rocminfo` under `set -o
  pipefail`, failing a module with no useful message.
- `grep -c … || echo 0` produced `"0\n0"` (grep exits 1 on zero matches *and*
  prints `0`), breaking the plan tally arithmetic.
- The Unsloth module clobbered `~/.local/bin/unsloth`, which belongs to Unsloth
  Studio; the venv CLI is now `unsloth-venv`.

### Security
- Internal Tailscale hostname moved out of tracked files into an untracked
  `local.conf`.
- AMD ISP4 sources are fetched from the kernel tree at a pinned ref and
  sha256-verified rather than committed.

### Changed
- Licensed MIT.

[1.0.0]: https://github.com/kinncj/halomarchy/releases/tag/v1.0.0
