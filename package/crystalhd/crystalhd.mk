################################################################################
#
# crystalhd (Broadcom BCM70012 userspace library)
#
# Upstream history, all verified 2026-10-27: original Broadcom source
# vanished; the LibreELEC fork we once pointed at now 404s (repo gone);
# the living mirror is crystalhd-arch on GitHub (last push 2021, used by
# the AUR). Its v20131127 tarball sha512 matches the AUR record exactly
# and is recorded in crystalhd.hash.
#
# STATUS: dormant — the project's A1218 has no card. See
# board/atv1/linux.fragment for the enable-when-the-card-arrives plan.
#
################################################################################

CRYSTALHD_VERSION = v20131127
CRYSTALHD_SITE = $(call github,crystalhd-arch,libcrystalhd,$(CRYSTALHD_VERSION))
# Mirror's own LICENSE (README/API label it LGPL-2.1; the Broadcom-era
# original was BSD-ish. Trust the LICENSE file in the tarball.)
CRYSTALHD_LICENSE = LGPL-2.1+
CRYSTALHD_LICENSE_FILES = LICENSE
CRYSTALHD_INSTALL_STAGING = YES
CRYSTALHD_AUTORECONF = YES

# libcrystalhd headers + bcgatch API are what Kodi 16/17's CrystalHD
# video accelerator links against; the runtime ioctl path is the kernel
# driver (in-tree through Linux 3.16.x including the final stable
# 3.16.85; removed in 3.17 — see linux.fragment), and eudev creates
# /dev/crystalhd — no init script needed here.
#
# Kodi ordering: buildroot's kodi package does not know about external
# crystalhd; when the card path is enabled, ensure kodi sees the staged
# lib: add "KODI_DEPENDENCIES += crystalhd" via this tree and rebuild
# kodi (kodi-dirclean), then confirm the kodi configure log picked it
# up — do not assume it.

$(eval $(autotools-package))
