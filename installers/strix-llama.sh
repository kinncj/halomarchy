#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# halo-box/strix-llama.cpp — a gfx1151 llama.cpp fork with speculative prefill.
#
# Why: on Strix Halo, decode is pinned by memory bandwidth (~256 GB/s against a
# 17.5 GB dense model) and no engine moves it much. Time-to-first-token is not
# pinned by anything. Measured on a ZBook Ultra G1a at 70 W, 32k context:
#
#     builtin llama.cpp   TTFT 163.8s   decode 20.75 tok/s
#     this + p=0.30       TTFT  49.6s   decode 21.1  tok/s   3.3x
#
# It is LOSSY: a small draft model scores the prompt and low-scoring chunks
# never reach the big model. Verify retrieval before trusting a ratio -- at
# p=0.15 the same setup measured 3/5 needles, losing the MIDDLE of the document
# while keeping the beginning and end. Speed that drops the line you needed is
# not speed.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

PREFIX="${STRIX_LLAMA_PREFIX:-$HOME/.local/share/strix-llama}"
DRAFT_REPO="${STRIX_LLAMA_DRAFT_REPO:-unsloth/Qwen3.5-2B-GGUF}"
DRAFT_GLOB="${STRIX_LLAMA_DRAFT_GLOB:-*UD-Q4_K_XL*}"
JOBS="${STRIX_LLAMA_JOBS:-8}"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    rm -rf "$PREFIX"
    ok "strix-llama removed (point your server back at its builtin engine)"
    exit 0
fi

for c in git cmake glslc; do
    have_cmd "$c" || { warn "missing $c -- install it and re-run"; exit 1; }
done

# Three things that are not obvious and each cost an hour to find:
#
# 1. Arch ships the Vulkan loader but not always the headers, and llama.cpp's
#    Vulkan backend additionally wants SPIRV-Headers with a CMake config. Both
#    are header-only, so vendor them rather than requiring root.
# 2. The built llama-server is a thin wrapper whose RPATH points into the build
#    tree. Copy it anywhere and it still resolves -- until something launches it
#    with a clean environment, and then it exits 127. The install must be
#    self-contained.
# 3. Lemonade's llamacpp.*_bin wants the PATH TO THE BINARY, not the directory.
#    Given a directory it reports "Failed to execute: <dir>".
info "vendoring Vulkan and SPIRV headers (no root needed)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
run git clone -q --depth 1 https://github.com/KhronosGroup/Vulkan-Headers.git "$work/vk"
run git clone -q --depth 1 https://github.com/KhronosGroup/SPIRV-Headers.git "$work/spv"
run cmake -S "$work/spv" -B "$work/spv/b" -DCMAKE_INSTALL_PREFIX="$work/prefix" >/dev/null
run cmake --install "$work/spv/b" >/dev/null

info "cloning strix-llama.cpp"
run git clone -q --depth 1 https://github.com/halo-box/strix-llama.cpp.git "$work/src"

# -j8 rather than all cores: this is a sustained all-core load, which is the
# documented trigger for the ZBook Ultra G1a's no-log power-off. See docs.
info "building for gfx1151 (Vulkan, -j${JOBS}; this is the power-hungry step)"
run cmake -S "$work/src" -B "$work/src/b" -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release \
    -DVulkan_INCLUDE_DIR="$work/vk/include" -DCMAKE_PREFIX_PATH="$work/prefix" \
    -DCMAKE_CXX_FLAGS="-I$work/prefix/include -I$work/vk/include" \
    -DCMAKE_C_FLAGS="-I$work/prefix/include -I$work/vk/include" >/dev/null
run nice -n 10 cmake --build "$work/src/b" -j"$JOBS" --target llama-server llama-bench >/dev/null

info "installing to $PREFIX"
run mkdir -p "$PREFIX/bin" "$PREFIX/draft"
run cp "$work/src/b/bin/llama-server" "$PREFIX/bin/llama-server.real"
run cp "$work/src/b/bin/llama-bench"  "$PREFIX/bin/"
find "$work/src/b" \( -name '*.so' -o -name '*.so.*' \) -exec cp -P {} "$PREFIX/bin/" \; 2>/dev/null || true
# Self-contained launcher: survives being started with a clean environment.
cat > "$PREFIX/bin/llama-server" <<'W'
#!/usr/bin/env bash
d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$d${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$d/llama-server.real" "$@"
W
run chmod +x "$PREFIX/bin/llama-server"
"$PREFIX/bin/llama-server" --version 2>&1 | head -1 | sed 's/^/    /'

info "fetching the prefill draft model (~1.3 GB)"
have_cmd hf || { warn "hf CLI missing; fetch $DRAFT_REPO $DRAFT_GLOB into $PREFIX/draft yourself"; exit 0; }
run hf download "$DRAFT_REPO" --include "$DRAFT_GLOB" --local-dir "$PREFIX/draft" >/dev/null

ok "strix-llama installed"
cat <<NOTE

  Not wired up for you -- point your server at it when you want it:

      <server> config set llamacpp.vulkan_bin=$PREFIX/bin/llama-server

  and pass, per load:

      --spec-prefill -mpd $PREFIX/draft/<draft>.gguf --spec-prefill-p 0.30

  Start at 0.30 and measure retrieval before going lower. Lower is faster and
  loses the middle of long prompts. UNINSTALL=1 removes all of it.
NOTE
