# T-015: descent gate (DESIGN 11: stands at (0, -9.5) in the Antechamber, closed
# until every mandatory bay is resolved, then open - white, beacon language).
# Two nodes in ONE .glb: the static frame and the door slab. The mesh carries the
# dull closed colours; the open state (white, beacon_open) is engine-side, and
# the door being its own node lets the engine slide or recolour it.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
m = C.Mesh()
frame = m.col("prop_block")
trim = m.col("slab_trim")
door_c = m.col("beacon_closed")
m.box((-2.0, 0, 2.1), (1.0, 1.0, 4.2), frame)          # left pillar
m.box((2.0, 0, 2.1), (1.0, 1.0, 4.2), frame)           # right pillar
m.box((0, 0, 4.6), (5.0, 1.0, 0.8), frame)             # lintel
for sx in (-2.0, 2.0):
    m.box((sx, 0, 4.1375), (1.0, 1.0, 0.125), trim)    # pillar trim band
m.box((0, 0, 0.075), (5.0, 1.0, 0.15), trim)           # sill
m.finish("descent_gate_frame")
m2 = C.Mesh()
m2.box((0, 0, 2.175), (3.0, 0.4, 4.05), door_c)        # door slab, closed pose
m2.box((-0.9, 0, 2.175), (0.1, 0.42, 4.05), trim)      # stiffener
m2.box((0.9, 0, 2.175), (0.1, 0.42, 4.05), trim)       # stiffener
m2.finish("descent_gate_door")
C.export("descent_gate")
