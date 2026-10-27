#!/bin/sh
# ATV1 kiosk: X + Kodi on tty1, driven by /etc/inittab respawn.
#
# Heterogeneous fleet: on unit A card0 is i915 (GMA950). On unit B BOTH
# drivers probe — i915 claims card0 for the iGPU, the 7300 lands on
# card1 — so X must be pinned to the right screen by the xstartup
# GPU-select (roadmap TODO in LOG.md); /dev/dri itself just needs any
# card bound. Cold boot from USB is slowest; wait up to 15 s.

# Give DRM/nouveau a moment after cold boot (USB storage boot is slowest)
i=0
while [ ! -e /dev/dri/card0 ] && [ "$i" -lt 15 ]; do
        sleep 1
        i=$((i + 1))
done

# Audio defaults (HDMI first; flip to the S/PDIF device here if preferred)
[ -f /etc/asound.conf ] || cp -f /etc/asound.conf.example /etc/asound.conf 2>/dev/null

export HOME=/root
export XDG_RUNTIME_DIR=/tmp

exec startx /usr/bin/kodi -fs -- :0 -nolisten tcp vt7
