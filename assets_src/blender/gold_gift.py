# T-015: gold gift (TERRAIN_SPEC 12.2: #FFC83D, emission x2.0, engine-side).
# Taller/narrower than the black gift so the two silhouettes read apart.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
m = C.Mesh()
gold = m.col("gold_gift")
m.box((0, 0, 0.26), (0.52, 0.52, 0.52), gold)   # box
m.box((0, 0, 0.57), (0.60, 0.60, 0.10), gold)   # lid
m.box((0, 0, 0.70), (0.24, 0.24, 0.24), gold)   # bow block
m.box((0, 0, 0.88), (0.34, 0.10, 0.10), gold)   # bow wing X
m.box((0, 0, 0.88), (0.10, 0.34, 0.10), gold)   # bow wing Y
m.finish("gold_gift")
C.export("gold_gift")
