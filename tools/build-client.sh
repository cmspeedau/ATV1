#!/bin/sh
# build-client.sh — cross-build the Rust appliance client for ATV1.
#
# WHY this script exists: Buildroot 2017.08-era has no Rust toolchain
# (rust arrived ~2018.05), but the era is pinned by Kodi 17 / Mesa nv40 /
# kernel 4.14. The split is therefore: system = era container,
# client = modern Rust toolchain linking against the era SDK.
#
# Run from the CLIENT SOURCE REPO (atv1-client crate), inside a container
# with a modern rustup toolchain, with the Buildroot SDK extracted:
#
#   SDK: produced by `make sdk` in the era build container
#        (output/images/atv1_i386_buildroot-linux-gnu_sdk-buildroot.tar.gz)
#   then:
#     tar xf <sdk>.tar.gz -C /opt/sdk && /opt/sdk/relocate-sdk.sh
#     SDK_PATH=/opt/sdk CLIENT_DIR=. ./build-client.sh
#
# Compatibility notes (verify on target — ARCHITECTURE Stage-1A/M2):
#   * target i586-unknown-linux-gnu, glibc (era SDK ships glibc 2.24);
#     modern rustc still supports glibc >= 2.17 baselines for this target
#   * prefer Edition-2021, no nightly; keep deps away from io-uring/
#     newer-kernel-only syscalls (box has 4.14)
#   * the binary is then copied to <external>/client/atv1-client and
#     BR2_PACKAGE_ATV1_CLIENT=y picks it up in post-build.sh
set -eu

SDK="${SDK_PATH:?set SDK_PATH to the relocated Buildroot SDK directory}"
CLIENT="${CLIENT_DIR:?set CLIENT_DIR to the atv1-client crate directory}"
TARGET=i586-unknown-linux-gnu

# shellcheck disable=SC1091
. "$SDK/environment-setup"
# environment-setup exports CC/CXX/CFLAGS for i586-buildroot-linux-gnu;
# cargo must link through the SDK's gcc wrapper so we get the era glibc
# and the era kernel headers' symbols, not the host's.
export CARGO_TARGET_I586_UNKNOWN_LINUX_GNU_LINKER="$CC"
export CC_i586_unknown_linux_gnu="$CC"
export CFLAGS_i586_unknown_linux_gnu="${CFLAGS:-}"

rustup target add "$TARGET"

cargo build --release --target "$TARGET" --manifest-path "$CLIENT/Cargo.toml"

OUT="$CLIENT/target/$TARGET/release/atv1-client"
[ -f "$OUT" ] || { echo "expected $OUT" >&2; exit 1; }
file "$OUT" | grep -q 'Intel 80386' || { echo "not a 32-bit i386 binary" >&2; exit 1; }
echo "OK: $OUT"
echo "next: cp $OUT <this-tree>/client/atv1-client  # then enable BR2_PACKAGE_ATV1_CLIENT=y"
