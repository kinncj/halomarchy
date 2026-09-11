#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# Expose the 'ai' control command on PATH.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    remove_path "$HOME/.local/bin/ai"; exit 0
fi
link_bin "$REPO_DIR/bin/ai" "$HOME/.local/bin/ai"
ok "ai available on PATH"
