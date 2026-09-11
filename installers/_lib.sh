#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# Shared helpers for per-module installers. Sourced, not executed.
#
# Expects these env vars from install.sh:
#   REPO_DIR, DRY_RUN, UNINSTALL, HEIMDALL_HUB, KINN_VENV

_TUI="$(dirname "${BASH_SOURCE[0]}")/_tui.sh"
# shellcheck source=installers/_tui.sh
source "$_TUI"

# Per-module scripts render inside the section box, so map the plain helpers
# to the indented variants.
ok()   { iok   "$@"; }
warn() { iwarn "$@"; }
err()  { ierr  "$@"; }
info() { iinfo "$@"; }

# run <cmd...>: execute, or describe in dry-run
run() {
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
        info "would: $*"
    else
        "$@"
    fi
}

# ── plan accounting ──────────────────────────────────────────────────────────
# Every verb below reports its intent as a plan row and tallies it, so
# --dry-run answers: what is already correct, what gets added, what CHANGES.
# Modules run as separate processes, so the tally is appended to $PLAN_FILE
# and rendered by install.sh at the end.
plan() {   # plan <state> <item> [detail]
    tui_plan_row "$1" "$2" "${3:-}"
    [ -n "${PLAN_FILE:-}" ] && printf '%s\n' "$1" >> "$PLAN_FILE"
    return 0
}

# Does the target differ from what we would install?
_state_file() {   # _state_file <src> <dst>
    [ -e "$2" ] || { echo new; return; }
    if cmp -s "$1" "$2" 2>/dev/null; then echo same; else echo update; fi
}

_state_link() {   # _state_link <target> <linkpath>
    [ -e "$2" ] || [ -L "$2" ] || { echo new; return; }
    if [ "$(readlink -f "$2" 2>/dev/null)" = "$(readlink -f "$1" 2>/dev/null)" ]; then
        echo same
    else
        echo update
    fi
}

_pkg_version()      { pacman -Q  "$1" 2>/dev/null | awk '{print $2}'; }
# No `exit` in awk — see gpu_target(); SIGPIPE under pipefail would fail this
# command substitution and kill the module via set -e.
_pkg_repo_version() { pacman -Si "$1" 2>/dev/null | awk -F': ' '/^Version/ && !seen {print $2; seen=1}'; }

# ── pacman ───────────────────────────────────────────────────────────────────
pkg_installed() { pacman -Q "$1" >/dev/null 2>&1; }

# pkg_install <pkg>...  — only touches pacman for packages actually missing
pkg_install() {
    local missing=() p have want
    for p in "$@"; do
        if pkg_installed "$p"; then
            have="$(_pkg_version "$p")"; want="$(_pkg_repo_version "$p")"
            if [ -n "$want" ] && [ "$have" != "$want" ]; then
                plan update "$p" "$have -> $want"; missing+=("$p")
            else
                plan same "$p" "$have"
            fi
        else
            plan new "$p" "$(_pkg_repo_version "$p")"; missing+=("$p")
        fi
    done
    [ "${#missing[@]}" -eq 0 ] && return 0
    run sudo pacman -S --needed --noconfirm "${missing[@]}"
}

# pkg_install_overwrite <path> <pkg>... — for packages that collide on a file
pkg_install_overwrite() {
    local path="$1"; shift
    if pkg_installed "$1"; then plan same "$1" "$(_pkg_version "$1")"; return 0; fi
    plan new "$1" "$(_pkg_repo_version "$1") (--overwrite $path)"
    run sudo pacman -S --needed --noconfirm --overwrite "$path" "$@"
}

# aur_install <pkg>... — AUR packages, via yay. Same plan semantics as pkg_install.
aur_install() {
    local missing=() p
    for p in "$@"; do
        if pkg_installed "$p"; then plan same "$p" "$(_pkg_version "$p") (aur)"
        else plan new "$p" "aur"; missing+=("$p"); fi
    done
    [ "${#missing[@]}" -eq 0 ] && return 0
    have_cmd yay || { err "yay required for AUR packages: ${missing[*]}"; return 1; }
    run yay -S --needed --noconfirm "${missing[@]}"
}

# _ver_lt <a> <b> — true when version a < b. No `head -1`: closing the pipe
# early SIGPIPEs sort under pipefail.
_ver_lt() {
    [ "$1" = "$2" ] && return 1
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | awk 'NR==1')" = "$1" ]
}

# ── systemd / files ──────────────────────────────────────────────────────────
unit_install() { file_install "$1" "$2" 644; }
file_install() {
    local st; st="$(_state_file "$1" "$2")"
    plan "$st" "$2" "$([ "$st" = update ] && echo 'content differs' || true)"
    [ "$st" = same ] && return 0
    run sudo install -Dm"${3:-644}" "$1" "$2"
}
unit_reload()     { run sudo systemctl daemon-reload; run systemctl --user daemon-reload; }
unit_enable() {
    local en ac; en=$(systemctl is-enabled "$1" 2>/dev/null || true)
    ac=$(systemctl is-active "$1" 2>/dev/null || true)
    if [ "$en" = enabled ] && [ "$ac" = active ]; then plan same "$1" "enabled/active"; return 0; fi
    plan update "$1" "${en:-?}/${ac:-?} -> enabled/active"
    run sudo systemctl enable --now "$1"
}
unit_disable()    { info "disable $1"; run sudo systemctl disable --now "$1"; }
unit_enable_user() {
    local en ac; en=$(systemctl --user is-enabled "$1" 2>/dev/null || true)
    ac=$(systemctl --user is-active "$1" 2>/dev/null || true)
    if [ "$en" = enabled ] && [ "$ac" = active ]; then plan same "$1" "enabled/active (user)"; return 0; fi
    plan update "$1" "${en:-?}/${ac:-?} -> enabled/active (user)"
    run systemctl --user enable --now "$1"
}
unit_disable_user(){ info "disable --user $1"; run systemctl --user disable --now "$1"; }

# User units live under $HOME and need no root, so they get their own verbs:
# routing them through file_install/unit_install would prompt for a password to
# write a file you already own.
user_unit_dir() { echo "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; }
user_unit_install() {   # user_unit_install <src> <unit-name>
    local dst st; dst="$(user_unit_dir)/$2"
    st="$(_state_file "$1" "$dst")"
    plan "$st" "$dst" "$([ "$st" = update ] && echo 'content differs' || true)"
    [ "$st" = same ] && return 0
    run install -Dm644 "$1" "$dst"
    run systemctl --user daemon-reload
}
link_bin() {
    local st; st="$(_state_link "$1" "$2")"
    plan "$st" "$2" "-> $1"
    [ "$st" = same ] && return 0
    run mkdir -p "$(dirname "$2")"
    run ln -sf "$1" "$2"
}
remove_path() {
    if [ -e "$1" ] || [ -L "$1" ]; then plan remove "$1"; run rm -rf "$1"
    else plan same "$1" "absent"; fi
}

# ── vendored-source fetching ─────────────────────────────────────────────────
# Third-party sources are NOT committed: they are fetched from their upstream at
# a pinned ref and verified against a checksum manifest. Keeps this repo MIT-only
# and avoids redistributing other projects' code.
#
# fetch_verified <dest-dir> <manifest> <base-url> <ref>
fetch_verified() {
    local dest="$1" manifest="$2" base="$3" ref="$4"
    have_cmd curl || { err "curl required to fetch sources"; return 1; }

    mkdir -p "$dest"
    if (cd "$dest" && sha256sum --quiet -c "$manifest" 2>/dev/null); then
        plan same "$dest" "$(awk 'END{print NR}' "$manifest") files verified @ $ref"
        return 0
    fi

    plan new "$dest" "fetch $(awk 'END{print NR}' "$manifest") files @ $ref"
    [ "${DRY_RUN:-0}" -eq 1 ] && return 0

    local f
    while read -r _ f; do
        [ -n "$f" ] || continue
        curl -fsSL --max-time 60 "${base}/${f}?h=${ref}" -o "$dest/$f" \
            || { err "fetch failed: $f"; return 1; }
    done < "$manifest"

    if (cd "$dest" && sha256sum --quiet -c "$manifest"); then
        ok "fetched and verified $(awk 'END{print NR}' "$manifest") files @ $ref"
    else
        err "checksum mismatch after fetch — refusing to use these sources"
        return 1
    fi
}

# ── guards ───────────────────────────────────────────────────────────────────
have_cmd()     { command -v "$1" >/dev/null 2>&1; }
require_arch() { [ -f /etc/arch-release ] || { err "not an Arch-based system"; return 1; }; }

gpu_target() {
    local rocminfo_bin
    if have_cmd rocminfo; then rocminfo_bin=rocminfo
    elif [ -x /opt/rocm/bin/rocminfo ]; then rocminfo_bin=/opt/rocm/bin/rocminfo
    else return 0; fi
    # No `exit` in awk: it closes the pipe early, and under `set -o pipefail`
    # the resulting SIGPIPE on rocminfo fails the whole command substitution.
    "$rocminfo_bin" 2>/dev/null | awk -F: '/Name:.*gfx/ && !seen {gsub(/ /,"",$2); print $2; seen=1}'
}

# Everything in this repo is pinned to gfx1151; say so loudly if it isn't.
assert_gfx1151() {
    local t; t="$(gpu_target)"
    if [ -z "$t" ]; then info "GPU target not detectable yet (rocminfo absent)"; return 0; fi
    if [ "$t" = gfx1151 ]; then ok "GPU target $t"
    else warn "GPU target is '$t', not gfx1151 — pins here target Strix Halo"; fi
}
