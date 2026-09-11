#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# Ollama (ROCm) with tuning drop-in.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    unit_disable ollama 2>/dev/null || true
    run sudo rm -f /etc/systemd/system/ollama.service.d/override.conf
    ok "ollama service removed (models kept)"; exit 0
fi

pkg_install ollama-rocm
unit_install "$REPO_DIR/files/systemd/system/ollama.service.d/override.conf" \
             /etc/systemd/system/ollama.service.d/override.conf
unit_reload
unit_enable ollama
ok "ollama on :11434"
