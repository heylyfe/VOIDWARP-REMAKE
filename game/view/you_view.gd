extends Node3D
#
# YOU?! view (ticket T-035; ENEMIES.md "Husk -> YOU?!", DESIGN.md section 5.6,
# the T-083 anim block in sprites.json section 1.6 - read here, never re-declared).
#
# View layer only: it READS the behavior's row dictionary and never writes sim
# state. The sim row carries everything the anim block speaks with:
#   "anim_state"   - one of the anim block state keys (spawn / idle_chase /
#                    telegraph / attack / recover)
#   "anim_state_t" - ticks spent in the state (telegraph = 90 ticks to release)
#   "rings"        - live shockwave rings, {"x", "y", "z", "r"} each
#
# Frame choice follows sprites.json's "animations" (the shared billboard
# machinery); the per-state RATES come from the anim block's own rows
# (telegraph fps 16, idle_chase/recover fps 8). The telegraph effect comes from
# the anim block's `telegraph` effect params: shake_u (sprite shake), rgb_split_px
# (the "0 -> 6" ramp, applied to the sprite shader as it grows), color (the
# feet_ring + band colour, #FF2A2A). The attack row drives the expanding band
# (the ring_release effect: a 1.0 u TALL translucent red band, never a decal).
#
# BILLBOARDING / TRANSPARENCY hard rules: the sprite always faces the camera
# (billboard.gd); the sprite shader discards alpha < 0.5 (the scissor rule);
# the band and feet ring stay translucent.

const BillboardScript := preload("res://view/billboard.gd")
const AssetLoadScript := preload("res://view/asset_load.gd")   # U4: fail-soft loads (text/scene/texture/stream)

const SHEET_REL := "res://content/enemies/you/sprites.json"
const FOLDER_REL := "res://content/enemies/you"
const BAND_SEGMENTS := 32
const BAND_ALPHA := 0.35
const BAND_HEIGHT := 1.0
const FEET_RING_TUBE := 0.03
const FEET_RING_Y := 0.02
const FEET_RING_ALPHA := 0.9
const ATTACK_FRAME := 4                   # the anim block attack row: you_04
const SPAWN_TICKS := 30.0                 # the anim block spawn row: 30 ticks

var billboard = null               # BillboardScript instance (the PNG enemy)
var _sprite_wrap: Node3D = null    # shake (telegraph) + fade pop (spawn) live here
var feet_ring: MeshInstance3D = null
var band: MeshInstance3D = null
var _band_mat: StandardMaterial3D = null
var _feet_mat: StandardMaterial3D = null
var _split_mat: ShaderMaterial = null
var _anim_block: Dictionary = {}   # the sprites.json "anim" block (section 1.6)
var _telegraph_ticks := 90.0
var _telegraph_fps := 16.0
var _chase_fps := 8.0
var _shake_u := 0.05
var _split_max_px := 6.0
var _red := Color(1.0, 0.1647, 0.1647)    # replaced by the block's effect color
var _t: float = 0.0


func setup(sheet_path: String = SHEET_REL, folder: String = FOLDER_REL) -> void:
	for child in get_children():
		child.free()
	var doc: Dictionary = {}
	var parsed = JSON.parse_string(AssetLoadScript.text(sheet_path))
	if parsed is Dictionary:
		doc = parsed
	_anim_block = doc.get("anim", {})
	_read_anim_block()
	_sprite_wrap = Node3D.new()
	_sprite_wrap.name = "SpriteWrap"
	add_child(_sprite_wrap)
	billboard = BillboardScript.new()
	_sprite_wrap.add_child(billboard)
	if not doc.is_empty():
		billboard.setup_from_sheet(doc, folder)
	_split_mat = _split_shader()
	billboard.material_override = _split_mat
	_build_feet_ring()
	_build_band()


## Pull every number this view needs from the anim block, with the stated values
## as fallbacks (the block is T-083's binding spec; nothing here re-declares it).
func _read_anim_block() -> void:
	var states: Dictionary = _anim_block.get("states", {})
	var tele: Dictionary = states.get("telegraph", {})
	_telegraph_ticks = float(tele.get("total_ticks", 90))
	_telegraph_fps = float(tele.get("fps", 60.0 / float(tele.get("ticks_per_frame", 3.75))))
	var idle: Dictionary = states.get("idle_chase", {})
	_chase_fps = float(idle.get("fps", 8.0))
	var fx: Dictionary = (tele.get("effect", {}) as Dictionary).get("params", {})
	_shake_u = float(fx.get("shake_u", 0.05))
	_split_max_px = _parse_split_target(str(fx.get("rgb_split_px", "0 -> 6")))
	_red = Color(str(fx.get("color", "#FF2A2A")))


static func _parse_split_target(s: String) -> float:
	var arrow := s.find("->")
	if arrow < 0:
		return 6.0
	var rest := s.substr(arrow + 2).strip_edges()
	var num := ""
	for i in rest.length():
		var ch := rest[i]
		if ch.is_valid_int() or ch == ".":
			num += ch
		else:
			break
	if num == "":
		return 6.0
	return float(num)


## The anim block's state ids, for callers/tests that prove the wiring.
func anim_state_ids() -> Array:
	_read_anim_block()
	return (_anim_block.get("states", {}) as Dictionary).keys()


func _build_feet_ring() -> void:
	feet_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.97
	torus.outer_radius = 1.03
	_feet_mat = StandardMaterial3D.new()
	_feet_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_feet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_feet_mat.albedo_color = Color(_red.r, _red.g, _red.b, FEET_RING_ALPHA)
	_feet_mat.emission_enabled = true
	_feet_mat.emission = _red
	_feet_mat.disable_fog = true
	_feet_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	feet_ring.mesh = torus
	feet_ring.material_override = _feet_mat
	feet_ring.rotation.x = -PI / 2.0
	feet_ring.position = Vector3(0.0, FEET_RING_Y, 0.0)
	feet_ring.visible = false
	add_child(feet_ring)


func _build_band() -> void:
	band = MeshInstance3D.new()
	band.mesh = _open_cylinder(BAND_SEGMENTS, 1.0, BAND_HEIGHT)
	_band_mat = StandardMaterial3D.new()
	_band_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_band_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_band_mat.albedo_color = Color(_red.r, _red.g, _red.b, BAND_ALPHA)
	_band_mat.emission_enabled = true
	_band_mat.emission = _red
	_band_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	band.material_override = _band_mat
	band.visible = false
	add_child(band)


# Open cylinder, unit radius, y in [0, height] - only the side wall (the band).
static func _open_cylinder(segments: int, radius: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		var p2 := Vector3(cos(a0) * radius, height, sin(a0) * radius)
		var p3 := Vector3(cos(a1) * radius, height, sin(a1) * radius)
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p2)
		st.add_vertex(p1)
		st.add_vertex(p3)
	return st.commit()


func _split_shader() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_nearest;
uniform float split_px = 0.0;
uniform float tex_w = 256.0;
uniform float fade = 1.0;
void fragment() {
\tvec2 uv = UV;
\tvec2 off = vec2(split_px / tex_w, 0.0);
\tvec4 c = texture(tex, uv);
\tfloat r = texture(tex, uv + off).r;
\tfloat b = texture(tex, uv - off).b;
\tvec3 rgb = vec3(r, c.g, b);
\tfloat a = c.a * fade;
\tif (a < 0.5) {
\t\tdiscard;
\t}
\tALBEDO = rgb;
\tALPHA = a;
}"""
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


# One frame of view. row is the sim row (read-only); dt is seconds elapsed.
# The caller places this node at the enemy's feet; the view never writes sim state.
func sync(row: Dictionary, dt: float, cam_pos: Vector3 = Vector3.ZERO) -> void:
	_t += dt
	if billboard == null:
		return
	var state := str(row.get("anim_state", "idle_chase"))
	var state_t := float(row.get("anim_state_t", 0))
	var anims: Dictionary = billboard.anims
	var cycle = anims.get("cycle", null)
	if cycle != null:
		var want_fps := _telegraph_fps if state == "telegraph" else _chase_fps
		if not is_equal_approx(float(cycle["fps"]), want_fps):
			cycle["fps"] = want_fps
	billboard.advance_animation(dt)
	if state == "attack":
		billboard.frame_i = ATTACK_FRAME
		billboard._apply_frame(ATTACK_FRAME)
	_drive_effects(state, state_t, row)
	_sync_band(row)
	if cam_pos != Vector3.ZERO:
		billboard.face_camera(cam_pos)


func _drive_effects(state: String, state_t: float, row: Dictionary) -> void:
	var split := 0.0
	var fade := 1.0
	var shake := Vector3.ZERO
	if state == "telegraph":
		var k := clampf(state_t / maxf(_telegraph_ticks, 1.0), 0.0, 1.0)
		split = _split_max_px * k
		shake = Vector3(sin(_t * 91.0), 0.0, cos(_t * 113.0)) * _shake_u
	elif state == "spawn":
		fade = clampf(state_t / SPAWN_TICKS, 0.05, 1.0)
	_sprite_wrap.position = shake
	if _split_mat != null:
		_split_mat.set_shader_parameter("split_px", split)
		_split_mat.set_shader_parameter("fade", fade)
		if billboard != null and billboard.texture != null:
			_split_mat.set_shader_parameter("tex", billboard.texture)
			var tw := float(billboard.texture.get_width())
			if tw > 0.0:
				_split_mat.set_shader_parameter("tex_w", tw)
	# the feet plane is the node's local y = 0 plane (the caller places us at the feet)
	if feet_ring != null:
		feet_ring.visible = state == "telegraph"


func _sync_band(row: Dictionary) -> void:
	if band == null:
		return
	var rings: Array = row.get("rings", [])
	if rings.is_empty():
		band.visible = false
		return
	var ring: Dictionary = rings[rings.size() - 1]
	var r := maxf(float(ring.get("r", 0.0)), 0.05)
	band.visible = true
	band.scale = Vector3(r, 1.0, r)
	# the band stays at the ring's release point, not under the floating body
	band.position = Vector3(float(ring.get("x", 0.0)) - position.x,
		float(ring.get("y", 0.0)) - position.y,
		float(ring.get("z", 0.0)) - position.z)
