# T-015: black gift (TERRAIN_SPEC 12.2: body #050608, rim ribbon #7CFFF4 x1.5).
# Box-and-wedge voxel style; 1 Blender unit = 1 game u, Z up, base on the floor.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
m = C.Mesh()
body = m.col("black_gift_body")
rim = m.col("black_gift_rim")
m.box((0, 0, 0.21), (0.62, 0.62, 0.42), body)   # box
m.box((0, 0, 0.47), (0.70, 0.70, 0.10), body)   # lid
m.box((0, 0, 0.26), (0.72, 0.12, 0.54), rim)    # ribbon along X
m.box((0, 0, 0.26), (0.12, 0.72, 0.54), rim)    # ribbon along Y
m.box((0, 0, 0.58), (0.16, 0.16, 0.10), rim)    # knot
m.finish("black_gift")
C.export("black_gift")
