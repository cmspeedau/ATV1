# ATV1 — Buildroot Kodi appliance for the Apple TV 1st gen (A1218)

Pentium M "Crofton" 1 GHz · **NVIDIA GeForce Go 7300** (64 MB) ·
**Broadcom BCM70012 CrystalHD** (1080p H.264 HW decode) · 256 MB RAM ·
10/100 Ethernet · 2× USB 2.0 · 2.5" SATA · 32-bit EFI · dead-silent.

The idea: a fully source-built, vendor-lock-in-free Kodi box. Kodi 17
(Krypton) + CrystalHD = hardware 1080p H.264/MPEG-2. Buildroot keeps the
whole userspace inside 256 MB. This is a hand-rolled LibreELEC-7-era
image you own end to end: kernel defconfig → rootfs → disk image.

## 1. Repo layout (this directory = br2-external tree)

```
external.desc / external.mk / Config.in   tree registration
configs/atv1_defconfig                    the product (commit everything here)
board/grub-i386-efi.cfg                   GRUB menu embedded in bootia32.efi
board/grub-bios.cfg                       legacy-BIOS fallback menu
board/atv1/
  linux.fragment                          kernel symbols (merge once, see §4)
  genimage.cfg                            MBR: FAT boot + ext4 rootfs
  post-build.sh / post-image.sh           exec bits + EFI assembly + image
  rootfs-overlay/
    etc/inittab                           serial getty + Kodi kiosk on tty1
    etc/atv1/startkodi.sh                 startx + kodi -fs
    etc/asound.conf.example               HDMI audio default, S/PDIF noted
    root/.kodi/userdata/advancedsettings.xml   RAM-tuned Kodi 17
package/crystalhd/                        LibreELEC-maintained BCM70012 userspace
```

## 2. Where to build — NOT on this volume

This tree lives on **ExFAT** (`/Volumes/EXTData`). Text files are happy
here; a Buildroot **build** is not (no symlinks/permissions → fakeroot
and image generation fail). Build in a Linux container on a native-fs
volume, from a copy of this tree:

```sh
# macOS side: Docker Desktop. Image is the era-matched host (gcc 6, py2.7).
docker run -it --rm -v /Volumes/EXTData:/extdata debian:stretch bash
```

```sh
# inside the container
apt-get update && apt-get install -y --no-install-recommends \
  build-essential git cpio rsync file bc wget python perl unzip \
  bison flex sed libncurses-dev libssl-dev ca-certificates

# copy the tree off ExFAT — exclude AppleDouble junk that ExFAT carries
rsync -a --exclude='._*' --exclude='.DS_Store' /extdata/Projects/ATV1/ /root/atv1/
git clone --depth 1 --branch 2017.08.x \
  https://git.buildroot.net/buildroot /root/buildroot

make -C /root/buildroot O=/root/out \
  BR2_EXTERNAL=/root/atv1 atv1_defconfig
make -C /root/buildroot O=/root/out                    # long first build
# image lands at /root/out/images/atv1-disk.img → copy to /extdata/.../images/
```

When finished, copy `linux.config` and any defconfig/menuconfig deltas
**back into this tree** — the container is disposable, the tree is the
product. `git init` here and commit the defconfig + board dir.

## 3. Era is load-bearing (read before bumping Buildroot)

Everything below was true of Buildroot ≈2017.08 and is false later:

| Dependency | Why 2017.08-era |
|---|---|
| Kodi **17.6** | CrystalHD video accelerator **removed in Kodi 18** |
| Mesa with **nv40** DRI | classic nv4x driver gone from Mesa ≥ 17.3 → Go 7300 = llvmpipe |
| kernel **4.14** | `staging/crystalhd` deleted upstream ≈4.16 |
| grub2 **i386-efi** target | ATV1 firmware is 32-bit EFI (like MacBook2,1) |
| python2 add-ons | this era's add-on ecosystem |

Newer Buildroot = re-creating all five by hand. Don't chase it. If a
symbol in the defconfig doesn't exist at your era point, `make xconfig`
and search — names drift; §5 lists the ones to verify.

## 4. Kernel bring-up (one-time, then commit the result)

`linux.fragment` is documentation + input for a one-time merge:

```sh
cd /root/out/build/linux-4.14.335
# Buildroot already ran the i386 defconfig; merge the fragment:
./scripts/kconfig/merge_config.sh -m .config /root/atv1/board/atv1/linux.fragment
make oldconfig          # accept defaults on prompts
# back in Buildroot:
make O=/root/out linux-update-defconfig \
  BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=/root/atv1/board/atv1/linux.config
```

Copy the generated `linux.config` into `board/atv1/`, then in
`configs/atv1_defconfig` swap the two `BR2_LINUX_KERNEL_USE_*` lines to
`USE_CUSTOM_CONFIG`. **Never commit Buildroot's `.config`; only this
fragment + the captured defconfig.** After kernel edits:
`make O=/root/out linux-rebuild all`.

Non-obvious symbols already reasoned through in the fragment:

* `CONFIG_CRYSTALHD=y` **built-in** — /dev/crystalhd exists before Kodi starts
* `# CONFIG_DRM_I915 is not set` — the 945GUX northbridge carries a GMA950;
  X must bind the 7300 (which owns the HDMI port), never the iGPU
* `ATA_PIIX` **and** `SATA_AHCI` — 2007 firmware may present either mode
* NIC: broadnet of 2007 candidates (e1000/tg3/bnx2/sky2/r8169) — enable all,
  `dmesg | grep -i eth` tells you which is real, then prune
* `EFI_MIXED=y` — 32-bit EFI handing over to the 32-bit kernel

## 5. menuconfig verification checklist

Era names drift; verify these exist/enabled after `atv1_defconfig`:

- [ ] `MESA3D` → GLX (desktop GL) enabled; **nv40 DRI driver** present.
      Missing nv40? Drop to Buildroot **2017.05** or **2016.11**.
- [ ] `xinit` (provides `startx`) — symbol name is `BR2_PACKAGE_XINIT`
      here; search if it moved.
- [ ] `kodi` → python bindings on; a default **skin** addon selected
      (Estuary/Confluence — confirm one is built, Kodi without a skin is
      a black screen).
- [ ] `grub2` → **i386-efi** target exists, and note which filename it
      emits (post-image.sh globs the common names; adjust if odd).
      If your era predates grub2: use `BR2_TARGET_GRUB=y` (legacy),
      `board/grub-bios.cfg`, ext2 (not ext4) rootfs — grub-legacy can't
      read ext4 extents.
- [ ] `eudev` (default on) — creates `/dev/crystalhd` automatically.
- [ ] `crystalhd` (this tree) — **after first successful download, pin
      `CRYSTALHD_VERSION` in package/crystalhd/crystalhd.mk to the actual
      commit and add a `.hash`.** Kodi links libcrystalhd from staging;
      if it built before crystalhd: `make crystalhd kodi-dirclean all`.

## 6. Booting the box

The A1218's firmware verifies its own EFI binaries until you unlock it:

1. **atv-linux-loader** — github.com/DistroHopper39B/atv-linux-loader —
   USB loader that boots Linux on the ATV1's 32-bit EFI.
   Newer sibling: **ATV1sm** (distrohopper39b.com/atv1sm) bypasses the
   EFI image verification outright and adds USB input/boot.
2. Classic route: patchstick (Play+Right on the Apple Remote at power),
   then atv-boot-loader chainloads `board/grub-bios.cfg` instead.
3. `atv1-disk.img` → a modest **USB 2.0** stick (old EHCI: avoid
   power-hungry drives; a hub only if you must plug a keyboard too).
4. First boot: watch over **serial** (UART header mod, 57600 8N1) or any
   HDMI display. GRUB menu → pick the USB entry (root=sdb2/sdc2).
5. Expected: `login:` on serial, Kodi fullscreen on HDMI.
   `ps aux | grep kodi`, `ls /dev/crystalhd`, `dmesg | grep -iE 'nouveau|7300'`
   — confirm which NIC got a link with `ifconfig -a`.

Iterate: edit tree → re-copy into container → `make O=/root/out all`
→ re-dd stick. Overlay/post-build changes rebuild in seconds.

## 7. Permanent install

Boot the stick, then `dd` the same image to the internal bay — the A1218
takes a **standard 2.5" SATA** drive (no ZIF weirdness), so this is the
WD Green 2 TB: rootfs P2 + the rest of the disk unformatted for now, or
grow it later (`resize2fs` + P2 resize; or add a P3 media partition).
From macOS, after a clean unmount: `sudo dd if=atv1-disk.img of=/dev/rdiskN bs=4m`.

## 8. Roadmap (deliberately not in v1)

- **IR remote**: lirc `macmini` era driver + eventlircd → Apple Remote.
  Until then: Kodi's :8080 JSON-RPC + any phone remote app (enabled in
  advancedsettings.xml).
- **Squashfs rootfs + overlay data partition + zram** — the real RAM
  win; kernel fragment already carries the commented symbols.
- 2 GB DDR2 experiment (mixed reports on this board — v1 targets 256 MB).
- SMB/NFS client mount for library on the Mac mini.
- `make legal-info` + a pinned `.hash` per package when it's a "product".

## 9. Known limits (frozen in 2008 silicon, by design)

No HEVC/VP9/AV1 ever; no modern Kodi (18+); no Inputstream → no YouTube/
IPTV add-ons; 100 Mbps Ethernet ≈ 11 MB/s stream cap; stock ATV1 has no
Wi-Fi driver without extracted b43 firmware (use the wire). Judge it
against a 2016 library and it's magic; judge it against 2026 codecs and
build the N100 box too.
