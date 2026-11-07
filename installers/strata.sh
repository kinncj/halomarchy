#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# Strata (Niko1221/Strata) — a sparse-MoE engine with a gfx1151 path.
#
# WHY: on Strix Halo a dense model is pinned by memory bandwidth (~256 GB/s
# against a 17.5 GB model) and no engine moves it much. A SPARSE model is the
# only way past that, and time-to-first-token is not bandwidth-bound at all.
# Measured on a ZBook Ultra G1a at 70 W, warm medians, Qwen3.8-Flash-Next
# UD-IQ4_XS against Lemonade's dense 27B on the same machine:
#
#               decode tok/s      prefill tok/s    TTFT
#   8k          49.6  vs 24.6     1,116            7.9s  vs  32.4s
#   32k         55.4  vs 20.8     1,083           31.0s  vs 163.8s
#   131k        47.7  vs  --      1,135          116.0s  vs  cannot run
#
# Prefill is FLAT from 8k to 131k. That, not the decode, is the win: the dense
# path's 163.8s to first token at 32k was the real cost of working locally.
#
# This module installs the service only. The model artifacts are ~96 GB and are
# built locally (a pack, and an MTP draft layer fetched from the BF16
# checkpoint); UNINSTALL=1 removes the unit. See docs/strata.md.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

STRATA_HOME="${STRATA_HOME:-$HOME/strata}"
STRATA_PY="${STRATA_PY:-$STRATA_HOME/venv/bin/python}"
STRATA_PROFILE="${STRATA_PROFILE:-$STRATA_HOME/profiles/flash-next.json}"
STRATA_PORT="${STRATA_PORT:-13306}"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    unit_disable_user strata 2>/dev/null || true
    rm -f "$(user_unit_dir)/strata.service"
    run systemctl --user daemon-reload
    ok "strata unit removed (the engine and model files in $STRATA_HOME are kept)"
    exit 0
fi

# Every piece the unit needs, named so a missing one is obvious rather than a
# systemd start failure five minutes later.
missing=0
check() {   # check <path> <what>
    if [ -e "$1" ]; then plan same "$2"; else plan add "$2 — MISSING: $1"; missing=1; fi
}
check "$STRATA_HOME/engine/strata"        "engine binary (packaged hip-halo build)"
check "$STRATA_HOME/control/strata.py"    "strata-control (the API server)"
check "$STRATA_PY"                        "python with the server's requirements"
check "$STRATA_HOME/pack/index.txt"       "model pack"
check "$STRATA_HOME/mtp-rt/experts.bin"   "MTP draft layer"
check "$STRATA_PROFILE"                   "run config (profile)"

if [ "$missing" -ne 0 ]; then
    warn "Strata is not fully built on this machine — installing the unit anyway,"
    warn "but it will not start until the pieces above exist. docs/strata.md has"
    warn "the build: the release engine + control archives, iq_pack.py for the"
    warn "pack, and mtp_fetch/mtp_pack/mtp_rt for the draft layer."
fi

# Render first, then install: installing the raw template would make the plan
# compare it against the substituted file on disk and report "differs" forever.
rendered="$(mktemp)"
sed -e "s|@STRATA_PY@|${STRATA_PY}|g" \
    -e "s|@STRATA_HOME@|${STRATA_HOME}|g" \
    -e "s|@STRATA_PROFILE@|${STRATA_PROFILE}|g" \
    -e "s|@STRATA_PORT@|${STRATA_PORT}|g" \
    "$(dirname "$0")/../files/systemd/user/strata.service" > "$rendered"
user_unit_install "$rendered" strata.service
rm -f "$rendered"

# DELIBERATELY NOT ENABLED, like lemond: this laptop is a desktop first. The
# engine holds 55 GiB of experts resident, so it starts when you ask for it:
#   ai start strata      (or: halo --backend=strata up)
run systemctl --user daemon-reload
ok "strata.service installed, NOT enabled — start it with 'ai start strata'"
ok "serves an OpenAI + Anthropic API on 127.0.0.1:${STRATA_PORT}"
