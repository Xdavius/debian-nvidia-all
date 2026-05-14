# Patch inventory

This file is a maintenance note only. Pacstall expects the patch files listed in
`source=()` to stay next to the pacscript, so the files are not moved into
subdirectories.

## Active with the local test set

- `99-local-kernel-compat-390.patch`
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

Keep these if the pacscript may later support 470/older proprietary drivers.
They are not needed for the current local 390 + 580 test set unless a matching
driver version is added.

- `kernel-6.0-470.patch`
- `kernel-6.19-470.patch`
- `kernel-7.0-470.patch`
- `legacy-kernel-6.4.diff`
- `legacy-kernel-6.5.diff`
- `legacy-kernel-6.6.diff`
- `gcc-14-470.diff`

## Old kernel compatibility baggage

These mostly come from the older `nvidia-all` compatibility pile for Linux 4.x
and 5.x transitions. They are likely obsolete for Debian 13 unless a very old
driver is tested against a very specific old or custom kernel.

- `kernel-4.16.patch`
- `kernel-4.19.patch`
- `kernel-5.0.patch`
- `kernel-5.1.patch`
- `kernel-5.2.patch`
- `kernel-5.3.patch`
- `kernel-5.4.patch`
- `kernel-5.4-prime.diff`
- `kernel-5.4-symver.diff`
- `kernel-5.5.patch`
- `kernel-5.6.patch`
- `kernel-5.7.patch`
- `kernel-5.8.patch`
- `kernel-5.9.patch`
- `kernel-5.10.patch`
- `kernel-5.11.patch`
- `kernel-5.12.patch`
- `kernel-5.14.patch`
- `kernel-5.16.patch`
- `kernel-5.16-std.diff`
- `kernel-5.17.patch`
- `5.6-ioremap.diff`
- `5.6-legacy-includes.diff`
- `5.8-legacy.diff`
- `5.9-gpl.diff`
- `5.11-legacy.diff`

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
