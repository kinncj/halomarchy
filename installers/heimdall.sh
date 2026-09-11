#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# Heimdall metrics daemon + privileged helper.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    unit_disable heimdall-daemon 2>/dev/null || true
    unit_disable heimdall-helper 2>/dev/null || true
    run sudo rm -f /etc/systemd/system/heimdall-daemon.service /etc/systemd/system/heimdall-helper.service
    # Packages are left installed; removing them is the user's call.
    ok "heimdall units removed"; exit 0
fi

# Both come from the AUR. The helper is what unlocks power.cpu (RAPL is
# 0400 root:root) and the package pair must match in version.
aur_install heimdall-daemon-bin heimdall-helper-bin

# The helper runs as root and the daemon as you; a shared group gates the 0660
# socket in /run/heimdall so the network-facing daemon stays unprivileged.
run sudo groupadd -f heimdall
run sudo usermod -aG heimdall "$USER"

if [ -z "${HEIMDALL_HUB:-}" ]; then
    warn "HEIMDALL_HUB unset — set it in local.conf or the environment"
    info "skipping heimdall (nothing to stream to)"
    exit 0
fi

unit_install "$REPO_DIR/files/systemd/system/heimdall-helper.service" /etc/systemd/system/heimdall-helper.service

# The daemon unit is a template (@HEIMDALL_HUB@, @USER@). Render it to a temp
# file FIRST, then install that -- otherwise the plan would compare the raw
# template against the substituted file on disk and report "differs" forever.
rendered="$(mktemp)"; trap 'rm -f "$rendered"' EXIT
sed -e "s|@HEIMDALL_HUB@|${HEIMDALL_HUB}|g" -e "s|@USER@|${USER}|g" \
    "$REPO_DIR/files/systemd/system/heimdall-daemon.service" > "$rendered"
unit_install "$rendered" /etc/systemd/system/heimdall-daemon.service

unit_reload
unit_enable heimdall-helper
unit_enable heimdall-daemon
ok "heimdall streaming to $HEIMDALL_HUB"
