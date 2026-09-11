# Shell style

Bash, `set -euo pipefail`, targeting Arch. `bash -n` must pass; `tests/run.sh`
enforces the rules below.

## Rules that bite

### Never `exit` inside `awk` in a pipeline

```bash
# WRONG — awk closes the pipe, rocminfo gets SIGPIPE, pipefail fails the
# substitution, set -e kills the module with no useful message.
t=$(rocminfo | awk '/gfx/{print $2; exit}')

# RIGHT
t=$(rocminfo | awk '/gfx/ && !seen {print $2; seen=1}')
```

This cost real debugging time: a module reported "installer failed" with no
output, because `assert_gfx1151` died on a SIGPIPE.

### Never `grep -c … || echo 0`

`grep` exits **1** on zero matches *and* prints `0`, so the fallback appends a
second one and the variable becomes `"0\n0"` — an arithmetic syntax error later.

```bash
n=$(awk -v k="$key" '$0==k{n++} END{print n+0}' "$file")
```

### Compare versions numerically

`7.10` is greater than `7.2`. String comparison gets this backwards.

```bash
_ver_lt() {
    [ "$1" = "$2" ] && return 1
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | awk 'NR==1')" = "$1" ]
}
```

Note `awk 'NR==1'`, not `head -1` — same SIGPIPE trap.

### Prefer `awk` over `grep`/`sed` for parsing

One tool, no `-E`/`-P` portability questions, and it sidesteps both traps
above. Tests flag `grep -c` fallbacks and `awk`-exit pipelines.

## Output

Never `printf` raw ANSI in a module. Use `_lib.sh`'s `ok` / `warn` / `err` /
`info`, which render indented inside the section box and respect `NO_COLOR`.

For long operations use `tui_spinner_start` / `tui_spinner_stop ok|fail`.
Animation auto-disables on non-TTY and under `TUI_NO_ANIM=1`.

## Quoting

Quote every expansion. Prefer `"${var:-default}"` over unquoted defaults —
`set -u` turns an unset variable into a hard failure, which is usually what you
want, but not for optional config.

## Portability

Arch-only is fine; `pacman` is assumed. Do not assume GNU-only flags beyond
what coreutils on Arch provides, and do not assume `/bin/bash` is 5.x when the
same helper might be sourced elsewhere.
