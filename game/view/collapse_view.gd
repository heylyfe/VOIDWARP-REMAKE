extends Node3D
#
# Platform collapse view (owner request 2026-11-20; sim/collapse.gd owns the schedule).
#
# This node IS the drop root: it carries every non-hub level mesh (level_mesher PART_REST)
# plus one merged crack overlay (a quad 0.02 u over each collapsing tile top). The hub's
# meshes are built separately by the world and never parented here, so nothing on the
# spawn platform can crack or fall.
#
#   idle      overlay hidden, node at rest.
#   cracking  overlay visible from the start tick itself; crack_progress (0..1 over the
#             300-tick phase) widens and reveals the crack network; the last 60 ticks the
#             node shudders (a few cm, deterministic from the tick).
#   fallen    from the fall tick the node drops on a ballistic curve (g = 32 u/s^2, the
#             controller's gravity) and is hidden DROP_TICKS later, so it never lingers.
#
# Read-only on sim state: sync(st, tick) is called once per sim tick from the world's view
# pass. Cost per tick is one transform write and one shader uniform - nothing is rebuilt.

const CollapseScript := preload("res://sim/collapse.gd")

const HU := 0.5
const LIFT := 0.02          # overlay height over the tile top (no z-fight)
const GRAVITY := 32.0
const DROP_TICKS := 60      # 1.0 s of visible drop (16 u), then hidden
const SHUDDER_TICKS := 60
const SHUDDER_AMP := 0.05

const CRACK_SHADER := "
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 crack_color : source_color = vec3(0.02, 0.02, 0.04);
uniform vec3 glow_color : source_color = vec3(0.55, 1.0, 0.95);

varying vec3 v_world;

vec2 h2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Voronoi shard edges, ~3 shards per tile: F2 - F1 is small on a crack line.
	vec2 p = v_world.xz * 1.7;
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	vec2 c1 = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = h2(ip + g);
			vec2 r = g + o - fp;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
				c1 = ip + g;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	float edge = sqrt(f2) - sqrt(f1);
	float width = mix(0.035, 0.11, progress);
	float line = 1.0 - smoothstep(width * 0.5, width, edge);
	// shards reveal their outline progressively: 45% at the start tick, all by 60%
	float reveal = step(h2(c1 + vec2(17.0, 3.0)).x, 0.45 + 0.9 * progress);
	float a = line * reveal;
	if (a < 0.02) {
		discard;
	}
	float core = 1.0 - smoothstep(0.0, width * 0.45, edge);
	vec3 col = mix(crack_color, glow_color, core * (0.35 + 0.65 * progress));
	ALBEDO = col;
	ALPHA = a * 0.95;
}
"

var overlay: MeshInstance3D = null
var _mat: ShaderMaterial = null
var _meshes: Array = []
var _rest_y := 0.0


## rest_meshes: level_mesher.build(lv, {}, PART_REST)["meshes"]; st: collapse.create(lv).
func setup(lv: Dictionary, rest_meshes: Dictionary, st: Dictionary) -> void:
	name = "PlatformCollapse"
	for mn in rest_meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = rest_meshes[mn]
		add_child(mi)
		_meshes.append(mi)
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CRACK_SHADER
	_mat.shader = sh
	var m := build_overlay(lv, st)
	overlay = MeshInstance3D.new()
	overlay.name = "Cracks"
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if m != null:
		m.surface_set_material(0, _mat)
		overlay.mesh = m
	overlay.visible = false
	add_child(overlay)
	position = Vector3.ZERO
	visible = true


func mesh_instances() -> Array:
	return _meshes


## One merged quad per collapsing tile (flat tops and ramp slopes; a tile under a prop is
## skipped - the prop box covers it). null when nothing collapses.
static func build_overlay(lv: Dictionary, st: Dictionary) -> ArrayMesh:
	var prop_at := {}
	for p in lv.get("props", []):
		prop_at["%d,%d,%d" % [int(p[0]), int(p[1]), int(p[2])]] = true
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var idx := PackedInt32Array()
	for t in lv.get("tiles", []):
		var key := "%d,%d,%d" % [int(t[0]), int(t[1]), int(t[2])]
		if not CollapseScript.listed(st, key) or prop_at.has(key):
			continue
		var x := float(t[0])
		var z := float(t[1])
		var lo := float(t[2]) * HU + LIFT
		var kind := int(t[3])
		var cs := [Vector2(x, z), Vector2(x + 1.0, z), Vector2(x + 1.0, z + 1.0), Vector2(x, z + 1.0)]
		var b := pos.size()
		for c in cs:
			var f := 0.0
			match kind - 1:
				0:
					f = c.x - x
				1:
					f = c.y - z
				2:
					f = x + 1.0 - c.x
				3:
					f = z + 1.0 - c.y
			pos.append(Vector3(c.x, lo + HU * f, c.y))
			nor.append(Vector3.UP)
		idx.append_array(PackedInt32Array([b, b + 2, b + 1, b, b + 3, b + 2]))
	if idx.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nor
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## The view pass: read the collapse state on sim tick `tick`.
func sync(st: Dictionary, tick: int) -> void:
	var ph := CollapseScript.phase(st)
	if ph == CollapseScript.PHASE_IDLE:
		overlay.visible = false
		position = Vector3.ZERO
		visible = true
		return
	if ph == CollapseScript.PHASE_CRACKING:
		overlay.visible = overlay.mesh != null
		_mat.set_shader_parameter("progress", CollapseScript.crack_progress(st, tick))
		var left := int(st["fall_tick"]) - tick
		if left <= SHUDDER_TICKS:
			var amp := SHUDDER_AMP * (1.0 - float(left) / float(SHUDDER_TICKS))
			position = Vector3(amp * sin(float(tick) * 2.7), 0.0, amp * cos(float(tick) * 3.1))
		else:
			position = Vector3.ZERO
		visible = true
		return
	# fallen
	var n := CollapseScript.ticks_since_fall(st, tick)
	if n >= DROP_TICKS:
		visible = false
		return
	var t := float(n) / 60.0
	_mat.set_shader_parameter("progress", 1.0)
	overlay.visible = overlay.mesh != null
	position = Vector3(0.0, -0.5 * GRAVITY * t * t, 0.0)
	visible = true


## Drop offset in u (<= 0) on the current frame; for tests and probes.
func drop_offset() -> float:
	return position.y
