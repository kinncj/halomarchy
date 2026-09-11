#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# Unsloth venv, pinned for gfx1151.
#
# Upstream's documented install is BROKEN on Strix Halo: it pins torch==2.8.0
# from the rocm6.4 index, whose arch list runs gfx1102 -> gfx1200 with NO
# gfx1151. Every tensor op dies with "HIP error: invalid device function".
# The rocm7.2 wheels do include gfx1151. See docs/decisions.md.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

VENV="${KINN_VENV:-$HOME/ai/unsloth}"
ROCM_INDEX="https://download.pytorch.org/whl/rocm7.2"
BNB_WHL="https://github.com/bitsandbytes-foundation/bitsandbytes/releases/download/continuous-release_main/bitsandbytes-1.33.7.preview-py3-none-manylinux_2_24_x86_64.whl"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    unit_disable_user unsloth-studio 2>/dev/null || true
    remove_path "$(user_unit_dir)/unsloth-studio.service"
    remove_path "$HOME/.local/bin/unsloth-venv"
    remove_path "$VENV"
    exit 0
fi

have_cmd uv || { err "uv missing — run the packages module first"; exit 1; }
_pip() { run "$VENV/bin/pip" "$@"; }

# ── Unsloth Studio service ───────────────────────────────────────────────────
# The venv is a library, not a daemon — `ai start unsloth` has nothing to start
# there. Unsloth *Studio* is the daemon: it serves the UI on :8888 and
# supervises llama-server. So the unit wraps Studio, and `ai` drives it next to
# lemond and ollama.
#
# Studio installs itself (its own installer, into ~/.unsloth) and owns
# ~/.local/bin/unsloth; this repo only wraps it. If it is absent we say so and
# leave the unit uninstalled rather than shipping a unit that cannot start.
#
# Deliberately a path, not `command -v unsloth`: the venv ships a binary of the
# same name, so a PATH lookup resolves to whichever comes first — and inside an
# activated venv that is the wrong one. Override with KINN_STUDIO_BIN if your
# Studio lives somewhere else; the unit is rendered against that path.
STUDIO_BIN="${KINN_STUDIO_BIN:-$HOME/.local/bin/unsloth}"
studio_service() {
    if [ ! -e "$STUDIO_BIN" ]; then
        warn "Unsloth Studio not installed — skipping the unsloth-studio unit"
        info "install it from https://docs.unsloth.ai/ then re-run this module"
        return 0
    fi
    # The unit is a template (@STUDIO_BIN@). Render FIRST, then install the
    # rendered file -- installing the raw template would make the plan compare
    # it against the substituted file on disk and report "differs" forever.
    local rendered; rendered="$(mktemp)"
    sed -e "s|@STUDIO_BIN@|${STUDIO_BIN}|g" \
        "$REPO_DIR/files/systemd/user/unsloth-studio.service" > "$rendered"
    user_unit_install "$rendered" unsloth-studio.service
    rm -f "$rendered"
    unit_enable_user unsloth-studio
}

# The pip work is expensive and not meaningfully previewable command-by-command,
# so in dry-run report the resulting state and stop rather than claim success
# for steps that never ran.
if [ "${DRY_RUN:-0}" -eq 1 ]; then
    if [ -x "$VENV/bin/python" ]; then
        cur=$("$VENV/bin/python" -c 'import torch;print(torch.__version__)' 2>/dev/null || echo "none")
        if [ "$cur" = "2.12.1+rocm7.2" ]; then
            plan same "$VENV" "torch $cur"
        else
            plan update "$VENV" "torch $cur -> 2.12.1+rocm7.2"
        fi
    else
        plan new "$VENV" "python 3.12 + torch 2.12.1+rocm7.2"
    fi
    plan_link_state=$(_state_link "$VENV/bin/unsloth" "$HOME/.local/bin/unsloth-venv")
    plan "$plan_link_state" "$HOME/.local/bin/unsloth-venv" "-> $VENV/bin/unsloth"
    studio_service
    exit 0
fi

if [ ! -x "$VENV/bin/python" ]; then
    info "creating venv at $VENV (python 3.12; unsloth[amd] needs 3.11-3.13)"
    run uv venv --python 3.12 "$VENV"
fi
run uv pip install --python "$VENV/bin/python" pip

# torch 2.12.1, NOT 2.13 -- unsloth_zoo requires torch<2.13.0.
# triton-rocm 3.7.1 is torch 2.12's own pin; it needs hipDrvLaunchKernelEx,
# a symbol absent from the rocm6.4 runtime but present in 7.2.
tui_spinner_start "torch 2.12.1+rocm7.2 + triton-rocm 3.7.1"
if _pip install --no-cache-dir "torch==2.12.1+rocm7.2" "triton-rocm==3.7.1" \
      torchvision torchaudio --index-url "$ROCM_INDEX" \
      --extra-index-url https://pypi.org/simple >/dev/null 2>&1; then
    tui_spinner_stop ok "torch 2.12.1+rocm7.2"
else
    tui_spinner_stop fail "torch install failed"; exit 1
fi

# bitsandbytes <=0.49.2 has a 4-bit decode NaN bug on every AMD GPU.
tui_spinner_start "bitsandbytes (ROCm preview)"
if _pip install --force-reinstall --no-cache-dir --no-deps "$BNB_WHL" >/dev/null 2>&1; then
    tui_spinner_stop ok "bitsandbytes"
else
    tui_spinner_stop fail "bitsandbytes failed"; exit 1
fi

tui_spinner_start "unsloth[amd] (from git)"
if _pip install "unsloth[amd] @ git+https://github.com/unslothai/unsloth" >/dev/null 2>&1; then
    tui_spinner_stop ok "unsloth"
else
    tui_spinner_stop fail "unsloth failed"; exit 1
fi

# unsloth[amd] drags in plain `triton`, which shadows triton-rocm: both own
# site-packages/triton/. Remove both, then reinstall only the matched one.
tui_spinner_start "repairing triton shadowing"
_pip uninstall -y triton pytorch-triton-rocm >/dev/null 2>&1 || true
run rm -rf "$VENV/lib/python3.12/site-packages/triton"
if _pip install --no-cache-dir "triton-rocm==3.7.1" --index-url "$ROCM_INDEX" \
      --extra-index-url https://pypi.org/simple >/dev/null 2>&1; then
    tui_spinner_stop ok "triton-rocm 3.7.1 (single copy)"
else
    tui_spinner_stop fail "triton repair failed"; exit 1
fi

# xformers/torchao are deliberately absent: no rocm7.2 wheels exist and the
# rocm6.4 builds hard-pin torch 2.8.0. torch SDPA is the fallback.

# Unsloth Studio (curl install.sh) also owns ~/.local/bin/unsloth and points it
# at ~/.unsloth/studio/. Different tool, same name -- link the venv's CLI under
# a distinct name so both survive.
link_bin "$VENV/bin/unsloth" "$HOME/.local/bin/unsloth-venv"

if [ "${DRY_RUN:-0}" -ne 1 ]; then
    info "verifying gfx1151 support"
    PATH=/opt/rocm/bin:$PATH "$VENV/bin/python" - <<'PYCHECK' || { err "verification failed"; exit 1; }
import sys, torch
arch = torch.cuda.get_arch_list()
if 'gfx1151' not in ' '.join(arch):
    sys.exit(f"gfx1151 MISSING from wheel arch list: {arch}")
print(f"    torch {torch.__version__} | gfx1151 present | {torch.cuda.get_device_name(0)}")
PYCHECK
    ok "venv verified for gfx1151"
fi

studio_service
