#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# Peak-power guard: cap the CPU clock (persisting across boot and resume) and
# keep power-profiles-daemon off `performance`. The ZBook Ultra G1a powers off
# instantly under all-core boost bursts; see docs/decisions.md §16.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

TOOL=/usr/local/bin/kinn-cpu-cap
CONF=/etc/kinn/cpu-cap
UNIT=/etc/systemd/system/kinn-cpu-cap.service
HOOK=/usr/lib/systemd/system-sleep/kinn-cpu-cap
CAP_MHZ="${KINN_CPU_CAP_MHZ:-3000}"
PROFILE="${KINN_POWER_PROFILE:-balanced}"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    systemctl is-enabled kinn-cpu-cap.service >/dev/null 2>&1 && unit_disable kinn-cpu-cap.service
    [ -x "$TOOL" ] && run sudo "$TOOL" clear
    for f in "$CONF" "$UNIT" "$HOOK" "$TOOL"; do
        if [ -e "$f" ]; then plan remove "$f"; run sudo rm -f "$f"; else plan same "$f" "absent"; fi
    done
    unit_reload
    ok "CPU cap removed; clocks back to hardware maximum"; exit 0
fi

file_install "$REPO_DIR/bin/kinn-cpu-cap"                        "$TOOL" 755
file_install "$REPO_DIR/files/systemd/system-sleep/kinn-cpu-cap" "$HOOK" 755
unit_install "$REPO_DIR/files/systemd/system/kinn-cpu-cap.service" "$UNIT"

# The cap itself is one number in /etc/kinn/cpu-cap, set from local.conf so
# raising it is a config change, not a code change.
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$CAP_MHZ" > "$tmp"
file_install "$tmp" "$CONF" 644

unit_reload
unit_enable kinn-cpu-cap.service        # --now applies the cap immediately

# power-profiles-daemon remembers the last profile across boots, so setting it
# once is persistent until someone picks `performance` from the menu again.
if have_cmd powerprofilesctl; then
    cur="$(powerprofilesctl get 2>/dev/null || true)"
    if [ "$cur" = "$PROFILE" ]; then plan same "power profile" "$PROFILE"
    else plan update "power profile" "${cur:-?} -> $PROFILE"; run powerprofilesctl set "$PROFILE"; fi
fi

if [ -x "$TOOL" ]; then ok "$("$TOOL" status)"; else info "cap tool not installed yet (dry-run?)"; fi
