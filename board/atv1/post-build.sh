#!/bin/sh
# Runs with TARGET_DIR populated, before the rootfs image is built.
set -eu

# ExFAT safety net: the external tree may live on a volume that cannot
# store exec bits (this project's tree lives on /Volumes exFAT). Make
# every shell script in the overlay executable regardless.
[ -f "$TARGET_DIR/etc/atv1/startkodi.sh" ] && chmod 0755 "$TARGET_DIR/etc/atv1/startkodi.sh"
[ -f "$TARGET_DIR/etc/init.d/S20datadirs" ] && chmod 0755 "$TARGET_DIR/etc/init.d/S20datadirs"

# Prebuilt Rust client (ARCHITECTURE doc; era Buildroot has no rustc —
# see package/atv1-client/Config.in and tools/build-client.sh).
if [ "${BR2_PACKAGE_ATV1_CLIENT}" = "y" ]; then
        CLIENT="${BR2_EXTERNAL_ATV1_PATH:-}/client/atv1-client"
        if [ -f "$CLIENT" ]; then
                install -m 0755 "$CLIENT" "$TARGET_DIR/usr/bin/atv1-client"
                echo "post-build: installed atv1-client from $CLIENT"
        else
                echo "post-build: BR2_PACKAGE_ATV1_CLIENT=y but $CLIENT missing" >&2
                exit 1
        fi
fi

exit 0
