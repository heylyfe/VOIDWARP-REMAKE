# T-015: tall jar (DESIGN 11: lobby props). Slim stepped jar, taller and thinner
# prop-block body with slab-trim foot, band and lip.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
m = C.Mesh()
body = m.col("prop_block")
trim = m.col("slab_trim")
m.box((0, 0, 0.05), (0.40, 0.40, 0.10), trim)    # foot
m.box((0, 0, 0.65), (0.34, 0.34, 1.10), body)    # body 0.10..1.20
m.box((0, 0, 1.05), (0.38, 0.38, 0.06), trim)    # band
m.box((0, 0, 1.325), (0.22, 0.22, 0.25), body)   # neck 1.20..1.45
m.box((0, 0, 1.51), (0.32, 0.32, 0.12), trim)    # lip 1.45..1.57
m.finish("tall_jar")
C.export("tall_jar")
