# Blender +Y is forward, which glTF converts to Godot -Z.
# PlayerBody is at the feet. The six limb meshes retain their authored joint
# origins so the view can rotate them. Head details inherit the neck rotation.
# The hat terminates at Z = 1.80 u in the rest pose.
import math
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t015_common as C

C.begin()
bpy = C.bpy
root = bpy.data.objects.new("PlayerBody", None)
bpy.context.scene.collection.objects.link(root)


def build(name, parent, location, draw):
    mesh = C.Mesh()
    draw(mesh)
    obj = mesh.finish(name)
    obj.parent = parent
    obj.location = location
    return obj


def face(mesh, points, color):
    first = len(mesh.verts)
    mesh.verts.extend(points)
    mesh.cols.extend([color] * len(points))
    mesh.faces.append(tuple(range(first, first + len(points))))


def tones(mesh, role):
    base = "player_" + role
    return [mesh.col(base + suffix) for suffix in ("", "_side", "_light")]


def block(mesh, center, size, role):
    front, side, top = tones(mesh, role)
    mesh.box(center, size, front, face_colors=[side, top, side, side, front, front])


def loft(mesh, rings, color, top, bottom):
    count = len(rings[0])
    face(mesh, rings[0][::-1], bottom)
    for lower, upper in zip(rings, rings[1:]):
        for i in range(count):
            j = (i + 1) % count
            face(mesh, [lower[i], lower[j], upper[j], upper[i]], color(i))
    face(mesh, rings[-1], top)


def ring(rx, ry, z, *, center_y=0, slope=0, power=1, count=32, phase=0):
    points = []
    for i in range(count):
        angle = i * math.tau / count + phase
        x, y = math.cos(angle), math.sin(angle)
        y = ry * math.copysign(abs(y) ** power, y)
        points.append((rx * math.copysign(abs(x) ** power, x),
                       y + center_y, z + y * slope))
    return points


def head(mesh):
    front, side, light = tones(mesh, "skin")
    layers = [(0.104, 0.091, -0.331), (0.139, 0.118, -0.310),
              (0.153, 0.129, -0.264), (0.153, 0.129, -0.143),
              (0.132, 0.111, -0.110), (0.108, 0.088, -0.100)]
    loft(mesh, [ring(x, y, z, power=0.44) for x, y, z in layers],
         lambda i: front if 2 <= i < 13 else side, light, side)


def brim(mesh):
    front, side, light = tones(mesh, "hat")
    layers = [(0.251, 0.193, -0.109), (0.263, 0.202, -0.090),
              (0.255, 0.193, -0.067)]
    loft(mesh, [ring(x, y, z, slope=-0.17, power=0.62, count=16) for x, y, z in layers],
         lambda i: front if i < 8 else side, light, side)


def hat(mesh):
    front, side, light = tones(mesh, "hat")
    band = mesh.col("player_band")
    band_side = mesh.col("player_band_side")
    layers = [(0.131, -0.073, -0.014), (0.112, -0.014, -0.025),
              (0.047, 0.285, -0.065), (0.035, 0.327, -0.069),
              (0.012, 0.400, -0.076)]
    rings = [ring(r, r * 0.92, z, center_y=y, count=16) for r, z, y in layers]
    for i, (lower, upper) in enumerate(zip(rings, rings[1:])):
        for j in range(len(lower)):
            k = (j + 1) % len(lower)
            if i == 2:
                color = band if j < 8 else band_side
            else:
                color = light if 2 <= j < 6 else front if j < 9 else side
            face(mesh, [lower[j], lower[k], upper[k], upper[j]], color)
    face(mesh, rings[-1], front)


def tapered_branch(mesh, knots, colors):
    # A small polygonal cross-section keeps the branches and hair faceted.
    points = [Vector(point) for point, _ in knots]
    rings = []
    tangent = (points[-1] - points[0]).normalized()
    guide = tangent.cross(Vector((0, 1, 0)))
    if guide.length < 0.1:
        guide = tangent.cross(Vector((1, 0, 0)))
    guide.normalize()
    for i, (point, (_, radius)) in enumerate(zip(points, knots)):
        axis = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        u = (guide - axis * axis.dot(guide)).normalized()
        v = axis.cross(u)
        rings.append([point + radius * (u * math.cos(a) + v * math.sin(a))
                      for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2)])
    loft(mesh, rings, lambda i: colors[i % len(colors)], colors[0], colors[1])


def antlers(mesh):
    colors = tones(mesh, "hat")
    branches = [
        [(.114, -.040, -.067, .025), (.180, -.063, .011, .022),
         (.211, -.077, .096, .017), (.210, -.096, .171, .014),
         (.248, -.114, .214, .010), (.290, -.132, .263, .007),
         (.302, -.133, .303, .004), (.286, -.126, .337, .001)],
        [(.194, -.072, .055, .014), (.243, -.055, .096, .011),
         (.265, -.047, .147, .006), (.269, -.049, .177, .001)],
        [(.245, -.055, .102, .009), (.246, -.050, .149, .005), (.235, -.054, .174, .001)],
        [(.210, -.094, .163, .013), (.169, -.101, .203, .010),
         (.140, -.097, .247, .006), (.129, -.088, .276, .001)],
        [(.165, -.100, .208, .009), (.182, -.102, .246, .006),
         (.180, -.100, .296, .001)],
        [(.181, -.101, .258, .006), (.206, -.108, .275, .004), (.214, -.108, .303, .001)],
        [(.252, -.117, .216, .010), (.220, -.125, .249, .006), (.207, -.125, .276, .001)],
    ]
    for side in (-1, 1):
        for branch in branches:
            tapered_branch(mesh, [((side * x, y, z), r) for x, y, z, r in branch], colors)


def ruff(mesh):
    colors = tones(mesh, "hair")
    for layer, count in enumerate((17, 12)):
        for i in range(count):
            angle = math.tau * (i + layer * 0.43) / count
            x, y = math.cos(angle), math.sin(angle)
            # Short fringe across the face, longer clumps at the sides and back.
            fringe = y > 0.63
            spread = 0.034 + 0.014 * math.sin(i * 4.1 + layer)
            drop = (0.071 if fringe else 0.152) + 0.031 * math.cos(i * 2.9)
            z = -0.088 + layer * 0.082 - y * 0.027
            tapered_branch(mesh, [
                ((x * 0.099, y * 0.103, z), 0.025),
                ((x * 0.157, y * 0.142, z - drop * 0.35), 0.031 - layer * 0.006),
                ((x * (0.161 + spread) + 0.018 * y, y * (0.146 + spread),
                  z - drop if layer == 0 else z + 0.021 + spread), 0.001),
            ], colors)


def expression(mesh):
    ink = mesh.col("player_ink")
    for x in (-0.052, 0.052):
        face(mesh, [(x + 0.017 * math.cos(a), 0.1305, -0.197 - 0.029 * math.sin(a))
                    for a in (i * math.tau / 16 for i in range(16))], ink)
    for i in range(16):
        x0 = (i / 16 - 0.5) * 0.108
        x1 = ((i + 1) / 16 - 0.5) * 0.108
        def smile_z(x):
            return -0.288 + 0.046 * (x / 0.054) ** 2
        z0, z1 = smile_z(x0), smile_z(x1)
        face(mesh, [(x0, 0.1305, z0 + 0.0055), (x1, 0.1305, z1 + 0.0055),
                    (x1, 0.1305, z1 - 0.0055), (x0, 0.1305, z0 - 0.0055)], ink)


build("Torso", root, (0, 0, 0.80),
      lambda m: block(m, (0, 0, 0.017), (0.536, 0.278, 0.554), "cloth"))
head_joint = build("Head", root, (0, 0, 1.40), head)
for name, draw in (("WitchHat", hat), ("HatBrim", brim), ("Antlers", antlers),
                   ("HairRuff", ruff), ("Face", expression)):
    build(name, head_joint, (0, 0, 0), draw)

for side, suffix in ((-1, "L"), (1, "R")):
    build("Arm" + suffix, root, (side * 0.34, 0, 1.38),
          lambda m: block(m, (side * 0.049, 0, -0.505), (0.222, 0.263, 0.555), "skin"))
    build("Leg" + suffix, root, (side * 0.16, 0, 0.85),
          lambda m: block(m, (-side * 0.026, 0, -0.577), (0.264, 0.25, 0.546), "boot"))

C.export("player_figure")
