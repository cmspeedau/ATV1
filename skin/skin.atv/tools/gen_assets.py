#!/usr/bin/env python
# Generates every raster asset skin.atv needs — from nothing.
# Runs at build time (post-build.sh, container python2 or host python3;
# stdlib only). Output lands in resources/skins/Default/media/.
# Why generated: no Apple assets in the tree, no binary PNGs in git,
# and the whole visual identity stays auditable as source.
import os, struct, zlib

def png(path, w, h, pixels):
    # pixels: list of h rows, each w tuples (r,g,b,a)
    raw = b''.join(b'\x00' + b''.join(struct.pack('4B', *p) for p in row)
                   for row in pixels)
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    data = (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9))
            + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(data)

W = lambda r: (255, 255, 255, r)
# vertical stage: deep near-black blue -> black (Apple TV room), 160x90
# scaled at draw time = cheap
def stage():
    rows = []
    for y in range(90):
        t = y / 89.0
        # dark blue up top falling to black, slight center glow left
        r = int(6 + 10 * (1 - t)); g = int(8 + 12 * (1 - t)); b = int(16 + 20 * (1 - t))
        rows.append([(r, g, b, 255) for _ in range(160)])
    return rows
# focus bar: gold-white warm highlight with soft vertical edges
def focus():
    rows = []
    for y in range(36):
        t = y / 35.0
        a = 255
        if t < 0.25: a = int(255 * t / 0.25)
        if t > 0.75: a = int(255 * (1 - t) / 0.25)
        rows.append([(232, 160, 13, a) for _ in range(8)])  # Apple gold
    return rows
# thin solid bar for progress slider fill/track
def bar():
    return [[(255, 255, 255, 200) for _ in range(8)] for _ in range(6)]
# poster placeholder: neutral gray with subtle border
def poster():
    rows = []
    for y in range(90):
        row = []
        for x in range(64):
            edge = x < 2 or y < 2 or x > 61 or y > 87
            row.append((60, 60, 64, 255) if edge else (48, 48, 52, 255))
        rows.append(row)
    return rows
# addon icon: gold bar on stage
def icon():
    rows = []
    for y in range(128):
        row = []
        for x in range(128):
            inbar = 40 <= y <= 88 and 16 <= x <= 112
            t = (y - 40) / 48.0
            edgefade = 255 if 0.15 < t < 0.85 else 160
            row.append((232, 160, 13, edgefade) if inbar else (8, 10, 18, 255))
        rows.append(row)
    return rows

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, '..', 'media')
    if not os.path.isdir(out):
        os.makedirs(out)
    png(os.path.join(out, 'stage.png'), 160, 90, stage())
    png(os.path.join(out, 'focus.png'), 8, 36, focus())
    png(os.path.join(out, 'bar.png'), 8, 6, bar())
    png(os.path.join(out, 'poster.png'), 64, 90, poster())
    png(os.path.join(out, 'icon.png'), 128, 128, icon())

main()
