#!/usr/bin/env python3
"""Tighten Afacad Flux's vertical metrics in place.

The shipped font declares ascender 1.0 em / descender 0.333 em (1.33 line box) while its
glyphs only reach +0.83 em (accented caps) and -0.22 em (descenders). That leaves a big
gap above the text and makes wrapped lines float apart. This rewrites hhea and OS/2
(typo + win) to the measured extents and fixes the table checksums.

    python3 tools/tighten_font_metrics.py prodline/fonts/AfacadFlux-VariableFont_slnt,wght.ttf
"""
import struct, sys

ASC_EM, DESC_EM = 0.83, 0.23

def checksum(b):
    b = b + b"\0" * (-len(b) % 4)
    return sum(struct.unpack(">%dI" % (len(b) // 4), b)) & 0xFFFFFFFF

path = sys.argv[1]
d = bytearray(open(path, "rb").read())
num = struct.unpack(">H", d[4:6])[0]
tables = {}
for i in range(num):
    rec = 12 + 16 * i
    tag, _, off, ln = struct.unpack(">4sIII", d[rec:rec + 16])
    tables[tag.decode()] = (rec, off, ln)

_, head, _ = tables["head"]
upm = struct.unpack(">H", d[head + 18:head + 20])[0]
asc, desc = round(ASC_EM * upm), round(DESC_EM * upm)

_, hhea, _ = tables["hhea"]
struct.pack_into(">hhh", d, hhea + 4, asc, -desc, 0)
_, os2, _ = tables["OS/2"]
struct.pack_into(">hhhHH", d, os2 + 68, asc, -desc, 0, asc, desc)
fs = struct.unpack(">H", d[os2 + 62:os2 + 64])[0] | (1 << 7)  # USE_TYPO_METRICS
struct.pack_into(">H", d, os2 + 62, fs)

# Table checksums, then head.checkSumAdjustment over the whole file.
struct.pack_into(">I", d, head + 8, 0)
for tag, (rec, off, ln) in tables.items():
    struct.pack_into(">I", d, rec + 4, checksum(bytes(d[off:off + ln])))
struct.pack_into(">I", d, head + 8, (0xB1B0AFBA - checksum(bytes(d))) & 0xFFFFFFFF)

open(path, "wb").write(d)
print(f"upm {upm}: ascender {asc}, descender -{desc}, line gap 0")
