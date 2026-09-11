---
description: Scaffold a new installers/ module following the repo contract
argument-hint: <module-name> [what it should do]
---

Create a new installer module named `$1` in this repo.

Read `.claude/skills/kinn-setup/SKILL.md` first — it defines the contract you
must follow.

Steps:

1. Create `installers/$1.sh`, executable, with the SPDX header used by the
   other modules.
2. It must `set -euo pipefail`, source `_lib.sh`, handle `UNINSTALL=1` early,
   and use only `_lib.sh` verbs (`pkg_install`, `file_install`, `unit_enable`,
   `link_bin`, `run`, …) so dry-run and uninstall work for free.
3. Add `$1` to `KNOWN_MODULES` in `install.sh`, positioned so its dependencies
   run first. State the ordering reason in a comment if it isn't obvious.
4. If it introduces a pin, a workaround, or anything a reader would later ask
   "why is this here?" about, add an entry to `docs/decisions.md`.
5. Verify: `bash -n installers/$1.sh` and `./install.sh --dry-run --target $1`.
   The dry-run must show plan rows, not just `would:` lines — if it doesn't,
   you bypassed a `_lib.sh` verb.

Show me the diff before committing anything.
