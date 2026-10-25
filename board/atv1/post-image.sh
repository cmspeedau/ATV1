#!/bin/sh
# Assemble the EFI layout and build the whole-disk image.
# Runs after rootfs.ext4 / bzImage / grub image exist in BINARIES_DIR.
set -eu

BIN_DIR="${BINARIES_DIR:?}"

# Locate the GRUB ia32 EFI image produced by the grub2 package.
# Buildroot has named this artifact a few different ways across eras:
#   bootia32.efi, grub_i386_efi.efi, grub_i386-efi.img, core.efi
GRUB_EFI="$(find "$BIN_DIR" -maxdepth 2 -type f \
        \( -name 'bootia32.efi' -o -name 'grub*ia32*.efi*' -o -name 'grub*i386*.efi*' -o -name 'grub_i386*img' \) \
        | head -n1)"

if [ -z "$GRUB_EFI" ]; then
        echo "post-image: no GRUB ia32 EFI image found in $BIN_DIR:" >&2
        ls -l "$BIN_DIR" >&2
        echo "Adjust the find(1) names in board/atv1/post-image.sh to match" >&2
        echo "what 'make' produced for BR2_TARGET_GRUB2_I386_EFI." >&2
        exit 1
fi

echo "post-image: installing $GRUB_EFI -> EFI/boot/bootia32.efi"
mkdir -p "$BIN_DIR/EFI/boot"
cp -f "$GRUB_EFI" "$BIN_DIR/EFI/boot/bootia32.efi"

exec support/scripts/genimage.sh -c "$(dirname "$0")/genimage.cfg"
