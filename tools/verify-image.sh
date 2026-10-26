#!/bin/sh
# Verify atv1-disk.img end to end — run inside the era build container
# (needs sfdisk/mdir/tune2fs; macOS host has none of them):
#
#   docker run --rm -v atv1-work:/work -v ~/ATV1/images:/export \
#     atv1-build:stretch /atv1-src/tools/verify-image.sh /export/atv1-disk.img
#
# Checks (all read from the actual bytes, not the build log):
#   1. MBR: three dos partitions, P1 type 0xC bootable
#   2. P1 (vfat): contains bzImage and EFI/boot/bootia32.efi
#   3. P2 (rootfs): mountable ext, label reported
#   4. P3 (data): ext4 labeled ATV1DATA, ~64 MiB, empty
set -eu

# Verify with the SAME era binaries that built the image (mdir/tune2fs/
# dumpe2fs live in buildroot's host/bin; debian-stretch base lacks them).
PATH="/work/out/host/bin:$PATH"

IMG="${1:?usage: verify-image.sh /export/atv1-disk.img}"
DIR=$(mktemp -d)
trap 'rm -rf "$DIR"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# sfdisk (util-linux, MBR mode) dumps 'start= N, size= N, Id= X[, bootable]'
pd() { sfdisk -d "$IMG" 2>/dev/null | grep "img$1[ :]" || true; }
part_start() { echo "$1" | sed -n 's/.*start= *\([0-9]*\).*/\1/p'; }
part_size()  { echo "$1" | sed -n 's/.*size= *\([0-9]*\).*/\1/p'; }

P1=$(pd 1); P2=$(pd 2); P3=$(pd 3)
[ -n "$P1" ] && [ -n "$P2" ] && [ -n "$P3" ] || fail "expected 3 partitions, got: [$P1][$P2][$P3]"
# this era's sfdisk prints 'type=c'; later ones 'Id=  c' — match both
echo "$P1" | grep -Eq '(type|Id)= *c' || fail "P1 not type 0xC (W95 FAT): $P1"
echo "$P1" | grep -q bootable        || fail "P1 not marked bootable: $P1"
echo "OK  MBR: P1 fat+bootable | P2 $(part_size "$P2") sect | P3 $(part_size "$P3") sect"

# P1: extract and inspect the FAT
dd if="$IMG" of="$DIR/p1" bs=512 skip="$(part_start "$P1")" count="$(part_size "$P1")" status=none
# NB: mdir prints 8.3 short names with a SPACE for the dot ('grub     cfg')
mdir -i "$DIR/p1" :: | grep -Eiq 'bzimage'                || fail "bzImage missing from boot.vfat"
mdir -i "$DIR/p1" ::EFI/BOOT | grep -Eiq 'bootia32[ .]efi' || fail "EFI/BOOT/bootia32.efi missing"
mdir -i "$DIR/p1" ::EFI/BOOT | grep -Eiq 'grub[ .]+cfg'    || fail "EFI/BOOT/grub.cfg missing"
echo "OK  P1 vfat: bzImage + EFI/boot/bootia32.efi + grub.cfg present"

# P2: the rootfs ext (label reported, content is stamped buildroot)
dd if="$IMG" of="$DIR/p2" bs=512 skip="$(part_start "$P2")" count="$(part_size "$P2")" status=none
P2LBL=$(tune2fs -l "$DIR/p2" 2>/dev/null | awk -F: '/volume name/{gsub(/^ +/,"",$2);print $2}')
[ -n "$P2LBL" ] || fail "P2 is not an ext filesystem"
echo "OK  P2 ext rootfs (label: ${P2LBL:-none})"

# P3: empty ext4 labeled ATV1DATA
dd if="$IMG" of="$DIR/p3" bs=512 skip="$(part_start "$P3")" count="$(part_size "$P3")" status=none
P3LBL=$(tune2fs -l "$DIR/p3" 2>/dev/null | awk -F: '/volume name/{gsub(/^ +/,"",$2);print $2}')
[ "$P3LBL" = "ATV1DATA" ] || fail "P3 label is '$P3LBL', want ATV1DATA"
KBLK=$(dumpe2fs -h "$DIR/p3" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2);print $2}')
[ "${KBLK:-0}" -ge 65536 ] || fail "P3 fs too small: $KBLK blocks"
# 'empty' means NO USER CONTENT — a clean mkfs.ext4 legitimately spends
# ~11% of a 64 MiB fs on journal + metadata, so free-blocks is the wrong
# test. debugfs says the root dir's size: 12-1024 B with only . ..
# lost+found present is the ground truth for 'nothing installed'.
ROOTSZ=$(debugfs -R "stat /" "$DIR/p3" 2>/dev/null | sed -n 's/.*[Ss]ize: \([0-9]*\).*/\1/p' | head -1)
[ "${ROOTSZ:-0}" -gt 0 ] && [ "${ROOTSZ:-9999}" -le 1024 ] \
  || fail "P3 root dir not empty (dir size ${ROOTSZ:-unreadable} B)"
echo "OK  P3 ext4: label ATV1DATA, $KBLK blocks, root dir ${ROOTSZ} B = empty as designed"

echo "ALL OK: $IMG"
