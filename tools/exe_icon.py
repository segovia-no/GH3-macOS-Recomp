#!/usr/bin/env python3
"""Writes the largest icon of a PE executable as a single-image .ico.

  exe_icon.py <file.exe> <out.ico>      (--list: print the icons)

Reads the first RT_GROUP_ICON (type 14) and picks its largest entry; the
image itself is the RT_ICON (type 3) resource with that id (a PNG or a
DIB). macOS's sips reads the result.
"""

import struct
import sys


def sections(d):
    pe = struct.unpack_from("<I", d, 0x3C)[0]
    n = struct.unpack_from("<H", d, pe + 6)[0]
    opt = struct.unpack_from("<H", d, pe + 20)[0]
    o = pe + 24 + opt
    magic = struct.unpack_from("<H", d, pe + 24)[0]
    dd = pe + 24 + (96 if magic == 0x10B else 112)
    rsrc_rva = struct.unpack_from("<I", d, dd + 2 * 8)[0]
    secs = [struct.unpack_from("<8sIIII", d, o + 40 * i) for i in range(n)]
    return rsrc_rva, secs


def main():
    d = open(sys.argv[1], "rb").read()
    rsrc_rva, secs = sections(d)

    def off(rva):
        for _, vs, va, rs, ra in secs:
            if va <= rva < va + max(vs, rs):
                return ra + rva - va
        raise SystemExit("exe_icon: address outside sections")

    base = off(rsrc_rva)

    def entries(dir_off):
        named, ids = struct.unpack_from("<HH", d, base + dir_off + 12)
        for i in range(named + ids):
            name, ptr = struct.unpack_from("<II", d, base + dir_off + 16 + 8 * i)
            yield name, ptr

    def leaf(ptr):  # descend to the first language's data
        while ptr & 0x80000000:
            ptr = next(entries(ptr & 0x7FFFFFFF))[1]
        rva, size = struct.unpack_from("<II", d, base + ptr)
        return d[off(rva):off(rva) + size]

    by_type = {name: ptr for name, ptr in entries(0)}
    icons = {name: ptr for name, ptr in entries(by_type[3] & 0x7FFFFFFF)}
    group = leaf(next(entries(by_type[14] & 0x7FFFFFFF))[1])
    count = struct.unpack_from("<H", group, 4)[0]
    best = None
    for i in range(count):
        w, h, colors, _, planes, bpp, size, icon_id = struct.unpack_from(
            "<BBBBHHIH", group, 6 + 14 * i)
        w, h = w or 256, h or 256
        if "--list" in sys.argv:
            print(f"icon {icon_id}: {w}x{h} {bpp} bpp, {size} bytes")
        key = (w * h, bpp)
        if best is None or key > best[0]:
            best = (key, w, h, colors, planes, bpp, icon_id)
    if "--list" in sys.argv:
        return
    _, w, h, colors, planes, bpp, icon_id = best
    img = leaf(icons[icon_id])
    ico = struct.pack("<HHH", 0, 1, 1) + struct.pack(
        "<BBBBHHII", w % 256, h % 256, colors, 0, planes, bpp, len(img), 22) + img
    open(sys.argv[2], "wb").write(ico)
    print(f"exe_icon: {w}x{h} {bpp} bpp")


if __name__ == "__main__":
    main()
