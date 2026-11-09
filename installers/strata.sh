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
STRATA_QUANT="${STRATA_QUANT:-UD-IQ4_XS}"
# PINNED on purpose. unsloth re-uploaded UD-IQ4_XS under the same name and the
# same path with Q5_0 expert down-projections, which this engine refuses to
# start on. A quant name is not a version; the revision is. docs/strata.md has
# how that was caught before an 87 GiB download.
STRATA_GGUF_REV="${STRATA_GGUF_REV:-766911a6b7369840a91dbcd95f9f997acaab6cd6}"
STRATA_GGUF_DIR="${STRATA_GGUF_DIR:-${HF_HOME:-$HOME/.cache/huggingface}/hub/models--unsloth--Qwen3.8-Flash-Next-GGUF/snapshots/$STRATA_GGUF_REV/$STRATA_QUANT}"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    unit_disable_user strata 2>/dev/null || true
    rm -f "$(user_unit_dir)/strata.service"
    run systemctl --user daemon-reload
    ok "strata unit removed (the engine and model files in $STRATA_HOME are kept)"
    exit 0
fi

# The run config is not a preference file: --mmap-experts and --ple-io direct
# are the difference between running and an OOM kill on 128 GB, and
# reasoning_effort is the fuse that stops a reasoning model returning an empty
# answer to any client that does not send one. Hand-rolling it is how a rebuilt
# machine loses all three, so it is rendered from the measured template.
# NEVER overwritten: an existing profile may be tuned past this one.
install_profile() {
    local native ple rendered
    if [ -e "$STRATA_PROFILE" ]; then
        plan same "run config (profile) — kept as it is"
        return 0
    fi
    # Shard 1 carries the native weights, shard 2 the PLE table. Globbed rather
    # than spelled out: the shard count changed between re-uploads.
    native=$(find "$STRATA_GGUF_DIR" -maxdepth 1 -name '*-00001-of-*.gguf' 2>/dev/null | sort | head -1)
    ple=$(find "$STRATA_GGUF_DIR" -maxdepth 1 -name '*-00002-of-*.gguf' 2>/dev/null | sort | head -1)
    if [ -z "$native" ] || [ -z "$ple" ]; then
        plan add "run config (profile) — MISSING: no $STRATA_QUANT shards in $STRATA_GGUF_DIR"
        warn "the model is not downloaded at the pinned revision, so the profile"
        warn "cannot be rendered. docs/strata.md has the hf download command; then"
        warn "re-run this module, or copy files/strata/flash-next.json.in by hand."
        missing=1
        return 0
    fi
    plan add "$STRATA_PROFILE" "rendered from the measured template"
    [ "${DRY_RUN:-0}" -eq 1 ] && { info "would: render $STRATA_PROFILE"; return 0; }
    rendered="$(mktemp)"
    sed -e "s|@STRATA_HOME@|${STRATA_HOME}|g" \
        -e "s|@STRATA_NATIVE_GGUF@|${native}|g" \
        -e "s|@STRATA_PLE_GGUF@|${ple}|g" \
        "$(dirname "$0")/../files/strata/flash-next.json.in" > "$rendered"
    install -Dm644 "$rendered" "$STRATA_PROFILE"
    rm -f "$rendered"
    return 0
}

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
install_profile

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
