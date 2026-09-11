#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# PATH + ROCm environment for login shells and services.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    run sudo rm -f /etc/profile.d/rocm.sh /usr/local/bin/rocminfo /usr/local/bin/hipcc
    ok "environment removed"; exit 0
fi

file_install "$REPO_DIR/files/profile.d/rocm.sh" /etc/profile.d/rocm.sh

# profile.d covers login shells only. bitsandbytes shells out to rocminfo from
# non-login contexts (Jupyter kernels, user services), so expose the two that
# matter in a directory already on the default PATH.
for b in rocminfo hipcc; do
    [ -x "/opt/rocm/bin/$b" ] && run sudo ln -sf "/opt/rocm/bin/$b" "/usr/local/bin/$b"
done
ok "rocm.sh + /usr/local/bin shims installed"
assert_gfx1151
