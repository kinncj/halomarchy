#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# Playwright's Chromium on the GPU (ANGLE/Vulkan/RADV) instead of SwiftShader,
# machine-wide: wraps the cached binaries and keeps them wrapped across
# `playwright install`. See docs/decisions.md §15.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

TOOL="$HOME/.local/bin/playwright-gpu"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    unit_disable_user playwright-gpu.path 2>/dev/null || true
    [ -x "$TOOL" ] && run "$TOOL" unwrap
    remove_path "$(user_unit_dir)/playwright-gpu.path"
    remove_path "$(user_unit_dir)/playwright-gpu.service"
    remove_path "$TOOL"
    ok "playwright browsers restored"; exit 0
fi

link_bin "$REPO_DIR/bin/playwright-gpu" "$TOOL"
user_unit_install "$REPO_DIR/files/systemd/user/playwright-gpu.service" playwright-gpu.service
user_unit_install "$REPO_DIR/files/systemd/user/playwright-gpu.path"    playwright-gpu.path
unit_enable_user playwright-gpu.path

# Wrap what is already downloaded. `status` is read-only, so the plan stays
# truthful under --dry-run; only `wrap` mutates.
n=0
while read -r st bin; do
    n=$((n+1))
    case "$st" in
        wrapped)    plan same   "$bin" "on GPU" ;;
        plain)      plan update "$bin" "SwiftShader -> GPU wrapper" ;;
        broken)     plan update "$bin" "repair interrupted wrap" ;;
        incomplete) plan same   "$bin" "still downloading; path unit will wrap it" ;;
    esac
done < <("$REPO_DIR/bin/playwright-gpu" status)
[ "$n" -eq 0 ] && info "no Playwright browsers cached yet; they get wrapped on first install"
run "$REPO_DIR/bin/playwright-gpu" wrap

if have_cmd vulkaninfo; then
    dev=$(vulkaninfo --summary 2>/dev/null | awk -F= '/deviceName/ && !seen {gsub(/^ +/,"",$2); print $2; seen=1}')
    [ -n "$dev" ] && ok "WebGL will run on: $dev" || warn "vulkaninfo reported no device — wrapper falls back to SwiftShader"
fi
