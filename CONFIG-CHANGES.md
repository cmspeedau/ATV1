# CONFIG-CHANGES.md — every build-configuration change, in order

Scoped to the *configuration* files: `configs/atv1_defconfig`,
`board/atv1/linux.fragment`, `board/atv1/genimage.cfg`, `external.mk`,
`tools/container-build.sh`, `Config.in`/`package/*/Config.in`.
Narrative reasoning lives in `LOG.md`; this file is the ledger —
what symbol changed, old → new, and the one-line why. Newest last,
because an append-only ledger is the only kind that stays trustworthy.

---

## 2026-10-25 23:15 — `857198d` — tree created (initial values)

| Setting | Initial value | Note |
|---|---|---|
| `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE` | `4.14.335` | believed "last LTS with staging/crystalhd" — later proven wrong |
| `BR2_INSTALL_LIBSTDCPP` | `y` | wrong symbol (promptless — silently dropped) |
| `BR2_PACKAGE_XORG_SERVER` | `y` | later-era naming; dropped by this era's kconfig |
| kernel fragment | crystalhd staging + fb + NIC candidates | |
| grub | ia32-efi + bios menus | from day one |

## 2026-10-25 23:36 — `20c62bc` — disk-layout alignment

- defconfig **+** `BR2_PACKAGE_E2FSPROGS`, `BR2_PACKAGE_GPTFDISK`,
  `BR2_PACKAGE_GPTFDISK_SGDISK` — on-target disk surgery for the
  install/grow flow (ARCHITECTURE §4).
- genimage.cfg: three-partition layout (boot.vfat / rootfs / data).

## 2026-10-26 09:12 — `db0378c` — the era-kconfig purge

Era kconfig *silently drops* assignments to unknown or promptless
symbols — five settings that "looked set" were not set:

| Symbol | Change | Why |
|---|---|---|
| `BR2_INSTALL_LIBSTDCPP=y` | → `BR2_TOOLCHAIN_BUILDROOT_CXX=y` | the latter is the prompt; it selects the former |
| `BR2_PACKAGE_XORG_SERVER=y` | → `BR2_PACKAGE_XORG7=y` + `BR2_PACKAGE_XSERVER_XORG_SERVER=y` | era naming |
| arch | + explicit `BR2_x86_pentium_m=y` | i586 default hides Kodi (needs MMX+SSE); pentium_m claims only what CPUID hadn't yet disproved — **SSE2 gate recorded here: "not before CPUID shows it"** |
| libc | + explicit `BR2_TOOLCHAIN_BUILDROOT_GLIBC=y` | crystalhd userspace + Rust client target |
| kernel capture flow | comment rewritten | fragment re-applies per defconfig run; no menuconfig capture |

Audit added: verify the generated `.config` after every defconfig.

## 2026-10-26 09:02 / 10:12 — `07ed82e`, `efc9df1`

- container-build.sh created (idempotent; /work volume resumes builds).
- `BR2_KERNEL_HEADERS_4_12=y` — era toolchain headers pin.

## 2026-10-27 01:13 — `cb4773a` — fragment: retpoline off

- fragment **+** `# CONFIG_RETPOLINE is not set` — canonical form
  required; `# CONFIG_RETPOLINE=n` disables **nothing** (verified on
  generated `.config`; saves speculative-jmp overhead on Crofton).
- container-build.sh **+** `set -euo pipefail` — a `make | tee` failure
  had reported "finished" while broken.

## 2026-10-27 01:15 — `d420e4a` — kernel for crystalhd (WRONG, superseded)

- `BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE`: `4.14.335` → `4.13.16`
  ("last release with in-tree crystalhd") — later archaeology: last
  in-tree release is the **3.16.x** series. Kept in the ledger.

## 2026-10-27 01:28 — `dbcde31` — premise fix #1 (half-right, superseded in part)

- kernel: `4.13.16` → **`4.9.337`**; headers `4_12` → **`4_9`** — card
  absent, so crystalhd stops being a pin; 4.9 chosen on era grounds.
- `BR2_PACKAGE_XDRIVER_XF86_VIDEO_NOUVEAU` **— removed**
- `BR2_PACKAGE_MESA3D_DRI_DRIVER_NOUVEAU` **— removed**
  (overcorrection: true for the stock unit only — see `2b18c5f`).

## 2026-10-27 02:08–02:15 — `870f41e`, `356e93b` — crystalhd record

- dormant `package/crystalhd/` repointed: dead LibreELEC fork →
  crystalhd-arch/libcrystalhd v20131127, sha512 `28009f…` recorded.
- fragment comment: **buy only BCM970012 (`14e4:1612`)**; in-tree driver
  died in 3.17, enablement = kernel flip to 3.16.85 (documented flip,
  not yet applied).

## 2026-10-27 02:23–02:25 — `489cb7e`, `6f8fbc6`, `f061f59` — image pipeline

- post-build: `${BR2_PACKAGE_ATV1_CLIENT:-}` guard (unselected = unset).
- post-image: grub EFI found at `efi-part/EFI/BOOT/bootia32.efi`.
- genimage.cfg → **genimage 9's real option surface**: vfat has no
  `label` (volume name via `extraargs = "-n ATV1BOOT"`); ext4 section
  knows only `label`; an invented `use-inode-count` deleted.

## 2026-10-27 10:26 — `2b18c5f` — fleet config follows Stage-0 evidence

Kernel fragment:

| Symbol | Change | Evidence |
|---|---|---|
| `CONFIG_8139TOO` | **+ =y** | unit B NIC = Realtek `10ec:8139` (ioreg) |
| `CONFIG_DRM_I915=y` | kept | unit A (stock) GMA950 |
| `CONFIG_DRM_NOUVEAU`, `CONFIG_DRM_TTM` | **restored =y** | unit B Go 7300 `10de:01d7` behind PCIe bridge owns its HDMI |
| NIC candidate list (e1000/tg3/bnx2/sky2/r8169) | kept | cheap insurance until unit A's NIC is observed |

defconfig:

| Symbol | Change | Why |
|---|---|---|
| `BR2_PACKAGE_XDRIVER_XF86_VIDEO_NOUVEAU` | **restored =y** | unit B's X driver |
| `BR2_PACKAGE_MESA3D_DRI_DRIVER_NOUVEAU` | **restored =y** | nv40 hardware GL (Gone in Mesa ≥ 17.3 — the era pin's raison d'être) |
| `BR2_PACKAGE_MESA3D_GALLIUM_DRIVER_SWRAST` | kept | unit A's GL floor |
| `BR2_PACKAGE_HOST_DOSFSTOOLS` | **+ =y** | genimage 9 execs `mkdosfs` (undocumented; found by failure) |
| `BR2_PACKAGE_HOST_MTOOLS` | **+ =y** | genimage 9 execs `mcopy`/`mmd` |

## 2026-10-27 10:29–10:30 — `44535e8`, `d221ec0` — host-tools phantom

- external.mk **+** `HOST_GENIMAGE_DEPENDENCIES += host-genext2fs
  host-e2fsprogs` (v9 execs `genext2fs` + `tune2fs`; era genimage.mk
  declares neither).
- **The phantom lesson:** that append alone did nothing — this era
  only *instantiates* a package's rules when its `.config` symbol is
  enabled:
  - defconfig **+** `BR2_PACKAGE_GENEXT2FS=y` (instantiates; no
    HOST-only symbol exists this era, so the 40 KB binary also rides
    in the rootfs — legitimate disk-surgery kit).
  - container-build.sh **+** explicit idempotent prebuild:
    `make host-genext2fs host-e2fsprogs host-dosfstools host-mtools`
    after defconfig — post-image never depends on graph subtleties.

## 2026-10-27 10:32 — `f8ad316` — genimage content-model fix

- genimage.cfg: `rootfs-data.ext4` ext4-block →
  **`file { name = "atv1-data.ext4"; copy = false }`**; `rootfs.ext4`
  declared explicitly **`file { copy = false }`** — because an ext4
  block in genimage 9 is fed `cp -a --rootpath` and buildroot's
  genimage.sh sets `--rootpath ${TARGET_DIR}` (the whole rootfs; the
  genext2fs ENOSPC). The `file` handler embeds pre-built raw files.
- post-image.sh **+** `mkfs.ext4 -F -q -L ATV1DATA atv1-data.ext4 65536`
  — the empty 64 MiB data fs is formatted here now.

---

## Effective config snapshot (first-good image, 2026-10-27)

| Key | Value |
|---|---|
| Buildroot | 2017.08.x (`a2493ca`, reports 2017.08.2) |
| `BR2_x86_pentium_m=y` | SSE2 proven since → pentium4 promotion unlocked but deferred (roadmap; full rebuild) |
| libc / C++ | glibc / `BR2_TOOLCHAIN_BUILDROOT_CXX=y`; headers `BR2_KERNEL_HEADERS_4_9` |
| Kernel | `4.9.337` + fragment: `DRM_I915=y`, `DRM_NOUVEAU=y`, `DRM_TTM=y`, `8139TOO=y`, NIC insurance, retpoline off, STAGING off |
| X | XORG7 + server + intel/nouveau/fbdev DDX + xinit |
| Mesa 17.1.5 | EGL+GLES, `DRI_DRIVER_NOUVEAU` (nv40 HW GL), `GALLIUM_DRIVER_SWRAST` |
| Kodi | 17.3-Krypton |
| Data-partition deps | genext2fs (target+host), dosfstools/mtools host, e2fsprogs both |
| genimage | 9; MBR, P1 vfat(32M, `-n ATV1BOOT`, bootable, starts sector 1 — v9 does not align) / P2 rootfs via file-handler / P3 atv1-data.ext4 via file-handler |
| Image | 608 MiB; sha256 `6b0c907d…ce79a0a0` (LOG.md milestone entry) |

**Standing rule** (every entry above earned it): after any defconfig or
fragment edit, run `make atv1_defconfig` and **audit the generated
`.config` for the named symbols** — this era's kconfig drops what it
doesn't recognize, without a word.
