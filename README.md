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
tools/seed-dl.sh                          seed /work/dl from the Release bundle (§3)
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

## 3. dl/ — the download cache outlives the upstreams

Upstream sources rot (two already died: retired `git://` endpoints —
buildroot would just hang). The durable copy lives in THIS repo as a
Release asset, `atv1-dl.tar` (459 MiB, 158 tarballs incl. the two dead
overrides, minus abandoned-kernel leftovers),
`sha256 e555a313b36ce7936e09c0edce53dff7c5700b5ceab5a260e701a8f2fdcf328a`.
Seed any fresh machine with it — the script verifies that sha, and
buildroot independently verifies every `.hash` afterward:

```sh
tools/seed-dl.sh        # downloads (if missing), sha-checks, extracts to atv1-work:/work/dl
```

Regenerating the bundle after a config change (then update URL+sha in
tools/seed-dl.sh and re-upload the Release asset):

```sh
docker run --rm -v atv1-work:/work:ro -v "$HOME/ATV1/images:/export" \
  atv1-build:stretch sh -c 'cd /work && tar cf /export/atv1-dl.tar dl && sha256sum /export/atv1-dl.tar'
```

History of the two dead downloads (their files are IN the bundle —
listed here because the filenames ARE the version pins):

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
Licensing: the bundle is a redistribution of openly-licensed build
sources (GPL et al.) — it feeds the build; it never enters any MIT
binary we ship.

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

The A1218 firmware verifies its own EFI binaries: stock firmware boots
**Apple-signed `boot.efi` chains only** — our MBR+`bootia32.efi` stick is
never blessed on ANY firmware era (signature, not format, is the wall).
The path that works on unmodified firmware 3 is Apple's own **recovery
scan** (never closed, because restore had to keep working): a GPT disk
whose partition type is the Apple TV Recovery GUID, holding Apple's
signed `boot.efi`, which chainloads our `mach_kernel` (atv-linux-loader,
MIT) with kernel+initramfs embedded.

### Door #1 — restore-layout stick (rear USB port)

Built by `tools/make-atvrecv-disk.sh` (sources + pins in its header:
mesu DMG sha1 `97623d8d…` → `boot.efi` sha256 `c7f57cc2…`,
DummyKext 1.0, loader repo). Burn:

```sh
diskutil list                                # find the stick: /dev/diskN
diskutil unmountDisk /dev/diskN
sudo dd if=~/ATV1/images/atv1-recv-disk.img of=/dev/rdiskN bs=4m   # Ctrl-T = progress
sync
sudo dd if=/dev/rdiskN bs=512 count=1312802 2>/dev/null | shasum -a 256
# expect: 48e9f8d846388ce7a2297cddc077fedf0624caa0328e266b60b92d7e0ed16570
```

Notes: the backup GPT sits at the image tail (~641 MiB), not the stick's
end — macOS/Linux may offer to "repair"/"Initialize"; **refuse both**
(the primary GPT is authoritative and the ATV scan only reads that).
Plug into the REAR USB port, power on — no button combo: the recovery
scan runs on every boot. Expect the grey Apple logo, then Linux; the
beacon + serial (57600) tell you if HDMI stays dark.

### Door #2 — internal IDE drive

Same image (`atv1-recv-disk.img`) dd'ved to the 2.5" PATA/IDE disk —
the scan does not care what bus the atvrecv partition rides.

### The MBR image (`atv1-disk.img`) — what it's for now

It is NOT bootable by stock firmware (see wall above); it remains the
pipeline artifact (rootfs + kernel + grub config) and boots fine under
ATV1sm (distrohopper39b.com/atv1sm), which bypasses the signature check
and adds USB boot. Burn ritual for it (1245185 sectors):

```sh
sudo dd if=/dev/rdiskN bs=512 count=1245185 2>/dev/null | shasum -a 256
# sha pinned in LOG.md / CONFIG-CHANGES.md; re-pin after every rebuild
```

macOS `dd` is BSD: no `status=progress`/`status=wall` (it aborts and writes
nothing). SIGINFO (Ctrl-T) prints live transfer stats.

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

**SSH access (root) — plain by design.** dropbear runs from boot (the
package's `S50dropbear`; `-R` ⇒ host key regenerates every boot, so expect
the yes/no once per session or add `-o UserKnownHostsFile=/dev/null`):

```sh
ssh root@<atv1-ip>        # password: frontrow
```

`root` / `frontrow` is the fleet default, written here on purpose: this
is a LAN appliance meant to be usable by more than one person, and the
password follows the NitoTV-era convention the modded units already
carry. It RESETS on every re-flash — convenience, not a defense line;
this box must not be reachable off-LAN.

Admins with the fleet key (private half at `~/.ssh/atv1_fleet` on the
admin machine, public half baked into the image) get in without a password:

```sh
ssh -i ~/.ssh/atv1_fleet root@<atv1-ip>
```

Serial console (57600 8N1): `login:` root, same password.

**Boot beacon (headless discovery), two stages.** The INITRAMFS beacon
fires first: as soon as the kernel + NIC + DHCP are alive — before any
disk is touched — the unit grabs a lease and shouts gratuitous ARP +
broadcast ping every 60 s forever (a `kmsg` line reads
`ATV1 INITRAMFS-OK ip=...`). The ROOTFS beacon (S60beacon) takes the
shout over after switch_root and adds Kodi JSON-RPC on `:8080`. So a
MAC sighting proves the kernel lives even if handover fails, and the
absence of any sighting after boot means the boot died pre-initramfs —
the two failure classes are now distinguishable without serial:

```sh
arp -a | grep -i "<unit-mac>"        # appears UNPROMPTED via gratuitous ARP
curl -s http://<ip>:8080/jsonrpc -d '{"jsonrpc":"2.0","id":1,"method":"Application.GetProperties","params":["version"]}'
```

If neither ever shows after a boot attempt, the boot died before Linux —
that's an EFI/boot-chain answer, not a config answer (see paths above).

## 6. Permanent install (internal drive)

The drive is 2.5" **PATA/IDE 44-pin** (ATA-6, e.g. Toshiba MK-series; NOT
SATA — earlier docs were wrong, see ATV1-SPECS correction 2026-10-27).
Any capacity ≥ 641 MiB works: dd `atv1-recv-disk.img`, then grow P3 into
the remaining space — repartition from a Mac/Linux host (the image's
backup GPT needs relocating to the new disk end: `sgdisk -e` on Linux),
then `resize2fs` (in the rootfs) while unmounted. `/data` is mounted by
LABEL (`ATV1DATA`), so nothing else changes. **Never re-image P3** —
recovery model = re-flash P1/P2 and keep P3 (no OTA on this boot chain).

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
