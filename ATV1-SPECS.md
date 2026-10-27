# ATV1 (A1218 / Mac1,1) — Hardware Facts

Fleet hardware record. Every line tagged by how it is known:
- **[V]** verified on our units via SSH (`ioreg`/`CPUID`/`sw_vers`), 2026-10-27
- **[A]** Apple's published literature, not re-measured
- **[E]** expected, NOT yet observed — first boot of our image confirms or corrects

Probe access to unit B (reference unit; these flags for THAT host only):

```sh
ssh -oKexAlgorithms=+diffie-hellman-group1-sha1 \
    -oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedAlgorithms=+ssh-rsa \
    -oCiphers=+aes256-cbc,aes128-cbc,3des-cbc frontrow@10.0.0.8
# user/pass: frontrow/frontrow. PATH is nearly empty: export
# PATH=/bin:/usr/bin:/sbin:/usr/sbin first; sort/uniq absent, use awk.
```

## Shared platform

| Item | Spec | Tag |
|---|---|---|
| CPU | Pentium M "Crofton" 1.00 GHz, 32-bit; brand string masked to `Genuine Intel(R) processor` | [V] |
| CPUID features | `FPU VME DE PSE TSC MSR PAE MCE CX8 APIC SEP MTRR PGE MCA CMOV PAT CLFSH DS ACPI MMX FXSR SSE SSE2 SS TM EST TM2` | [V] |
| SSE2 | present → pentium4 codegen permitted (promotion still deferred; full rebuild) | [V] |
| RAM | 256 MB soldered | [A]; usable [E] |
| Chipset | Intel 945 + ICH7, all PCI ids `8086:27xx` | [V] |
| iGPU | Intel GMA 950 (northbridge-internal) | [A]; display path live [E] |
| Ethernet | Realtek RTL8139, PCI `10ec:8139`, 10/100 → driver `8139too` | [V] unit B; [E] unit A |
| WiFi | Broadcom `14e4`, Apple subsystem `106b`; SKU undecoded; no driver in our image (era b43 needs extracted firmware — use wire) | [V] vendor |
| USB | 2× USB 2.0 | [A] |
| SATA | one 2.5" SATA port (stock HDD 40 GB; current disks per unit unknown) | [A]/[E] |
| Firmware | 32-bit Apple IA32 EFI → `bootia32.efi`; verifies its own EFI binaries until unlocked | [A]; boot [E] |
| Video out | HDMI via SDVO on the 945 (hotplug quirks [E]) | [A] |
| Audio out | HDMI + optical | [A]; unexercised |
| Other | IR receiver (Apple Remote), front LED, fanless/passive | [A]/[V] |
| Console | UART header, 57600 8N1 | community docs; [E] |

## Expansion slot (mini-PCIe)

- One slot behind a PCIe bridge (`IOPCI2PCIBridge` in ioreg tree). [V]
- CrystalHD: buy ONLY BCM970012 (BCM70012 chip, PCI `14e4:1612` — only id
  the in-tree driver binds; BCM970015/AW-VD920 identical-looking, never
  work). Driver in-tree ≤ 3.16.x, deleted 3.17 → kernel flip 3.16.85. [V]
- No CrystalHD card installed in either unit. [V]

## Units

### Unit A — stock (10.0.0.46 when up)
- Original Apple ATV OS; SSH closed; :8080 web resets non-Safari; DAAP :3689. [V]
- MAC `00:23:32:33:FC:21`. [V]
- GPU (GMA950) and NIC (RTL8139): expected from unit B + Apple spec. [E]
- Rear panel carries a **USB 2.0 host port** (photo import; also the era
  patchstick entry point) — owner-observed, and Apple's archived tech
  specs list it. Correction logged 2026-10-27 (earlier chat claim "no
  external USB" was wrong twice over: port exists, and is exactly where
  our stick was plugged). [V: apple.com/appletv/specs via archive 2008-12]
- Apple-era SKUs: 40GB or 160GB drive, Wi-Fi draft-n (SKU details moot:
  wired design). [V: same spec page]

### Unit B — aTVFlash/NitoTV mod (10.0.0.8)
- Base OS: Apple TV OS 10.4.7, build 8N6014 = firmware 3.0.2 (last
  official), plus aTV Flash softmod; SSH as frontrow (flags above). [V]
- MAC `00:17:F2:F7:98:9D`. [V]
- GPU: NVIDIA GeForce Go 7300 (G72M), PCI `10de:01d7`, Apple subsystem
  `106b`, 64-bit GART, behind the PCIe bridge (mini-PCIe upgrade card);
  Apple NVDA driver bound; **owns this unit's HDMI**; GMA950 also present
  as secondary. [V]

## Per-unit stack in our image (one image, both units)

| Concern | Unit A | Unit B |
|---|---|---|
| kernel DRM | i915 | nouveau (both built in) |
| X DDX | xf86-video-intel | xf86-video-nouveau |
| GL | swrast (GL 2.1 software) | nv40 classic DRI (hardware) |
| screen pick | default probe OK | [E] X probes iGPU first → xstartup must force nouveau (roadmap) |
| NIC | 8139too [E] | 8139too [V] |

## Access on OUR image (documented by design)

- ssh (dropbear, auto-start): `root` / `frontrow` — plain on purpose,
  a LAN appliance people must be able to administer, same convention
  unit B's mod already uses. Resets every re-flash. [V at defconfig;
  first-boot confirmation pending]
- Admin key (no password): ed25519 fleet keypair; public half baked to
  `/root/.ssh/authorized_keys`, private half lives ONLY at
  `~/.ssh/atv1_fleet` on the admin machine. [V target audit]
- Serial console 57600 8N1: `login:` root, same password.
- Kodi kiosk needs no credential; media/management = coordinator.

## Open items (observation that closes each)

| Unknown | Closed by |
|---|---|
| 32-bit EFI boot path (biggest risk) | first USB boot |
| stock USB-boot openness (firmware-era lottery) | read unit A: Settings → Version on screen; AND the restore-layout stick (signed boot.efi chain) — our MBR+bootia32 stick can NEVER be blessed by stock EFI regardless of era: signature, not format, is the wall |
| unit A NIC + GPU | same boot: `lspci -nn`, `ifconfig -a` |
| SDVO/HDMI behavior | same boot: `dmesg \| grep -iE 'drm\|sdvo\|hdmi'` |
| swrast speed at 1 GHz | first playback session |
| RAM ceiling, disk identity per unit | `free`, `lsblk` at first boot |
| WiFi SKU | ioreg decode if ever needed (not needed: wired design) |
