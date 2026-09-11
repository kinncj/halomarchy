#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# Vulkan/RADV + 32-bit stack for Proton, plus gamemode and mangohud.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

[ "${UNINSTALL:-0}" -eq 1 ] && { info "gaming packages are left installed"; exit 0; }

# lib32-* is the half people forget; Proton needs the 32-bit ICD loader.
pkg_install vulkan-radeon lib32-vulkan-radeon vulkan-icd-loader \
            lib32-vulkan-icd-loader vulkan-tools gamemode lib32-gamemode \
            mangohud lib32-mangohud steam

if have_cmd vulkaninfo; then
    dev=$(vulkaninfo --summary 2>/dev/null | awk -F= '/deviceName/ && !seen {gsub(/^ +/,"",$2); print $2; seen=1}')
    [ -n "$dev" ] && ok "Vulkan: $dev" || warn "vulkaninfo reported no device"
else
    info "vulkaninfo unavailable (dry-run?)"
fi
