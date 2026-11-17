# T-015: beacon (TERRAIN_SPEC 12.2). Closed (dull #3A4A55, emission 0) and open
# (#E8FFFF, emission x4.0, light column) share ONE mesh: this mesh carries the
# closed colours; the open state is an engine-side material/emission swap on the
# same geometry, so there is exactly one beacon mesh and no baked open variant.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
m = C.Mesh()
c = m.col("beacon_closed")
m.box((0, 0, 0.15), (1.6, 1.6, 0.30), c)    # stepped base, tier 1
m.box((0, 0, 0.45), (1.2, 1.2, 0.30), c)    # stepped base, tier 2
m.box((0, 0, 0.72), (0.8, 0.8, 0.24), c)    # stepped base, tier 3
m.box((0, 0, 1.62), (0.4, 0.4, 1.6), c)     # pylon
m.box((0, 0, 2.60), (0.56, 0.56, 0.56), c)  # head core
m.box((0, 0, 3.00), (0.32, 0.32, 0.24), c)  # head cap
m.finish("beacon")
C.export("beacon")
