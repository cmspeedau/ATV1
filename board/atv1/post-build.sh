#!/bin/sh
# Runs with TARGET_DIR populated, before the rootfs image is built.
set -eu

# Exec-bit safety net: the tree lives on APFS now and stores modes
# properly, but copies (Finder, zip, an ExFAT detour) can strip them,
# and an init script without +x fails silently at boot. Make every
# overlay script executable regardless.
[ -f "$TARGET_DIR/etc/atv1/startkodi.sh" ] && chmod 0755 "$TARGET_DIR/etc/atv1/startkodi.sh"
[ -f "$TARGET_DIR/etc/init.d/S20datadirs" ] && chmod 0755 "$TARGET_DIR/etc/init.d/S20datadirs"
[ -f "$TARGET_DIR/etc/init.d/S50kodi" ] && chmod 0755 "$TARGET_DIR/etc/init.d/S50kodi"

# ssh fleet pubkey (README §5): tighten perms regardless of how the
# overlay was copied (dropbear refuses sloppy authorized_keys modes).
[ -d "$TARGET_DIR/root/.ssh" ] && chmod 0700 "$TARGET_DIR/root/.ssh"
[ -f "$TARGET_DIR/root/.ssh/authorized_keys" ] && chmod 0600 "$TARGET_DIR/root/.ssh/authorized_keys"

# Prebuilt Rust client (ARCHITECTURE doc; era Buildroot has no rustc —
# see package/atv1-client/Config.in and tools/build-client.sh).
# NOTE the :- default: unselected BR2_ options are UNSET in the
# post-build environment, and set -u makes a bare ${VAR} an instant
# fatal error (this exact mistake killed target-finalize 2026-10-27).
if [ "${BR2_PACKAGE_ATV1_CLIENT:-}" = "y" ]; then
        CLIENT="${BR2_EXTERNAL_ATV1_PATH:-}/client/atv1-client"
        if [ -f "$CLIENT" ]; then
                install -m 0755 "$CLIENT" "$TARGET_DIR/usr/bin/atv1-client"
                echo "post-build: installed atv1-client from $CLIENT"
        else
                echo "post-build: BR2_PACKAGE_ATV1_CLIENT=y but $CLIENT missing" >&2
                exit 1
        fi
fi

# skin.atv (GPL-2.0-only, original artwork — see skin/skin.atv/README.md):
# installed into Kodi's user-dir addons; the overlay's
# userdata/guisettings.xml selects it via lookandfeel.skin. All raster
# assets are GENERATED at build time by tools/gen_assets.py (stdlib
# python — container host python is python2, script is 2/3-safe): no
# binary PNGs in git, no Apple assets, visual identity auditable as
# source. Fonts come from BR2_PACKAGE_DEJAVU; install path varies by
# package, so FIND it — never guess (silent-drop lesson).
if [ -d "${BR2_EXTERNAL_ATV1_PATH:-}/skin/skin.atv" ]; then
        SKIN="$TARGET_DIR/root/.kodi/addons/skin.atv"
        rm -rf "$SKIN"
        mkdir -p "$SKIN/media" "$SKIN/fonts"
        cp -a "${BR2_EXTERNAL_ATV1_PATH}/skin/skin.atv/." "$SKIN/"
        python "$SKIN/tools/gen_assets.py"
        for f in DejaVuSans.ttf DejaVuSans-Bold.ttf; do
                SRC=$(find "$TARGET_DIR/usr/share/fonts" -name "$f" 2>/dev/null | head -1)
                if [ -n "$SRC" ]; then
                        install -m 0644 "$SRC" "$SKIN/fonts/$f"
                else
                        echo "post-build: $f not in target — BR2_PACKAGE_DEJAVU missing?" >&2
                        exit 1
                fi
        done
        echo "post-build: installed skin.atv -> $SKIN (assets generated, fonts copied)"
fi

exit 0
