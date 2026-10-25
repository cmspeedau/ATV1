#!/bin/sh
# ATV1 kiosk: X + Kodi on tty1, driven by /etc/inittab respawn.
#
# The 7300 (DRI nv40) must be card0 — i915 is deliberately absent from the
# kernel, so there is only ever one GPU device. If /dev/dri/card0 is slow to
# appear on a cold boot, the short wait below handles it.

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
