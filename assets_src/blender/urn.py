# T-015: urn (DESIGN 11: lobby props along the walls). Stepped box urn in the
# prop-block colour with slab-trim foot, band and lip.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
m = C.Mesh()
body = m.col("prop_block")
trim = m.col("slab_trim")
m.box((0, 0, 0.06), (0.44, 0.44, 0.12), trim)   # foot
m.box((0, 0, 0.36), (0.60, 0.60, 0.48), body)   # belly
m.box((0, 0, 0.30), (0.64, 0.64, 0.06), trim)   # belly band
m.box((0, 0, 0.68), (0.48, 0.48, 0.16), body)   # shoulder
m.box((0, 0, 0.85), (0.30, 0.30, 0.18), body)   # neck
m.box((0, 0, 0.99), (0.42, 0.42, 0.10), trim)   # lip
m.finish("urn")
C.export("urn")
