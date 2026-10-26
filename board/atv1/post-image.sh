#!/bin/sh
# Assemble the EFI layout and build the whole-disk image.
# Runs after rootfs.ext4 / bzImage / the grub2 efi-part exist in BINARIES_DIR.
set -eu

BIN_DIR="${BINARIES_DIR:?}"
BOARD_DIR="$(cd "$(dirname "$0")" && pwd)"

# This era's grub2 package (BR2_TARGET_GRUB2_I386_EFI) produces a whole
# EFI system partition skeleton: images/efi-part/EFI/BOOT/bootia32.efi
# (+ startup.nsh + its own grub.cfg). Observed 2026-10-27; an earlier
# version of this script searched maxdepth 2 and could never see a file
# that lives three directories down.
GRUB_EFI="$(find "$BIN_DIR/efi-part" -maxdepth 4 -type f -name 'bootia32.efi' \
        2>/dev/null | head -n1)"

if [ -z "$GRUB_EFI" ]; then
        echo "post-image: no bootia32.efi under $BIN_DIR/efi-part:" >&2
        ls -lR "$BIN_DIR" >&2
        exit 1
fi

# The grub.cfg buildroot generated hardcodes root=/dev/sda1 — wrong for
# our layout (rootfs is partition 2). Replace it with the board config:
# internal-vs-USB root entries, rootwait/rootdelay, and console=tty1 +
# console=ttyS0,57600 (onboard UART = the Stage-0 bring-up console).
GRUB_CFG_SRC="$BOARD_DIR/../grub-i386-efi.cfg"
[ -f "$GRUB_CFG_SRC" ] || { echo "post-image: missing $GRUB_CFG_SRC" >&2; exit 1; }

echo "post-image: EFI from $GRUB_EFI, grub.cfg from $GRUB_CFG_SRC"
rm -rf "$BIN_DIR/EFI"
mkdir -p "$BIN_DIR/EFI/boot"
cp -f "$GRUB_EFI" "$BIN_DIR/EFI/boot/bootia32.efi"
cp -f "$GRUB_CFG_SRC" "$BIN_DIR/EFI/boot/grub.cfg"

# P3 data partition content: an EMPTY ext4 labeled ATV1DATA, formatted
# here because genimage 9 ext images are fed from --rootpath (= the
# whole target rootfs; see genimage.cfg comment for the ENOSPC story).
# 65536 x 1K = 64 MiB; -F because it is a regular file. mkfs.ext4 and
# friends are on PATH here — post-image runs with buildroot's host/bin
# (that is also how 'genimage' itself resolves).
DATA_IMG="$BIN_DIR/atv1-data.ext4"
rm -f "$DATA_IMG"
mkfs.ext4 -F -q -L ATV1DATA "$DATA_IMG" 65536
echo "post-image: data fs $DATA_IMG (label ATV1DATA, 64 MiB, empty)"

exec support/scripts/genimage.sh -c "$BOARD_DIR/genimage.cfg"
