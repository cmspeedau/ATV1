################################################################################
#
# crystalhd (Broadcom BCM70012 userspace, LibreELEC-maintained fork)
#
# Original Broadcom source vanished; LibreELEC maintains the buildable
# fork used by the OpenELEC/LibreELEC AppleTV1 images. Pin the commit
# after the first successful download (see comment below) for
# reproducible builds.
#
################################################################################

CRYSTALHD_VERSION = master
CRYSTALHD_SITE = $(call github,LibreELEC,crystalhd,$(CRYSTALHD_VERSION))
CRYSTALHD_LICENSE = BSD-3c (Broadcom source), GPL-2.0+ (utils)
CRYSTALHD_LICENSE_FILES = COPYING
CRYSTALHD_INSTALL_STAGING = YES
CRYSTALHD_AUTORECONF = YES

# libcrystalhd headers + bcgatch API are what Kodi 16/17's CrystalHD
# video accelerator links against; the runtime ioctl path is the
# in-kernel staging driver (CONFIG_CRYSTALHD=y, built-in), and eudev
# creates /dev/crystalhd — no init script needed here.
#
# No .hash file: pre-2020 Buildroot warns but tolerates its absence for
# git tarballs. After the first successful download, pin
# CRYSTALHD_VERSION to the commit SHA you actually received and record
# the sha256 from dl/ into a .hash file for reproducibility.
#
# 2026-10-27, observed: the master-archive download 404s (repo gone or
# branch renamed). This package is DORMANT (no card in the box), so the
# dead URL blocks nothing; before ever enabling it, find the fork's
# current home and pin a commit. See also Config.in: the kernel-side
# driver needs LibreELEC's out-of-tree module, not an in-tree kernel.

$(eval $(autotools-package))
