# Module contract

Every file in `installers/` is a **standalone executable**, not a sourced
library. `install.sh` runs it with `bash "$installer"` and judges it by exit
code alone.

```mermaid
sequenceDiagram
    participant I as install.sh
    participant M as installers/&lt;name&gt;.sh
    participant L as _lib.sh
    participant S as pacman / systemd / pip

    I->>I: parse flags, order KNOWN_MODULES
    I->>M: bash installer (DRY_RUN, UNINSTALL, REPO_DIR exported)
    M->>L: source _lib.sh
    M->>L: pkg_install / file_install / unit_enable / link_bin
    L->>L: compute state -> plan row
    alt DRY_RUN=1
        L-->>M: report only
    else
        L->>S: execute
    end
    M-->>I: exit code
    I->>I: tally plan, render summary
```

## Required shape

```bash
#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# One line saying what this module owns.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    # undo what module_run does, then exit 0
    exit 0
fi

pkg_install some-package
file_install "$REPO_DIR/files/x.conf" /etc/x.conf
unit_enable some.service
```

Then add the module name to `KNOWN_MODULES` in `install.sh`.

## Rules

1. **One concern per module.** If you need "and" to describe it, split it.
2. **Idempotent.** Re-running must be a no-op that reports `same`.
3. **Never call `pacman` / `systemctl` / `ln` / `pip` directly.** Use a
   `_lib.sh` verb. Bypassing them silently breaks `--dry-run` and `--uninstall`
   — the module will appear to work while writing during a dry-run.
4. **Every mutating action reports through `plan`.** No `plan` call means the
   item vanishes from the tally, so the plan under-reports.
5. **Handle `UNINSTALL=1` first**, before any state inspection.
6. **Expensive, non-previewable work short-circuits in dry-run.** The `unsloth`
   module reports the resulting state and exits rather than claiming success
   for pip steps that never ran.
7. **Order dependencies explicitly.** `KNOWN_MODULES` order is load-bearing;
   comment the reason when it isn't obvious.

## Available verbs

| Verb | Reports |
|---|---|
| `pkg_install <pkg>…` | `same` (with version) / `update` (old → new) / `new` |
| `aur_install <pkg>…` | same, via `yay` |
| `pkg_install_overwrite <path> <pkg>` | for packages colliding on one file |
| `file_install <src> <dst> [mode]` | compares **content** |
| `unit_install <src> <dst>` | `file_install` with mode 644 |
| `unit_enable` / `unit_enable_user` | compares enabled/active state |
| `link_bin <target> <link>` | compares **resolved** symlink targets |
| `remove_path <path>` | `remove` / `same` |
| `fetch_verified <dir> <manifest> <base> <ref>` | checksum-verified download |
| `run <cmd…>` | executes, or prints `would:` in dry-run |
| `plan <state> <item> [detail]` | raw plan row |

## Templates

If a file needs machine-specific values, **render it to a temp file first**,
then `file_install` that. Installing the raw template and patching it in place
makes the plan compare a template against a substituted file, so it reports
`update` forever and the plan never reads clean. See `installers/heimdall.sh`.
