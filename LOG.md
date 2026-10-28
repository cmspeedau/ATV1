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

## 2026-10-27 (night) — skin rebuild failure: python2 encoding (self-inflicted, instructive)

- First skin rebuild died in post-build: python2.7 rejected
  `gen_assets.py` — "Non-ASCII character '\xe2' … no encoding declared"
  (em-dashes in comments; py3 tolerates, py2 demands PEP 263). The
  pre-commit smoke test ran on the HOST's python3 — wrong interpreter;
  production is the container's python2. Fix: `# -*- coding: utf-8 -*-`
  line 2; re-proven INSIDE the container image with python2 2.7.13
  (5 PNGs, byte-identical to py3's output).
- The failure is the design working: post-build runs `set -eu`, so a
  broken asset generator is a build error, never a skinless boot.
- Same run's audit, otherwise green: skin dir + both userdata files
  land in target; `DejaVuSans.ttf` + `DejaVuSans-Bold.ttf` present at
  `/usr/share/fonts/dejavu/`. `/export` image untouched — still
  `9a8d1598…` (pre-skin).
- Sentinel lesson: `docker wait c; echo $?` prints wait's own status,
  not the container's — the "exit: 0" above was a lie. Capture
  docker wait's STDOUT as the code.

## 2026-10-27 (night) — skin image green; burn candidate pinned

- Skin rebuild: container exit 0. New artifact: 609 MiB, sha256
  `396dce1bd4f789b3df88e601c3310180b02679340d4d068811e47540e2cd1f07`
  (supersedes post-SMB `9a8d1598…`, pre-skin).
- `tools/verify-image.sh`: ALL OK — MBR (P1 0xC bootable), P1 has
  bzImage + bootia32.efi + grub.cfg, P2 ext rootfs, P3 ATV1DATA 64 MiB
  empty.
- Deeper than the verifier (its checks stop at partition metadata):
  `debugfs` (era host bin) on the extracted P2 proves inside the IMAGE:
  `/root/.kodi/addons/skin.atv/{addon.xml,xml,media,fonts,tools}` —
  `fonts/DejaVuSans.ttf` Size 757076, `media/stage.png` Size 367;
  `/root/.kodi/userdata/{guisettings,sources,advancedsettings}.xml`.
  Skin present in the burned bytes, not just the staging dir.

## 2026-10-27 (late) — dl/ durability: Release bundle + seed script

- Motivation: the download cache — the thing that makes rebuilds work
  at all — lived in exactly one place (the docker volume), and upstream
  is already dead twice (the git:// overrides). "The internet still has
  it" is not a reproducibility story.
- Bundle: `atv1-dl.tar`, 459 MiB, 158 entries = `/work/dl` minus the
  abandoned-kernel graveyard (4.14.335, 4.13.16, 4.12.14, 4.11.12,
  4.10.17, 4.4.27, 4.9.8/30/45/65 ≈ 800 MB of dead attempts), incl.
  both dead-upstream override files. sha256
  `e555a313b36ce7936e09c0edce53dff7c5700b5ceab5a260e701a8f2fdcf328a`.
  Volume itself untouched (bundle built read-only); staged at
  `~/ATV1/images/atv1-dl.tar` (gitignored, as all artifacts).
- Release asset, not git tree: GitHub hard-blocks >100 MB per file in
  trees (linux-4.9.337 alone is 97 MB — borderline) and 459 MB would
  bloat history forever; Releases = same repo, plain URL, 2 GB/file.
  No LFS: clones without git-lfs silently get pointer files — the
  buildroot hash gate would catch it, but the failure mode is ugly.
- `tools/seed-dl.sh`: pinned sha256 gate + buildroot's own per-file
  `.hash` gate = two independent checks, nothing passes silently.
  README §3 rewritten around it; dead-override recipe kept as history.
- PENDING HUMAN HANDS: create GitHub Release, tag `dl-2017.08.2`
  (web UI — no gh CLI here), upload `~/ATV1/images/atv1-dl.tar`.
  seed-dl.sh 404s until that upload exists.
  → LANDED as tag `1` instead (name differs, content identical —
    GitHub-computed asset digest matches the pin); seed-dl.sh URL
    updated to reality. See Current state.

## 2026-10-27 (late-er) — ssh reality check: enabled-but-locked, plus a
## double-Kodi bug caught before first boot

- Question asked: "ssh enabled and password/user noted?" Evidence from
  the BUILT target, not memory:
  - dropbear IS started at boot — the buildroot 2017.08 dropbear package
    ships its own S50dropbear (provenance: dropbear.mk); runs with `-R`
    (host key regenerated every boot).
  - root's shadow is `root::` (EMPTY — deliberate: passwordless serial
    console). dropbear refuses blank passwords over ssh by default →
    as committed, ssh was enabled but NO-ONE-ELSE could log in: no
    password, no key. Not "noted" — unfixable-by-design; fixed properly:
  - fleet ed25519 keypair generated on the admin Mac
    (`~/.ssh/atv1_fleet`, private key NEVER in git); PUBLIC key baked to
    overlay `root/.ssh/authorized_keys`; post-build enforces 0700/0600
    (dropbear is picky, so are we). README §5 documents both paths:
    key login, and serial `passwd` as the no-key fallback (empty shadow
    returns on every reflash — the key is the permanent identity).
- BUG caught en route: the kodi package ALSO installs S50kodi, starting
  a second Kodi at boot racing the inittab-respawned kiosk. Masked with
  an overlay stub (overlays copy after packages; stub is a loud no-op).
- startkodi.sh header comment said "i915 deliberately absent from the
  kernel" — stale from the pre-heterogeneous-fleet era and flatly
  wrong now; rewritten to describe both units (card0=i915 on A; on B
  i915 grabs card0, 7300 is card1, X-pin = GPU-select TODO).
- Rebuild needed (overlay changed): re-pin sha after.

## 2026-10-27 (later) — root access policy: plain password, documented

- Owner's call: ssh must be PLAIN so other people can use the units,
  and the credential must be NOTED. Implemented:
  defconfig `BR2_TARGET_GENERIC_ROOT_PASSWD="frontrow"` (era mechanism
  verified in skeleton-init-common.mk + system/Config.in: plain string
  hashed at finalize by host-mkpasswd, auto-`select`ed; method md5;
  ENABLE_ROOT_LOGIN already y). Fleet key stays as the admin identity —
  password is the human door, the key is ours.
- Why "frontrow": the modded unit's established convention (SPECS) —
  one credential story across the fleet; LAN-only appliance by design
  (no off-LAN exposure is a requirement, not a suggestion). Resets on
  every re-flash — stated in README/SPECS so nobody believes it's
  durable security.
- Docs: README §5 rewritten (password-first, key second, serial same
  password); SPECS gains an "Access on OUR image" section with
  provenance tags. Serial console note: it now PROMPTS for the password
  (previously empty-shadow = no prompt).

## 2026-10-27 (evening-2) — boot beacon: headless discovery wired in

- Trigger: first-boot attempts on stock unit A show no HDMI and no LAN
  presence (expected pre-boot-chip: stock EFI offers no USB path). While
  the boot-chain question settles (ATV1sm ordering / drive-shackle
  loader route), the image now finds itself whenever it CAN boot:
  - `S60beacon` overlay init: waits for eth0 lease (120 s budget),
    writes `ATV1 UP ip=... mac=...` to /dev/kmsg (serial sees it), then
    gratuitous ARP + broadcast ping every 60 s — the unit lands in any
    LAN host's ARP table unprompted, no IP preknowledge needed.
  - Kodi JSON-RPC webserver enabled via guisettings: ids verified from
    THIS kodi.bin's strings (`services.webserver`, `services.webserverport`
    — not the Kodi 18 naming); localhost lockdown is 18+, 17 binds open.
  - busybox 1.27.2 confirmed to ship arping+ping applets (build-side
    `.config` audit — target binary won't exec on the host, don't).
- Host-side discovery commands documented in README §5.
- Rebuild DONE + verify green: burn candidate now
  `bd35e7fadad9aa3b779703d21358a706cf2b2e4b56ace08f982c22d3b668f8c2`
  (S60beacon 0755 on target, webserver settings present, verify ALL OK;
  supersedes ac2b1690… as burn candidate).
- STICK FORENSICS: user's stick read back `56c5c946…` ≠ ac2b1690 ⇒
  that stick was BAD BYTES. Every unit-A boot conclusion drawn with it
  is VOID — re-burn from bd35e7fa, verify, THEN test boot.
- SPECS correction (owner challenge): rear USB 2.0 host port EXISTS
  (Apple archived tech specs, 2008-12 capture; photo-import port; the
  era patchstick entry). My "no external USB" claim was wrong.
  Strategy fact recorded: stock EFI blesses Apple-SIGNED boot.efi
  chains regardless of disk format ⇒ the MBR+bootia32 stick can never
  stock-boot on any era; the signed-boot.efi restore-layout image is
  the only stick shape with a chance (era-leniency lottery — read
  unit A's Settings → Version).

## Current state / next

- Burn candidate `ac2b1690…` (skin + ssh access + masked package-Kodi
  + root/frontrow): verify-image ALL OK, and debugfs inside P2 confirms
  from the image bytes — `$1$` shadow, fleet `authorized_keys`, masked
  `S50kodi`, auto-start `S50dropbear`. ssh = `root`/`frontrow` (plain
  by design, README §5 + SPECS), fleet key = admin identity; serial
  console same password (now prompts). dl bundle is LIVE: GitHub
  Release tag `1` (uploaded as `1`, not the planned `dl-2017.08.2` —
  seed-dl.sh URL follows reality; HEAD 200 @ 481,566,720 B, GitHub's own
  asset digest = the pinned sha, `tools/seed-dl.sh` green end-to-end).
  Next milestone: USB boot of
  unit A (README §5): answers the 32-bit EFI path, unit A NIC/GPU,
  SDVO behavior, and whether skin.atv renders on swrast at 1 GHz
  (`~/.kodi/temp/kodi.log` for skin errors). Then unit B run with
  the xstartup GPU-select (roadmap).
- Parked: pentium4 rebuild; DESIGN-LANGUAGE.md (iCraftMusic, uncommitted);
  build-client.sh glibc-claim fix; stale-copy deletion.
- Docs are four files: README (how-to), ATV1-SPECS (hardware+provenance),
  CONFIG-CHANGES (config ledger), LOG (this). Keep them current with
  every relevant commit; keep them command-grade.

## 2026-10-27 (late) — restore-layout disk: the fw-3 boot path BUILT

- Owner read unit A Settings → Version: firmware 3. Not a dead end:
  fw 3 closed USB *boot-selection* but never closed the *recovery scan*
  (restore had to keep working) — that scan is what atv-linux-loader
  rides, and its working examples run on exactly this era.
- atvrecv GUID VERIFIED from source, not memory: GNU parted 3.6
  libparted/labels/gpt.c `PARTITION_APPLE_TV_RECOVERY_GUID`
  = **5265636F-7665-11AA-AA11-00306543ECAC** ("Reco"+"ve", Apple OUI).
  Memory candidate 426F6F74-… = Apple *Boot* type — wrong partition
  type, never burned. (Source fetch saga: gparted delegates to
  libparted; gitlab raw 406s; ftp.gnu.org tarball → labels/gpt.c.)
- boot.efi: mesu DMG downloaded (sha1 97623d8d… = loader-README pin ✓),
  hdiutil-mounted, extracted `OSBoot/System/Library/CoreServices/boot.efi`
  → sha256 `c7f57cc2b37af75597419b0bd2b88b357d2a6f696ce30749a073a0eba25fee40`
  (298,800 B). Stays in images/ (gitignored) — Apple binary never enters
  the repo; build script re-checks the sha at assemble time.
- DummyKext 1.0 + atv-linux-loader cloned (MIT). `make KERNEL=bzImage
  INITRAMFS=atv1-initrd.cpio.gz` (clang --target=i386-apple-darwin8,
  CLT ld) → mach_kernel 7,899,048 B, both stages proven in the bytes.
- initramfs: board/atv1/initramfs-init (busybox hardlinks: sh/mount/
  blkid/switch_root/mknod…; root=LABEL→device poll 60 s; switch_root;
  serial-sh fallback on failure) packed by tools/mkcpio-newc.py
  (deterministic newc; era container's target cpio is unrunnable i386).
- GPT: tools/atvrecv_gpt.py (no brew/gdisk on host; stdlib-only,
  deterministic). THREE bugs it took real parsers to catch: entry field
  order (attrs precedes first_lba — spec says after last_lba); missing
  NumberOfPartitionEntries+SizeOfPartitionEntry header fields (macOS
  read "entry size 0" → zero partitions); both invisible to my own
  CRC self-audit (my CRC covered my own wrong layout). Standing rule:
  GPT is only "valid" per an independent parser. Final image parses
  clean in macOS `gpt -r show` (all 3 slices + GUIDs) and its P1 FAT
  mounts via macOS's own driver (boot.efi sha re-checked through the
  mount ✓, Dummy.kext + plist readable ✓).
- post-image.sh now `tune2fs -L ATV1ROOT` on rootfs.ext4 before genimage
  (LABEL-root is bus-independent: stick lands sdb2 behind the internal
  sda; internal boot = sda2). Lesson re-learned the hard way:
  standalone post-image reruns must (a) rsync repo→/work/atv1 first and
  (b) set BINARIES_DIR+BUILD_DIR+TARGET_DIR+host bin/sbin PATH — one
  skipped-sync run produced a mislabeled image that verify caught
  (label: <none>) before it could burn.
- Burn candidates (supersede bd35e7fa / cdd4269c):
  MBR  atv1-disk.img      `1049f792948f4041e550e62b6e7bcc5bd87dc96e661a24bb495de5390b2ed597` (1,245,185 sect)
  GPT  atv1-recv-disk.img `7d3c46810d48d6e5d55752aac6937716b4c59966d062e4f16c8eca56ce6d1135` (1,312,802 sect = 641 MiB)
- README §5 rewritten (signature-wall truth, door #1 rear-USB restore
  stick + read-back verify one-liner, door #2 internal); §6 SATA→PATA
  corrected there too. One-liner caveat: backup GPT at image tail may
  make macOS/Linux offer repair — refuse; primary GPT is authoritative.
- BURN FORENSICS 2 (owner session): first two read-backs hashed
  e3b0c442… (the EMPTY-STRING sha) — dd never opened a device
  (`if=` empty / stderr suppressed by MY one-liner; `dd: no value
  specified for if` was the tell). Lesson pinned: forensic reads must
  NEVER carry 2>/dev/null and must show "N+0 records out".
- BURN PROVEN WITHOUT SUDO: diskutil shows disk2 = our GPT exactly —
  s1 Apple_Recovery(=5265636F GUID mapped) 64Mi @ offset 1048576,
  s2 512Mi, s3 64Mi, plus my builder's partition-UUID fingerprint
  00000001-0000-5641-… → the stick IS atv1-recv-disk.img. Finder/
  Disk Utility "not an image" complaint = UDIF-only format gate,
  raw dumps (any dd image) never open there; Disk Utility Restore
  would also rebuild the map and erase the atvrecv GUID — raw
  writers (dd/Etcher) are the only correct burn tools for this disk.

## 2026-10-27 16:x — first restore-stick boot: logo→pink→silence; ROOT CAUSE = no DHCP stanza (mine)

- Owner test (stick burned from 7d3c4681 — burn itself PROVEN good via
  diskutil partition read, see above): grey Apple logo → PINK screen →
  no network trace. Grey logo = recovery scan ate the stick and boot.efi
  chainloaded mach_kernel: the entire boot-chain premise WORKS.
- MY FALSE ALARM, retracted same hour: "kernel has no NIC driver" was
  based on a head-truncated grep + a .ko find for a BUILT-IN driver;
  CONFIG_8139TOO=y is in .config and baked in. Violated our own rule;
  retraction logged so the claim can't haunt the tree.
- REAL ROOT CAUSE (found in files, no hardware needed): the rootfs
  /etc/network/interfaces was the buildroot skeleton = LOOPBACK ONLY.
  eth0 was never configured → no lease → S60beacon's 120-s wait expired
  → exit → total silence from a possibly-healthy box. The beacon was
  unmissable by design and impossible to hear by omission. (The pink
  screen may literally have been working Kodi.)
- FIX (beacon2): (1) overlay interfaces gains `auto eth0 / dhcp`;
  (2) S60beacon waits FOREVER (fixed timeout = false death);
  (3) INITRAMFS beacon: background udhcpc(-n -q) + manual ifconfig +
    gratuitous ARP loop BEFORE root handover → stage telemetry:
    MAC seen + :8080 dead = stuck at initramfs; MAC seen + :8080 live =
    fully booted; MAC absent = pre-initramfs death. Applets verified in
    the built cpio by extraction on the host (16 links incl.
    udhcpc/arping/ping/route/ifconfig).
- Burn candidates (beacon2; supersede 1049f792 / 7d3c4681): MBR
  c3ca5b94ba08f7e1f58aac773bcadb29d66d8b95d94d5fc3effc6e98dd85d920 and
  GPT atv1-recv-disk.img 23b1e4afb5d24c1468b89e53c9a2215b219f2eac2a8e98bc4db098bafec5c2fa
  (1,312,802 sectors; verify-image ALL OK incl. ATV1ROOT label).
- Process lessons pinned: no `2>/dev/null` on forensic reads (twice);
  standalone post-image needs rsync+O=/work/out+host PATH; read
  fragments AND .config AND the shipped rootfs, not one of them.

## 2026-10-27 17:x — INCIDENT: restore image dd'd onto the wrong disk (owner's 2TB Passport)

- The re-burn command named /dev/rdisk2 from a listing read ~an hour
  earlier; between then and execution the USB disks renumbered (stick
  30.8G -> disk4, Passport 2T -> disk2). 672 MB of atv1-recv-disk.img
  landed at the HEAD of "My Passport 0827", destroying its primary GPT
  and the first 672 MB of its first volume (EXT DATA). Proof: disk2 now
  reports our builder fingerprint UUID 00000001-0000-5641-… on s1.
  Cause: mine — violated the re-enumerate-before-every-dd rule myself.
- Damage model: backup GPT at the 2 TB drive's END survived (dd covered
  only the first 672 MB). `sudo gpt recover /dev/rdisk2` should restore
  the map; Projects (HFS+ at ~1.9 TB) expected fully alive; EXT DATA
  head structures gone — content beyond 672 MB intact, recovery via
  DMDE/R-Studio class if needed. Passport parked until recovery.
- RULE (pinned, non-negotiable): every dd block in chat/README lists
  `diskutil list external` + a `diskutil info | grep "Disk Size"` guard
  in the SAME paste as the dd; target size must match the media being
  burned (30-ish GB for stick tests). Never carry a diskN across messages.
- Consequence for the boot test: the STICK still holds the OLD mute
  image (7d3c4681); the beacon2 image (23b1e4af) has never been on
  hardware. Re-burn disk4 with the guard, then run the boot test.

## 2026-10-27 17:4x — root cause #2 FOUND in loader arithmetic + log-anywhere plumbing

- Forensics on bzImage vs loader source (linux.c): loader computes payload at
  (setup_sects+1)*512 = 15872; OUR kernel's authoritative payload_offset
  field (setup_header +0x57, read per bootparam.h in-tree) = 128 → real
  payload at 16000 (gzip magic verified there). EFI-stub section between
  setup and payload ⇒ legacy arithmetic lands 128 B early ⇒ jump into stub
  tail ⇒ instant death. Explains logo→pink→silence EXACTLY. Debian images
  the loader author tested apparently align differently — our kernel
  doesn't. Fix: tools/patches/atv-loader-payload-offset.patch (MIT vendor
  tree; honored automatically by make-atvrecv-disk.sh stage 2 tripwire).
- Console visibility while at it: kernel fragment += CONFIG_FB +
  CONFIG_FB_EFI (efifb takes the boot.efi framebuffer the loader hands
  over via screen_info); plist adds console=tty0. Pink should become
  readable text once the payload fix lands.
- LOG ANYWHERE (owner ask "output to a log file"), two channels:
  1) initramfs save_console(): dumps kernel ring to the ATVRECV FAT
     partition (/atv1-kmsg.txt) before handover AND on both fatal paths.
  2) S61logdump (rootfs): mounts ATVRECV at /boot, rewrites
     /boot/atv1-kmsg.txt every 20 s + copies kodi.log to
     /boot/atv1-kodi.log. Pull stick → read on Mac. Network-free,
     serial-free, HDMI-independent.
  Plus (existing): ssh fleet key once IP known = full journal/dmesg.
- Candidates (fix+logs build): MBR db8c3d35…; GPT atv1-recv-disk.img
  d4dacb31b14a3a10ed2f4893e0fa6f930393f8d6e17d2801281155d3462d63ce
  (mach_kernel 25cddafa…, initrd a50429e4…). verify-image ALL OK.

## 2026-10-27 18:4x — stick-forensics verdict + STALE-OBJECT TRAP found (retread of "rebuilt")

- Boot test 2 forensics (owner-extracted P1, read via hdiutil — macOS FAT
  driver still refuses mtools FSInfo): atv1-kmsg.txt ABSENT through a
  proven-working mount ⇒ death BEFORE /init. Burn integrity re-proven at
  file level (FAT mach_kernel sha == build 25cddafa; plist correct).
- Recorder was itself broken: initrd applet list lacked dmesg AND sync
  (verified by extracting the built cpio: 16 links, no dmesg). Even a
  living kernel would have logged a stub, not the ring. FIXED: dmesg+sync
  added to stage 1 list.
- kconfig truth: CONFIG_FB is SELECTed by DRM (drivers/gpu/drm/Kconfig:45)
  — no fragment can remove it; it was =y in ALL builds incl. the booting
  era. The ONLY real kernel diff in the failed build was CONFIG_FB_EFI
  (+plist console=tty0). efifb probe is the death-site suspect (binds
  boot.efi's framebuffer via screen_info after initcalls, before /init).
- STALE-OBJECT TRAP (the big one): loader Makefile has `%.o: %.c` with NO
  dep on kernel_bin.h/initramfs_bin.h → header regeneration did NOT
  recompile linux.o → every make-atvrecv-disk re-run after the f8 round
  RELINKED STALE linux.o. f8d41b9c→d4dacb31→(afe0cd8f) all carried the
  SAME mach_kernel bytes 25cddafa. RETRACT: "d4dacb31 rebuilt the kernel
  blob" — it relinked the old one. FIX: stage 2 now rm -f *.o. Content
  proof chain now mandatory (embedded-bzImage byte-compare, below).
- Boot-2 content proof: decompressed the burned vmlinux (zlib wbits=31)
  — efifb symbols PRESENT (14) ⇒ the FB_EFI kernel DID run on hardware
  and died pre-init. Suspect stands on proof, not inference.
- Experiment build (FB_EFI OFF via canonical "# CONFIG_FB_EFI is not
  set" + recorder + panic=5 panic_on_oops=1, console=tty0 dropped):
  recv ab6c65c2e540ad6c930188d2382e87b0724184f18e0f7574c502ea371949f56f
  (1312802 sect). mach_kernel bb70e9b4… CONTENT-PROVEN: embedded bzImage
  (a12906fb…, 7,518,448 B, FB_EFI OFF) and initrd (9df2383b… w/ dmesg+
  sync) byte-identical to build outputs inside it. MBR atv1-disk.img
  56f345dd… (grub path, new kernel too).
- OUTCOMES: beacon/stick-log ⇒ kernel booted (efifb convicted; re-add
  later with correct screen_info handling). Visible 5 s reboot cycle ⇒
  kernel panics pre-init, panic=5 caught it — next suspect is generic
  early kernel. Identical frozen logo ⇒ efifb CLEARED; suspect moves to
  first-run generic early kernel / loader bp handoff.

## 2026-10-27 19:1x — boot test 3: panic CYCLE observed (kernel finally executes) -> environment-sanitized burn

- Owner saw grey logo -> black -> grey logo = panic + panic=5 reboot cycle.
  First time the kernel RUNS on this hardware (payload fix proven live at
  boot, not just in bytes). FB_EFI formally off suspect list (absent from
  running image, content-proven bb70e9b4 burn).
- Stick #3 extraction: still NO atv1-kmsg.txt. Two consistent worlds:
  W1 = early panic <~10s (ACPI/e820/EFI handoff paths); W2 = kernel
  reached /init but PCI layer dead (no /dev/sd* => save_console silent,
  no NIC => no beacon, 60s root-hunt fails -> exec sh -> kill-init panic
  -> cycle at ~65s). One dead PCI subsystem explains all three silences;
  2007 EFI firmware + ACPI-driven probing is the classic landmine.
  DISCRIMINATOR: cycle interval (asked owner: seconds vs ~minute).
- Loader source audit: e820 converter = textbook (real desc size, sane
  types, merge logic); bp memset+selective fill; initrd at
  kernel_base+kernel_size, kernel above it, no self-overlap;
  ramdisk_image/size 32-bit fields set. No smoking gun in source.
- Burn #4 = flags-only change (mach_kernel byte-identical bb70e9b4):
  acpi=off noapic noefi mem=256M added to Kernel Flags. If it boots ->
  bisect one flag per burn to name the culprit. If it still cycles fast
  -> W1 hardens: suspect loader bp handoff deeper (heap/end_of_kexec,
  xloadflags, type_of_loader) + try early initcall audit.
  Candidate: d8dfebabdb8cffb5fbd3bfa3cb83f49534f07e0be544ae95d876a2381b183cfa

## 2026-10-27 19:5x — boot-4 forensics + TWO reader false-alarms (mine) + synthetic-e82amap burn

- Boot-4 (d8dfebab, flags acpi=off noapic noefi mem=256M): stick re-extract
  initially showed the OLD 663-B plist -> "flags never tested" — FALSE
  ALARM. Cause: STALE hdiutil mount of the previous image serving the
  same /Volumes/ATVRECV path (07:45 mtimes gave it away) + owner's 19:53
  extraction TRUNCATED (42.7/64 MiB, read stopped mid-partition). Raw
  grep on the extraction bytes + fresh mount on a fresh copy: NEW plist
  WAS on the stick (694 B, 08:11, all four flags). Boot-4 was the real
  build; verdict stands:
- VERDICT: sanitized environment did NOT save the kernel — still pre-init
  fast death, no atv1-kmsg.txt. e820 QUALITY remains live (mem= shrinks
  the map, does not replace it).
- Burn #5 = synthetic map: memmap=exactmap memmap=256M@0 replaces the
  boot.efi→e820 conversion entirely (that conversion has never run
  against a live kernel). Flags-only change; mach_kernel unchanged
  bb70e9b4; image-internal FAT verified by bytes (mount-independent).
  Candidate: 7c74002437aa424abfa9ea74fcfa4c5bf46f0e59dd5f991ea727e30ebebba63b
- Reader discipline update (mine): every hdiutil read starts with detach-
  by-path + fresh copy + unique mountpoint; every extraction must verify
  size 67108864 before mount; stderr on dd/cmp never suppressed.

## 2026-10-27 20:4x — boot-5: SYNTHETIC MAP REMOVED THE PANIC (hang replaces cycle) -> GPU-initcall suspect

- Boot-5 (7c740024, memmap=exactmap memmap=256M@0): owner observed
  FROZEN LOGO with NO ~5s reboot cycle — panic=5 armed, so: no panic.
  Full-size clean stick extraction: still NO atv1-kmsg.txt; plist 715 B
  confirms real build ran. => kernel survives memory setup now (boot.efi
  map proven poison for 3-4's fast deaths) but hangs BEFORE /init and
  before any network/storage visible effect.
- Suspect #1 now = device initcalls (run after memory init, before init):
  GMA950 was POSTed by EFI GOP, never by legacy VGA ROM; 4.9 i915/nouveau
  register-wait behavior against an engine it doesn't expect = classic
  no-panic hang. Fits every silence (no log, no beacon, no panic).
- Boot-6 = a57dc710… (flags-only, mach_kernel unchanged bb70e9b4): adds
  nomodeset + initcall_blacklist=i915_init,nouveau_drm_init. NAMES
  VERIFIED IN 4.9 SOURCE: module_init(i915_init) in i915_pci.c:513;
  module_init(nouveau_drm_init) in nouveau_drm.c:1132 (NOT nouveau_init —
  the naive guess would have been a silent no-op).
  If base system lives: ssh in, dmesg tells us the GPU story from a live
  box; GPU becomes a tracked bug, boot pipeline advances.

## 2026-10-27 21:1x — boot-6 verdict (GPU alone not sufficient) + boot-7: ROM-hole map fix + SCREAMING init

- Boot-6 (a57dc710, GPU initcalls blacklisted): frozen logo again, no
  panic cycle, no beacon, stick re-extract (full-size, fresh build
  confirmed, plist 771 B): STILL no atv1-kmsg.txt. GPU blacklisting
  alone did not restore the network/init. Suspect space now: (a) hung
  pre-init anyway (my own map flaw below is a live mechanism), or
  (b) init ran but block/USB layer never appeared (save_console blind,
  silent exec-sh fallback forever-frozen). Untestable-as-designed —
  fixed in this build.
- OWN BUG FOUND: memmap=exactmap memmap=256M@0 marks the legacy BIOS
  ROM shadow (0xA0000-0xFFFFF) as usable RAM. Allocator handing out
  ROM-backed pages = classic no-panic early hang; my synthetic map
  carried a real defect while serving as the experiment. boot-7 map:
  memmap=640K@0 + memmap=255M@1M (era-correct, hole excluded).
- SCREAMING INIT (board/atv1/initramfs-init rewrite):
  * proc+sysfs mounted at init start
  * save_console NOW logs dmesg + /proc/partitions + /sys/block +
    /sys/class/net, called at init START and every 10 s of a 30 s hunt
    (log appearing = init alive; timestamps/growth = which device-
    world existed)
  * fatal paths -> scream_reboot(): sysrq 'b' hard reboot. NEW SIGNAL
    ALPHABET: reboot cycle at ~35-40 s = INIT RAN, hunt failed
    (device layer dead, and the stick will carry the inventory dump
    IF any block device ever appeared); FOREVER-FROZEN = hung before
    init (next blacklist round: PCI/USB initcalls).
- Candidate: 9e5ca4972eab316a34030eaed148a6a3484c2fb7d7ef26c29cd9ce0d13b05539
  (mach_kernel 4eb7be8a NEW — initrd changed as intended; FAT flags
  image-internal verified).

## 2026-10-28 — external review integrated: udhcpc EVENT-SCRIPT fix, and the awk/cut trap the review walked into

- External review (claud) of boot failures + udhcpc change, cross-checked
  against instruments:
  * CORRECT and adopted: initramfs beacon parsed udhcpc STDOUT for
    ip=/router= text. BusyBox's contract is the -s EVENT SCRIPT (env:
    interface/ip/subnet/router); stdout is no promise, and this cpio
    ships no default.script => the old beacon could hold a real lease
    and still report nothing. New board/atv1/udhcpc.script (bound/
    renew/deconfig) packed into initrd, wired via -s. Telemetry-only:
    cannot cause/mask the pre-init question.
  * REJECTED after binary check: review's make-script adds awk+cut
    applet links and its scripts USE awk/cut. strings on the era
    busybox: awk=0 cut=0 — the applets are NOT in this build; the
    links would be dead and the beacon would silently eval empty
    even on a working DHCP. (My own boot-7 beacon had the same awk
    dependency — also fixed.) Rule: initramfs scripts are POSIX-ash
    + verified-applet-ONLY (sh ash mount umount mkdir sleep cat blkid
    switch_root ls mknod ifconfig udhcpc arping ping route dmesg
    sync). IP/MAC now parsed by shell token loops.
  * Build-note trap logged: an apostrophe inside the docker single-
    quoted sh -c string broke stage 1 parsing — build scripts must
    avoid apostrophes inside inner single-quoted blocks.
- Boot-7b candidate 090e3c5e96f6d83973e8fbd10c5b83174d836876debdcd31390f9134eed464c3
  (mach_kernel 8ff54bc3; initrd content-verified: udhcpc.script PRESENT,
  awk/cut links 0, beacon uses -s, scream_reboot intact; FAT flags ==
  boot-7 exactly: exactmap 640K@0+255M@1M, nomodeset, blacklist).
  boot-7 proper (9e5ca497) never burned: 7b supersedes it (same
  discriminator + working telemetry; boot-7 outcome unknowable but
  moot).

## 2026-10-28 — boot-7b = pre-init hang CONFIRMED (3-min test) -> probe #A: USB initcalls blacklisted

- 7b burned byte-perfect (090e3c5e verified), boot result: grey logo
  FROZEN; 3-minute powered test: still frozen, NO scream cycle, no log,
  no beacon. With corrected synthetic map + GPU off + acpi/noapic/noefi:
  death is BEFORE /init and is a HANG, not a fault (panic=5 silent).
- Cleared by counterfactual: paging-state theory (boots #3/#4 ran the
  timer path under boot.efi's paging state -> head_32 survives it).
- Front suspect: 2007 Intel USB legacy/SMM emulation colliding with
  Linux HCD reset (system-wide deadlock, no fault, frozen logo — era
  classic; ICH6-era firmware + UHCI/EHCI built-ins).
- PROBE #A = ba0a6634af7923d732becda848b53171f16a2352c4ca7d14684c96a40ae6163c
  (flags-only; mach_kernel UNCHANGED 8ff54bc3). All USB initcalls, names
  VERIFIED in-tree (lesson applied): usb_init (subsys), uhci_hcd_init,
  ehci_hcd_init, ehci_pci_init, ohci_hcd_mod_init, ohci_pci_init.
  ALGEBRA: cycle@~50s (+beacon race 15-25s) => init runs => USB initcall
  layer convicted. Frozen past 3 min => USB cleared too; next layer =
  ata_piix/PCI-probing class, same method.

## 2026-10-28 — STATE: probe #A delivered, awaiting burn+boot (nothing pending in repo)

- Probe #A candidate ba0a6634af7923d732becda848b53171f16a2352c4ca7d14684c96a40ae6163c
  built, image-internal FAT flag-verified, README expect-line re-pinned,
  pushed (00add83). NOT yet burned or booted as of this entry — no
  result claimed.
- Burn+boot protocol handed to owner: self-discovering gate block
  (find 30.8 GB disk at exec time, size-gate <100 GB, dd, readback
  1312802 sectors), then POWER ON + 3 FULL MINUTES EYES ON CLOCK.
  This probe CANNOT boot rootfs by design (root is USB, blacklisted):
  its success signal is BEACON ~15-25 s and/or SCREAM-CYCLE ~50 s
  (= init runs = USB initcall layer convicted -> pivot to internal-IDE
  install path). Frozen past 3 min = USB cleared -> probe #B targets
  ata_piix-class initcalls (names to be verified in-tree first).
- Housekeeping: stale ARP watcher from boot-7b round cancelled by owner
  (expected; that boot's datum already recorded). Fresh watcher arms at
  "hash pasted + powering on".
- Standing rules reaffirmed tonight, all in force: verified applet
  names + verified initcall names before they enter a script/cmdline;
  size-gated self-discovering dd everywhere; hdiutil reads = detach +
  fresh copy + unique mountpoint; no stderr suppression on forensic
  dd/cmp; apostrophe-free inner single-quoted blocks; every candidate
  ships with content-proof (embedded-bytes compare) not timestamps.

## 2026-10-28 — probe #A answered (USB CLEARED) -> probe #B: i8042_init blacklisted (SMM-emulated 8042 theory)

- Probe #A (ba0a6634) burned byte-perfect, booted, 3-min test: FROZEN,
  no beacon, no cycle. => USB initcall layer is NOT the pre-init hang.
- Sharpened theory: 2007 Apple firmware's USB LEGACY EMULATION lives in
  an SMM-driven *emulated 8042 controller* (firmware polls USB HID and
  feeds i8042 registers). The kernel's i8042 controller test/reset/
  handshake pokes the same emulated registers -> deadlock class identical
  to the USB-SMM theory but EARLIER, which explains why probe #A changed
  nothing. i8042_init verified: drivers/input/serio/i8042.c:1643
  module_init(i8042_init), SERIO_I8042=y.
- Blacklist ALGEBRA (cumulative is rigorous here): #A exonerated the
  USB set; therefore if scream-cycle (~50s) appears WITH i8042_init
  additionally blacklisted, the difference set convicts i8042 alone.
  Frozen past 3 min => i8042 cleared; next: snd_hda_intel (firmware
  boot-chime shares HDA), then ata_piix class.
- Probe #B candidate 86b8c1c33f9c48a52ff0aaccba5e150e2abe04fcf558752d9ea4eea5bb222ae8
  (flags-only; mach_kernel unchanged
  8ff54bc3; only difference from #A = +i8042_init in blacklist).

## 2026-10-28 — CONVICTION: i8042_init is the nine-boot hang (probe #B scream, 60-70 s period)

- Probe #B (86b8c1c3): screen CYCLE with 60-70 s period = scream_reboot
  path (init + 30 s hunt + sysrq b). init RAN. Combined with probe #A
  (frozen with USB blacklisted): difference set = {i8042_init} => the
  kernel's i8042 controller handshake against the firmware's
  SMM-emulated 8042 (Apple USB legacy emulation) was THE pre-init
  hang. First behavioral conviction of the project; kernel+init are
  PROVEN ALIVE on unit A silicon via this loader path.
- VICTORY-LAP boot #8 = 8443465b360ae668fce85f165a0fd3e1a79a0de5da83d035f79c6fe78be5b9a6
  (flags-only; mach_kernel unchanged 8ff54bc3): USB six-name blacklist
  REMOVED (root must enumerate to mount), blacklist now
  i915_init,nouveau_drm_init,i8042_init. Everything else identical.
  OUTCOME ALGEBRA (all branches readable):
    ssh/beacon + no cycle      => full boot; GPU+i8042 remain the only
                                  disabled subsystems (Kodi dark until
                                  DRM debug from a live shell)
    scream-cycle returns       => USB initcall side ALSO collides with
                                  SMM (legacy emulation polls the HC);
                                  pivot: un-blacklist uhci-only next,
                                  and/or internal-IDE install path
    frozen > 3 min             => new third class; re-probe from here
- Permanent-fleet note (to resolve post-boot): the i8042 blacklist is
  likely RIGHT for the whole fleet (same era firmware on unit B too);
  revisit only for a real PS/2 need, which the hardware lacks.

## 2026-10-28 — external consolidated review received: lags current evidence; recommendations already in force

- Review's knowledge horizon = LOG.md at boot-7 CANDIDATE DEFINITION
  (line 628). It therefore misses four later hardware events recorded
  here since: boot-7b (3-min frozen => map-hole fix alone did NOT
  resolve), probe #A (USB initcalls cleared at 3 min), probe #B
  (SCREAM CYCLE 60-70 s => i8042_init convicted by difference set),
  and boot-#8 build 8443465b (USB restored, blacklist = GPU + i8042).
- Its "best hypothesis" (ROM-shadow hole in the 256M@0 synthetic map)
  is now PARTIALLY REFUTED by evidence: boot-7b ran the hole-free map
  and still froze; the hole was real but not the hang. The convicted
  mechanism (SMM-emulated i8042 handshake) was listed by the review
  only as one of several unranked "PCI/USB/initcall + loader handoff"
  directions. No repo action from the review.
- All five of its recommended practices are ALREADY the standing rules
  logged tonight (re-enumerate+size-gate every dd; candidate-specific
  fresh extractions; inventory-guided device triage; one-variable
  initcall probes with verified names; build-content proof gates +
  loader *.o clean). Its udhcpc-callback proposal was integrated
  earlier (with the awk/cut applet rejection — review's snapshot
  pre-dates that correction too).

## 2026-10-28 — Community EFI reference research (owner request): references EXIST; one documented ATV1 firmware bug we have never applied; new top hypothesis

### References found (all public, all verified online today)
1. davilla/atv-bootloader (GitHub mirror of code.google.com/p/atv-bootloader, GPL-2.0,
   Mar 2008, Scott Davilla; lineage: Edgar "gimli" Hucek mach_linux_boot -> James
   McKenzie mb_boot_tv -> atv-bootloader). SAME TRICK AS OURS: embeds kernel+initrd
   in a Mach-O "mach_kernel" that boot.efi loads. Files that matter to us:
   - linux_code.c :: quirk_fixup_efi_memmap(), dated note 2007-11-26: "The appletv
     efi firmware has a bug that effects linux kernel when booting from efi. Three
     EFI RunTime Services Code/Data segments overlap a declared free memory
     segment. This can cause code/data overwrites and result in unknown
     crashes/hangs when running linux." Their fix: trim the free segment that
     overlaps RT_CODE/RT_DATA, plus a hard split of the segment containing
     0x025AE000 (rationale unclear - possibly self-layout-specific; port with care).
   - linux_code.c :: fill_e820map(): actual-EFI-map -> E820 converter (same
     textbook algorithm our loader e820.c carries).
   - boot_loader.c header: a REAL captured ATV1 EFI memmap (mem00..mem09, RAM top
     0x10000000, mach_kernel loads 0x02000000) + notes incl. "PCI: BIOS Bug: MCFG
     area at f0000000 is not E820-reserved".
   - README: "some installers ... assuming a video bios (it's hiding in the AppleTV),
     these will hang and do bad things" - era corroboration of our legacy-probe
     hang class; they used vesafb off the boot.efi linear framebuffer, no VGA BIOS.
   - Issue #4 (filed 2008, era): USB devices DO enumerate under Linux on this
     hardware (pen drives immediately; USB hard drives needed a +5s rcS delay
     before scanning /proc/partitions). => stick-invisible-to-Linux is NOT a
     firmware law - era kernels (2.6.24-ish) booted USB roots on fw-current ATVs.
     Era corpus: penubuntu/XBMC-Live USB boots, kexec-style second-stage patterns.
2. DistroHopper39B/ATV1sm (2025): replaces the Mach-O inside Apple Service
   Diagnostics (ASD.acm/Contents/MacOS/ASD - executed UNsigned by the signed ASD
   path, offsets figured by Rairii/Wack0) to gain code execution WITH EFI BOOT
   SERVICES, then hooks LoadImage/StartImage/UnloadImage/Exit (OpenCore-derived)
   to lift the EFI signature lock. Result: rEFInd "works perfectly", GRUB2/
   NetBSD-10.1 boot+install+run (incl. from USB), GopShimDxe adds GOP video.
   Fleet-risk notes logged: (a) Apple IA32-EFI memory-map bug can SOFT-BRICK
   (NVRAM) on some OS loads - their protocol is a PRAM reset (CMOS battery out +
   cmd-opt-p-r); (b) Alpine via ATV1sm sees 194 MB RAM vs 212 MB via boot.efi
   path; (c) author calls it non-reference quality; (d) requires a mediafire-hosted
   ASD disk image - supply-chain hazard for a fleet; do not adopt casually.
3. CSMWrap/SeaBIOS: DEAD on ATV1 by their own test - firmware lacks the PCI I/O
   protocol -> VGA arbitration broken. Confirms only two EFI paths exist on this
   machine: boot.efi-payload (our path) or the ATV1sm boot-services bypass.
4. Era docs for the install path: Kodi wiki "Archive:HOW-TO:Install Gentoo and
   XBMC on Apple TV 1" (internal PATA install procedure, credits atv-bootloader),
   ReactOS wiki Apple TV (1st gen) page, xbmc-boxee-iview archive wiki (Ubuntu 9.10).

### Synthesis -> NEW TOP HYPOTHESIS (explains two unrelated-looking failures)
- The community-documented firmware map bug is an OVERLAP: RT_CODE/RT_DATA segments
  (firmware code+data, low in the first 256 MB) alias into a segment declared free.
- Our CURRENT synthetic map (memmap=exactmap 640K@0 + 255M@1M) declares the ENTIRE
  first 256 MB as RAM - INCLUDING those firmware RT/SMM/ACPI-NVS regions. Linux
  early allocator therefore reuses live firmware code/data pages.
- Consequences chain: (1) when firmware SMM legacy-emulation code later runs (the
  i8042 poll! the USB handoff!), its own data structures have been trampled ->
  deadlock class we convicted in i8042, AND boot-8 USB ownership failure (firmware
  still holding the port, its state corrupted) -> possibly the SAME root cause.
  (2) Boots #3/#4 fast-panicked with the real map passed UNQUORKED - exactly the
  crash davilla fixed with the overlap trim. We skipped their fix and went
  synthetic; synthetic traded a crash for firmware corruption.
- Correct era path, per reference: ACTUAL EFI map + overlap quirk fixup -> e820.
  NEVER TRIED BY US. Candidate boot #9 (after owner go): loader-side port of
  quirk_fixup_efi_memmap into work-loader (GPL->GPL, patch lives in
  tools/patches/, binary stays device-side per license firewall), drop all memmap=
  flags, keep blacklist i915_init,nouveau_drm_init,i8042_init.
- Effect on path decision: internal-PATA stays the product end-state and the
  strategic recommendation; but the claim "firmware never hands USB to Linux" is
  REFUTED by era evidence, so the real-map+quirk boot is now ranked ABOVE the
  EHCI-only lottery ticket as the next stick-path experiment.
- Also adopted as standing knowledge: USB enumeration can be SLOW on this box
  (era: +5s needed for HDDs) - our 30 s hunt window is adequate, keep it.

No image built this round; boot-8 (8443465b) remains the last burned candidate.

## 2026-10-28 — BOOT #9 built: REAL EFI map + atv-bootloader overlap quirk (loader change, content-proven)

- LOADER CHANGE (first non-flags candidate since the payload fix):
  atv1_memmap_quirk.c ports davilla's quirk_fixup_efi_memmap() - RT_CODE/
  RT_DATA union computed from the LIVE firmware map, every RAM-typed
  descriptor overlapping it TRIMMED (never split; zero-page descriptors
  now skipped at e820 conversion). Era hard-split at 0x025AE000 NOT
  ported (layout-specific to their image; rationale logged). GPL-2.0
  attribution header on patch file + source; firewall rule restated:
  patch and mach_kernel stay GPL/device-side, never enter MIT app code.
- FLAGS CHANGE (paired, single experiment = "real map done right"):
  memmap=exactmap memmap=640K@0 memmap=255M@1M REMOVED. All else identical
  to boot-8: blacklist i915_init,nouveau_drm_init,i8042_init; acpi=off
  noapic noefi panic=5 rootwait root=LABEL=ATV1ROOT nomodeset console.
- CANDIDATE 48e9f8d846388ce7a2297cddc077fedf0624caa0328e266b60b92d7e0ed16570
  (1312802 sect). mach_kernel NOW 395796b766a82b69 / 7899116 B - changed,
  as it must; content-proofs: 3 ATV1-QUIRK strings present in built
  mach_kernel (linked, not stale-object), quirk .o timestamp inside this
  build, image FAT plist verified post-build with ZERO memmap occurrences.
- BOOT-9 ALGEBRA (instruments: screen clock + ARP watcher + stick log):
    beacon/ssh/stick-log => real-map+quirk path WORKS; USB ownership
      theory confirmed; next: re-enable GPU debugging from live shell.
    fast cycle ~5-10s (boots 3/4 signature) => map still kills pre-init
      even quirked => overlap-quirk hypothesis REFUTED for our fw3;
      synthetic map returns, internal-PATA becomes next step.
    scream ~60-70s no log => kernel+init fine on real map, stick STILL
      invisible => map exonerated for USB specifically => EHCI-only probe
      or internal-PATA (owner's call, as before).
    frozen >3min => new class; re-probe from here.
- Watcher re-arms on "hash pasted + booting". Boot-8 remains last BOOTED
  candidate; boot-9 is build+proof only until owner burns.

## 2026-10-28 — BOOT #9 verdict: era map quirk CONFIRMED (no fast panic; init on real map) + map EXONERATED for USB -> BOOT #10 EHCI-only probe

- Boot-9 (48e9f8d8) burned byte-perfect, booted: SCREAM CYCLE 60-70s,
  no beacon (watcher window silent), stick log absent. READS:
  1) MILESTONE: the fast-panic signature (boots 3/4, ~5-10s) is GONE.
     The atv-bootloader RT-overlap quirk makes the REAL firmware map
     bootable on unit A. Synthetic exactmap crutch RETIRED permanently.
     The era's documented firmware bug was real and it was ours.
  2) Map formally EXONERATED for the USB failure: with the corrected map,
     USB drivers loaded, init running - stick STILL never enumerates
     (scream = block layer empty; ext4 root would have mounted any sd*).
  3) NIC still never observed (8139too unproven across ALL worlds).
- BOOT #10 = b264eaf95eecfa7668572fc3594937b511b5955b57b1544c9a745daa640a98cd
  (flags-only vs boot-9; mach_kernel UNCHANGED 395796b7, re-verified).
  Era-classic USB-2-only boot: + uhci_hcd_init, ohci_hcd_mod_init,
  ohci_pci_init blacklisted (verified in-tree names); usb_init +
  ehci_hcd_init + ehci_pci_init stay restored; i8042+GPU stay off.
  ALGEBRA:
    beacon/ssh/FULL BOOT      => stick enumerates on EHCI when UHCI
                                  companions stay dormant => WIN, make
                                  permanent + revisit GPU.
    scream 60-70s AND log now appears on stick => enumeration FIXED,
                                  root-hunt failure is a different bug
                                  (label/fs) => readable from the log.
    scream 60-70s, no log     => EHCI-only also blind => STICK PATH DEAD
                                  on this firmware => internal-PATA
                                  install (product end-state; loader now
                                  proven-good on real map for it).
    fast panic / frozen       => new signal, re-probe.
- If boot-10 dead-ends: the internal-PATA install inherits a loader with
  the era map fix - every prior PATA plan stands, log target = internal
  P1, NIC debug happens over ssh once beacon proves NIC, else pull drive.

## 2026-10-28 — BOOT #10 verdict: EHCI-only ALSO blind -> STICK PATH DEAD on unit A firmware -> PIVOT: internal PATA install

- Boot-10 (b264eaf9) burned byte-perfect + post-boot identity verified
  (stick plist flags exact, mach_kernel 395796b7/7899116B). Result:
  scream 60-70s, NO atv1-kmsg.txt, NO kodi log, no beacon (watcher full
  window). Extraction of P1 verified clean (64 MiB read, hdiutil mount).
- USB REGIME ALGEBRA NOW EXHAUSTIVE:
    all-USB up        (boot-8)  -> no enumeration
    EHCI-only         (boot-10) -> no enumeration
    UHCI-only                   -> unwinnable by physics (USB-2 stick on
                                   companion transceiver requires EHCI to
                                   release the port; EHCI absent = port
                                   stays firmware-owned)
    USB blacklisted   (probe A) -> no storage BY DESIGN
  => stick path formally DEAD on unit A stock fw3. Firmware keeps the
  boot port after boot.efi exits; no in-Linux driver regime claims it.
  Era community DID boot USB on this firmware (atv-bootloader issues) -
  remaining unknowns are era-kernel config deltas we cannot chase
  blindly; every additional probe is a burn with unknown odds, while the
  internal path is the PRODUCT END-STATE anyway.
- NIC (8139too): still never observed across EVERY world (acpi=off
  noapic PIC routing unproven). Becomes debuggable from a live internal
  boot instead of deduced.
- PIVOT DECIDED (pre-authorized direction since boot-8 analysis):
  INSTALL TARGET = internal 2.5" PATA drive, burn via IDE/PATA->USB
  adapter, restore-layout image unchanged (boot.efi recovery scan reads
  internal disk natively - Apple's own restore path does this).
  BURN IMAGE = boot-9 build 48e9f8d846388ce7a2297cddc077fedf0624caa0328e266b60b92d7e0ed16570
  (chosen over boot-10: UHCI/OHCI drivers REGISTERED = maximal live-
  shell debug surface for USB re-binding experiments later; both boot
  identical from PATA since ata_piix does the mounting).
  LOADER STATE PROVEN for this path: real map + era quirk boots to init
  (boot-9/10 screams PROVE kernel+init alive on correct map); i8042+GPU
  blacklist stands.
- PATA ROUND INSTRUMENTS: success look = grey logo, NO cycle (GPU off =
  dark by design). Watch ARP beacon (NIC's last unproven chance); if
  silent after ~3 min: power off, pull drive, read internal P1 FAT via
  adapter -> atv1-kmsg.txt (full dmesg incl. ata_piix + 8149too + USB
  probe attempts) + atv1-kodi.log. Burn protocol = manual diskutil-list
  confirmation (adapter disk size unknown; NO heuristic dd; Passport is
  NOT a target under any circumstances).
