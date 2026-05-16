# Patch inventory

This file is a maintenance note only. Pacstall expects the patch files listed in
`source=()` to stay next to the pacscript.

## Current project state (update)

- The active pacscript is now `pacscript/nvidia-driver-run.pacscript`.
- Patch files are stored in `pacscript/`.
- For the proprietary 470 branch, the current active approach is a cumulative
  patch: `470-kernel-7.0.patch`.
- This document still keeps the broader historical inventory below on purpose.

## Naming convention (cumulative patches)

Going forward, cumulative patch naming follows:

- `<nvidia-main-branch>-kernel-<max-kernel-supported>.patch`

Examples:

- `390-kernel-7.0.patch`
- `470-kernel-7.0.patch`

Policy:

- patches are cumulative (large unified patches),
- each patch targets one NVIDIA main branch,
- file name indicates the maximum tested/supported kernel family,
- patches are expected to support both GCC and Clang toolchains.

## Patch creation context (new cumulative patches)

When creating a new branch patch (for example `470-kernel-7.0.patch`), use this
ordered context and checklist.

### 1) Target and scope definition

- Pick one NVIDIA main branch (example: `390`, `470`, `580`).
- Define the maximum kernel family covered by the patch name.
- Keep one unified cumulative patch per branch target.

### 2) Technical prerequisites (mandatory)

- Must be compatible with both **GCC** and **Clang** builds.
- Must be **cumulative and unified** (single large patch per branch target).
- Must be validated with a **minimum kernel baseline of 6.12**.
- Must cover custom/LTS variants, including **XanMod LTS kernels**.

### 3) Integration rules

- Integrate all required fixes into the cumulative patch instead of adding a
  long split series.
- Keep pacscript rules simple: one branch rule -> one cumulative patch.
- Preserve compatibility logic for DKMS/toolchain selection.

### 4) Validation workflow (required before merge)

- Apply patch on a clean extracted NVIDIA source tree.
- Build-test with GCC and Clang/lld.
- Test at least:
  - baseline kernel `6.12`
  - upper target kernel family from the patch name (example `7.0`)
  - LTS/custom flavor (XanMod LTS when available)
- Confirm module build success (`nvidia.ko`, `nvidia-uvm.ko`,
  `nvidia-modeset.ko`, `nvidia-drm.ko`).

### 5) Documentation and maintenance

- Update this file (`PATCHES.md`) with the new active cumulative patch.
- Remove or archive obsolete split patch fragments once replacement is
  validated.

## Active with the local test set

- `390-kernel-7.0.patch`
  - Target: NVIDIA 390.157 proprietary/legacy `kernel/` tree.
  - Current role: local compatibility patch for Debian 13 and newer/custom
    kernels.
  - Tested locally: applies to `NVIDIA-Linux-x86_64-390.157.run`.

- `0001-Enable-atomic-kernel-modesetting-by-default.diff`
  - Target: recent `kernel-open/` tree.
  - Current role: enable atomic modesetting by default for better Wayland
    behavior.
  - Tested locally: applies to `NVIDIA-Linux-x86_64-580.159.03.run`.

- `fix-hw-cursor-kde.diff`
  - Target: recent `kernel-open/` tree.
  - Current role: KDE hardware cursor fix.
  - Tested locally: applies to `NVIDIA-Linux-x86_64-580.159.03.run`.

## Open-module candidates

These are kept because they target recent open-module layouts, but they did not
apply to the local 580.159.03 runfile during the last test. They may already be
upstreamed, version-specific, or intended for a slightly different source tree.

- `0002-Add-IBT-support.diff`
- `Add-IBT-support.diff`
- `nvidia-open-gcc-ibt-sls.diff`
- `fix-hdmi-names.diff`
- `silence-event-assert-until-570.diff`
- `kernel-7.0-580.patch`

## Modern or future kernel compatibility

These are mostly useful when testing custom, backported, XanMod, TKG, or future
kernels. They are not necessarily useful for Debian 13's default 6.12 kernel
with a current NVIDIA driver.

- `kernel-6.12.patch`
- `kernel-6.17.patch`
- `kernel-6.19.patch`
- `kernel-7.0.patch`
- `kernel-7.1.patch`
- `gcc-15.diff`

## Legacy 470 and older-driver support

Current status for 470 proprietary support:

- Active patch: `470-kernel-7.0.patch`
  - Role: cumulative compatibility patch for the 470 branch.
  - Intended coverage: kernels from 6.12 up to 7.0, including GCC and
    clang/lld builds.
  - Note: this patch replaces the previously split 470 patch series and
    compatibility fragments.

## Old kernel compatibility baggage

Most Linux 4.x/5.x legacy compatibility patches from the old `nvidia-all`
stack were removed from this repository.

- Current status: no dedicated 4.x/5.x compatibility patch files are kept in
  the active patch set.

## Miscellaneous or version-specific

These need a matching driver/version test before deciding whether they are still
useful.

- `01-ipmi-vm.diff`
- `02-ipmi-vm.diff`
- `455-crashfix.diff`
- `6.1-6-7-8-gpl.diff`
- `6.11-fbdev.diff`
- `Enable-atomic-kernel-modesetting-by-default.diff`
- `GFP_RETRY_MAYFAIL-test.diff`
- `gcc-14.diff`
- `linux-version.diff`
- `list_is_first.diff`
- `make-modeset-fbdev-default.diff`
- `make-modeset-fbdev-default-565.diff`
- `nvidia-bsb-dsc-fix.diff`
- `nvidia-settings-libxnvctrl_so.diff`
