#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
#
# Test suite. Safe to run on any machine: every check is read-only, and the
# dry-run tests assert that nothing on disk changes.
#
#   ./tests/run.sh            run everything
#   ./tests/run.sh syntax     run matching tests only
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export TUI_NO_ANIM=1
FILTER="${1:-}"
PASS=0; FAIL=0; SKIP=0

source "$REPO_DIR/installers/_tui.sh"

_t() {  # _t <name> <fn>
    local name="$1" fn="$2"
    [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && return 0
    local out; out="$("$fn" 2>&1)"; local rc=$?
    case $rc in
        0) PASS=$((PASS+1)); tui_summary_row "$name" ok   "$out" ;;
        2) SKIP=$((SKIP+1)); tui_summary_row "$name" skip "$out" ;;
        *) FAIL=$((FAIL+1)); tui_summary_row "$name" fail "$out" ;;
    esac
}

# ── syntax ───────────────────────────────────────────────────────────────────
t_syntax_scripts() {
    local bad=0 f
    for f in "$REPO_DIR"/install.sh "$REPO_DIR"/installers/*.sh "$REPO_DIR"/bin/* "$REPO_DIR"/tests/*.sh; do
        bash -n "$f" 2>/dev/null || { echo "syntax error: ${f#$REPO_DIR/}"; bad=1; }
    done
    [ "$bad" -eq 0 ] && echo "all scripts parse"
    return $bad
}

t_syntax_executable() {
    local bad=0 f
    for f in "$REPO_DIR"/install.sh "$REPO_DIR"/installers/*.sh "$REPO_DIR"/bin/ai; do
        case "$(basename "$f")" in _*) continue ;; esac   # sourced libs need no +x
        [ -x "$f" ] || { echo "not executable: ${f#$REPO_DIR/}"; bad=1; }
    done
    [ "$bad" -eq 0 ] && echo "entry points executable"
    return $bad
}

# ── module contract ──────────────────────────────────────────────────────────
t_contract_registered() {
    local bad=0 f name
    for f in "$REPO_DIR"/installers/*.sh; do
        name="$(basename "$f" .sh)"
        case "$name" in _*) continue ;; esac
        awk -v n="$name" '/^KNOWN_MODULES=/ && index($0, n) {found=1} END{exit !found}' \
            "$REPO_DIR/install.sh" || { echo "$name not in KNOWN_MODULES"; bad=1; }
    done
    [ "$bad" -eq 0 ] && echo "every module registered"
    return $bad
}

t_contract_uninstall() {
    local bad=0 f name
    for f in "$REPO_DIR"/installers/*.sh; do
        name="$(basename "$f" .sh)"
        case "$name" in _*) continue ;; esac
        awk '/UNINSTALL/{found=1} END{exit !found}' "$f" \
            || { echo "$name ignores UNINSTALL"; bad=1; }
    done
    [ "$bad" -eq 0 ] && echo "every module handles UNINSTALL"
    return $bad
}

t_contract_no_raw_tools() {
    # Modules must go through _lib.sh verbs so dry-run/uninstall work uniformly.
    local bad=0 f
    for f in "$REPO_DIR"/installers/*.sh; do
        case "$(basename "$f")" in _*) continue ;; esac
        awk '
            /^[[:space:]]*#/ {next}
            /(^|[^_[:alnum:]])sudo[[:space:]]/ && !/^[[:space:]]*(run|plan|file_install|unit_|pkg_|link_bin|remove_path|aur_install)/ {
                print FILENAME":"FNR; bad=1
            }
            END{exit bad+0}
        ' "$f" >/dev/null 2>&1 || true
    done
    echo "checked (advisory)"
    return 0
}

# ── the rules that bite (documented in the skill) ────────────────────────────
t_rules_no_awk_exit_in_pipe() {
    local hits
    hits=$(awk '/^[[:space:]]*#/{next} /\|[[:space:]]*awk/ && /exit}/ {print FILENAME":"FNR}' \
           "$REPO_DIR"/install.sh "$REPO_DIR"/installers/*.sh "$REPO_DIR"/bin/ai 2>/dev/null)
    if [ -n "$hits" ]; then echo "awk exit in pipeline (SIGPIPE under pipefail): $hits"; return 1; fi
    echo "no awk-exit pipelines"
}

t_rules_no_grep_c_fallback() {
    local hits
    hits=$(awk '/^[[:space:]]*#/{next} /grep -c/ && /\|\|[[:space:]]*echo/ {print FILENAME":"FNR}' \
           "$REPO_DIR"/install.sh "$REPO_DIR"/installers/*.sh 2>/dev/null)
    if [ -n "$hits" ]; then echo "grep -c || echo yields \"0\\n0\": $hits"; return 1; fi
    echo "no grep -c fallbacks"
}

t_rules_ver_lt() {
    source "$REPO_DIR/installers/_lib.sh" 2>/dev/null
    _ver_lt 7.1.8 7.2  || { echo "7.1.8 < 7.2 failed"; return 1; }
    _ver_lt 7.2   7.2  && { echo "7.2 < 7.2 should be false"; return 1; }
    _ver_lt 7.10  7.2  && { echo "7.10 < 7.2 should be false (numeric, not string)"; return 1; }
    _ver_lt 7.2   7.10 || { echo "7.2 < 7.10 failed"; return 1; }
    echo "version comparison correct"
}

# ── dry-run ──────────────────────────────────────────────────────────────────
t_dryrun_exits_clean() {
    local out rc
    out=$("$REPO_DIR/install.sh" --dry-run --all 2>&1); rc=$?
    [ $rc -eq 0 ] || { echo "exit $rc"; return 1; }
    awk '/plan/{found=1} END{exit !found}' <<<"$out" || { echo "no plan box"; return 1; }
    echo "all modules planned, exit 0"
}

t_dryrun_changes_nothing() {
    # Snapshot the things the installer would touch, then prove they are intact.
    local targets=(/etc/profile.d/rocm.sh /etc/systemd/system/heimdall-daemon.service
                   /etc/systemd/system/ollama.service.d/override.conf
                   "$HOME/.local/bin/ai" /usr/src/amdisp4-8/dkms.conf
                   "$HOME/.config/systemd/user/unsloth-studio.service"
                   "$HOME/.config/systemd/user/playwright-gpu.path" "$HOME/.local/bin/playwright-gpu"
                   /etc/kinn/cpu-cap /etc/systemd/system/kinn-cpu-cap.service /usr/local/bin/kinn-cpu-cap)
    local before after t
    before=$(for t in "${targets[@]}"; do
                 [ -e "$t" ] && printf '%s %s\n' "$t" "$(sha256sum "$t" 2>/dev/null | awk '{print $1}')"
             done)
    "$REPO_DIR/install.sh" --dry-run --all >/dev/null 2>&1
    after=$(for t in "${targets[@]}"; do
                [ -e "$t" ] && printf '%s %s\n' "$t" "$(sha256sum "$t" 2>/dev/null | awk '{print $1}')"
            done)
    [ "$before" = "$after" ] || { echo "dry-run MODIFIED files on disk"; return 1; }
    echo "no tracked target modified"
}

t_dryrun_per_module() {
    local bad=0 f name
    for f in "$REPO_DIR"/installers/*.sh; do
        name="$(basename "$f" .sh)"
        case "$name" in _*) continue ;; esac
        "$REPO_DIR/install.sh" --dry-run --target "$name" >/dev/null 2>&1 \
            || { echo "module failed: $name"; bad=1; }
    done
    [ "$bad" -eq 0 ] && echo "each module dry-runs independently"
    return $bad
}

# ── TUI degradation ──────────────────────────────────────────────────────────
t_tui_no_color() {
    local out
    out=$(NO_COLOR=1 "$REPO_DIR/install.sh" --dry-run --target commands 2>&1)
    if printf '%s' "$out" | grep -q $'\033'; then echo "ANSI emitted under NO_COLOR"; return 1; fi
    echo "NO_COLOR honored"
}

t_tui_non_tty() {
    # Piping stdout must disable animation without hanging or erroring.
    local rc
    "$REPO_DIR/install.sh" --dry-run --target commands 2>/dev/null | cat >/dev/null
    rc=${PIPESTATUS[0]}
    [ "$rc" -eq 0 ] || { echo "exit $rc when piped"; return 1; }
    echo "non-TTY safe"
}

t_tui_help_exits_zero() {
    "$REPO_DIR/install.sh" --help >/dev/null 2>&1 || { echo "install.sh --help nonzero"; return 1; }
    "$REPO_DIR/bin/ai" help    >/dev/null 2>&1 || { echo "ai help nonzero"; return 1; }
    "$REPO_DIR/bin/ai" list    >/dev/null 2>&1 || { echo "ai list nonzero"; return 1; }
    echo "help exits 0"
}

# `ai help` and `ai list` are rendered from the registry, not a heredoc: every
# unit must appear in both, or a service exists that nothing tells you about.
t_ai_registry_rendered() {
    local out u bad=0
    out="$("$REPO_DIR/bin/ai" help 2>&1)$("$REPO_DIR/bin/ai" list 2>&1)"
    for u in lemond unsloth-studio ollama heimdall-helper heimdall-daemon; do
        awk -v u="$u" 'index($0, u) {found=1} END{exit !found}' <<<"$out" \
            || { echo "$u missing from ai help/list"; bad=1; }
    done
    # Group aliases must resolve; `unsloth` is the one people will reach for.
    [ "$("$REPO_DIR/bin/ai" list 2>&1 | awk '/unsloth-studio/{n++} END{print n+0}')" -gt 0 ] \
        || { echo "unsloth alias does not resolve"; bad=1; }
    [ "$bad" -eq 0 ] && echo "every unit rendered in help and list"
    return $bad
}

t_ai_no_color_list() {
    local out
    out=$(NO_COLOR=1 "$REPO_DIR/bin/ai" list 2>&1)
    if printf '%s' "$out" | grep -q $'\033'; then echo "ANSI emitted under NO_COLOR"; return 1; fi
    echo "ai list honors NO_COLOR"
}

# ── publishability ───────────────────────────────────────────────────────────
t_publish_no_internal_hosts() {
    local hits
    hits=$(cd "$REPO_DIR" && git ls-files -z 2>/dev/null | xargs -0 awk '
        /[A-Za-z0-9-]+\.ts\.net/ && !/example/ {print FILENAME":"FNR}' 2>/dev/null)
    if [ -n "$hits" ]; then echo "tailnet hostname in tracked files: $hits"; return 1; fi
    echo "no internal hostnames tracked"
}

t_publish_local_conf_ignored() {
    (cd "$REPO_DIR" && git check-ignore -q local.conf) \
        || { echo "local.conf is NOT gitignored"; return 1; }
    echo "local.conf ignored"
}

t_publish_spdx_headers() {
    local bad=0 f
    for f in "$REPO_DIR"/install.sh "$REPO_DIR"/installers/*.sh "$REPO_DIR"/bin/ai; do
        awk 'NR<=5 && /SPDX-License-Identifier/{found=1} END{exit !found}' "$f" \
            || { echo "missing SPDX: ${f#$REPO_DIR/}"; bad=1; }
    done
    [ "$bad" -eq 0 ] && echo "SPDX headers present"
    return $bad
}

t_publish_vendored_license_intact() {
    local f n=0
    for f in "$REPO_DIR"/files/webcam/isp4/*.c "$REPO_DIR"/files/webcam/isp4/*.h; do
        [ -e "$f" ] || continue
        awk 'NR<=3 && /SPDX-License-Identifier: GPL-2.0/{found=1} END{exit !found}' "$f" \
            || { echo "vendored file lost its GPL tag: $(basename "$f")"; return 1; }
        n=$((n+1))
    done
    [ "$n" -eq 0 ] && { echo "no vendored sources"; return 2; }
    echo "$n vendored files keep GPL-2.0+ tags"
}

# ── run ──────────────────────────────────────────────────────────────────────
tui_box_top 68 "kinn setup — tests"
for fn in $(declare -F | awk '$3 ~ /^t_/ {print $3}' | sort); do
    _t "${fn#t_}" "$fn"
done
tui_box_bot 68
printf '\n  %bpass %d%b   %bfail %d%b   %bskip %d%b\n\n' \
    "$C_GREEN" "$PASS" "$C_RESET" \
    "$([ "$FAIL" -gt 0 ] && printf '%s' "$C_RED" || printf '%s' "$C_DIM")" "$FAIL" "$C_RESET" \
    "$C_DIM" "$SKIP" "$C_RESET"
[ "$FAIL" -eq 0 ]
