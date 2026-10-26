# ATV1 Engineering Log

Chronological record of how this tree got the way it is: decisions, evidence,
failed builds and what each one taught. **README.md is the current truth**;
this file is the history, so a future reader (or future us) never has to
re-litigate a settled question from memory. Memory got things wrong twice
here — every claim below traces to a command and its output, or a source
read.

Rule of the project applied to ourselves: **no silent success** — anything
unverified says Unknown, including the tree's own hardware claims.

---

## 2026-10-25 — Tree bootstrap

- `857198d`: br2-external tree created against **Buildroot 2017.08.x**
  (`a2493ca`, reports 2017.08.2). Era pins and their evidence live in
  README §3; the short version: Kodi **17.3-Krypton** (last release with
  CrystalHD support), Mesa **17.1.5** (nv40 classic DRI is gone in ≥ 17.3),
  grub2 i386-efi, python2 with `.py` install.
- `20c62bc`: aligned with the ARCHITECTURE doc — disk layout P1 boot.vfat /
  P2 rootfs / P3 ATV1DATA (LABEL-mounted, survives re-imaging), dev-vs-product
  boot paths, prebuilt Rust client hook (this era of Buildroot predates
  rust-package, so `atv1-client` is cross-built out-of-tree), gptfdisk +
  e2fsprogs on target for Stage-0 disk surgery.
- Tree moved to APFS at `~/ATV1`; AppleDouble junk (`._*`) ignored and
  stripped; file modes normalized (only the scripts and `S20datadirs` +x).

## 2026-10-26 — The era toolchain reality checks

- `db0378c`: **era kconfig silently drops unknown or promptless symbols** —
  `defconfig` lines can vanish with zero warnings. Fix: always audit the
  generated `.config` after `make defconfig` (a named-symbol audit list is
  the standing pattern; 23 symbols at the time).
- `2825a07`: same parser, other direction — kconfig treats space-indented
  help prose as commands. Config.in help text must be tab-indented.
- `07ed82e`: era build host containerized — `tools/Dockerfile.build`
  (Debian stretch) + `tools/container-build.sh` (idempotent; `/work` docker
  volume makes an interrupted build resume).
  `9171d42`: stretch mirrors are dead since LTS end (2025-06) — apt sources
  point at `archive.debian.org`.
- `efc9df1`: toolchain `kernel-headers` pinned to the era's 4.12, then later
  raised to match the chosen kernel (see below).

## 2026-10-27 01:1x — Kernel decisions

- `cb4773a`: retpoline disabled via fragment. **Lesson: `# CONFIG_X=n` in a
  kernel fragment disables nothing** — kconfig only honors the canonical
  `# CONFIG_X is not set` form. Proven on generated `.config`.
  `container-build.sh` gained `pipefail` the same night: without it a failing
  `make | tee` looked like success and the script reported "finished" on a
  broken build (a masked kernel `archprepare` error lied about its own
  failure).
- `d420e4a`: kernel pinned 4.13.16 believing it the last release with the
  in-tree `crystalhd` staging driver. **This was wrong and later corrected**
  (see crystalhd entry): the last kernel with in-tree crystalhd is the
  **3.16.x** series (final stable 3.16.85; deleted in 3.17).
- Final position: **kernel 4.9.337 + `BR2_KERNEL_HEADERS_4_9`** — chosen on
  era grounds, *not* pinned by crystalhd anymore, because the fleet has no
  CrystalHD card (user-confirmed; card purchase planned, see below).

## 2026-10-27 01:28 — Premise fix #1 (and why it needed a #2)

- `dbcde31`: unit on the table (stock, 10.0.0.46) has no CrystalHD card and,
  we believed, no NVIDIA GPU either → tree rewritten to GMA950 + swrast,
  "GeForce Go 7300 owns the HDMI" prose purged.
  **Half of this was right, half overcorrected** — see the Stage-0 SSH entry.
  Kept in the log deliberately: this project's failure mode was spec prose
  from memory, and this entry is the proof we only trust instruments.

## 2026-10-27 02:0x–02:1x — CrystalHD card, researched to ground truth

- `870f41e` + `356e93b`:
  - Driver history verified against v3.16.85 source: in-tree through 3.16.x,
    **deleted in 3.17**. Enable-when-card-arrives plan (in the fragment and
    README): kernel flip to 3.16.85 + headers 3.16 + `STAGING`/`CRYSTALHD`
    + re-enable the dormant package + `KODI_DEPENDENCIES += crystalhd`,
    verified via configure log.
  - **Buying constraint: the card must be a BCM970012 (BCM70012 chip, PCI
    `14e4:1612`) — the ONLY id the in-tree driver binds** (read from the
    driver's pci id table). BCM970015 / AW-VD920 cards look identical and do
    NOT work. User is buying accordingly.
  - Package source repointed from the dead LibreELEC fork to
    **crystalhd-arch/libcrystalhd v20131127**; sha512 `28009f…` verified
    against AUR and recorded in `crystalhd.hash`; license LGPL-2.1+.
    Package stays dormant until the card arrives.

## 2026-10-27 02:17 — Dead era endpoints (`dl/` overrides)

- `289837b`: two selected packages had dead `git://` upstreams; working
  archives staged in `dl/` and documented in README §2a:
  intel DDX `b57abe20` (gitlab.freedesktop.org archive), rtmpdump
  `fa8646da` (sources.buildroom.net — *buildroot.net*). Audited: no other
  selected package uses `git://`.

## 2026-10-27 02:2x — Image-assembly failure chain

Fixed one honest failure at a time (all in target-post-image / post-build):

1. `489cb7e` post-build crash: an unselected `BR2_PACKAGE_ATV1_CLIENT` is
   *unset*, not empty — guard with `${BR2_PACKAGE_ATV1_CLIENT:-}`.
2. `6f8fbc6` post-image assumed the wrong grub output path; the era grub2
   package actually emits `efi-part/EFI/BOOT/bootia32.efi`. (Era default
   grub.cfg also wrongly used `root=/dev/sda1`; ours: sda2/sdb2/sdc2,
   `console=tty1+ttyS0,57600` — README §6.)
3. `f061f59` genimage.cfg conformed to **genimage 9's real option surface**
   (era version; options added in later genimages simply fail to parse).
4. Host tools genimage 9 shells out to but never declares — enumerated from
   its own source (`execl` strings): `mkdosfs` (`mkdosfs: not found`) and
   `mcopy`/`mmd` → `BR2_PACKAGE_HOST_DOSFSTOOLS=y`,
   `BR2_PACKAGE_HOST_MTOOLS=y`.
5. `genext2fs: not found` — added `HOST_GENIMAGE_DEPENDENCIES +=
   host-genext2fs host-e2fsprogs` to external.mk (`make --eval` proved the
   append survives; external.mk is included after package/Makefile.in).
   `44535e8`.
6. **Still** `genext2fs: not found`. Root cause (`d221ec0`): *this era only
   instantiates a package's make rules when its `.config` symbol is enabled*
   — a dependency on a never-selected package is a **phantom** (the merged
   variable printed fine; variables are not rules). Fix in layers:
   `BR2_PACKAGE_GENEXT2FS=y` in defconfig (no HOST-only symbol exists this
   era; the 40 KB target binary is legitimate disk-surgery kit anyway) AND
   an explicit idempotent prebuild line in `container-build.sh`
   (`host-genext2fs host-e2fsprogs host-dosfstools host-mtools` right after
   defconfig), so post-image never depends on graph-order subtleties and a
   dead upstream fails at minute one instead of hour one.

Ops note, same night: **Docker Desktop can quit silently.** A run sat at
exit(2) for 8 hours with nobody watching; `docker ps` status is part of any
"why is it quiet" check. Containers are started `-d` with no restart policy
— after an engine restart, `docker start atv1-build`.

## 2026-10-27 morning — Stage-0 on unit B (real hardware, via SSH)

User: "10.0.0.8 running nitotv". Got in as `frontrow`/`frontrow`. That box
answered questions the docs could not. Modern OpenSSH refuses its 2007-era
server; working flags (this host ONLY, never elsewhere):

```
ssh -oKexAlgorithms=+diffie-hellman-group1-sha1 \
    -oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedAlgorithms=+ssh-rsa \
    -oCiphers=+aes256-cbc,aes128-cbc,3des-cbc frontrow@10.0.0.8
```

Its OS X shell has a nearly-empty PATH (use `/bin:/usr/bin:/sbin:/usr/sbin`;
`sort`/`uniq` are physically missing — use `awk`). Working expect scripts:
`/private/var/folders/.../opencode/atv-stage0*.exp`.

**Findings (raw evidence):**

- Banner: *aTV Flash*; `sw_vers`: Apple TV OS **10.4.7, build 8N6014**
  (= firmware 3.0.2, the last official); Darwin 8.8.2 i386.
- **CPUID (`machdep.cpu.features`): includes `SSE SSE2`** — the defconfig's
  "no SSE2 until CPUID proves it" gate is satisfied. pentium4 toolchain
  promotion unlocked; deferred to the next full rebuild (roadmap), since it
  rebuilds every package.
- **Ethernet = Realtek RTL8139**, PCI `10ec:8139` (ioreg: `device-id
  <39810000>`, `vendor-id <ec100000>`). NONE of the five "likely 2007"
  candidates (e1000/tg3/bnx2/sky2/r8169) matched. `CONFIG_8139TOO=y` added
  to the fragment; candidates stay as insurance until unit A's NIC is seen.
  Without this finding, first boot = no network on both boxes.
- **GPU: `display@0` = NVIDIA `10de:01d7` — GeForce Go 7300 (G72M)**,
  Apple subsystem (`106b`), behind an `IOPCI2PCIBridge` (expansion slot),
  Apple's NVDA driver loaded, active. It owns this unit's HDMI. The
  original README "GeForce Go 7300" spec was **true of this unit**; the
  01:28 purge overcorrected from seeing only the stock box.
- Chipset corroborates Mac1,1: Intel `8086:27xx` 945 family throughout;
  WiFi is Apple-branded Broadcom (`14e4`, subsystem `106b`).
- **Identities:** unit A = stock, MAC `00:23:32:33:FC:21` (.46, no SSH, web
  on 8080 resets non-Safari, DAAP 3689 open). Unit B = aTVFlash/NitoTV mod,
  MAC `00:17:F2:F7:98:9D` (.8).

**Config consequences (`2b18c5f`):** the fleet is heterogeneous, so the one
image carries both stacks — kernel `DRM_I915=y` + `DRM_NOUVEAU=y` (+TTM)
+`8139too`; X gets intel + nouveau + fbdev DDXs; Mesa gets nv40 classic DRI
(real hardware GL on unit B — the actual reason the Mesa era pin matters)
AND gallium swrast (unit A). Per-unit screen choice is an xstartup concern,
not a kernel one: **TODO — force the nouveau screen on unit B** (X probes
the iGPU first there and would paint on a dead output). Roadmap also carries
the pentium4 promotion and the NIC candidate prune-down after unit A is read.

What the findings buy, in one line each: 8139too prevents the worst first
debug day (no network, no SSH); the 7300 truth turns unit B from software-GL
crawling into hardware GL and keeps one image booting on both boxes; SSE2
unlocks a faster codegen pass everywhere; unit B's aTVFlash install doubles
as a reference OS on identical silicon (and both units' internal Apple OSes
stay untouched — our image lives on USB/P1-P2, nothing is a one-way door).

## 2026-10-27 — genimage 9's content model (the ENOSPC story)

Next post-image failure after the host tools were fixed: `genext2fs:
couldn't allocate a block (no free space)` on the 64 MB `ATV1DATA` image.
Read the v9 source instead of guessing:

- `collect_mountpoints()`: the root mountpoint is **`cp -a --rootpath`**
  and ext images without a mountpoint use it — i.e. an `ext4` image block
  in genimage 9 *always* receives a full copy of `--rootpath`.
- Buildroot's `support/scripts/genimage.sh` passes
  `--rootpath "${TARGET_DIR}"` — the whole rootfs staging tree. So the
  empty-data intent was asking genext2fs to pack the entire rootfs into
  64 MB. Not a size problem; a content-model problem.
- v9 has per-image mountpoint *plumbing* but no config option for it
  (dead code in this version).

Fix (era mechanism, verified in `image-file.c` + handler registration):
the **`file` handler** embeds a pre-built raw file from inputpath
(`copy = false` embeds it as-is; size = file size). So `post-image.sh`
now formats the data fs itself (`mkfs.ext4 -F -q -L ATV1DATA
atv1-data.ext4 65536` = empty ext4, 64 MiB, host e2fsprogs) and
`genimage.cfg` embeds it via `image rootfs-data.ext4 { file { name =
"atv1-data.ext4"; copy = false } }`. The rootfs partition reference is
likewise made an explicit `image rootfs.ext4 { file { copy = false } }`
(one mechanism, no undeclared-name fallbacks). `S20datadirs` fills the
partition on first boot.

## Current state (at last edit of this file)

- Build: resumed in detached container `atv1-build` with the host-tool and
  content-model fixes. Everything through rootfs + boot.vfat is stamped;
  this run is data-fs format + genimage assembly + export of
  `~/ATV1/images/atv1-disk.img`. Sentinel: background `docker wait`.
  Docker CLI note: `export PATH="$HOME/.docker/bin:$PATH"`.
- **Next milestone:** dd to a USB 2.0 stick, boot unit A (stock .46) via the
  32-bit-EFI bypass loader (ATVBootloader / ATV1sm, README §6), serial
  console 57600 8N1 if available; then the Stage-0 checklist on OUR image:
  `lspci -nn`, `ls /dev/fb*`, `dmesg | grep -iE 'i915|drm|sdvo|hdmi'`,
  `ifconfig -a` (which NIC got a link).
- Still Unknown (first boot answers all of it): unit A's NIC/GPU (inferred
  same-product, not observed), the 32-bit EFI boot path (the era's biggest
  unknown), SDVO→HDMI quirks on stock, swrast usability at 1 GHz.
- Parked: `DESIGN-LANGUAGE.md` (0.4.0-draft, uncommitted, in iCraftMusic);
  cross-build `atv1-client` via `tools/build-client.sh` (and fix its README's
  "glibc 2.24" claim — the era toolchain ships what it ships); trash the
  `ATV1.stale-copy-do-not-use` folder; pentium4 + xstartup GPU-select per
  roadmap; CrystalHD enablement when the BCM970012 card arrives.
