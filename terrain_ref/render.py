#!/usr/bin/env python
"""Pure-stdlib PNG renderer for VOIDWARP terrain reference levels.

Usage:
    python render.py --seed S --level L --out file.png [--scale 6]
    python render.py --sheet out/sheet_level1.png --level 1 --seeds 0:12
"""
import argparse
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voidgen  # noqa: E402

BG = (1, 11, 12)  # #010B0C

# light/dark base colors keyed by piece category
COL_ROOM = ((47, 183, 176), (10, 46, 48))        # #2FB7B0 / #0A2E30
COL_DEAD_END = ((143, 232, 224), (10, 46, 48))   # #8FE8E0 / #0A2E30
COL_LINK = ((42, 91, 255), (11, 26, 102))        # #2A5BFF / #0B1A66
COL_LOOP = ((176, 124, 255), (42, 26, 102))      # #B07CFF / #2A1A66
COL_DROP = ((255, 154, 61), (102, 48, 11))       # #FF9A3D / #66300B
COL_PROP = (90, 106, 106)                        # #5A6A6A
COL_PAD = (255, 255, 255)                        # #FFFFFF
COL_GIFT = (255, 200, 61)                        # #FFC83D
COL_MINE = (255, 79, 216)                        # #FF4FD8
COL_BEACON = (255, 255, 255)                     # #FFFFFF
COL_BEACON_EDGE = (255, 42, 42)                  # #FF2A2A


def write_png(path, width, height, rgb_bytes):
    """Write an 8-bit RGB PNG (color type 2), filter byte 0 per row."""
    stride = width * 3
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += rgb_bytes[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data +
                struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', ihdr))
        f.write(chunk(b'IDAT', zlib.compress(bytes(raw))))
        f.write(chunk(b'IEND', b''))


def _set_px(img, W, H, x, y, c):
    if 0 <= x < W and 0 <= y < H:
        i = (y * W + x) * 3
        img[i:i + 3] = bytes(c)


def _fill_rect(img, W, H, x0, y0, w, h, c):
    sx0 = max(0, x0)
    sy0 = max(0, y0)
    sx1 = min(W, x0 + w)
    sy1 = min(H, y0 + h)
    if sx0 >= sx1 or sy0 >= sy1:
        return
    row = bytes(c) * (sx1 - sx0)
    for y in range(sy0, sy1):
        i = (y * W + sx0) * 3
        img[i:i + len(row)] = row


def _tile_colors(piece):
    if piece is None:
        return COL_ROOM
    kind = piece.get('kind', 0)
    role = piece.get('role', 0)
    if role == 2:
        return COL_DEAD_END
    if role == 4:
        return COL_LOOP
    if role == 5:
        return COL_DROP
    if kind == 1 or role == 3:
        return COL_LINK
    return COL_ROOM


def render_image(L, scale=6):
    """Render level L to (width, height, rgb_bytes)."""
    tiles = L['tiles']
    xs = [t[0] for t in tiles]
    zs = [t[1] for t in tiles]
    ys = [t[2] for t in tiles]
    minx, maxx = min(xs), max(xs)
    minz, maxz = min(zs), max(zs)
    miny, maxy = min(ys), max(ys)
    span = max(1, maxy - miny)

    W = ((maxx - minx + 1) + 4) * scale
    H = ((maxz - minz + 1) + 4) * scale
    img = bytearray(bytes(BG) * (W * H))

    pieces = {p['id']: p for p in L['pieces']}

    def cell_px(x, z):
        return (x - minx + 2) * scale, (z - minz + 2) * scale

    # tiles: paint ascending y so higher tiles overwrite lower ones
    for t in sorted(tiles, key=lambda t: t[2]):
        x, z, y, tkind, tpiece = t
        px, py = cell_px(x, z)
        light, dark = _tile_colors(pieces.get(tpiece))
        base = light if (x + z) % 2 == 0 else dark
        f = 0.55 + 0.45 * (y - miny) / span
        color = tuple(min(255, int(c * f)) for c in base)
        _fill_rect(img, W, H, px, py, scale, scale, color)
        if tkind != 0:  # ramp tile: 1-pixel darker diagonal line
            darker = tuple(int(c * 0.5) for c in color)
            for i in range(scale):
                _set_px(img, W, H, px + i, py + i, darker)

    # props: filled square inset 1 pixel
    for p in L['props']:
        x, z = p[0], p[1]
        px, py = cell_px(x, z)
        ins = 1 if scale > 2 else 0
        _fill_rect(img, W, H, px + ins, py + ins,
                   max(1, scale - 2 * ins), max(1, scale - 2 * ins), COL_PROP)

    # pads: filled square
    for p in L['pads']:
        px, py = cell_px(p[0], p[1])
        _fill_rect(img, W, H, px, py, scale, scale, COL_PAD)

    # gifts / tripmines: centered square
    gs = max(2, scale // 2)
    for g in L['gifts']:
        px, py = cell_px(g['x'], g['z'])
        gx = px + (scale - gs) // 2
        gy = py + (scale - gs) // 2
        color = COL_GIFT if g.get('occ', 0) == 0 else COL_MINE
        _fill_rect(img, W, H, gx, gy, gs, gs, color)

    # beacon at cell (0, 0): white square with 1-pixel red border
    bx, by = cell_px(0, 0)
    _fill_rect(img, W, H, bx, by, scale, scale, COL_BEACON)
    edge = COL_BEACON_EDGE
    for i in range(scale):
        _set_px(img, W, H, bx + i, by, edge)
        _set_px(img, W, H, bx + i, by + scale - 1, edge)
        _set_px(img, W, H, bx, by + i, edge)
        _set_px(img, W, H, bx + scale - 1, by + i, edge)

    return W, H, bytes(img)


def render(L, path, scale=6):
    W, H, buf = render_image(L, scale)
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    write_png(path, W, H, buf)


def render_sheet(level, seeds, path):
    cell = 420
    gap = 4
    cols = 4
    rows = (len(seeds) + cols - 1) // cols
    W = cols * cell + (cols + 1) * gap
    H = rows * cell + (rows + 1) * gap
    img = bytearray(bytes(BG) * (W * H))

    for idx, seed in enumerate(seeds):
        L = voidgen.generate(seed, level)
        w, h, buf = render_image(L, 3)
        col = idx % cols
        row = idx // cols
        cx = gap + col * (cell + gap)
        cy = gap + row * (cell + gap)
        sx0 = max(0, (w - cell) // 2)
        sy0 = max(0, (h - cell) // 2)
        dx0 = cx + max(0, (cell - w) // 2)
        dy0 = cy + max(0, (cell - h) // 2)
        copy_w = min(w, cell)
        copy_h = min(h, cell)
        for dy in range(copy_h):
            src_i = ((sy0 + dy) * w + sx0) * 3
            dst_i = ((dy0 + dy) * W + dx0) * 3
            img[dst_i:dst_i + copy_w * 3] = buf[src_i:src_i + copy_w * 3]

    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    write_png(path, W, H, bytes(img))


def parse_seeds(spec):
    """Parse 'A:B' into list(range(A, B)); otherwise a single int."""
    spec = spec.strip()
    if ':' in spec:
        a, b = spec.split(':', 1)
        return list(range(int(a), int(b)))
    return [int(spec)]


def main(argv=None):
    ap = argparse.ArgumentParser(description='Render VOIDWARP terrain reference levels.')
    ap.add_argument('--seed', type=int, default=None)
    ap.add_argument('--level', type=int, required=True)
    ap.add_argument('--out', default=None)
    ap.add_argument('--sheet', default=None)
    ap.add_argument('--seeds', default=None)
    ap.add_argument('--scale', type=int, default=6)
    args = ap.parse_args(argv)

    if args.sheet:
        if not args.seeds:
            ap.error('--sheet requires --seeds (e.g. --seeds 0:12)')
        seeds = parse_seeds(args.seeds)
        render_sheet(args.level, seeds, args.sheet)
        return 0

    if args.out and args.seed is not None:
        L = voidgen.generate(args.seed, args.level)
        render(L, args.out, args.scale)
        return 0

    ap.error('expected either --seed S --out file.png, or --sheet file.png --seeds A:B')


if __name__ == '__main__':
    sys.exit(main())
