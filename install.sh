#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
#
# Provision this machine's AI + gaming stack (Strix Halo / gfx1151).
#
# Modules (run in this order unless --target is passed):
#   packages        ROCm toolchain, PyTorch, JDK, uv
#   environment     /etc/profile.d/rocm.sh + PATH shims
#   webcam          AMD ISP4 driver (DKMS below kernel 7.2, in-tree at/above)
#   gaming          Vulkan/RADV, lib32 stack, gamemode, mangohud, Steam
#   playwright      Playwright Chromium on the GPU (ANGLE/Vulkan), machine-wide
#   power           CPU clock cap + balanced profile (no more instant power-offs)
#   heimdall        metrics daemon + privileged helper
#   ollama          Ollama (ROCm) on :11434
#   lemonade        Lemonade Server on :13305
#   unsloth         pinned venv for fine-tuning + Studio service
#   commands        expose `ai` on PATH
#
# Usage:
#   ./install.sh                     # interactive, all modules
#   ./install.sh --all               # non-interactive, all modules
#   ./install.sh --target ollama     # one module (repeatable)
#   ./install.sh --dry-run           # print what would happen, change nothing
#   ./install.sh --uninstall         # tear down services and wiring
#   ./install.sh --no-animation      # skip the animated logo / spinners
#   ./install.sh --quiet             # suppress logo entirely

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── flags ─────────────────────────────────────────────────────────────────────
DRY_RUN=0
UNINSTALL=0
ALL=0
QUIET=0
TARGETS=()

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)      DRY_RUN=1 ;;
        --uninstall)    UNINSTALL=1 ;;
        --all)          ALL=1 ;;
        --quiet|-q)     QUIET=1 ;;
        --no-animation) export TUI_NO_ANIM=1 ;;
        --target)       shift; TARGETS+=("$1") ;;
        --target=*)     TARGETS+=("${1#--target=}") ;;
        -h|--help)      usage ;;
        *)              printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

# Machine-specific values (hub address, etc.) live in an untracked local.conf
# so this repo can be published without leaking internal hostnames.
# shellcheck source=/dev/null
[ -f "${REPO_DIR}/local.conf" ] && . "${REPO_DIR}/local.conf"

# ── load TUI helpers ──────────────────────────────────────────────────────────
# shellcheck source=installers/_tui.sh
source "${REPO_DIR}/installers/_tui.sh"

[ -f /etc/arch-release ] || { err "not an Arch-based system"; exit 1; }

# ── intro ─────────────────────────────────────────────────────────────────────
[ "$QUIET" -ne 1 ] && tui_logo

action="install"
[ "$UNINSTALL" -eq 1 ] && action="uninstall"
[ "$DRY_RUN" -eq 1 ]   && action="${action} (dry-run)"

log "${C_BOLD}kinn setup${C_RESET} ${C_DIM}— ${action}${C_RESET}"
log "${C_DIM}repo:${C_RESET} ${C_CYAN}$REPO_DIR${C_RESET}"

gpu=$( { command -v rocminfo >/dev/null 2>&1 && rocminfo; } 2>/dev/null \
       || /opt/rocm/bin/rocminfo 2>/dev/null || true )
gpu=$(printf '%s' "$gpu" | awk -F: '/Name:.*gfx/ && !seen {gsub(/ /,"",$2); print $2; seen=1}')
[ -n "$gpu" ] && log "${C_DIM}gpu:${C_RESET}  ${C_CYAN}${gpu}${C_RESET}"

# ── module order is load-bearing ──────────────────────────────────────────────
# environment must precede unsloth (bitsandbytes needs rocminfo on PATH);
# gaming must precede playwright (its Chromium wrapper needs the RADV ICD);
# packages must precede everything (installs uv and the ROCm toolchain).
KNOWN_MODULES=(packages environment webcam gaming playwright power heimdall ollama lemonade unsloth commands)

if [ "${#TARGETS[@]}" -eq 0 ]; then
    log ""
    log "${C_DIM}modules:${C_RESET} ${C_CYAN}${KNOWN_MODULES[*]}${C_RESET}"
    if [ "$ALL" -eq 1 ] || [ ! -t 0 ]; then
        TARGETS=("${KNOWN_MODULES[@]}")
    else
        printf '%b? %brun all modules? [Y/n] ' "$C_BOLD" "$C_RESET"
        read -r reply
        case "${reply:-y}" in
            [Yy]*|"") TARGETS=("${KNOWN_MODULES[@]}") ;;
            *)        err "aborted"; exit 1 ;;
        esac
    fi
fi

# On uninstall, tear down in reverse dependency order.
if [ "$UNINSTALL" -eq 1 ]; then
    rev=(); for (( i=${#TARGETS[@]}-1; i>=0; i-- )); do rev+=("${TARGETS[$i]}"); done
    TARGETS=("${rev[@]}")
fi

# ── dispatch ──────────────────────────────────────────────────────────────────
PLAN_FILE="$(mktemp)"; trap 'rm -f "$PLAN_FILE"' EXIT
export REPO_DIR DRY_RUN UNINSTALL TUI_NO_ANIM PLAN_FILE
export HEIMDALL_HUB="${HEIMDALL_HUB:-}"
export KINN_VENV="${KINN_VENV:-$HOME/ai/unsloth}"
export KINN_STUDIO_BIN="${KINN_STUDIO_BIN:-$HOME/.local/bin/unsloth}"
export KINN_CPU_CAP_MHZ="${KINN_CPU_CAP_MHZ:-3000}"
export KINN_POWER_PROFILE="${KINN_POWER_PROFILE:-balanced}"

exit_code=0
declare -a SUMMARY_TOOL SUMMARY_STATUS SUMMARY_DETAIL

for mod in "${TARGETS[@]}"; do
    installer="${REPO_DIR}/installers/${mod}.sh"
    tui_section "${mod}" 60
    if [ ! -x "$installer" ]; then
        tui_box_bot 60
        ierr "no installer for '${mod}' (expected ${installer})"
        SUMMARY_TOOL+=("$mod"); SUMMARY_STATUS+=("fail"); SUMMARY_DETAIL+=("missing installer")
        exit_code=1
        continue
    fi
    if bash "$installer"; then
        tui_box_bot 60
        SUMMARY_TOOL+=("$mod"); SUMMARY_STATUS+=("ok"); SUMMARY_DETAIL+=("$action")
    else
        tui_box_bot 60
        ierr "${mod} installer failed"
        SUMMARY_TOOL+=("$mod"); SUMMARY_STATUS+=("fail"); SUMMARY_DETAIL+=("returned non-zero")
        exit_code=1
    fi
done

# ── plan tally ────────────────────────────────────────────────────────────────
# Answers the question --dry-run exists for: what actually changes?
# awk, not `grep -c || echo 0`: grep exits 1 on zero matches, so the fallback
# fires *in addition to* grep's own "0" and the variable becomes "0\n0".
_tally() { awk -v k="$1" '$0==k{n++} END{print n+0}' "$PLAN_FILE" 2>/dev/null || echo 0; }
n_new=$(_tally new); n_upd=$(_tally update)
n_same=$(_tally same); n_rm=$(_tally remove)

log ""
tui_box_top 60 "plan"
tui_plan_row new    "to install" "$n_new"
tui_plan_row update "to change"  "$n_upd"
tui_plan_row remove "to remove"  "$n_rm"
tui_plan_row same   "unchanged"  "$n_same"
tui_box_bot 60
if [ "$DRY_RUN" -eq 1 ]; then
    log ""
    if [ "$((n_new + n_upd + n_rm))" -eq 0 ]; then
        ok "nothing to do — system already matches this repo"
    else
        info "dry-run: nothing was written. Re-run without --dry-run to apply."
    fi
fi

# ── summary ───────────────────────────────────────────────────────────────────
log ""
tui_box_top 60 "summary"
i=0
while [ "$i" -lt "${#SUMMARY_TOOL[@]}" ]; do
    tui_summary_row "${SUMMARY_TOOL[$i]}" "${SUMMARY_STATUS[$i]}" "${SUMMARY_DETAIL[$i]}"
    i=$((i+1))
done
tui_box_bot 60

if [ "$exit_code" -eq 0 ] && [ "$UNINSTALL" -ne 1 ]; then
    log ""
    info "log out and back in for PATH and heimdall group membership"
    info "${C_CYAN}ai status${C_RESET}   check services"
    info "${C_CYAN}ai help${C_RESET}     service commands"
fi

exit $exit_code
