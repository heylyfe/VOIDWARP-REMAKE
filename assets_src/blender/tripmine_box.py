# T-015: tripmine box (DESIGN 3.3: black framed box, six-pointed star centre).
# Star = three crossing bars at 0/60/120 deg (hexagram silhouette, boxes only),
# pink #FF4FD8 = the mine tell (TERRAIN_SPEC 12.2: the only pink in the level).
import math, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
m = C.Mesh()
frame = m.col("black_gift_body")
panel = m.col("platform_dark")
pink = m.col("tripmine_particles")
h, t = 0.22, 0.06
for sx in (-1, 1):
    for sy in (-1, 1):
        m.box((sx * (h - t / 2), sy * (h - t / 2), 0.25), (t, t, 0.5), frame)
    m.box((sx * (h - t / 2), 0, 0.47), (t, 0.38, t), frame)
    m.box((sx * (h - t / 2), 0, 0.03), (t, 0.38, t), frame)
    m.box((0, sx * (h - t / 2), 0.47), (0.38, t, t), frame)
    m.box((0, sx * (h - t / 2), 0.03), (0.38, t, t), frame)
for p in ((0.245, 0, 0.25), (-0.245, 0, 0.25)):
    m.box(p, (0.01, 0.36, 0.36), panel)
for p in ((0, 0.245, 0.25), (0, -0.245, 0.25)):
    m.box(p, (0.36, 0.01, 0.36), panel)
m.box((0, 0, 0.46), (0.40, 0.40, 0.04), panel)
m.box((0, 0, 0.04), (0.40, 0.40, 0.04), panel)
for deg in (0, 60, 120):
    m.box((0, 0, 0.49), (0.46, 0.055, 0.02), pink, rot_z=math.radians(deg))
m.finish("tripmine_box")
C.export("tripmine_box")
