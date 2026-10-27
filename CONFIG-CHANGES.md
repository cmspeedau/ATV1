# CONFIG-CHANGES.md — build-config ledger

Append-only. Scope: `configs/atv1_defconfig`, `board/atv1/linux.fragment`,
`board/atv1/genimage.cfg`, `external.mk`, `tools/container-build.sh`,
`Config.in`s. Format: commit → change (`old → new`) → reason. Failure
stories behind entries: LOG.md.

- `857198d` 10-25 — initial: kernel `4.14.335` (belief: last w/ crystalhd —
  wrong); `BR2_INSTALL_LIBSTDCPP=y`; `BR2_PACKAGE_XORG_SERVER=y` (both
  later found to be silently dropped); fragment = i386 + fb + NIC guesses.
- `20c62bc` 10-25 — + `E2FSPROGS`, `GPTFDISK(+SGDISK)` (on-target disk
  surgery for install/grow); genimage → 3-partition layout.
- `db0378c` 10-26 — era-kconfig purge: `INSTALL_LIBSTDCPP` →
  `TOOLCHAIN_BUILDROOT_CXX`; `XORG_SERVER` → `XORG7`+`XSERVER_XORG_SERVER`;
  + explicit `BR2_x86_pentium_m` (i586 hides Kodi: needs MMX+SSE; SSE2
  gate: "not before CPUID proves it"); + explicit `TOOLCHAIN_BUILDROOT_GLIBC`.
  Rule: audit generated `.config`.
- `efc9df1` 10-26 — `BR2_KERNEL_HEADERS_4_12=y` (era headers).
- `cb4773a` 10-27 — fragment: `# CONFIG_RETPOLINE is not set` (canonical
  form; `=n` comment disables nothing). container-build.sh: `pipefail`.
- `d420e4a` 10-27 — kernel `4.14.335 → 4.13.16` (crystalhd belief; WRONG
  — last in-tree carrier is 3.16.85 — kept as history).
- `dbcde31` 10-27 — kernel `4.13.16 → 4.9.337`, headers `4_12 → 4_9`
  (no card → card unpin; era LTS). REMOVED nouveau X DDX +
  `MESA3D_DRI_DRIVER_NOUVEAU` (overcorrection; restored below).
- `870f41e`/`356e93b` 10-27 — crystalhd pkg: dead fork →
  crystalhd-arch v20131127 + sha512 `28009f…`; fragment: buy-only-BCM970012
  (`14e4:1612`) + enable plan prose.
- `489cb7e` 10-27 — post-build: `${BR2_PACKAGE_ATV1_CLIENT:-}` (unset-safe).
- `6f8fbc6` 10-27 — post-image: grub EFI read from
  `efi-part/EFI/BOOT/bootia32.efi` (that package's real output path).
- `f061f59` 10-27 — genimage.cfg → genimage 9 surface: vfat `label` doesn't
  exist → `extraargs = "-n ATV1BOOT"`; ext4 = `label` only; invented
  `use-inode-count` deleted.
- `2b18c5f` 10-27 — Stage-0 evidence in: fragment + `CONFIG_8139TOO=y`
  (NIC `10ec:8139`, ioreg); fragment + `CONFIG_DRM_NOUVEAU=y`
  `CONFIG_DRM_TTM=y` (unit B `10de:01d7` owns its HDMI); defconfig +
  `XDRIVER_XF86_VIDEO_NOUVEAU=y` + `MESA3D_DRI_DRIVER_NOUVEAU=y` (nv40
  HW GL; gone from Mesa ≥ 17.3); swrast kept for unit A; +
  `BR2_PACKAGE_HOST_DOSFSTOOLS=y`, `BR2_PACKAGE_HOST_MTOOLS=y` (genimage 9
  execs `mkdosfs`/`mcopy`/`mmd`; undeclared). NIC guesses kept as
  insurance until unit A observed.
- `44535e8` 10-27 — external.mk: `HOST_GENIMAGE_DEPENDENCIES +=
  host-genext2fs host-e2fsprogs` (execs `genext2fs`+`tune2fs`). NOTE:
  append alone = phantom unless packages are instantiated (next entry).
- `d221ec0` 10-27 — defconfig + `BR2_PACKAGE_GENEXT2FS=y` (instantiates
  rules; era has no HOST-only symbol; +40 KB on target, acceptable);
  container-build.sh + prebuild `host-genext2fs host-e2fsprogs
  host-dosfstools host-mtools` after defconfig (deterministic; era
  gates package rules on `.config` symbols — the root cause).
- `f8ad316` 10-27 — genimage content-model fix: `rootfs.ext4` declared
  `file { copy = false }`; `rootfs-data.ext4` ext4-block →
  `file { name = "atv1-data.ext4"; copy = false }` (v9 feeds ext images
  `cp -a --rootpath` = whole rootfs → ENOSPC; `file` embeds raw input).
  post-image.sh + `mkfs.ext4 -F -q -L ATV1DATA atv1-data.ext4 65536`.
- `ec71426` 10-27 — SMB OS-level client: fragment +
  `CONFIG_CIFS=y`; defconfig + `BR2_PACKAGE_CIFS_UTILS=y`; fstab +
  commented mount example; README §6a. Client-only by design. AUDITED
  post-rebuild: merged kernel `.config` has `CONFIG_CIFS=y`, target has
  `/sbin/mount.cifs` — green.
- `10e296d` 10-27 — skin.atv v0.1: defconfig + `BR2_PACKAGE_DEJAVU=y`
  (era package is `dejavu`; later `ttf-dejavu` naming does not exist
  here — verified in `package/*/Config.in` before setting, silent-drop
  rule); post-build.sh + skin install → `/root/.kodi/addons/skin.atv/`
  + `gen_assets.py` run + DejaVu copy via `find` (hard-fails if
  missing — no silent skinless boot); overlay userdata + `guisettings.xml`
  (lookandfeel.skin, screensaver/mouse off) + `sources.xml`
  (`/data/media/*`). Skin itself: `skin/skin.atv/`, GPL-2.0-only, zero
  Apple assets (rasters generated at build, fonts Bitstream-Vera); no
  PNGs/TTFs in git (.gitignore). Kernel untouched.
- `d7d9a5d` 10-27 — defconfig + `BR2_TARGET_GENERIC_ROOT_PASSWD=
  "frontrow"` (owner's call: plain, documented LAN credential — README
  §5 + SPECS. Era path verified in source: `skeleton-init-common.mk`
  hashes the string at finalize via auto-`select`ed `HOST_MKPASSWD`,
  method md5 = what dropbear speaks. Audited: symbol in generated
  `.config`, `$1$…` in target shadow AND in P2 bytes. Companion
  `91e8b38` (overlay-only, outside this ledger's files): fleet pubkey
  baked, package `S50kodi` masked, serial root login same password.

## Effective config (first-good image, 2026-10-27)

| Key | Value |
|---|---|
| Buildroot | 2017.08.x (`a2493ca`) |
| Toolchain | `BR2_x86_pentium_m` + glibc + C++ (pentium4 unlocked by SSE2 CPUID, deferred) |
| Kernel | 4.9.337 + headers 4_9 + fragment (`DRM_I915`, `DRM_NOUVEAU`, `DRM_TTM`, `8139TOO`, NIC insurance, retpoline off, STAGING off, EFI_MIXED) |
| X / GL | XORG7 + intel/nouveau/fbdev + xinit; Mesa 17.1.5 EGL+GLES + `DRI_DRIVER_NOUVEAU` + `GALLIUM_DRIVER_SWRAST` |
| Kodi | 17.3-Krypton |
| Skin | `skin.atv` v0.1 (GPL-2.0-only, build-generated art) + `DEJAVU` fonts |
| Image deps | `HOST_DOSFSTOOLS`, `HOST_MTOOLS`, `GENEXT2FS` + external.mk deps + build-script prebuild |
| genimage | 9; MBR; P1 vfat 32M `-n ATV1BOOT` bootable (starts sector 1 — v9 doesn't align); P2 rootfs via `file`; P3 64M via `file` (formatted by post-image) |
| Artifacts | MBR `atv1-disk.img` 609 MiB sha256 `56f345dd909feb4dd8079318d20a5ad9fe33061d1530ebd04c9a6355fa2e20e8` **and** restore-layout `atv1-recv-disk.img` 641 MiB sha256 `ab6c65c2e540ad6c930188d2382e87b0724184f18e0f7574c502ea371949f56f` — efifb-experiment build (FB_EFI OFF single-variable revert, recorder dmesg+sync fix, panic=5; mach_kernel bb70e9b4 content-proven fresh after stale-object fix, LOG 18:4x); chain …→23b1e4af→f8d41b9c→d4dacb31→afe0cd8f(stale-superseded)→ab6c65c2 / …→c3ca5b94→db8c3d35→56f345dd |

Standing rule: any defconfig/fragment edit → rerun `make atv1_defconfig`
and grep the generated `.config` for the symbols you set. This era drops
the unknown silently.
