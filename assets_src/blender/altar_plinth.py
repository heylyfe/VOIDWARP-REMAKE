# T-015: altar plinth (DESIGN 11: 1.2 x 1.0 x 1.2 u). Prop-block body with the
# slab trim band, hub-dais top plate carrying the 12-point star sigil inlay
# (6 crossing bars at 30 deg steps, boxes only), exhibit hovers above it.
import math, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
m = C.Mesh()
body = m.col("prop_block")
trim = m.col("slab_trim")
top = m.col("hub_dais")
sigil = m.colx("hub_dais", "sigil_hex")
m.box((0, 0, 0.4375), (1.2, 1.2, 0.875), body)
m.box((0, 0, 0.9375), (1.2, 1.2, 0.125), trim,
      face_colors=[trim, top, trim, trim, trim, trim])
for k in range(6):
    m.box((0, 0, 1.005), (0.9, 0.07, 0.01), sigil, rot_z=math.pi * k / 6.0)
m.finish("altar_plinth")
C.export("altar_plinth")
