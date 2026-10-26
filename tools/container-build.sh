#!/bin/bash
# Runs INSIDE atv1-build:stretch (tools/Dockerfile.build).
# Idempotent: /work is a docker volume, so an interrupted build resumes.
#
#   docker run -d --name atv1-build \
#     -v ~/ATV1:/atv1-src:ro -v ~/ATV1/images:/export \
#     -v atv1-work:/work atv1-build:stretch \
#     /atv1-src/tools/container-build.sh
#
# pipefail matters: without it, a failing `make | tee` looks like
# success and the script reports "finished" on a broken build (seen
# 2026-10-26: kernel archprepare error was masked, FAIL line lied).
set -euo pipefail

BR=/work/buildroot
EXT=/work/atv1
OUT=/work/out
DL=/work/dl
LOG=/work/build.log

[ -d "$BR/.git" ] || git clone --depth 1 --branch 2017.08.x \
  https://git.buildroot.net/buildroot "$BR"

# always sync the freshest external tree (source is mounted read-only)
mkdir -p "$EXT"
rsync -a --delete --exclude='images/' --exclude='.git/' /atv1-src/ "$EXT/"

make -C "$BR" O="$OUT" BR2_EXTERNAL="$EXT" BR2_DL_DIR="$DL" atv1_defconfig

# Explicitly prebuild the host tools genimage 9 execs at post-image time
# (genext2fs, tune2fs via e2fsprogs, mkdosfs via dosfstools, mcopy/mmd
# via mtools). Root lesson from two 'not found' failures: this era's
# buildroot only instantiates a package's rules when its .config symbol
# is enabled (HOST_GENIMAGE_DEPENDENCIES pointing at an uninstantiated
# package is a phantom), and relying on the dependency graph to order
# these against post-image is subtle. Forcing them here is idempotent
# (no-op once their stamps exist) and makes post-image deterministic.
make -C "$BR" O="$OUT" BR2_EXTERNAL="$EXT" BR2_DL_DIR="$DL" \
  host-genext2fs host-e2fsprogs host-dosfstools host-mtools

make -C "$BR" O="$OUT" BR2_DL_DIR="$DL" -j"$(nproc)" 2>&1 | tee "$LOG"

# hand the artifact back; genimage writes atv1-disk.img under images/
if [ -f "$OUT/images/atv1-disk.img" ]; then
  cp -f "$OUT/images/atv1-disk.img" /export/atv1-disk.img
  cp -f "$LOG" /export/build.log 2>/dev/null || true
  echo "OK: /export/atv1-disk.img written"
else
  echo "FAIL: build finished but atv1-disk.img is missing — see $LOG" >&2
  exit 1
fi
