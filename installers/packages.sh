#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
# Base ROCm compute toolchain + language runtimes.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

[ "${UNINSTALL:-0}" -eq 1 ] && { info "packages are left installed on uninstall"; exit 0; }

# rocm-hip-sdk pulls hipcc, rocm-llvm, rocBLAS, MIOpen, RCCL, rocSOLVER...
# amdsmi -- NOT rocm-smi-lib -- is what provides /opt/rocm/bin/amd-smi.
pkg_install rocm-hip-sdk rocwmma amdsmi python-pytorch-rocm jdk-openjdk uv
ok "compute toolchain ready"
