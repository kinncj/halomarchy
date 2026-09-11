#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# Lemonade Server (AMD) + ROCm llama.cpp backend.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    unit_disable_user lemond 2>/dev/null || true
    ok "lemond disabled (models kept)"; exit 0
fi

# lemonade-server and lemonade-desktop both ship
# /usr/share/pixmaps/lemonade-app.svg and neither declares a conflict -- an
# Arch packaging bug. That icon is the ONLY overlapping path between the two
# manifests, so a scoped overwrite is safe.
pkg_install_overwrite /usr/share/pixmaps/lemonade-app.svg lemonade-server
unit_enable_user lemond

if have_cmd lemonade && [ "${DRY_RUN:-0}" -ne 1 ]; then
    info "installing llamacpp:rocm backend (~1.7 GB, gfx1151-specific runtime)"
    lemonade backends install llamacpp:rocm || warn "backend install failed; run manually"
fi
ok "lemonade on :13305"
