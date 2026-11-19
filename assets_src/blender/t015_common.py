# assets_src/blender/t015_common.py - shared helpers for the T-015 model scripts.
#
# Box-and-wedge voxel style only (TERRAIN_SPEC.md section 12.1 rule 5): axis-aligned
# boxes, optionally rotated in whole steps around Z. Vertex colours come from
# game/data/palette.json (TERRAIN_SPEC.md section 12.2). No textures, no downloaded
# assets, no sculpting, no smooth shading. The script is the source of truth; the
# .glb it writes is a build artifact.
#
# Run inside Blender:  blender --background --python <model>.py --python-exit-code 1

import bpy
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PALETTE_PATH = os.path.join(ROOT, "game", "data", "palette.json")

# The 6 faces of a box as corner-index quads, wound CCW seen from outside.
# Order: 0:-Z (bottom)  1:+Z (top)  2:-Y  3:+X  4:+Y  5:-X
QUADS = [
    (0, 3, 2, 1),
    (4, 5, 6, 7),
    (0, 1, 5, 4),
    (1, 2, 6, 5),
    (2, 3, 7, 6),
    (3, 0, 4, 7),
]


def _srgb_to_linear(c):
    """The standard sRGB transfer function (IEC 61966-2-1): decode one channel."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgba(hexstr):
    # glTF defines COLOR_0 as LINEAR, so the palette's sRGB bytes must be
    # decoded to linear here - otherwise Godot treats them as linear and
    # re-encodes linear->sRGB for display, rendering every model lighter
    # than its palette.
    h = hexstr.lstrip("#")
    return (_srgb_to_linear(int(h[0:2], 16) / 255.0),
            _srgb_to_linear(int(h[2:4], 16) / 255.0),
            _srgb_to_linear(int(h[4:6], 16) / 255.0), 1.0)


def begin():
    """Factory-reset to an empty scene so every run is deterministic."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


class Mesh:
    """Accumulates boxes, then bakes them into one mesh with vertex colours."""

    def __init__(self):
        with open(PALETTE_PATH, "r", encoding="utf-8") as f:
            self.roles = json.load(f)["roles"]
        self.verts = []
        self.faces = []
        self.cols = []

    def col(self, role):
        return hex_rgba(self.roles[role]["hex"])

    def colx(self, role, key):
        """A named sub-key of a role, e.g. sigil_hex / trim_hex."""
        return hex_rgba(self.roles[role][key])

    def box(self, center, size, color, rot_z=0.0, face_colors=None):
        """Add one box. center/size in u (1 Blender unit = 1 game u, Z up).
        face_colors: optional 6-list matching QUADS, overrides color per face."""
        cx, cy, cz = center
        hx, hy, hz = size[0] / 2.0, size[1] / 2.0, size[2] / 2.0
        corners = [
            (-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
            (-hx, -hy, +hz), (hx, -hy, +hz), (hx, hy, +hz), (-hx, hy, +hz),
        ]
        ca, sa = math.cos(rot_z), math.sin(rot_z)
        pts = []
        for (x, y, z) in corners:
            pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca, cz + z))
        for fi, quad in enumerate(QUADS):
            col = color if face_colors is None else face_colors[fi]
            base = len(self.verts)
            for v in quad:
                self.verts.append(pts[v])
                self.cols.append(col)
            self.faces.append((base, base + 1, base + 2, base + 3))

    def finish(self, name):
        """Bake one mesh + object named `name`; returns the object."""
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts, [], self.faces)
        mesh.validate()
        mesh.update()
        # FLOAT_COLOR (not BYTE_COLOR): BYTE_COLOR quantizes the stored float and
        # the glTF exporter then re-scales it to uint16, which Godot truncates
        # back to 8 bit - losing a full byte step on some channels. FLOAT_COLOR
        # goes through the whole chain (Blender -> glb float32 -> Godot Color)
        # unchanged. hex_rgba() hands us LINEAR values (glTF COLOR_0 is linear),
        # so the engine renders the palette hex, not an sRGB-lifted copy.
        attr = mesh.color_attributes.new(name="COL_0", type="FLOAT_COLOR",
                                         domain="POINT")
        flat = []
        for c in self.cols:
            flat.extend(c)
        attr.data.foreach_set("color", flat)
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        print("T015_MESH %s verts=%d tris=%d"
              % (name, len(self.verts), len(self.faces) * 2))
        return obj


def export(name):
    """Write game/assets/models/<name>.glb (whole scene, Y-up per glTF spec)."""
    out_dir = os.environ.get("T015_MODELS_OUT") or os.path.join(
        ROOT, "game", "assets", "models")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_materials="NONE",
        export_all_vertex_colors=True,
        export_vertex_color_name="COL_0",
        export_cameras=False,
        export_lights=False,
    )
    print("T015_WROTE " + path)
    return path
