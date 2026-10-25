#!/bin/sh
# Runs INSIDE atv1-build:stretch (tools/Dockerfile.build).
# Idempotent: /work is a docker volume, so an interrupted build resumes.
#
#   docker run -d --name atv1-build \
#     -v ~/ATV1:/atv1-src:ro -v ~/ATV1/images:/export \
#     -v atv1-work:/work atv1-build:stretch \
#     /atv1-src/tools/container-build.sh
set -eu

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
