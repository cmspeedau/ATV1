# skin.atv "ATV1" — Apple-TV-inspired Kodi 17 skin

Original work, GPL-2.0-only (same license family as Kodi itself, so it
ships cleanly in the appliance image). **No Apple assets**: no Apple
fonts, artwork, icons, or copied UI graphics — the design language
(black radial-gradient stage, white Helvetica-adjacent type via DejaVu,
warm-white/gold focus bar) is drawn from scratch by
`tools/gen_assets.py` at build time.

## Why it looks like this (constraints, not taste)
- 1 GHz Pentium M + software GL: everything is a handful of small
  textures scaled at runtime — no fanart walls, no heavy animations,
  no large alpha stacks.
- 256 MB RAM: views are single-column lists, artwork is lazily bound.
- Kiosk appliance: media management and text entry live on the
  coordinator (ARCHITECTURE doc), so this skin implements the kiosk's
  actual surface and says what it omits.

## Surface (v0.1)
Home shelf (Movies / TV Shows / Music / Restart Kodi), list views for
movie/TV/season/episode/music libraries, video-info dialog, player
overlay + OSD (play/pause/stop/seek/info), confirm/select/OK/progress
dialogs, startup screen.

## Out of scope on purpose (v0.1)
- System settings UI and any text input (no on-screen keyboard):
  config happens via ssh/coordinator.
- Notifications, screensavers, PVR, file manager, skin settings.
These windows are simply unstyled if force-opened; nothing in the
kiosk flow opens them.

## Build integration
`post-build.sh` copies this directory into `/root/.kodi/addons/skin.atv/`,
runs `tools/gen_assets.py` (stdlib-only python; emits the gradient,
focus bar, and poster placeholder PNGs into `media/`), and drops in
DejaVuSans TTFs (BR2_PACKAGE_DEJAVU, Bitstream-Vera license). The
default skin is selected by `userdata/guisettings.xml` in the
rootfs-overlay.
