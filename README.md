# ATV1 — Buildroot Kodi appliance for the Apple TV 1st gen (A1218)

Pentium M "Crofton" 1 GHz · 256 MB RAM · 10/100 Ethernet · 2× USB 2.0 ·
2.5" SATA · 32-bit EFI · dead-silent. Two units, one image, proven
heterogeneous (see §6 Stage-0 findings): **unit A** (stock) carries only
the Intel GMA950 of the i945GMS chipset; **unit B** (aTVFlash-modded)
carries a mini-PCIe **GeForce Go 7300** that owns its HDMI. Neither
unit has a CrystalHD card (that was always a mini-PCIe add-on mod).

The idea: a fully source-built, vendor-lock-in-free Kodi box. With no
decoder card, H.264 is software work for a 1 GHz Celeron M — the honest
envelope is SD and easy 720p, and that is what ships as the claim. The
era pin to Kodi 17.3 stays because 17 is the last release with CrystalHD
support: if a BCM70012 mini-PCIe card is ever added (the famous 1080p
mod), 18-and-later can't use it at all. Buildroot keeps the whole
userspace inside 256 MB. This is a hand-rolled LibreELEC-7-era image
you own end to end: kernel defconfig → rootfs → disk image.

**This README is the current truth. [`LOG.md`](LOG.md) is the engineering
history** — decisions, evidence, every failed build and what it taught,
including the two hardware premises this project got wrong and how the
hardware corrected them. **[`ATV1-SPECS.md`](ATV1-SPECS.md) is the
hardware record** — fleet inventory with a provenance tag on every line
(verified / Apple literature / expected-but-unobserved).

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
    etc/fstab                             LABEL mounts: /data survives re-imaging
    etc/init.d/S20datadirs                /data managed tree (media/sync/updates/journal)
    etc/atv1/startkodi.sh                 startx + kodi -fs
    etc/asound.conf.example               HDMI audio default, S/PDIF noted
    root/.kodi/userdata/advancedsettings.xml   RAM-tuned Kodi 17
package/crystalhd/                        LibreELEC-maintained BCM70012 userspace (dormant — no card)
package/atv1-client/                      prebuilt Rust client hook (config only)
tools/build-client.sh                     out-of-era Rust cross-build vs era SDK
client/                                   ← convention path for the built binary (untracked)
```

## 2. Where to build — Linux container either way

This tree lives on **APFS** at `~/ATV1` (moved from ExFAT 2026-10-25;
git and text files are happy here, no AppleDouble junk, permissions
real). What has **not** changed: Buildroot cannot build on macOS itself,
so every build happens in a Linux container, from a copy of this tree —
building *through* a Docker bind-mount of the Mac's disk is technically
possible but glacially slow for Buildroot's hundreds of thousands of
small files. rsync in, build on the container's native fs:

```sh
# macOS side: Docker Desktop or colima. Image is the era-matched host (gcc 6, py2.7).
docker run -it --rm -v ~/ATV1:/atv1-src debian:stretch bash
```

```sh
# inside the container — stretch is archived (LTS ended 2025-06), repoint apt
# at archive.debian.org or apt-get update fails against dead mirrors
printf 'deb http://archive.debian.org/debian stretch main\ndeb http://archive.debian.org/debian-security stretch/updates main\n' > /etc/apt/sources.list
apt-get update -o Acquire::Check-Valid-Until=false && apt-get install -y --no-install-recommends \
  build-essential git cpio rsync file bc wget python perl unzip \
  bison flex sed libncurses-dev libssl-dev ca-certificates

# copy the tree onto the container's own fs — build speed, not correctness
rsync -a /atv1-src/ /root/atv1/
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

## 2a. dl/ cache overrides — era protocol rot (documented, reproducible)

Two era packages download over `git://`, a protocol upstreams have
since retired; the build would hang silently forever. Both tarballs
are staged in the shared `dl/` cache instead — no buildroot source was
touched (the vendor tree stays pristine):

| package | era URL (dead) | staged from | commit |
|---|---|---|---|
| xdriver_xf86-video-intel | `git://anongit.freedesktop.org` | gitlab.freedesktop.org per-commit archive | `b57abe20…` |
| rtmpdump | `git://git.ffmpeg.org` | `sources.buildroot.net` (buildroot's own era snapshot mirror) | `fa8646da…` |

A fresh build host reproduces this with two curls (URLs are the
per-commit archive/snapshot forms above). Neither pkg had a `.hash` at
this era — buildroot warns and accepts; the commit SHAs in the
filenames are the pin. Verified 2026-10-27: no other selected package
uses `git://` (audit: all 30 such pkgs cross-checked against the
generated .config — none selected).

## 3. Era is load-bearing (read before bumping Buildroot)

Everything below was true of Buildroot ≈2017.08 and is false later:

| Dependency | Why 2017.08-era |
|---|---|
| Kodi **17.3** | last release with the CrystalHD accelerator (**removed in 18**) — pays off only if a card is added later |
| Mesa **17.1.x** | unit B's nv40 (Go 7300) needs Mesa's NOUVEAU classic DRI — nv40 support is gone from Mesa ≥ 17.3. Unit A's GMA950 has no buildable hardware GL in this combo at all (classic i915 deleted in 17.1; no i915g/llvmpipe options here) → gallium swrast = GL 2.1 software, exactly Kodi 17's floor |
| kernel **4.9.x LTS** | Buildroot 2017.08's own LTS. NOT pinned by CrystalHD anymore — no card is installed, and the in-tree staging driver is verified absent from 4.9.337 and every later era kernel (an earlier note here claimed the kernel was chosen for crystalhd; the hardware inventory proved that moot) |
| grub2 **i386-efi** target | ATV1 firmware is 32-bit EFI (like MacBook2,1) |
| python2 add-ons | this era's add-on ecosystem |

Newer Buildroot = re-creating all five by hand. Don't chase it. If a
symbol in the defconfig doesn't exist at your era point, `make xconfig`
and search — names drift; §5 lists the ones to verify.

## 4. Kernel bring-up (fragment wired — no manual capture)

`board/atv1/linux.fragment` is merged by Buildroot itself on every
configure: `configs/atv1_defconfig` sets

```
BR2_LINUX_KERNEL_CONFIG_FRAGMENT_FILES="$(BR2_EXTERNAL_ATV1_PATH)/board/atv1/linux.fragment"
```

— i386 defconfig first, fragment second, `oldconfig` resolves. Edit the
fragment, rerun `make atv1_defconfig` (or `linux-reconfigure`), rebuild.
No menuconfig capture, no committed kernel `.config` — the fragment is
the whole record. Syntax rules learned the hard way:

* disable with the canonical `# CONFIG_X is not set` — a
  `# CONFIG_X=n` comment does **not** disable anything (this exact
  form silently "redefined" nothing and left RETPOLINE on);
* never put `# CONFIG_X=y` "future" lines in a fragment — write prose
  instead; comment-styled settings are ambiguous to config mergers.

Non-obvious symbols already reasoned through in the fragment:

* crystalhd: **nothing to enable today** (no card). Verified plan for
  when one arrives: kernel flips to 3.16.85 — the last in-tree home of
  CONFIG_CRYSTALHD (driver deleted in 3.17) — plus the alive
  crystalhd-arch userspace mirror (hash recorded) (fragment prose)
* `CONFIG_DRM_I915=y` — GMA950 is the A1218's only GPU; HDMI rides an
  SDVO bridge (2007 hotplug quirks = Stage-0 watch item). The earlier
  "7300 owns HDMI, never enable i915" bullet was wrong for this machine
  and would have guaranteed a black screen
* `ATA_PIIX` **and** `SATA_AHCI` — 2007 firmware may present either mode
* NIC: broadnet of 2007 candidates (e1000/tg3/bnx2/sky2/r8169) — enable all,
  `dmesg | grep -i eth` tells you which is real, then prune
* `EFI_MIXED=y` — 32-bit EFI handing over to the 32-bit kernel

## 5. menuconfig verification checklist

Era names drift; verify these exist/enabled after `atv1_defconfig`:

- [ ] `MESA3D` → gallium **swrast** driver selected. There is no
      hardware GL option for GMA950 in this era — if `_DRI_DRIVER_I915`
      looks tempting, it is stale: Mesa 17.1 can no longer build that
      driver. Kodi refuses GL < 2.0; swrast is the only honest GL here.
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
- [ ] `eudev` (default on) — device nodes for what's actually present
      (no `/dev/crystalhd` unless a card was added).
- [ ] `crystalhd` (this tree) — **dormant, do not enable yet**: no card
      in the box. Mirror is alive and verified (crystalhd-arch,
      sha512 in `crystalhd.hash`). Card to buy: **BCM970012** card
      (BCM70012 chip, PCI 14e4:1612 — the ONLY id the in-tree driver
      binds). BCM970015/AW-VD920 = wrong card, never works here.
      When a card arrives: flip kernel to 3.16.85 (last in-tree
      driver), enable the package, add `KODI_DEPENDENCIES += crystalhd`,
      rebuild Kodi and CHECK its configure log for crystalhd pickup.

## 6. Booting the box

**Two boot paths, by design (ARCHITECTURE doc §4 "A1218 boot reality"):**

* **Dev path (this tree, today):** GRUB ia32-efi on MBR via the EFI-
  verification bypass loaders (ATV1sm / atv-linux-loader). Fast iteration,
  but it is *not* the product boot story.
* **Product path (Stage-0 target, unobserved):** stock Apple chain —
  firmware loads Apple `boot.efi`, which loads `mach_kernel` (a wrapped
  32-bit kernel + initramfs), GPT layout with the `atvrecv` FAT32 boot
  partition. Buildroot emits the artifacts (bzImage-as-mach_kernel,
  initramfs, hashes) but the exact selection rules/partition map are
  **Unknown until observed on an A1218** — do not fabricate that image
  from a host. gptfdisk is in the rootfs for the observation work.

For path 1: the A1218's firmware verifies its own EFI binaries until you unlock it:

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
   `ps aux | grep kodi`, `lspci -nn | grep -i vga` (expect Intel
   82945G/GZ — GMA950), `dmesg | grep -iE 'i915|drm|sdvo|hDMI'`,
   `ls /dev/fb*`. No /dev/crystalhd unless a card was actually added
   — confirm which NIC got a link with `ifconfig -a`.

Iterate: edit tree → re-copy into container → `make O=/root/out all`
→ re-dd stick. Overlay/post-build changes rebuild in seconds.

### Stage-0 findings (recorded from hardware, 2026-10-27)

- **CPU (both units, CPUID via unit B's OS X):** `SSE SSE2` present —
  the defconfig's "no SSE2 until CPUID proves it" gate is satisfied;
  pentium4 toolchain promotion is unlocked (roadmap; needs a full
  rebuild, deliberately not folded into the baseline).
- **Unit B NIC (ioreg):** Realtek **RTL8139** (`10ec:8139`) → kernel
  `8139too`. None of the original five candidates matched it; they
  stay as insurance until unit A's NIC is seen.
- **Unit B GPU (ioreg display@0):** NVIDIA **Go 7300**, `10de:01d7`,
  Apple subsystem, behind a PCIe bridge, Apple's NVDA driver active —
  it owns this unit's HDMI. The original README "7300" spec was true
  of this unit all along.
- **Unit A GPU:** not yet read directly (stock firmware, no SSH); the
  i915/GMA950 expectation comes from Apple's Mac1,1 spec and the 945
  chipset family. First boot of our image is its confirmation.
- **Identities:** unit A = stock ATV OS, MAC `00:23:32:33:FC:21`, no
  SSH. Unit B = aTVFlash/NitoTV, ATV OS 10.4.7 (8N6014), MAC
  `00:17:F2:F7:98:9D`, `frontrow` SSH needs legacy kex/CBC options.

## 7. Permanent install

Boot the stick, then `dd` the image to the internal bay — the A1218 takes
a **standard 2.5" SATA** drive (no ZIF weirdness), so this is the WD Green
2 TB: P1 boot (32 M) + P2 rootfs (512 M) + P3 ATV1DATA. On target, grow
P3 across the rest of the disk and resize its filesystem — `sgdisk`,
`fdisk`, `e2fsprogs` are all in the rootfs for exactly this. `/data` is
LABEL-mounted, so nothing else needs to change. Never re-image P3; the
re-image model (re-flash P1/P2, keep P3) **is** the A1218 recovery story.
From macOS, after a clean unmount: `sudo dd if=atv1-disk.img of=/dev/rdiskN bs=4m`.

## 8. Roadmap (deliberately not in v1)

- **pentium4 toolchain promotion** — SSE2 proven by CPUID (§6
  findings); every package rebuilds, so it rides the next full build.
- **xstartup GPU-select for unit B** — X probes the iGPU first there;
  when `10de` is present, force the nouveau screen (xorg.conf.d
  snippet or BusID), else unit B paints on the GMA950's dead output.
- **NIC candidate prune-down** — after unit A's NIC is observed, drop
  the unused e1000/tg3/bnx2/sky2/r8169 insurance from the fragment.
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

## 10. Alignment with ARCHITECTURE-APPLE-TV-CONTROLS.md

The appliance design doc (iTunes-for-devices coordinator, Rust-only
client, whole-system Buildroot updates). Where this tree stands against it:

| Doc position | Tree status |
|---|---|
| A1218 boot = Apple EFI/`boot.efi`/`mach_kernel` chain, **experimental/target-specific** | §6 dev-vs-product path split; no fabricated GPT product image until Stage-0 observation (`sgdisk` in rootfs for the observation work) |
| **No OTA activation on A1218**; A/B is hypothetical | No A/B slots in genimage; recovery = re-image P1/P2, P3/`ATV1DATA` persists (S20datadirs + LABEL fstab). Matches "external recovery only" baseline |
| Persistent data / managed roots / update journal separate from system | P3 + `/data/{media,sync,updates,journal,diagnostics}`; media and Kodi sources never point at system partitions |
| Rust-only client, native UI, coordinator agent + Kodi adapter | 2017.08-era Buildroot **predates in-tree Rust (~2018.05)** → two-container split: system in the era image, client cross-built modern-rust → i586 glibc against the era **SDK** (`tools/build-client.sh`), installed by `BR2_PACKAGE_ATV1_CLIENT` |
| Startup model **Unknown** (headless vs foreground-over-Kodi) | startkodi.sh keeps the kiosk; client installs to `/usr/bin/atv1-client` without claiming the display until §8 is decided |
| Kodi adapter **Unknown** (add-on / API / filesystem-only contract) | Kodi 17 JSON-RPC :8080 enabled — the natural first candidate to *test and reject-or-adopt* against the doc's idempotent handoff/ack rules; JSON-RPC ack semantics are weak, so the doc's "never claim success from process presence" bar is exactly the test |
| Reproducible, signed, versioned artifacts; channels/promotion | Era Buildroot predates `BR2_REPRODUCIBLE` (~2020) — reproducibility is best-effort: pinned versions + recorded container digest + `.hash` files; **signing/promotion live outside Buildroot** (artifact + manifest signed after build). v1.0.0 release records = external tooling, per doc §5 |
| Coordinator = local LAN, ports/transport **Unknown** | Nothing in this tree listens except dropbear (dev) and Kodi :8080. No LAN protocol is pre-selected — doc §8 respected |
| LAN distribution is transport-only, device owns verification | N/A until Stage 2; update artifacts land in `/data/updates`, nothing self-activates |

**Doc-Stage → tree mapping:** Stage 0 (boot contract) = §6 product path,
needs hands-on A1218 observation; Stage 1 (UI shell) = Rust client crate;
Stage 1A (control plane) = client crate + no pre-selected transport;
Stage 2 (image pipeline) = this tree + external signing step; Stage 3/4
(reboot/health) = **gated on the boot-chain observation** — the honest
A1218 baseline remains re-image recovery. The doc's own acceptance gate
applies to this README: nothing here is "supported" until M1-M7 evidence
on real hardware.
