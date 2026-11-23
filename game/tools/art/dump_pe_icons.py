#!/usr/bin/env python3
"""Dump the icon resources of a Windows PE (stdlib only, no pefile).

Parses the PE headers, locates the resource directory (data dir index 2),
walks the resource tree (type -> id -> language) and prints one line per
RT_ICON frame and one line for the RT_GROUP_ICON. Exits 0 with "PEICONS OK"
when the wanted sizes are all covered by real frames; exits 1 otherwise.

    python game/tools/art/dump_pe_icons.py <path-to-exe> [size ...]

Verified semantics (cycle 7, on a Godot 4 windows export, PE32+):
    - e_lfanew at 0x3C; COFF header at e_lfanew+4 (20 bytes);
    - optional header at e_lfanew+24 = coff+20; magic 0x20b = PE32+;
    - data directories at coff+20+112 (PE32+) or coff+20+96 (PE32);
    - dir[2] = (rva, size) of the resource directory;
    - section table 40-byte entries at e_lfanew+24+SizeOfOptionalHeader;
      fields at +8 vsize, +12 vaddr, +16 rawsize, +20 rawptr;
    - resource dir entries are 8 bytes: name-or-id, and an offset whose top
      bit set means "subdirectory", relative to the resource section start;
    - a level-3 entry points to a 16-byte IMAGE_RESOURCE_DATA_ENTRY whose
      first two u32s are the leaf RVA and leaf byte size.
"""
import struct
import sys

RT_ICON = 3
RT_GROUP_ICON = 14
PNG_SIG = b"\x89PNG\r\n\x1a\n"


def u16(data, o):
    return struct.unpack_from("<H", data, o)[0]


def u32(data, o):
    return struct.unpack_from("<I", data, o)[0]


def parse_sections(data, e_lfanew):
    num = u16(data, e_lfanew + 6)
    opt_size = u16(data, e_lfanew + 20)
    sect0 = e_lfanew + 24 + opt_size
    out = []
    for i in range(num):
        s = sect0 + 40 * i
        name = data[s:s + 8].rstrip(b"\x00").decode("ascii", "replace")
        vsize, vaddr, rawsize, rawptr = struct.unpack_from("<IIII", data, s + 8)
        out.append((name, vaddr, vsize, rawsize, rawptr))
    return out


def rva_to_off(sections, rva):
    if rva is None:
        return None
    for _name, vaddr, vsize, _rawsize, rawptr in sections:
        if vaddr <= rva < vaddr + max(vsize, 1):
            return rawptr + (rva - vaddr)
    return None


def png_or_bmp_dims(d):
    """(w, h) of one icon image: PNG frame or BITMAPINFOHEADER frame.

    A BMP-style icon frame's biHeight counts XOR + AND rows (doubled);
    the visible height is half of it.
    """
    if len(d) >= 24 and d[:8] == PNG_SIG:
        return struct.unpack_from(">II", d, 16)
    if len(d) >= 12:
        w, h2 = struct.unpack_from("<II", d, 4)
        return w, h2 // 2
    return 0, 0


def main():
    if len(sys.argv) < 2:
        print("usage: dump_pe_icons.py <path-to-exe> [size ...]")
        return 2
    exe = sys.argv[1]
    want = set(int(a) for a in sys.argv[2:]) or {16, 32, 48, 64, 128, 256}
    data = open(exe, "rb").read()
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    coff = e_lfanew + 4
    opt_magic = u16(data, coff + 20)
    dd = coff + 20 + (112 if opt_magic == 0x20B else 96)
    # Data directory entries are 8 bytes each; the resource directory is
    # index 2, so its (rva, size) sits at dd + 16, not dd + 8 (that is
    # index 1, the import directory).
    res_rva = u32(data, dd + 16)
    res_size = u32(data, dd + 20)
    sections = parse_sections(data, e_lfanew)
    res_off = rva_to_off(sections, res_rva)
    print(f"PEICONS: .rsrc rva={res_rva:#x} file_off="
          f"{res_off if res_off is not None else -1:#x} size={res_size:#x}")
    if res_off is None:
        print("PEICONS MISSING: resource directory does not map to a section")
        return 1

    def entries(dir_abs):
        """[(name_or_id, target_abs, is_dir)] for one directory.

        The offset field is always relative to the resource section start
        with the top bit masked off. The bit marks a subdirectory; a clear
        bit points at a 16-byte IMAGE_RESOURCE_DATA_ENTRY. (The linker here
        writes leaf entries with the bit CLEAR, so never assume it is set.)
        """
        named, ids = u16(data, dir_abs + 12), u16(data, dir_abs + 14)
        out = []
        for i in range(named + ids):
            nid, fld = struct.unpack_from("<II", data, dir_abs + 16 + 8 * i)
            out.append((nid, res_off + (fld & 0x7FFFFFFF), bool(fld & 0x80000000)))
        return out

    def leaves(dir_abs):
        """Descend directories, returning (id, size, bytes) for every leaf."""
        out = []
        for nid, target, is_dir in entries(dir_abs):
            if is_dir:
                out.extend((nid, sz, img) for _i, sz, img in leaves(target))
            else:
                leaf_rva, leaf_size = struct.unpack_from("<II", data, target)
                fo = rva_to_off(sections, leaf_rva)
                if fo is not None:
                    out.append((nid, leaf_size, data[fo:fo + leaf_size]))
        return out

    frames = []
    grouped = []
    for nid, target, _is_dir in entries(res_off):
        if nid == RT_ICON:
            for frame_id, size, img in leaves(target):
                w, h = png_or_bmp_dims(img)
                frames.append((frame_id, size, w, h))
                print(f"PEICONS: RT_ICON id={frame_id} size={size} {w}x{h}")
        elif nid == RT_GROUP_ICON:
            for frame_id, size, img in leaves(target):
                if size >= 6:
                    count = u16(img, 4)
                    grouped.append((frame_id, size, count))
                    print(f"PEICONS: RT_GROUP_ICON id={frame_id} size={size} count={count}")

    have = {h for _fid, _sz, _w, h in frames}
    missing = sorted(want - have)
    if missing:
        print(f"PEICONS MISSING sizes: {missing}")
        return 1
    if not grouped:
        print("PEICONS MISSING: no RT_GROUP_ICON resource")
        return 1
    print("PEICONS OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
