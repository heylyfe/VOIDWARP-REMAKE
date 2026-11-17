# T-015: launch pad (TERRAIN_SPEC 12.2: #2A5BFF top, emission pulses 0.5-1.5 at
# 1 Hz - the pulse is engine-side). Slab-side sides with the trim band; corner
# posts in prop-block mark the pad footprint on the tile grid.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
m = C.Mesh()
top = m.col("launch_pad")
side = m.col("slab_side")
trim = m.col("slab_trim")
post = m.col("prop_block")
m.box((0, 0, 0.125), (2.0, 2.0, 0.25), side,
      face_colors=[side, top, side, side, side, side])
m.box((0, 0, 0.21875), (2.04, 2.04, 0.0625), trim,
      face_colors=[trim, top, trim, trim, trim, trim])
for sx in (-0.85, 0.85):
    for sy in (-0.85, 0.85):
        m.box((sx, sy, 0.32), (0.18, 0.18, 0.14), post)
m.finish("launch_pad")
C.export("launch_pad")
