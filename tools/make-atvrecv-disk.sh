#!/bin/bash
# make-atvrecv-disk.sh — build the fw-3 "restore-layout" disk image:
#
#   GPT [ P1 FAT32 atvrecv (Apple boot.efi + mach_kernel + plist +
#   Dummy.kext) | P2 ext4 rootfs LABEL=ATV1ROOT | P3 ext4 ATV1DATA ]
#
# This is the ONLY disk shape an unmodified Gen-1 Apple TV firmware 3
# can boot: the recovery scan that Apple never closed (restore had to
# keep working) looks for the Apple TV Recovery partition type GUID
# (5265636F-7665-11AA-AA11-00306543ECAC, verified from GNU parted 3.6
# libparted/labels/gpt.c) and chainloads the SIGNED boot.efi inside it;
# boot.efi then loads our mach_kernel (atv-linux-loader, MIT) which has
# our kernel + initramfs (board/atv1/initramfs-init) embedded, and hands
# off via root=LABEL=ATV1ROOT. Works the same on the rear USB port and
# as an internal IDE disk image.
#
# Inputs (all local, none committed — Apple assets stay device-side):
#   images/boot.efi          extracted from the pinned mesu DMG below
#     DMG https://mesu.apple.com/data/OS/061-7495.20100210.TAVfr/2Z694-6013-013.dmg
#     sha1 97623d8d21bb59b0f4dc9d1b1c037f25c9fe09c3  (pinned by loader README)
#     sha256 of boot.efi: c7f57cc2b37af75597419b0bd2b88b357d2a6f696ce30749a073a0eba25fee40
#   images/dummy-kext/Dummy.kext   github.com/DistroHopper39B/DummyKext 1.0
#   work-loader/atv-linux-loader   github.com/DistroHopper39B/atv-linux-loader
#   images/atv1-disk.img pipeline artifacts: rootfs.ext4 + bzImage
#
# Run from anywhere on the Mac host. Output: images/atv1-recv-disk.img.
set -euo pipefail
export PATH="$HOME/.docker/bin:$PATH"

ATV1="$HOME/ATV1"
IMG="$ATV1/images"
LOADER="$ATV1/work-loader/atv-linux-loader"
BOOT_EFI_SHA=c7f57cc2b37af75597419b0bd2b88b357d2a6f696ce30749a073a0eba25fee40
GUID_ATVRECV=5265636F-7665-11AA-AA11-00306543ECAC
GUID_LINUX=0FC63DAF-8483-4772-8E79-3D69D8477DE4

fail() { echo "make-atvrecv-disk: $*" >&2; exit 1; }

[ -f "$IMG/boot.efi" ] || fail "images/boot.efi missing - extract it from the pinned mesu DMG (see header)"
echo "$BOOT_EFI_SHA  $IMG/boot.efi" | shasum -a 256 -c - || fail "boot.efi sha256 mismatch"
[ -d "$IMG/dummy-kext/Dummy.kext" ] || fail "images/dummy-kext/Dummy.kext missing - unzip Dummy.kext.zip 1.0 (header has URL)"
[ -d "$LOADER" ] || fail "loader source missing at $LOADER"
docker ps >/dev/null || fail "docker daemon not reachable"

echo "== stage 1: initramfs + bzImage out of the era container =="
docker run --rm -v atv1-work:/work -v "$IMG:/export" -v "$ATV1:/atv1-src:ro" \
    atv1-build:stretch sh -eu -c '
    T=/work/out/target; H=/work/out/host; W=/work/tmp/initrd
    [ -x "$T/bin/busybox" ] || { echo "target busybox missing"; exit 1; }
    rm -rf "$W"; mkdir -p "$W/bin" "$W/sbin" "$W/dev" "$W/proc" "$W/sys" \
        "$W/mnt" "$W/root" "$W/tmp"
    for a in sh ash mount umount mkdir sleep cat blkid switch_root ls mknod \
             ifconfig udhcpc arping ping route dmesg sync; do
        ln -f "$T/bin/busybox" "$W/bin/$a"
    done
    # NOTE: do NOT add awk/cut links - this busybox build has neither
    # applet (verified via strings on the binary). Scripts must stay
    # POSIX-ash-only. See LOG.md 2026-10-28.
    cp /atv1-src/board/atv1/initramfs-init "$W/init"
    cp /atv1-src/board/atv1/udhcpc.script "$W/bin/udhcpc.script"
    chmod 0755 "$W/bin/udhcpc.script"
    "$H/bin/python" /atv1-src/tools/mkcpio-newc.py - "$W" | gzip -9n > /export/atv1-initrd.cpio.gz
    cp /work/out/images/bzImage /export/bzImage
    ls -l /export/atv1-initrd.cpio.gz /export/bzImage'
[ -s "$IMG/atv1-initrd.cpio.gz" ] || fail "initrd build produced nothing"

echo "== stage 2: mach_kernel (atv-linux-loader, clang --target=i386-apple-darwin8) =="
( cd "$LOADER" \
  && { grep -q ATV1-FIX linux.c \
       || patch -p1 -i "$ATV1/tools/patches/atv-loader-payload-offset.patch" \
       || fail "loader payload-offset patch would not apply"; } \
  && rm -f mach_kernel kernel_bin.h initramfs_bin.h *.o \
  && make KERNEL="$IMG/bzImage" INITRAMFS="$IMG/atv1-initrd.cpio.gz" >/dev/null \
  && cp mach_kernel "$IMG/mach_kernel" )
[ -s "$IMG/mach_kernel" ] || fail "mach_kernel build produced nothing"

echo "== stage 3: assemble GPT disk in the era container =="
docker run --rm -v atv1-work:/work -v "$IMG:/export" -v "$ATV1:/atv1-src:ro" \
    atv1-build:stretch bash -eu -o pipefail -c '
    H=/work/out/host; export MTOOLS_SKIP_CHECK=1
    export PATH="$H/bin:$H/sbin:/usr/sbin:/usr/bin:/bin"
    W=/work/tmp/atvrecv; rm -rf "$W"; mkdir -p "$W"
    # P1: 64 MiB FAT32, label ATVRECV, mtools-populated (no loop devices
    # in the container, but mtools speaks image files directly).
    dd if=/dev/zero of="$W/atvrecv.fat" bs=1M count=64 status=none
    mkdosfs -F 32 -n ATVRECV "$W/atvrecv.fat" >/dev/null
    M=(-i "$W/atvrecv.fat")
    mmd "${M[@]}" ::/System
    mmd "${M[@]}" ::/System/Library
    mmd "${M[@]}" ::/System/Library/Extensions
    cp /atv1-src/tools/atvrecv-boot.plist "$W/com.apple.Boot.plist"
    mcopy "${M[@]}" -o /export/boot.efi      ::/
    mcopy "${M[@]}" -o /export/mach_kernel   ::/
    mcopy "${M[@]}" -o "$W/com.apple.Boot.plist" ::/
    mcopy -s "${M[@]}" -o /export/dummy-kext/Dummy.kext ::/System/Library/Extensions/
    echo "P1 contents:"; mdir "${M[@]}" ::; mdir "${M[@]}" ::/System/Library/Extensions
    # P2: rootfs copy, labeled (idempotent even after post-image step)
    cp /work/out/images/rootfs.ext4 "$W/rootfs.img"
    tune2fs -L ATV1ROOT "$W/rootfs.img" >/dev/null
    # P3: data fs straight from the pipeline (already labeled ATV1DATA)
    cp /work/out/images/atv1-data.ext4 "$W/data.img"
    "$H/bin/python" /atv1-src/tools/atvrecv_gpt.py /export/atv1-recv-disk.img \
        "$W/atvrecv.fat:5265636F-7665-11AA-AA11-00306543ECAC:atvrecv" \
        "$W/rootfs.img:0FC63DAF-8483-4772-8E79-3D69D8477DE4:atv1root" \
        "$W/data.img:0FC63DAF-8483-4772-8E79-3D69D8477DE4:atv1data"'

echo "== result =="
shasum -a 256 "$IMG/atv1-recv-disk.img"
ls -l "$IMG/atv1-recv-disk.img"
SECT=$(($(stat -f %z "$IMG/atv1-recv-disk.img") / 512))
echo "sectors: $SECT  (use this in the read-back verify count)"
