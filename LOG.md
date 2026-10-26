# ATV1 Engineering Log

Append-only record of decisions, evidence, and failures. Newest last.
README.md = how-to; ATV1-SPECS.md = hardware; CONFIG-CHANGES.md = config
ledger; this file = why the tree looks like this. Discipline: nothing is
"supported" without a hardware observation; unverified = Unknown.

## 2026-10-25 — bootstrap (`857198d`…)

- br2-external against Buildroot 2017.08.x (`a2493ca`). Era pins:
  Kodi 17.3 (last CrystalHD), Mesa 17.1.x (last nv40 classic DRI),
  grub2 i386-efi (32-bit EFI firmware), python2 add-ons.
- Layout per ARCHITECTURE doc: P1 boot.vfat / P2 rootfs / P3 ATV1DATA
  (LABEL-mounted; survives re-imaging = the recovery model). Rust client
  cross-built out-of-era (this Buildroot predates in-tree Rust).
- Tree lives on APFS; AppleDouble junk stripped; exec bits on scripts only.

## 2026-10-26 — silent-drop reality of era kconfig (`db0378c`)

- Five defconfig settings "looked set" and were dropped: promptless
  symbol (`BR2_INSTALL_LIBSTDCPP` → set `BR2_TOOLCHAIN_BUILDROOT_CXX`),
  later-era name (`XORG_SERVER` → `XORG7` + `XSERVER_XORG_SERVER`).
- Standing rule: audit the generated `.config` after every defconfig run.
- Config.in help prose must be tab-indented (kconfig parses space-indented
  prose as commands).
- Build host containerized: `tools/Dockerfile.build` (debian stretch =
  era gcc6/py2). Stretch apt moved to archive.debian.org (LTS ended
  2025-06; stock mirrors dead).

## 2026-10-27 01:1x — kernel + fragment corrections

- `# CONFIG_RETPOLINE=n` in a fragment disables NOTHING. Canonical
  `# CONFIG_RETPOLINE is not set` works. Verified on generated `.config`.
- container-build.sh needs `set -euo pipefail`: `make | tee` masked a
  failure and reported success once.
- CrystalHD kernel archaeology (from driver source + git history):
  in-tree through 3.16.x (final 3.16.85), deleted in 3.17. A belief that
  4.13.16 was the last carrier was wrong and reverted; kernel now
  4.9.337 + headers 4_9 (era LTS — card-independent, see next entry).

## 2026-10-27 01:28 — premise fix #1, then #2

- Unit at hand (stock, .46): no CrystalHD card → card stops being a pin.
  The same commit purged "7300 owns HDMI / never enable i915" prose as
  fiction — HALF WRONG: true of the second (modded) unit, see Stage-0.
- Lesson kept in the open: hardware claims come from instruments, not
  memory; both GPU paths are in the config now.

## 2026-10-27 02:0x — CrystalHD package + dead endpoints

- `package/crystalhd` repointed: dead LibreELEC fork →
  crystalhd-arch/libcrystalhd v20131127; sha512 `28009f…` recorded;
  LGPL-2.1+. Stays dormant: buy ONLY BCM970012 (`14e4:1612` binds;
  BCM970015/AW-VD920 do not). Enable plan in README §9.
- Dead `git://` downloads overridden via dl/ cache only (no buildroot
  edits): intel DDX `b57abe20…` (gitlab.freedesktop.org archive),
  rtmpdump `fa8646da…` (sources.buildroot.net). Audited: no other
  selected package uses git://. Commands: README §3.

## 2026-10-27 02:2x — post-build/post-image failure chain

Each failure → root cause → fix (all committed):
1. Unselected `BR2_PACKAGE_ATV1_CLIENT` is UNSET: guard `${VAR:-}` (set -u).
2. grub2 i386-efi output path is `images/efi-part/EFI/BOOT/bootia32.efi`.
3. genimage.cfg must use genimage 9's option surface (vfat has no
   `label` → `extraargs = "-n ATV1BOOT"`; ext4 knows only `label`).
4. Era default grub.cfg hardcoded `root=/dev/sda1`; ours: sda2/sdb2/sdc2,
   `console=tty1 console=ttyS0,57600`.

## 2026-10-27 02:3x — genimage 9 host-tool whack-a-mole → phantom lesson

- `mkdosfs: not found`, then `genext2fs: not found` ×2. genimage 9's
  execl'd binaries enumerated from its source: `mkdosfs mcopy mmd
  genext2fs tune2fs dd` (jffs2/ubifs unused).
- `HOST_GENIMAGE_DEPENDENCIES +=` alone did nothing: this era only
  INSTANTIATES package rules when the package's Kconfig symbol is
  enabled → enable `BR2_PACKAGE_GENEXT2FS` (+ belt: container-build.sh
  prebuilds `host-genext2fs host-e2fsprogs host-dosfstools host-mtools`).
- `BR2_PACKAGE_GENEXT2FS` is the only era symbol (no HOST_-only form);
  the 40 KB target binary is acceptable disk-surgery kit.

## 2026-10-27 morning — Stage-0 SSH probe of unit B (decisive evidence)

Access (that host only): `ssh -oKexAlgorithms=+diffie-hellman-group1-sha1
-oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedAlgorithms=+ssh-rsa
-oCiphers=+aes256-cbc,aes128-cbc,3des-cbc frontrow@10.0.0.8` (user/pass
frontrow/frontrow; legacy ATV OS X; PATH nearly empty — use
`/bin:/usr/bin:/sbin:/usr/sbin`; `sort`/`uniq` missing → use `awk`).

Raw findings (expect scripts kept at
`/private/var/folders/.../opencode/atv-stage0*.exp`):
- `sw_vers`: Apple TV OS 10.4.7 build 8N6014 (= firmware 3.0.2, last
  official) + aTV Flash/NitoTV banner.
- `machdep.cpu.features`: `FPU VME DE PSE TSC MSR PAE MCE CX8 APIC SEP
  MTRR PGE MCA CMOV PAT CLFSH DS ACPI MMX FXSR SSE SSE2 SS TM EST TM2`
  → **SSE2 exists** (pentium4 promotion unlocked; not yet applied).
- ioreg: `display@0` = `vendor-id <de100000> device-id <d7010000>` →
  **NVIDIA `10de:01d7` GeForce Go 7300**, Apple subsystem `106b`,
  behind `IOPCI2PCIBridge` (mini-PCIe slot), Apple NVDA driver active →
  owns unit B's HDMI. Chipset all `8086:27xx` (945/ICH7).
- ioreg NIC: `device-id <39810000> vendor-id <ec100000>` → **Realtek
  `10ec:8139`** — none of the five guessed NIC drivers matched →
  `CONFIG_8139TOO=y` added (without it: no network on first boot).
- Identities: unit A stock MAC `00:23:32:33:FC:21` (no SSH; :8080 resets
  non-Safari; DAAP :3689). Unit B MAC `00:17:F2:F7:98:9D`.
- Config consequence: one image carries BOTH stacks — kernel
  i915+nouveau+TTM+8139too; X intel+nouveau+fbdev; Mesa nv40 classic DRI
  (unit B HW GL) + gallium swrast (unit A). Unit B needs forced nouveau
  screen in xstartup (roadmap) or X paints on the iGPU.

## 2026-10-27 — genimage 9 content model (ext ENOSPC)

- `genext2fs: couldn't allocate a block` in the 64 MB data image. Cause
  (from v9 source): ext images' content = `cp -a --rootpath`, and
  buildroot's genimage.sh sets `--rootpath ${TARGET_DIR}` (whole rootfs).
  Per-image mountpoints: plumbing only, no config option in v9.
- Fix: `file` handler embeds pre-built raw files (`copy=false` as-is).
  post-image.sh formats `atv1-data.ext4` (`mkfs.ext4 -F -q -L ATV1DATA
  … 65536`); genimage.cfg embeds P2 and P3 via `file` blocks. Empty ext4
  via an ext4 block is impossible in v9 — don't retry that path.
- Also noted: genimage 9 does not align partitions (P1 starts at sector 1).

## 2026-10-27 — FIRST IMAGE: built, exported, verified

- `~/ATV1/images/atv1-disk.img`, 608 MiB, sha256
  `6b0c907d5a2eed9643e1f1455d2a8bbaea68b537f1bd2aba6154089dce79a0a0`.
- `tools/verify-image.sh` ALL OK from the bytes: MBR 3 partitions, P1
  FAT (bzImage + EFI/boot/bootia32.efi + grub.cfg) bootable, P2 ext
  rootfs, P3 ATV1DATA ext4 empty (debugfs root dir 1024 B).
- The verifier found 4 bugs in itself (sfdisk `type=` vs `Id=`, mdir
  renders 8.3 names with a space not a dot, tune2fs prints lowercase
  "volume name", a clean mkfs.ext4 spends ~11% on journal so free-blocks
  is the wrong emptiness test) and 0 in the image.
- Docker Desktop note: it quit silently once mid-failure (container sat
  at exit(2) for 8 h). Check `docker ps` when a run goes quiet.

## 2026-10-27 — SMB added at OS level

- Question "does the image have SMB?" answered from the build tree: no —
  server, client tools, kernel CIFS, and even Kodi's `smb://` transport
  (gated on unselected samba4 → `-DENABLE_SMBCLIENT=OFF`) were all off.
- Owner's call: OS-level client only (coordinator owns media
  management; the TV must never serve). Changes: fragment
  `CONFIG_CIFS=y` (4.9 client speaks SMB 2.1/3.0 = what macOS serves),
  defconfig `BR2_PACKAGE_CIFS_UTILS=y`, fstab gained a commented
  credentials-file example, README §6a documents the mount. Kodi sources
  point at the mount point, not `smb://`.
- Status: committed; rebuild pending — audit merged kernel `.config` for
  `CONFIG_CIFS=y` when it lands (fragment symbols are subject to the
  same silent-drop discipline). The pinned first-good sha below is the
  pre-SMB image; record the new one after rebuild + verify.

## 2026-10-27 (evening) — SMB rebuild green; skin.atv v0.1

- SMB rebuild complete: container exit 0; audit green — merged kernel
  `.config` has `CONFIG_CIFS=y`, buildroot `.config` has
  `BR2_PACKAGE_CIFS_UTILS=y`, `/work/out/target/sbin/mount.cifs`
  present (30 KB). New image: 608 MiB, sha256
  `9a8d159860c2e4b3e3acfe082c07aa12c8c14eb5827b9e8dd795c6f59cbfe79d`
  — supersedes the pinned first-good `6b0c907d…` (pre-SMB). verify-image
  rerun on this artifact pending (skin build supersedes it anyway —
  see next entry's Status).
- skin.atv v0.1: original Kodi 17 skin, GPL-2.0-only, zero Apple
  assets — all raster generated at build time by
  `skin/skin.atv/tools/gen_assets.py` (stdlib python, py2/3-safe),
  type = DejaVu (Bitstream Vera). Every convention verified against
  the skins bundled in the built target (`skin.estuary`,
  `skin.estouchy`), not from memory: classic window file names
  (`MyVideoNav.xml` covers all video-library windows,
  `MyMusicNav.xml` the music ones), `xml/` folder via `folder="xml"`,
  bare texture names resolve from `media/`, fonts defined in
  `xml/Font.xml` with TTFs in `fonts/`, power actions are
  `Quit()`/`Reset()`/`Powerdown()`.
- Skin scope = the kiosk's real surface (home shelf, library lists,
  video info, player overlay/OSD, confirm/select/progress/subtitle/
  button-menu dialogs). Deliberately out: settings UI, text entry
  (no on-screen keyboard), file manager, PVR — the coordinator
  manages (ARCHITECTURE), ssh exists for the rest.
- Integration: defconfig + `BR2_PACKAGE_DEJAVU=y` (the package is
  `dejavu` this era — the later `ttf-dejavu` naming does not exist
  here; silent-drop trap caught by grepping `package/*/Config.in`);
  post-build.sh installs the skin to `/root/.kodi/addons/skin.atv/`,
  runs gen_assets, copies DejaVuSans(+Bold) via `find` (path varies)
  — hard-fails if either is missing; overlay gains `guisettings.xml`
  (lookandfeel.skin=skin.atv, screensaver off, mouse off) and
  `sources.xml` (video→/data/media/library, music→/data/media/music).
- Status: committed; rebuild pending. After it lands: record new sha,
  rerun `tools/verify-image.sh`, audit target tree for the skin dir +
  generated `media/*.png` + `fonts/*.ttf`.

## Current state / next

- Post-SMB image (`9a8d1598…`) ready to burn; skin rebuild will
  re-pin the sha when it lands. Next milestone: USB boot of unit A
  (README §5): answers the 32-bit EFI path, unit A NIC/GPU, SDVO
  behavior, and whether skin.atv renders on swrast at 1 GHz
  (`~/.kodi/temp/kodi.log` for skin errors). Then unit B run with
  the xstartup GPU-select (roadmap).
- Parked: pentium4 rebuild; DESIGN-LANGUAGE.md (iCraftMusic, uncommitted);
  build-client.sh glibc-claim fix; stale-copy deletion.
- Docs are four files: README (how-to), ATV1-SPECS (hardware+provenance),
  CONFIG-CHANGES (config ledger), LOG (this). Keep them current with
  every relevant commit; keep them command-grade.
