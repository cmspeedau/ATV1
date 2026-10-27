#!/usr/bin/env python
# -*- coding: utf-8 -*-
# mkcpio-newc.py — deterministic newc-format cpio writer (stdlib only).
#
# Why: the era container's cpio is the i386 TARGET binary (unrunnable on
# the x86_64 host container), host-cpio is not built, and the kernel's
# initramfs reader demands u-star-cpio "newc". python (host/bin/python,
# 2.7, native) is already there. Deterministic: entries sorted by path,
# fixed mtime, fixed uid/gid — same tree in, byte-identical cpio out.
#
# Usage: mkcpio-newc.py OUTFILE ROOTDIR   (write to '-' for stdout)
#
# Handles: directories, regular files (hardlink-aware: st_nlink>1 stores
# data once, repeats with filesize 0), symlinks (data = target path).

from __future__ import print_function
import os
import stat
import sys

MAGIC = b"070701"
MTIME = 0  # fixed for reproducibility


def field(v):
    return ("%08X" % (v & 0xFFFFFFFF)).encode("ascii")


def pad4(n):
    return (4 - (n % 4)) % 4


class Writer(object):
    def __init__(self, f):
        self.f = f
        self.inos = {}   # (dev, ino) -> assigned ino
        self.ino_next = 1

    def header(self, name, mode, nlink, size, rdev=(0, 0), ino=None):
        if ino is None:
            ino = self.ino_next
            self.ino_next += 1
        name_b = name.encode("utf-8") + b"\0"
        hdr = (MAGIC
               + field(ino) + field(mode) + field(0) + field(0)
               + field(nlink) + field(MTIME) + field(size)
               + field(0) + field(0)           # devmajor, devminor
               + field(rdev[0]) + field(rdev[1])
               + field(len(name_b)) + field(0))
        assert len(hdr) == 110, len(hdr)
        self.f.write(hdr)
        self.f.write(name_b)
        self.f.write(b"\0" * pad4(len(hdr) + len(name_b)))
        return ino

    def payload(self, data):
        self.f.write(data)
        self.f.write(b"\0" * pad4(len(data)))

    def directory(self, path, name):
        self.header(name, 0o40755, 2, 0)

    def symlink(self, path, name):
        target = os.readlink(path)
        ino = self.header(name, 0o120777, 1, len(target))
        self.payload(target.encode("utf-8"))

    def regfile(self, path, name):
        st = os.stat(path)
        key = (st.st_dev, st.st_ino)
        if key in self.inos:
            # hardlink repeat: same ino, zero size, no data
            self.header(name, 0o100755, st.st_nlink, 0, ino=self.inos[key])
            return
        ino = self.header(name, 0o100755, max(st.st_nlink, 1), st.st_size)
        self.inos[key] = ino
        with open(path, "rb") as f:
            while True:
                chunk = f.read(1 << 20)
                if not chunk:
                    break
                self.payload_nopad(chunk)
        # total-size padding, once, after all chunks
        pad = pad4(st.st_size)
        self.f.write(b"\0" * pad)

    def payload_nopad(self, data):
        self.f.write(data)

    def trailer(self):
        self.header("TRAILER!!!", 0, 1, 0, ino=0)


def walk(root):
    entries = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        if rel_dir != ".":
            entries.append(("d", os.path.join(dirpath, ""),
                            rel_dir.replace(os.sep, "/")))
        for f in sorted(filenames + dirnames):
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, root).replace(os.sep, "/")
            if os.path.islink(p):
                entries.append(("l", p, rel))
            elif os.path.isdir(p):
                pass  # already recorded above
            elif os.path.isfile(p):
                entries.append(("f", p, rel))
            else:
                raise Exception("unsupported file type in %s" % p)
    entries.sort(key=lambda e: (e[2], e[0]))
    return entries


def main():
    if len(sys.argv) != 3:
        print("usage: mkcpio-newc.py OUTFILE ROOTDIR", file=sys.stderr)
        return 2
    out, root = sys.argv[1], sys.argv[2]
    out_f = sys.stdout.buffer if hasattr(sys.stdout, "buffer") else sys.stdout
    close_f = True
    if out != "-":
        out_f = open(out, "wb")
    w = Writer(out_f)
    for kind, path, name in walk(root):
        if kind == "d":
            w.directory(path, name)
        elif kind == "l":
            w.symlink(path, name)
        else:
            w.regfile(path, name)
    w.trailer()
    if close_f:
        out_f.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
