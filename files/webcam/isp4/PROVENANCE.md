# Fetched: AMD ISP4 capture driver

This directory is **not committed**. `installers/webcam.sh` downloads the AMD
ISP4 sources as merged into Linux **v7.2** from
`drivers/media/platform/amd/isp4/` in the kernel tree, at the ref pinned in
`../isp4.provenance`, and verifies every file against `../isp4.sha256`.
A checksum mismatch aborts the install rather than building unknown code.

- Copyright (C) 2025 Advanced Micro Devices, Inc.
- `SPDX-License-Identifier: GPL-2.0+` (unmodified, preserved per-file)

## Why they are here

The AUR package `amdisp4-dkms` (8-1) ships the **Nov-2025 patch revision**,
which still sets `vb2_ops.wait_prepare` / `wait_finish`. Both were removed from
videobuf2 before the driver merged upstream, so it does not compile against
current kernels. These merged sources do — verified building on 7.1.8, where
the only other API delta (`kmalloc_obj()`) already exists.

`installers/webcam.sh` copies these over `/usr/src/amdisp4-8/` on every run,
because any reinstall or update of the AUR package restores the broken originals.

Once the running kernel reaches 7.2, the in-tree driver supersedes all of this
and the DKMS package is removed instead. At that point this directory can be
deleted.

## Licensing note

This repository is MIT. Rather than aggregate GPL-2.0+ code into it — which is
permissible but muddies the licensing story — the sources are fetched from
their canonical upstream at install time. Nothing here redistributes AMD's
code, and per-file SPDX tags and copyright notices are never modified.
