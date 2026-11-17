# T-015: player figure (DESIGN 11: class exhibits show "the player model in that
# class's colours"; class tinting is engine-side). Blocky humanoid, 1.8 u tall
# total, prop-block body with slab-trim belt / chest plate / visor.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
m = C.Mesh()
body = m.col("prop_block")
trim = m.col("slab_trim")
m.box((-0.16, 0, 0.40), (0.22, 0.26, 0.80), body)   # left leg  0.00-0.80
m.box((0.16, 0, 0.40), (0.22, 0.26, 0.80), body)    # right leg 0.00-0.80
m.box((0, 0, 1.125), (0.56, 0.30, 0.65), body)      # torso 0.80-1.45
m.box((0, 0, 0.84), (0.58, 0.34, 0.08), trim)       # belt
m.box((0, 0.155, 1.22), (0.30, 0.06, 0.22), trim)   # chest plate
m.box((-0.35, 0, 1.12), (0.14, 0.24, 0.55), body)   # left arm
m.box((0.35, 0, 1.12), (0.14, 0.24, 0.55), body)    # right arm
m.box((0, 0, 1.625), (0.34, 0.32, 0.35), body)      # head 1.45-1.80
m.box((0, 0.17, 1.66), (0.26, 0.03, 0.08), trim)    # visor
m.finish("player_figure")
C.export("player_figure")
