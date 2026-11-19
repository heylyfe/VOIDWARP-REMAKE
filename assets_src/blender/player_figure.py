# T-015 REV: player figure, part set (J5). Same blocky prop-block + slab-trim style as the
# other T-015 models, but built as SEPARATE objects per limb, each with its mesh data
# authored relative to its joint origin (hip / shoulder / neck), so the engine can pose
# limbs procedurally by rotating the nodes:
#   PlayerBody (empty root, origin = feet centre)
#     Torso origin (0, 0, 0.80)   Head origin (0, 0, 1.40)
#     ArmL / ArmR origin (+-0.34, 0, 1.38)   LegL / LegR origin (+-0.16, 0, 0.85)
# Total height stays 1.80 u (head crest tops out exactly at 1.80). Class tinting is
# engine-side (DESIGN 11); palette roles only, no textures. The figure's forward is
# Blender +Y (visor side), which the glTF Y-up conversion lands on Godot's -Z.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
bpy = C.bpy  # the shared module already imports bpy
root = bpy.data.objects.new("PlayerBody", None)
bpy.context.scene.collection.objects.link(root)


def build(name, loc, fn):
    m = C.Mesh()
    fn(m)
    obj = m.finish(name)
    obj.location = loc
    obj.parent = root
    return obj


def torso(m):
    body = m.col("prop_block")
    trim = m.col("slab_trim")
    crate = m.col("prop_crate")
    gold = m.col("gold_gift")
    m.box((0, 0, 0.30), (0.54, 0.30, 0.60), body)      # chest 0.80-1.40
    m.box((0, 0, 0.04), (0.56, 0.32, 0.08), trim)      # belt 0.80-0.88
    m.box((0, 0.17, 0.04), (0.10, 0.03, 0.06), gold)   # belt buckle stud
    m.box((0, 0.165, 0.38), (0.30, 0.06, 0.24), trim)  # chest plate 1.06-1.30
    m.box((0, -0.195, 0.30), (0.32, 0.10, 0.36), crate)  # backpack 0.92-1.28
    m.box((0, -0.14, 0.62), (0.05, 0.05, 0.24), trim)    # antenna 1.30-1.54


def head(m):
    body = m.col("prop_block")
    trim = m.col("slab_trim")
    visor = m.col("black_gift_rim")
    m.box((0, 0, 0.20), (0.34, 0.32, 0.40), body)       # skull 1.40-1.80
    m.box((0, 0.165, 0.22), (0.26, 0.03, 0.08), visor)  # visor strip
    m.box((0, 0, 0.38), (0.08, 0.26, 0.04), trim)       # crest, tops at 1.80
    m.box((-0.185, 0, 0.18), (0.05, 0.14, 0.10), trim)  # left ear puck
    m.box((0.185, 0, 0.18), (0.05, 0.14, 0.10), trim)   # right ear puck


def arm(m):
    body = m.col("prop_block")
    trim = m.col("slab_trim")
    m.box((0, 0, -0.26), (0.14, 0.24, 0.56), body)  # arm, fingertip abs 0.73
    m.box((0, 0, 0.03), (0.22, 0.30, 0.12), trim)   # shoulder pad
    m.box((0, 0, -0.58), (0.16, 0.26, 0.14), trim)  # glove


def leg(m):
    body = m.col("prop_block")
    trim = m.col("slab_trim")
    m.box((0, 0, -0.425), (0.22, 0.26, 0.85), body)      # leg 0.85-0.00 (abs)
    m.box((0, 0.01, -0.77), (0.26, 0.30, 0.16), trim)    # boot 0.00-0.16
    m.box((0, 0.135, -0.425), (0.12, 0.03, 0.16), trim)  # knee strip


build("Torso", (0, 0, 0.80), torso)
build("Head", (0, 0, 1.40), head)
build("ArmL", (-0.34, 0, 1.38), arm)
build("ArmR", (0.34, 0, 1.38), arm)
build("LegL", (-0.16, 0, 0.85), leg)
build("LegR", (0.16, 0, 0.85), leg)

C.export("player_figure")
