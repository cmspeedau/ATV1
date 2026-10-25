#!/bin/sh
# Runs with TARGET_DIR populated, before the rootfs image is built.
set -eu

# ExFAT safety net: the external tree may live on a volume that cannot
# store exec bits (this project's tree lives on /Volumes exFAT). Make
# every shell script in the overlay executable regardless.
[ -f "$TARGET_DIR/etc/atv1/startkodi.sh" ] && chmod 0755 "$TARGET_DIR/etc/atv1/startkodi.sh"

exit 0
