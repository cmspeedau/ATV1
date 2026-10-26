# ATV1 — Buildroot Kodi appliance for the Apple TV 1st gen (A1218)

A fully source-built Kodi 17.3 appliance image for the 2007 Apple TV
(A1218: Pentium M 1 GHz, 256 MB RAM, 10/100 Ethernet, 32-bit EFI). Build
target is a 608 MB hybrid MBR disk image (`atv1-disk.img`) that boots from
USB. Honest envelope without a decoder card: SD and easy 720p software
decode. Buildroot keeps userspace inside 256 MB.

Docs: this README = how to build/boot it (current truth).
[`ATV1-SPECS.md`](ATV1-SPECS.md) = hardware facts with provenance tags.
[`CONFIG-CHANGES.md`](CONFIG-CHANGES.md) = ledger of every config change.
[`LOG.md`](LOG.md) = engineering history and failure records.

## 1. Repo layout (this directory = a br2-external tree)

```
external.desc / external.mk / Config.in   tree registration + genimage host-tool deps
configs/atv1_defconfig                    the product config
board/grub-i386-efi.cfg                   GRUB menu embedded in bootia32.efi
board/grub-bios.cfg                       legacy-BIOS fallback menu
board/atv1/
  linux.fragment                          kernel symbols; merged on every defconfig run
  genimage.cfg                            disk layout (file-handler partitions, see §7)
  post-build.sh                           exec bits; Rust client install; skin.atv install + asset gen
  post-image.sh                           EFI assembly; mkfs data fs; runs genimage
  rootfs-overlay/                         inittab, fstab (LABEL mounts), S20datadirs,
                                          startkodi.sh, kodi userdata (advancedsettings,
                                          guisettings=skin, sources), asound example
skin/skin.atv/                            original Kodi 17 skin, GPL-2.0 (§6b); no binaries in git
package/crystalhd/                        dormant until a card arrives (§9)
package/atv1-client/                      config hook for a prebuilt Rust binary
tools/Dockerfile.build                    era build host (debian stretch: gcc6, py2)
tools/container-build.sh                  the reproducible build script (§2)
tools/verify-image.sh                     image byte-level checks (§4)
tools/build-client.sh                     out-of-era Rust cross-build vs era SDK
client/                                   drop the built atv1-client binary here (untracked)
```

## 2. Build

All builds run in a Linux container (Buildroot cannot build on macOS;
the tree itself lives on APFS anywhere). One-time image build, then one
detached container run; the `atv1-work` volume makes every run resume
after interruption:

```sh
export PATH="$HOME/.docker/bin:$PATH"        # macOS Docker Desktop
cd ~/ATV1
docker build -t atv1-build:stretch -f tools/Dockerfile.build tools/
docker run -d --name atv1-build \
  -v "$HOME/ATV1:/atv1-src:ro" -v "$HOME/ATV1/images:/export" \
  -v atv1-work:/work \
  atv1-build:stretch /atv1-src/tools/container-build.sh
docker logs -f atv1-build                    # progress; hours on first build
```

The script clones Buildroot `2017.08.x`, rsyncs this tree into `/work`,
runs `make atv1_defconfig`, prebuilds genimage's host tools, builds
everything, and copies `atv1-disk.img` + `build.log` to `~/ATV1/images/`.
Overlay/post-build edits rebuild in seconds. Ops trap: Docker Desktop
quits silently — if it goes quiet, `docker ps` first; `docker start
atv1-build` resumes.

Before the FIRST build ever, seed the dead-download overrides (§3).
Manual alternative (any stretch-era Linux): clone `2017.08.x`,
`make O=out BR2_EXTERNAL=<tree> atv1_defconfig && make O=out`.

## 3. dl/ overrides — required, two dead era downloads

Two selected packages fetch over retired `git://` endpoints; buildroot
would hang with no error. Place both files in the download cache
(`/work/dl` on a fresh volume) — the filenames ARE the version pins:

```sh
docker run --rm -v atv1-work:/work atv1-build:stretch sh -c '
  mkdir -p /work/dl && cd /work/dl
  wget -q -O xdriver_xf86-video-intel-b57abe20e81f4b8e4dd203b6a9eda7ff441bc8ce.tar.gz \
    https://gitlab.freedesktop.org/xorg/driver/xf86-video-intel/-/archive/b57abe20e81f4b8e4dd203b6a9eda7ff441bc8ce/xf86-video-intel-b57abe20e81f4b8e4dd203b6a9eda7ff441bc8ce.tar.gz
  wget -q -O rtmpdump-fa8646daeb19dfd12c181f7d19de708d623704c0.tar.gz \
    https://sources.buildroot.net/rtmpdump-fa8646daeb19dfd12c181f7d19de708d623704c0.tar.gz'
```

Audited: no other selected package uses `git://`. These two had no
`.hash` at the era (buildroot warns; the commit-SHA filenames are the pin).

## 4. Verify the image (reads the bytes, not the log)

```sh
docker run --rm -v atv1-work:/work -v "$HOME/ATV1:/atv1-src:ro" \
  -v "$HOME/ATV1/images:/export" atv1-build:stretch \
  /atv1-src/tools/verify-image.sh /export/atv1-disk.img
```

Checks: MBR 3 partitions with P1 FAT bootable; P1 contains `bzImage`,
`EFI/BOOT/bootia32.efi`, `grub.cfg`; P2 is ext rootfs; P3 is ext4
labeled `ATV1DATA` and provably empty. Pin of the first-good image:
`sha256 6b0c907d5a2eed9643e1f1455d2a8bbaea68b537f1bd2aba6154089dce79a0a0`
(every rebuild regenerates; record yours in LOG.md).

## 5. Boot from USB (Stage 0)

The A1218 firmware verifies its own EFI binaries; 32-bit EFI means
`bootia32.efi` (which is what the image carries). Two ways in:

1. **ATV1sm** (distrohopper39b.com/atv1sm) — bypasses EFI verification,
   adds USB boot. Older sibling: atv-linux-loader
   (github.com/DistroHopper39B/atv-linux-loader).
2. Patchstick (Play+Right on the Apple Remote at power), then
   atv-boot-loader chainloads the BIOS menu (`board/grub-bios.cfg`).

```sh
diskutil list                                # find the stick: /dev/diskN
diskutil unmountDisk /dev/diskN
sudo dd if=~/ATV1/images/atv1-disk.img of=/dev/rdiskN bs=4m status=progress
```

Use a modest USB 2.0 stick (old EHCI; avoid power-hungry drives).
Console: onboard UART 57600 8N1, or HDMI — GRUB menu, pick the USB
entry (roots are sdb2/sdc2). First-boot checklist:

```
ifconfig -a                  # eth0 got a link (Realtek 8139 driver: 8139too)
lspci -nn                    # 8086:27xx chipset; 10de:01d7 only on unit B
ls /dev/fb*                  # /dev/fb0 present
dmesg | grep -iE 'i915|nouveau|drm|sdvo|hdmi'
ps aux | grep kodi           # kiosk on tty1
```

Still unobserved (first boot is the test): the 32-bit EFI path itself,
unit A's NIC/GPU, SDVO/HDMI hotplug quirks, swrast speed at 1 GHz.
Fleet/unit identities and evidence: ATV1-SPECS.md.

## 6. Permanent install (internal drive)

Standard 2.5" SATA; the image fits any drive. dd it, then grow P3 into
the remaining space (`sgdisk`/`fdisk`/`resize2fs` are in the rootfs):
grow the partition, `resize2fs` it. `/data` is mounted by LABEL
(`ATV1DATA`), so nothing else changes. **Never re-image P3** — recovery
model = re-flash P1/P2 and keep P3 (no OTA on this boot chain).

## 6a. SMB library mount (OS level)

The image carries the in-kernel SMB client (`CONFIG_CIFS=y`, speaks SMB
2.1/3.0 — what macOS sharing serves) and the `mount.cifs` helper
(cifs-utils). Client only: the TV never serves files.

```sh
# on the TV (or over ssh):
printf 'username=YOU\npassword=YOURPASS\n' > /etc/atv1/smb.creds
chmod 0600 /etc/atv1/smb.creds              # never put creds in /etc/fstab
mkdir -p /data/media/library
mount -t cifs //SERVER/SHARE /data/media/library \
  -o vers=3.0,credentials=/etc/atv1/smb.creds,noatime
```

Point Kodi sources at `/data/media/library/...`, not at `smb://` — the
mount is invisible to Kodi's own (absent) SMB client and works for every
tool. Persistent variant: the commented fstab line in `/etc/fstab`
(uncomment, adjust server/share; `_netdev` keeps boot sane when the
server is down). If `mount -t cifs` fails with "bad protocol": macOS
can be told to speak 2.1 — use `vers=2.1`.

## 6b. Skin: skin.atv

The on-screen look is `skin/skin.atv` — original work, GPL-2.0-only
(Kodi's own license family; ships in the image cleanly), **no Apple
assets of any kind**: every raster comes from
`skin/skin.atv/tools/gen_assets.py` at build time, type is DejaVu
(Bitstream Vera license, `BR2_PACKAGE_DEJAVU`). Design language and
v0.1 scope: `skin/skin.atv/README.md`.

Mechanics:

- `post-build.sh` copies the skin to `/root/.kodi/addons/skin.atv/`,
  runs `gen_assets.py` (container's host python), copies the two DejaVu
  TTFs into the skin's `fonts/`. Missing fonts or failed asset gen fail
  the build — no silent skinless boot.
- Default skin + pre-seeded library sources: `userdata/guisettings.xml`
  and `userdata/sources.xml` in the rootfs-overlay (sources =
  `/data/media/library`, `/data/media/music` — the S20datadirs roots).
- No PNGs/TTFs in git; `media/` is generated — don't commit it.
- Kiosk surface on purpose: home shelf, library lists, info dialog,
  player/OSD, essential dialogs. Absent by design: settings UI, any
  text entry, file manager, PVR. Config happens via ssh/coordinator.
- First boot: if Kodi comes up in Estuary instead, the skin was skipped
  — read `~/.kodi/temp/kodi.log` (XML errors land there, not on screen).

## 7. Era is load-bearing — do not bump Buildroot

| Pin | Reason (false in later eras) |
|---|---|
| Kodi 17.3 | last release with CrystalHD support (removed in 18) |
| Mesa 17.1.x | nv40 classic DRI (unit B's GL) is gone from Mesa ≥ 17.3 |
| kernel 4.9.337 LTS | era's own LTS; NOT crystalhd-pinned (no card) |
| grub2 i386-efi | the firmware is 32-bit EFI |
| genimage 9 | disk config uses its option surface; its ext images are fed `cp -a --rootpath`, so P2/P3 are embedded via the `file` handler and P3 is formatted by post-image.sh |

Config-edit rules (each learned from a silent failure):

1. After editing defconfig/fragment: `make atv1_defconfig`, then audit
   the generated `.config` for the symbols you set — this era's kconfig
   silently drops assignments to unknown or promptless symbols.
2. Kernel fragment disable syntax: canonical `# CONFIG_X is not set`
   only; `# CONFIG_X=n` disables nothing.
3. Host tools genimage 9 execs are undeclared in its era package
   (`genext2fs`, `tune2fs`, `mkdosfs`, `mcopy`): enabled in defconfig +
   prebuilt by container-build.sh. A dependency on a package whose
   Kconfig symbol is off is a phantom — enable the package.

## 8. menuconfig-era name checklists

After `atv1_defconfig`, confirm in `.config`: `BR2_PACKAGE_MESA3D=y` +
`GALLIUM_DRIVER_SWRAST` + `DRI_DRIVER_NOUVEAU`; `XORG7` +
`XSERVER_XORG_SERVER` + intel/nouveau/fbdev DDX + xinit; kodi python
bindings + default skin built; grub2 i386-efi emits
`efi-part/EFI/BOOT/bootia32.efi` (post-image.sh reads that path).
There is deliberately NO `_DRI_DRIVER_I915`: Mesa 17.1 cannot build it.

## 9. CrystalHD card plan (dormant — follow when a card arrives)

Buy ONLY a **BCM970012** card (BCM70012 chip, PCI `14e4:1612` — the
only id the in-tree driver binds; BCM970015/AW-VD920 never work here).
Driver history: in-tree through 3.16.x, deleted in 3.17. Enablement:

1. defconfig: kernel → `3.16.85`, headers → `3_16`
2. fragment: `CONFIG_STAGING=y`, `CONFIG_CRYSTALHD=y`
3. enable `BR2_PACKAGE_CRYSTALHD` (mirror alive; sha512 in its `.hash`)
4. `KODI_DEPENDENCIES += crystalhd`; rebuild Kodi and confirm crystalhd
   in its configure log — do not assume it linked.

## 10. Roadmap

- pentium4 toolchain promotion (SSE2 proven via CPUID; full rebuild).
- xstartup GPU-select for unit B: force the nouveau screen when
  `10de` is present, else X paints on the iGPU's dead output.
- NIC prune: drop e1000/tg3/bnx2/sky2/r8169 once unit A's NIC is seen.
- IR remote (lirc macmini era driver); JSON-RPC :8080 works meanwhile.
- Squashfs rootfs + overlay + zram (the real RAM win).
- SMB client mounts: DONE at OS level (§6a: kernel CIFS + cifs-utils +
  fstab example). NFS remains open if ever needed.
- `make legal-info` + a pinned `.hash` per package when this ships as a
  product.

## 11. Limits of the silicon (by design, not bugs)

No HEVC/VP9/AV1; no Kodi 18+; no InputStream add-ons; ~11 MB/s
Ethernet; stock WiFi unsupported (b43 firmware extraction — use the
wire). Two internal Apple OSes stay untouched as factory fallbacks:
this image lives on USB or on P1-P2 you re-flash yourself.

## 12. Design-doc alignment

Repo positions vs ARCHITECTURE-APPLE-TV-CONTROLS.md (coordinator/agent
design): no A/B slots or OTA on A1218 (re-image recovery only); P3 +
`/data/*` managed roots separate from system; Rust client built
out-of-era (`tools/build-client.sh`, era predates in-tree Rust) and
installed via `BR2_PACKAGE_ATV1_CLIENT`; nothing listens except dropbear
(dev) and Kodi :8080; product boot-chain (stock GPT/`boot.efi`) stays
Unknown until observed on hardware — nothing here claims support without
a hardware observation.
