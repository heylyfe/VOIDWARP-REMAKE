# Glider: the hang glider the player flies under while ctl.gliding (owner request
# 2026-11-20, two reference images). A swept, rounded delta wing with a scalloped
# trailing edge, a bright cyan rim tracing the whole outline, a translucent membrane
# that fades from pale gray at the nose to teal at the trailing edge, a light-gray
# skeleton (keel, crossbar, A-frame + control bar) and a rounded pod sitting in a
# rectangular frame of light-gray blocks with a gap in the middle (the player's torso
# stands in that gap).
#
# Unlike the box-only T-015 props, the wing outline and the rods are free polygons:
# a delta wing cannot be built from axis-aligned boxes. Vertex colours still carry the
# whole palette (the .glb has no material); the rods/blocks/pod bake facet tones from a
# fixed light direction so the unshaded engine material still reads as 3D.
#
# Frame: 1 Blender unit = 1 game u, Z up, +Y forward (glTF -> Godot -Z forward).
# ORIGIN = the hang point (where the keel meets the A-frame apex). The engine mounts
# the origin at (0, 2.25, +0.20) Godot in the 1.80 u player figure's space, i.e. 0.45 u
# over the hat and 0.20 u behind the body centre; the frame then rings the chest at
# 1.20 u. Measured extents: span 3.00 u (x +-1.50), chord 2.10 u (nose y +1.25 ->
# trailing edge y -0.85), wing 0.20-0.34 u over the hang point.
#
# Separate named objects (the engine and test_glider_view.gd find them by name):
#   Wing      translucent membrane (the engine gives it an alpha material)
#   WingRim   cyan tube along the full outline
#   Keel      nose-to-tail rod          Crossbar  span-wise rod
#   AFrame    two downtubes + control bar
#   Pod       the rounded pilot bubble  PodFrame  four blocks + bars around a gap
#
# Colours are glider-local (sRGB hex, decoded to linear by t015_common.hex_rgba): they
# are kept here, not in t015_common.py, so this model never touches the shared roles.
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

GLIDER_ROLES = {
    "frame_light": "#F4F7F8",
    "frame_dark": "#9AA3A7",
    "membrane_lead": "#CBD4D7",
    "membrane_mid": "#8CCBD1",
    "membrane_trail": "#2FB2BE",
    "rim": "#3FF4FF",
}

# Light direction for the baked facet tones (up, a little forward and to the right).
_L = (0.35, 0.45, 0.82)
_LN = math.sqrt(sum(c * c for c in _L))
LIGHT = tuple(c / _LN for c in _L)


def lin(role):
    return C.hex_rgba(GLIDER_ROLES[role])


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))


def tone(normal):
    """Facet tone for the light-gray structure from a face normal."""
    n = math.sqrt(sum(c * c for c in normal)) or 1.0
    d = sum(normal[i] / n * LIGHT[i] for i in range(3))
    t = max(0.0, min(1.0, 0.5 + 0.5 * d))
    return mix(lin("frame_dark"), lin("frame_light"), t)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def scale(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def norm(a):
    n = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]) or 1.0
    return (a[0] / n, a[1] / n, a[2] / n)


def face(m, pts, col):
    """One polygon, unique vertices (flat facet colour)."""
    base = len(m.verts)
    for p in pts:
        m.verts.append(p)
        m.cols.append(col)
    m.faces.append(tuple(range(base, base + len(pts))))


def shaded_face(m, pts):
    n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
    face(m, pts, tone(n))


def tube(m, a, b, ra, rb, sides=8, color=None, caps=True):
    """A tapered n-sided rod from a to b with pointed-round caps. Faces wind outward.
    color=None bakes facet tones; a colour paints every face flat (the rim)."""
    d = norm(sub(b, a))
    up = (0.0, 0.0, 1.0) if abs(d[2]) < 0.9 else (1.0, 0.0, 0.0)
    u = norm(cross(d, up))
    v = cross(d, u)
    ring_a, ring_b = [], []
    for i in range(sides):
        th = 2.0 * math.pi * i / sides
        off = add(scale(u, math.cos(th)), scale(v, math.sin(th)))
        ring_a.append(add(a, scale(off, ra)))
        ring_b.append(add(b, scale(off, rb)))
    tip_a = sub(a, scale(d, ra * 0.9))
    tip_b = add(b, scale(d, rb * 0.9))
    for i in range(sides):
        j = (i + 1) % sides
        quads = [[ring_a[i], ring_a[j], ring_b[j], ring_b[i]]]
        if caps:
            quads.append([ring_b[i], ring_b[j], tip_b])
            quads.append([ring_a[j], ring_a[i], tip_a])
        for q in quads:
            if color is None:
                shaded_face(m, q)
            else:
                face(m, q, color)


# ---- wing planform -------------------------------------------------------------------
# Right half, nose -> wing tip -> scalloped trailing edge -> centre. Mirrored below.
HALF = [
    (0.00, 1.25), (0.30, 1.12), (0.62, 0.90), (0.92, 0.60), (1.18, 0.24),
    (1.36, -0.12), (1.46, -0.42), (1.50, -0.70), (1.30, -0.80), (1.04, -0.75),
    (0.80, -0.83), (0.52, -0.80), (0.30, -0.87), (0.00, -0.84),
]
SPAN_HALF = 1.50
NOSE_Y = 1.25


def wing_z(x, y):
    """Membrane height over the hang point: nose a touch high, tips drooping."""
    return 0.30 + 0.04 * (y / NOSE_Y) - 0.10 * (abs(x) / SPAN_HALF) ** 2


def outline():
    right = HALF
    left = [(-x, y) for (x, y) in reversed(HALF[1:-1])]
    pts = right + left
    # wind CCW seen from above (+Z) so the membrane's front face points up
    area = 0.0
    for i in range(len(pts)):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % len(pts)]
        area += x0 * y1 - x1 * y0
    if area < 0.0:
        pts = list(reversed(pts))
    return pts


# The membrane is translucent: its vertex alpha (exported in COLOR_0) runs from 0.80
# at the nose to 0.62 at the trailing edge; the engine draws Wing with an alpha
# material that multiplies albedo by the vertex colour, so the alpha lives HERE.
MEMBRANE_ALPHA_LEAD = 0.80
MEMBRANE_ALPHA_TRAIL = 0.62


def membrane_col(y):
    t = max(0.0, min(1.0, (NOSE_Y - y) / 2.1))
    if t < 0.5:
        c = mix(lin("membrane_lead"), lin("membrane_mid"), t / 0.5)
    else:
        c = mix(lin("membrane_mid"), lin("membrane_trail"), (t - 0.5) / 0.5)
    a = MEMBRANE_ALPHA_LEAD + (MEMBRANE_ALPHA_TRAIL - MEMBRANE_ALPHA_LEAD) * t
    return (c[0], c[1], c[2], a)


def build_wing():
    m = C.Mesh()
    ring = outline()
    cx, cy = 0.0, 0.10
    # three rings (centre, mid, rim) so the nose->trail gradient has real stops
    rings = []
    for t in (0.5, 1.0):
        rings.append([(cx + (x - cx) * t, cy + (y - cy) * t) for (x, y) in ring])
    centre = (cx, cy, wing_z(cx, cy))
    ci = len(m.verts)
    m.verts.append(centre)
    m.cols.append(membrane_col(cy))
    idx = []
    for r in rings:
        row = []
        for (x, y) in r:
            row.append(len(m.verts))
            m.verts.append((x, y, wing_z(x, y)))
            m.cols.append(membrane_col(y))
        idx.append(row)
    n = len(ring)
    for i in range(n):
        j = (i + 1) % n
        m.faces.append((ci, idx[0][i], idx[0][j]))
        m.faces.append((idx[0][i], idx[1][i], idx[1][j], idx[0][j]))
    return m.finish("Wing")


def build_rim():
    m = C.Mesh()
    ring = outline()
    rim = lin("rim")
    n = len(ring)
    for i in range(n):
        x0, y0 = ring[i]
        x1, y1 = ring[(i + 1) % n]
        a = (x0, y0, wing_z(x0, y0))
        b = (x1, y1, wing_z(x1, y1))
        tube(m, a, b, 0.038, 0.038, sides=6, color=rim)
    return m.finish("WingRim")


def build_keel():
    m = C.Mesh()
    tube(m, (0.0, 1.12, wing_z(0, 1.12) - 0.06), (0.0, -0.78, wing_z(0, -0.78) - 0.06),
         0.036, 0.024)
    return m.finish("Keel")


def build_crossbar():
    m = C.Mesh()
    y = 0.15
    mid = (0.0, y, wing_z(0, y) - 0.08)
    for sx in (-1.0, 1.0):
        tip = (sx * 1.18, y - 0.10, wing_z(1.18, y - 0.10) - 0.05)
        tube(m, mid, tip, 0.030, 0.020)
    return m.finish("Crossbar")


# The pod frame: four corner blocks around a gap the player's torso stands in,
# centred 0.20 u forward of the hang point at chest height.
FRAME_CY = 0.20
FRAME_Z = -1.05
CORNER_X = 0.48
CORNER_DY = 0.34


def build_aframe():
    m = C.Mesh()
    tube(m, (0.0, 0.0, 0.0), (0.0, 0.0, wing_z(0, 0) - 0.07), 0.022, 0.022)  # hang strap
    top = FRAME_Z + 0.11
    for sx in (-1.0, 1.0):
        # front downtubes: apex -> the front corner blocks
        tube(m, (sx * 0.04, 0.02, 0.0), (sx * CORNER_X, FRAME_CY + CORNER_DY, top),
             0.026, 0.022)
        # rear struts: keel, aft of the hang point -> the rear corner blocks
        tube(m, (sx * 0.03, -0.40, wing_z(0, -0.40) - 0.08),
             (sx * CORNER_X, FRAME_CY - CORNER_DY, top), 0.020, 0.018)
    return m.finish("AFrame")


def box_tones():
    # QUADS order: -Z, +Z, -Y, +X, +Y, -X
    return [tone(n) for n in ((0, 0, -1), (0, 0, 1), (0, -1, 0), (1, 0, 0),
                              (0, 1, 0), (-1, 0, 0))]


def build_pod_frame():
    m = C.Mesh()
    ft = box_tones()
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            m.box((sx * CORNER_X, FRAME_CY + sy * CORNER_DY, FRAME_Z),
                  (0.24, 0.26, 0.22), ft[1], face_colors=ft)
    # thin bars joining the blocks; the middle stays open (0.72 x 0.42 u gap)
    for sy in (-1.0, 1.0):
        m.box((0.0, FRAME_CY + sy * CORNER_DY, FRAME_Z - 0.03), (0.74, 0.08, 0.08),
              ft[1], face_colors=ft)
    for sx in (-1.0, 1.0):
        m.box((sx * CORNER_X, FRAME_CY, FRAME_Z - 0.03), (0.08, 0.44, 0.08),
              ft[1], face_colors=ft)
    return m.finish("PodFrame")


def build_pod():
    """The rounded bubble: a short cylinder capped by a hemisphere, seated on the
    front bar of the frame."""
    m = C.Mesh()
    cx, cy = 0.0, FRAME_CY + CORNER_DY
    z0 = FRAME_Z + 0.01
    r = 0.17
    h = 0.12
    seg = 12
    rings = 4

    def p(i, ang_up, rad, z):
        th = 2.0 * math.pi * i / seg
        return (cx + math.cos(th) * rad, cy + math.sin(th) * rad, z)

    for i in range(seg):
        j = i + 1
        # cylinder wall
        shaded_face(m, [p(i, 0, r, z0), p(j, 0, r, z0), p(j, 0, r, z0 + h), p(i, 0, r, z0 + h)])
        # bottom cap
        shaded_face(m, [p(j, 0, r, z0), p(i, 0, r, z0), (cx, cy, z0)])
        # hemisphere bands
        for k in range(rings):
            a0 = 0.5 * math.pi * k / rings
            a1 = 0.5 * math.pi * (k + 1) / rings
            r0, r1 = r * math.cos(a0), r * math.cos(a1)
            zz0, zz1 = z0 + h + r * math.sin(a0), z0 + h + r * math.sin(a1)
            if k == rings - 1:
                shaded_face(m, [p(i, 0, r0, zz0), p(j, 0, r0, zz0), (cx, cy, zz1)])
            else:
                shaded_face(m, [p(i, 0, r0, zz0), p(j, 0, r0, zz0),
                                p(j, 0, r1, zz1), p(i, 0, r1, zz1)])
    return m.finish("Pod")


C.begin()
build_wing()
build_rim()
build_keel()
build_crossbar()
build_aframe()
build_pod()
build_pod_frame()
C.export("glider")
