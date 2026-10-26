# ATV1 (Apple TV 1st gen, A1218 / Mac1,1) — Hardware Specifications

The fleet's hardware record. Companion to `README.md` (current truth) and
`LOG.md` (engineering history); this file answers "what is the silicon"
and — the part that matters here — **how do we know each line**.

Provenance tags:
- **[V]** — verified first-hand on our own units (ioreg / CPUID / `sw_vers`
  over SSH), 2026-10-27. Raw outputs live in `LOG.md`; expect scripts at
  `/private/var/folders/.../opencode/atv-stage0*.exp`.
- **[A]** — Apple's published spec literature (archived), not re-measured.
- **[E]** — expected/assumed, NOT yet observed on the unit in question;
  first boot of our image confirms or corrects.

## Platform (shared by both units)

| Item | Spec | Provenance |
|---|---|---|
| CPU | Intel Pentium M "Crofton" @ 1.00 GHz, 32-bit (i386), SSE2-capable | [V] CPUID via unit B |
| CPU brand string | reports `Genuine Intel(R) processor` — Apple masked it | [V] |
| CPUID features | `FPU VME DE PSE TSC MSR PAE MCE CX8 APIC SEP MTRR PGE MCA CMOV PAT CLFSH DS ACPI MMX FXSR SSE SSE2 SS TM EST TM2` | [V] verbatim |
| SSE2 | **present** — toolchain may use pentium4 codegen | [V] |
| Memory | 256 MB RAM, soldered | [A]; usable size [E] |
| Chipset | Intel 945 family + ICH7: PCI `8086:27xx` devices throughout the tree | [V] ids observed |
| iGPU | Intel GMA 950 (integrated in the 945 northbridge) | [A] + [V] on unit A side via chipset [E] for its display path |
| Ethernet | **Realtek RTL8139** PCI `10ec:8139` (10/100) | [V] unit B — decisive, none of the five "likely" NIC drivers matched |
| WiFi | Broadcom, Apple subsystem (`14e4:????`, subsystem `106b`) | [V] vendor; exact SKU not decoded |
| USB | 2× USB 2.0 | [A]; our first-boot test uses a modest USB 2.0 stick |
| SATA | one 2.5" SATA port (stock HDD was 40 GB) | [A]; current disk per unit unknown |
| Firmware | Apple EFI, **32-bit IA32 EFI** → `bootia32.efi`, not bootx64 | [A]/community; [E] — the biggest unknown, confirmed only when our stick boots |
| Video out | HDMI (via SDVO on the 945); Apple listed up to 1080i — 720p is the honest envelope for this build | [A]; SDVO quirks [E] |
| Audio out | HDMI audio (AC97/HDA era) + optical/TOSLINK | [A]; not yet exercised |
| Input | IR receiver (Apple Remote); front LED | [A] |
| Console | onboard UART header, 57600 8N1 (community-documented mod) | community; [E] |
| Cooling | passive, fanless — silent by design | [V] by observation; thermals during decode [E] |

## Expansion slot (mini-PCIe)

- One user-accessible mini-PCIe slot behind a PCIe bridge
  (`IOPCI2PCIBridge` in the ioreg tree). [V]
- **CrystalHD plan:** if a decoder card is added it **must** be a
  BCM970012 (BCM70012 chip, PCI `14e4:1612`) — the only id the in-tree
  driver ever bound; BCM970015 / AW-VD920 look identical and do NOT work.
  In-tree driver existed through kernel 3.16.x, deleted in 3.17. [V]
  (source archaeology in `LOG.md`)
- No CrystalHD card is installed in either unit today. [V]

## Fleet inventory

### Unit A — stock
- Firmware: original Apple ATV OS (no softmod), no SSH. [V] (banner-less,
  port 22 closed)
- MAC: `00:23:32:33:FC:21` (Apple wired OUI `00:23:32`). [V]
- Services seen: web config on :8080 (resets clients other than Safari),
  DAAP :3689. [V]
- GPU: GMA950 path — **expected** from Apple's Mac1,1 spec + chipset
  family, not yet read directly. [E]
- NIC: assumed RTL8139 like unit B (same product line). [E]

### Unit B — aTVFlash / NitoTV mod
- Firmware base: Apple TV OS 10.4.7, build **8N6014** (= official
  firmware 3.0.2, the last one) + aTV Flash softmod. [V]
- MAC: `00:17:F2:F7:98:9D` (Apple wired OUI `00:17:f2`). [V]
- SSH: `frontrow`/`frontrow`; needs legacy OpenSSH flags
  (diffie-hellman-group1-sha1 / ssh-rsa / CBC ciphers — unit B only,
  never elsewhere). Its OS X has a near-empty PATH and no `sort`/`uniq`. [V]
- **GPU: NVIDIA GeForce Go 7300 (G72M), PCI `10de:01d7`**, Apple
  subsystem (`106b`), 64-bit GART, behind the PCIe bridge — a mini-PCIe
  graphics-upgrade card, and it **owns this unit's HDMI** (Apple's NVDA
  driver loaded on it, display@0 active). [V]
- GMA950 also present as secondary device. [V]

## Implications for our image (one image, both units)

| Concern | Unit A | Unit B |
|---|---|---|
| Kernel DRM | `i915` | `nouveau` (+i915 built too; both in one image) |
| X DDX | xf86-video-intel | xf86-video-nouveau |
| GL | Mesa gallium **swrast** (GL 2.1 software) | Mesa 17.1 **nv40 classic DRI** (hardware GL) |
| Screen choice | default probe | [E] X probes the iGPU first — **TODO: xstartup must force the nouveau screen** (roadmap) |
| NIC | `8139too` [E] | `8139too` [V] |

## Still Unknown (each has a planned observation)

1. 32-bit EFI boot of our image (biggest risk) — first USB boot, Stage 0.
2. Unit A NIC + GPU truth — same boot.
3. SDVO→HDMI hotplug behavior on stock hardware — same boot, `dmesg`.
4. swrast at 1 GHz / 256 MB — Stage 1 usage observation.
5. RAM ceiling and disk identity per unit — `free`/`lsblk` at first boot.
6. Unit B's exact WiFi SKU — `ioreg` decode if it ever matters (no WiFi
   driver in our image this era; documented non-feature).
