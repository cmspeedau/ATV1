#!/bin/sh
# seed-dl.sh — (re)seed the build download cache on a fresh machine from
# THIS repo's GitHub Release. Rationale: two era downloads are already
# dead upstream; "the internet still has it" is not a reproducibility
# story. The bundle (158 tarballs incl. both dead-upstream overrides,
# minus the abandoned-kernel graveyard) is the one mirror we control.
#
# Two independent integrity gates — nothing passes silently:
#   1. this script pins the tarball sha256;
#   2. buildroot still verifies every .hash at build time, per file.
#
# Usage (host; needs the atv1-build:stretch image built — README §2):
#   tools/seed-dl.sh
# Idempotent: on a seeded volume, same-name files are rewritten with
# identical bytes and extras are kept.

set -eu

URL="https://github.com/cmspeedau/ATV1/releases/download/1/atv1-dl.tar"
SHA256="e555a313b36ce7936e09c0edce53dff7c5700b5ceab5a260e701a8f2fdcf328a"

HERE=$(cd "$(dirname "$0")/.." && pwd)
T="$HERE/images/atv1-dl.tar"          # images/ is gitignored; upload source lives here too
export PATH="$HOME/.docker/bin:$PATH"

if [ ! -f "$T" ]; then
        echo "downloading $URL"
        curl -fL --retry 3 -o "$T.part" "$URL"
        mv "$T.part" "$T"
fi

ACTUAL=$(shasum -a 256 "$T" | awk '{print $1}')
if [ "$ACTUAL" != "$SHA256" ]; then
        echo "seed-dl: SHA256 MISMATCH — refusing to seed" >&2
        echo "  expected $SHA256" >&2
        echo "  actual   $ACTUAL" >&2
        echo "  delete $T and rerun to re-download" >&2
        exit 1
fi
echo "sha256 OK: $ACTUAL"

docker volume inspect atv1-work >/dev/null 2>&1 || docker volume create atv1-work >/dev/null
docker run --rm -v atv1-work:/work -v "$HERE/images:/export" atv1-build:stretch \
        tar xf /export/atv1-dl.tar -C /work
echo "seeded /work/dl: $(docker run --rm -v atv1-work:/work atv1-build:stretch sh -c 'ls /work/dl | wc -l') entries"
