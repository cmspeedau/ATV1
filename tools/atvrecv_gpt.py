#!/usr/bin/env python
# -*- coding: utf-8 -*-
# atvrecv_gpt.py — deterministic whole-disk GPT builder (stdlib only).
#
# Why: no gdisk/sgdisk exists on the macOS host (no brew) and the era
# container's util-linux 2.29 GPT scripting is version roulette. GPT is a
# small, well-specified format; 200 reviewable lines beat that roulette.
# python here is the buildroot host python (2.7, native x86_64) inside the
# era container — same tool the initramfs builder uses.
#
# Usage:
#   atvrecv_gpt.py OUT.IMG PART.IMG:TYPE-GUID:NAME [PART.IMG:...] ...
#
# Layout produced (all sizes rounded up to 1 MiB = 2048 sectors):
#   LBA0        protective MBR (0xEE spanning the disk)
#   LBA1        primary GPT header          LBA2..33 entries
#   LBA2048..   partitions back-to-back, 1 MiB aligned
#   end-33..    backup GPT entries, backup header on the final LBA
#
# atvrecv type GUID 5265636F-7665-11AA-AA11-00306543ECAC ("Reco/ve",
# Apple OUI node) verified 2026-10-27 from GNU parted 3.6 source,
# libparted/labels/gpt.c PARTITION_APPLE_TV_RECOVERY_GUID + its
# flag_uuid_mapping[] — the exact GUID gparted's `atvrecv` flag writes.

from __future__ import print_function
import binascii
import os
import struct
import sys
import zlib

SECTOR = 512
ALIGN = 2048            # 1 MiB
FIRST_LBA = 2048        # first partition start
RESERVE_TAIL = 34       # backup entries (33) + backup header (1)


def unhex(s):
    return binascii.unhexlify(s)


def guid_bytes(text):
    """Textual GUID -> UEFI mixed-endian 16 bytes."""
    g = text.replace("-", "")
    return (struct.pack("<I", int(g[0:8], 16))
            + struct.pack("<H", int(g[8:12], 16))
            + struct.pack("<H", int(g[12:16], 16))
            + unhex(g[16:20]) + unhex(g[20:32]))


def utf16(text, width):
    b = b""
    for ch in text:
        b += struct.pack("<H", ord(ch))
    b += b"\x00\x00"
    assert len(b) <= width
    return b + b"\x00" * (width - len(b))


class Partition(object):
    def __init__(self, idx, path, type_guid, name):
        self.path = path
        self.type_guid = type_guid
        self.name = name
        size = os.path.getsize(path)
        assert size % SECTOR == 0, "%s not sector-multiple" % path
        self.sectors = size // SECTOR
        self.idx = idx
        self.start = 0
        self.end = 0          # inclusive

    def entry(self):
        uniq = struct.pack("<16s", struct.pack("<Q", 0x5641000000000000
                                                + self.idx))
        # UEFI spec order: type, unique, FIRST_LBA, LAST_LBA, attrs, name
        return (guid_bytes(self.type_guid) + uniq
                + struct.pack("<Q", self.start)
                + struct.pack("<Q", self.end)
                + struct.pack("<Q", 0)                 # attrs
                + utf16(self.name, 72))

    def copy_into(self, out):
        with open(self.path, "rb") as f:
            out.seek(self.start * SECTOR)
            while True:
                chunk = f.read(4 << 20)
                if not chunk:
                    break
                out.write(chunk)


def mbr_sectors(total):
    entry = (b"\x00"            # bootable
             + b"\x00\x02\x00"  # start CHS 0/1/1
             + b"\xEE"
             + b"\xff\xff\xff"  # end CHS maxed
             + struct.pack("<I", 1)
             + struct.pack("<I", min(total - 1, 0xFFFFFFFF)))
    mbr = bytearray(b"\x00" * 446 + entry + b"\x00" * (64 - len(entry))
                    + b"\x55\xaa")
    assert len(mbr) == SECTOR
    return bytes(mbr)


def gpt_header(my_lba, alt_lba, first_usable, last_usable, disk_guid,
               entry_lba, entries_crc):
    # UEFI 2.x GPT header, 92 bytes — note NumberOfPartitionEntries and
    # SizeOfPartitionEntry precede PartitionEntryArrayCRC32; omitting
    # them leaves SizeOfPartitionEntry=0 and macOS gpt sees no entries.
    body = (b"EFI PART"
            + struct.pack("<I", 0x00010000)  # revision 1.0
            + struct.pack("<I", 92)
            + struct.pack("<I", 0)           # crc placeholder
            + struct.pack("<I", 0)           # reserved
            + struct.pack("<Q", my_lba)
            + struct.pack("<Q", alt_lba)
            + struct.pack("<Q", first_usable)
            + struct.pack("<Q", last_usable)
            + guid_bytes(disk_guid)
            + struct.pack("<Q", entry_lba)
            + struct.pack("<I", 128)         # NumberOfPartitionEntries
            + struct.pack("<I", 128)         # SizeOfPartitionEntry
            + struct.pack("<I", entries_crc))
    assert len(body) == 92, len(body)
    body += b"\x00" * (92 - len(body))       # reserved to header size
    crc = zlib.crc32(body) & 0xFFFFFFFF
    return body[:16] + struct.pack("<I", crc) + body[20:]


def main():
    if len(sys.argv) < 3:
        print("usage: atvrecv_gpt.py OUT.IMG PART:GUID:NAME ...",
              file=sys.stderr)
        return 2
    out_path = sys.argv[1]
    parts = []
    for i, spec in enumerate(sys.argv[2:], start=1):
        path, type_guid, name = spec.split(":")
        parts.append(Partition(i, path, type_guid, name))

    cursor = FIRST_LBA
    for p in parts:
        p.start = cursor
        p.end = cursor + p.sectors - 1
        cursor = p.end + 1
        cursor += (ALIGN - (cursor % ALIGN)) % ALIGN
    total = cursor + RESERVE_TAIL
    first_usable = FIRST_LBA
    last_usable = total - RESERVE_TAIL  # first LBA of the tail reserve

    entries = b"".join([p.entry() for p in parts])
    entries += b"\x00" * (128 * 128 - len(entries))
    entries_crc = zlib.crc32(entries) & 0xFFFFFFFF

    with open(out_path, "wb") as out:
        os.ftruncate(out.fileno(), total * SECTOR)
        for p in parts:
            p.copy_into(out)
        # protective MBR (written last among LBA0 content; we never
        # touched LBA0 otherwise)
        out.seek(0)
        out.write(mbr_sectors(total))
        # primary GPT
        out.seek(1 * SECTOR)
        out.write(gpt_header(1, total - 1, first_usable, last_usable,
                             "41545631-5245-4356-0000-000000000001",
                             2, entries_crc))
        out.seek(2 * SECTOR)
        out.write(entries)
        # backup GPT
        out.seek((total - 33) * SECTOR)
        out.write(entries)
        out.seek((total - 1) * SECTOR)
        out.write(gpt_header(total - 1, 1, first_usable, last_usable,
                             "41545631-5245-4356-0000-000000000001",
                             total - 33, entries_crc))

    print("atvrecv_gpt: %s %d sectors (%d MiB)"
          % (out_path, total, total // 2048))
    for p in parts:
        print("  p%d %-10s LBA %d..%d (%d MiB) %s"
              % (p.idx, p.name, p.start, p.end, p.sectors // 2048,
                 p.type_guid))
    return 0


if __name__ == "__main__":
    sys.exit(main())
