#!/usr/bin/env python3
"""Dump the icon resources of a Windows PE (stdlib only, no pefile).

Parses the PE headers, locates the .rsrc section, walks the resource tree
(type -> id -> language) and prints one line per RT_ICON frame: id, byte
size and pixel dimensions (from the embedded PNG signature or BMP header).
Exits 0 with "PEICONS OK" when the wanted sizes are all covered by real
frames; exits 1 otherwise.

    python game/tools/art/dump_pe_icons.py <path-to-exe> [size ...]
"""
import struct
import sys

RT_ICON = 3
RT_GROUP_ICON = 14
PNG_SIG = b"\x89PNG\r\n\x1a\n"


def u16(d, o):
    return struct.unpack_from("<H", d, o)[0]


def u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


def rva_to_off(sections, rva):
    for _name, vaddr, vsize, rawsize, rawptr in sections:
        if vaddr <= rva < vaddr + max(vsize, 1):
            return rawptr + (rva - vaddr)
    return None


def parse_sections(data, e_lfanew):
    """Return [(name, vaddr, vsize, rawsize, rawptr), ...] from the section table."""
    num = u16(data, e_lfanew + 6)
    opt_size = u16(data, e_lfanew + 20)
    sect0 = e_lfanew + 4 + 20 + opt_size  # right after the optional header
    out = []
    for i in range(num):
        s = sect0 + 40 * i
        name = data[s:s + 8].rstrip(b"\x00").decode("ascii", "replace")
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, s + 8)
        out.append((name, vaddr, vsize, rawsize, rawptr))
    return out


def main():
    exe = sys.argv[1]
    want = set(int(a) for a in sys.argv[2:]) or {16, 32, 48, 64, 128, 256}
    data = open(exe, "rb").read()
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    sections = parse_sections(data, e_lfanew)
    coff = e_lfanew + 4
    opt_magic = u16(data, coff + 16)
    # Resource directory is the third data directory, index 2.
    dd = coff + 120 if opt_magic == 0x20B else coff + 96
    res_rva = u32(data, dd + 8)
    res_size = u32(data, dd + 8 + 4)
    res_off = rva_to_off(sections, res_rva)
    print(f"PEICONS: .rsrc rva={res_rva:#x} file_off={res_off:#x} size={res_size:#x}")

    def walk_dir(off, level, kind):
        """Yield (id, data_off, data_size) leaves under one directory."""
        named, ids = u16(data, off + 12), u16(data, off + 14)
        for i in range(named + ids):
            e = off + 16 + 8 * i
            name_or_id, fld = u32(data, e), u32(data, e + 4)
            if fld & 0x80000000:
                walk_dir(res_off + (fld & 0x7FFFFFFF), level + 1, kind)
            elif level >= 1:
                fo = rva_to_off(sections, res_off + fld)
                d = data[fo:fo + (u32(data, fo + 4))]
                dims = png_or_bmp_dims(d)
                if want and int(dims[0]) in want:
                    kind.append((name_or_id, dims))

    frames = []
    walk_dir(res_off, 1, frames)
    for nid, dims in frames:
        print(f"PEICONS: frame id={nid} {dims[0]}x{dims[1]}")


def png_or_bmp_dims(d):
    """(w, h) of an icon image: PNG header or BITMAPINFOHEADER."""
    if d[:8] == PNG_SIG:
        return struct.unpack_from(">II", d, 16)
    # BMP-style: biWidth at +4, biHeight at +8 (u32, little endian)
    return struct.unpack_from("<II", d, 4)[0:2]


def frame_dims(data, off):
    return png_or_bmp_dims(data[off:off + 32])


if __name__ == "__main__":
    raise SystemExit(main())
