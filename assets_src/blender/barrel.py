# T-015: barrel (DESIGN 11: lobby props). Stepped box barrel, prop-crate body,
# slab-trim hoops slightly proud of the belly. No curves (12.1 rule 5).
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
m = C.Mesh()
body = m.col("prop_crate")
trim = m.col("slab_trim")
m.box((0, 0, 0.11), (0.68, 0.68, 0.22), body)   # bottom
m.box((0, 0, 0.48), (0.80, 0.80, 0.52), body)   # belly 0.22..0.74
m.box((0, 0, 0.83), (0.68, 0.68, 0.18), body)   # top 0.74..0.92
m.box((0, 0, 0.94), (0.60, 0.60, 0.04), trim)   # lid plate
m.box((0, 0, 0.30), (0.84, 0.84, 0.07), trim)   # hoop, low
m.box((0, 0, 0.66), (0.84, 0.84, 0.07), trim)   # hoop, high
m.finish("barrel")
C.export("barrel")
