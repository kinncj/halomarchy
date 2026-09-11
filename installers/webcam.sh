#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Kinn Coelho Juliao <kinncj@protonmail.com>
# SPDX-License-Identifier: MIT
#
# ZBook Ultra G1a MIPI webcam (AMD ISP4).
#
# The ISP4 capture driver merged upstream in Linux 7.2. Below that we need the
# AUR `amdisp4-dkms` package -- but it does not build as shipped, for two
# reasons, so this module carries both fixes:
#
#   1. Its PKGBUILD seds @_PKGBASE@ while dkms.conf contains @_PKGNAME@, so
#      PACKAGE_NAME stays a literal placeholder and `dkms install` fails.
#   2. Its sources are the Nov-2025 patch revision, which still sets
#      vb2_ops.wait_prepare/wait_finish -- removed from videobuf2 before merge,
#      so it does not compile. The sources as merged in v7.2 are fetched from
#      the kernel tree at install time (pinned ref + sha256 manifest) and are
#      verified to build on 7.1.8.
#
# On 7.2+ the in-tree driver takes over and the DKMS package must be REMOVED,
# or it shadows the in-tree module.
set -euo pipefail
source "$(dirname "$0")/_lib.sh"

DKMS_PKG="amdisp4-dkms"
DKMS_NAME="amdisp4"
DKMS_VER="8"
SRC_DIR="/usr/src/${DKMS_NAME}-${DKMS_VER}"
VENDORED="$REPO_DIR/files/webcam/isp4"
MANIFEST="$REPO_DIR/files/webcam/isp4.sha256"
# shellcheck source=/dev/null
. "$REPO_DIR/files/webcam/isp4.provenance"

KVER_FULL="$(uname -r)"
KVER="${KVER_FULL%%-*}"

if [ "${UNINSTALL:-0}" -eq 1 ]; then
    if pkg_installed "$DKMS_PKG"; then
        plan remove "$DKMS_PKG"
        run sudo pacman -Rns --noconfirm "$DKMS_PKG"
    else
        plan same "$DKMS_PKG" "absent"
    fi
    exit 0
fi

# ── kernel 7.2+ : in-tree driver, DKMS must go ────────────────────────────────
if ! _ver_lt "$KVER" "7.2"; then
    ok "kernel $KVER has the in-tree ISP4 driver"
    if pkg_installed "$DKMS_PKG"; then
        plan remove "$DKMS_PKG" "shadows in-tree driver on $KVER"
        warn "removing $DKMS_PKG — the in-tree module supersedes it"
        run sudo pacman -Rns --noconfirm "$DKMS_PKG"
    else
        plan same "$DKMS_PKG" "not installed (correct for $KVER)"
    fi
    exit 0
fi

# ── kernel < 7.2 : DKMS required ──────────────────────────────────────────────
info "kernel $KVER < 7.2 — out-of-tree ISP4 driver required"
aur_install "$DKMS_PKG"

# The AMD sources are GPL-2.0+ and are NOT committed to this MIT repo. Fetch
# them from the kernel tree at the pinned ref and verify every checksum.
fetch_verified "$VENDORED" "$MANIFEST" "$ISP4_BASE" "$ISP4_REF" || exit 1

if [ "${DRY_RUN:-0}" -eq 1 ]; then
    # Report what the two fixes would do without touching /usr/src.
    if [ -f "$SRC_DIR/dkms.conf" ] && [ "$(awk -F'"' '/^PACKAGE_NAME=/{print $2}' "$SRC_DIR/dkms.conf")" = "$DKMS_NAME" ]; then
        plan same "$SRC_DIR/dkms.conf" "PACKAGE_NAME ok"
    else
        plan update "$SRC_DIR/dkms.conf" "PACKAGE_NAME placeholder -> $DKMS_NAME"
    fi
    # Only the files in the manifest are kernel sources; PROVENANCE.md and the
    # fetched LICENSE live alongside them but must never be copied to /usr/src.
    src_state=same
    while read -r _ f; do
        [ -n "$f" ] || continue
        cmp -s "$VENDORED/$f" "$SRC_DIR/$f" 2>/dev/null || src_state=update
    done < "$MANIFEST"
    plan "$src_state" "$SRC_DIR sources" "$([ "$src_state" = update ] && echo 'differ from vendored v7.2' || echo 'match vendored v7.2')"
    [ -e /dev/video0 ] && plan same /dev/video0 "present" || plan update /dev/video0 "missing"
    exit 0
fi

changed=0

# fix 1 — dkms.conf placeholder
if [ -f "$SRC_DIR/dkms.conf" ]; then
    if [ "$(awk -F'"' '/^PACKAGE_NAME=/{print $2}' "$SRC_DIR/dkms.conf")" = "$DKMS_NAME" ]; then
        plan same "$SRC_DIR/dkms.conf" "PACKAGE_NAME ok"
    else
        plan update "$SRC_DIR/dkms.conf" "PACKAGE_NAME -> $DKMS_NAME"
        sudo sed -i "s/@_PKGNAME@/${DKMS_NAME}/" "$SRC_DIR/dkms.conf"
        changed=1
    fi
else
    err "$SRC_DIR/dkms.conf missing — is $DKMS_PKG installed?"; exit 1
fi

# fix 2 — replace sources with the v7.2-merged copies (manifest files only)
while read -r _ f; do
    [ -n "$f" ] || continue
    if ! cmp -s "$VENDORED/$f" "$SRC_DIR/$f" 2>/dev/null; then
        sudo install -Dm644 "$VENDORED/$f" "$SRC_DIR/$f"
        changed=1
    fi
done < "$MANIFEST"
if [ "$changed" -eq 1 ]; then
    plan update "$SRC_DIR sources" "restored vendored v7.2"
else
    plan same "$SRC_DIR sources" "match vendored v7.2"
fi

# rebuild only when something actually changed or the module is absent
if [ "$changed" -eq 1 ] || ! dkms status "$DKMS_NAME/$DKMS_VER" 2>/dev/null | awk '/installed/{f=1} END{exit !f}'; then
    info "rebuilding DKMS module for $KVER_FULL"
    sudo dkms remove  "$DKMS_NAME/$DKMS_VER" --all 2>/dev/null || true
    sudo dkms install "$DKMS_NAME/$DKMS_VER" -k "$KVER_FULL"
    sudo modprobe -r amd_capture 2>/dev/null || true
    sudo modprobe amd_capture 2>/dev/null || true
else
    plan same "dkms $DKMS_NAME/$DKMS_VER" "built for $KVER_FULL"
fi

if [ -e /dev/video0 ]; then
    ok "webcam ready: /dev/video0 + /dev/media0"
    info "auto-exposure takes 1-2s to converge; first frames are near black"
else
    warn "/dev/video0 absent — check: dmesg | grep -i isp4"
fi
