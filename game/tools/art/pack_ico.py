#!/usr/bin/env python3
"""Pack the launcher icon PNGs into a single Windows .ico (stdlib only).

An .ico is a 6-byte header, then one 16-byte directory entry per image, then
the image data. Since Vista every entry may carry a PNG verbatim, so we do no
re-encoding here: the entries are the PNG files Godot already wrote.

    python game/tools/art/pack_ico.py <out.ico> <256.png> <128.png> ... <16.png>

Sizes are read from each PNG's IHDR (bytes 16..23), not from the filenames.
"""
import struct
import sys


def png_dimensions(data: bytes) -> tuple[int, int]:
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def build_ico(paths: list[str]) -> bytes:
    blobs: list[tuple[int, int, bytes]] = []
    for p in paths:
        with open(p, "rb") as f:
            data = f.read()
        w, h = png_dimensions(data)
        blobs.append((w, h, data))

    header = struct.pack("<HHH", 0, 1, len(blobs))  # reserved, type=icon, count
    entries, offset = b"", 6 + 16 * len(blobs)
    # The directory lists largest first; the 256 px frame stores 0, not 256.
    for w, h, data in sorted(blobs, key=lambda b: -b[0]):
        entries += struct.pack(
            "<BBBBHHII", w % 256, h % 256, 0, 0, 1, 32, len(data), offset
        )
        offset += len(data)
    return header + entries + b"".join(d for _, _, d in sorted(blobs, key=lambda b: -b[0]))


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    out, pngs = argv[1], argv[2:]
    if len(pngs) < 2:
        print("pack_ico: need at least two sizes for a useful .ico", file=sys.stderr)
        return 2
    data = build_ico(pngs)
    with open(out, "wb") as f:
        f.write(data)
    print(f"pack_ico wrote {out} ({len(data)} bytes, {len(pngs)} frames)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
