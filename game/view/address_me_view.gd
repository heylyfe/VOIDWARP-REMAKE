extends Node3D
#
# address me view (ticket T-039; ENEMIES.md "Operator -> address me", DESIGN.md
# section 5.10, the T-083 anim block in sprites.json section 1.10 - read here,
# never re-declared).
#
# View layer only: it READS the behavior's row dictionary and never writes sim
# state. The sim row carries everything the anim block speaks with:
#   "anim_state"   - one of the anim block state keys (spawn / telegraph / leaves /
#                    attack / recover)
#   "anim_state_t" - ticks spent in the state (spawn 12 / telegraph 300 / leaves 18 /
#                    attack 24; the kill resolves on the LAST countdown tick)
#   "still_t"      - the row's stillness counter (0..90; the green arc fills at 90)
#   "countdown_left" - the live rumble ticks (300 -> 0; the red ring drains over it)
#
# Wired to the anim block:
#   spawn      12 ticks, cycle_00, fade in (a brightness ramp - the scissor fade
#              would pop; the anim block's alpha fade on a TBD-quality placeholder,
#              D-T-039-x), "trumpet_on_appearance" - the spawn_trumpet cue
#   telegraph  300 ticks, cycle_00 held (loop), effect countdown_ring: a red ring
#              drains clockwise over the 300 ticks; tint neutral -> amber at tick
#              150 -> red at tick 240; a green stillness arc fills over 90 still ticks
#              and empties the moment still_t resets (SHAKING fills shake too);
#              rumble_tremolo 1 -> 6 Hz (the sprite trembles, faster over time);
#              rumble_build cue on entering the state
#   leaves     18 ticks, cycle_00, scale -> 0 with a soft puff (shrink_puff)
#   attack     24 ticks, cycle_01 (the explode frame) held, full-screen white flash
#              for the first 6 ticks, explode_boom cue on entering the state
#   recover    nothing on screen
#
# BILLBOARDING / TRANSPARENCY hard rules: the sprite always faces the camera
# (billboard.gd, unchanged); the sprite shader discards alpha < 0.5; the arcs are
# opaque-with-angle-discard ribbons, fog-exempt, unshaded.

const BillboardScript := preload("res://view/billboard.gd")
const AddressMeAudio := preload("res://view/audio/address_me_audio.gd")

const SHEET_REL := "res://content/enemies/address_me/sprites.json"
const FOLDER_REL := "res://content/enemies/address_me"
const SPAWN_TICKS := 12.0
const COUNTDOWN_TICKS := 300.0
const TINT_AMBER_AT := 150
const TINT_RED_AT := 240
const LEAVES_TICKS := 18.0
const ATTACK_FLASH_TICKS := 6.0     # the anim block: full_screen_white_flash_ticks
const STILL_TICKS := 90.0
const RING_INNER := 1.42
const RING_OUTER := 1.56
const ARC_INNER := 1.62
const ARC_OUTER := 1.78
const RING_Y := 1.25                 # mid-body for a 2.5 u body

var billboard = null               # BillboardScript instance (the PNG enemy)
var _sprite_wrap: Node3D = null    # shrink (leaves), tremble (telegraph), fade ramp
var _countdown_arc: MeshInstance3D = null
var _stillness_arc: MeshInstance3D = null
var _flash: ColorRect = null
var _countdown_mat: ShaderMaterial = null
var _stillness_mat: ShaderMaterial = null
var _prev_state := ""
var _anim_block: Dictionary = {}
var _shake_u := 0.05

func setup(sheet_path: String = SHEET_REL, folder: String = FOLDER_REL) -> void:
	for child in get_children():
		child.free()
	var doc: Dictionary = {}
	if FileAccess.file_exists(sheet_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(sheet_path))
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
		var cycle = billboard.anims.get("cycle", null)
		if cycle != null:
			cycle["fps"] = 0.001   # frames are pinned per anim state (spawn/telegraph hold cycle_00, attack holds cycle_01)
	_build_arcs()
	_build_flash()


## Pull the numbers this view needs from the anim block, with the stated values
## as fallbacks (the block is T-083's binding spec; nothing here re-declares it).
func _read_anim_block() -> void:
	var states: Dictionary = _anim_block.get("states", {})
	var tele: Dictionary = states.get("telegraph", {})
	_shake_u = float(((tele.get("effect", {}) as Dictionary).get("params", {})).get("shake_u", 0.05))


func anim_state_ids() -> Array:
	return (_anim_block.get("states", {}) as Dictionary).keys()


# One arc ribbon, built in the local XY plane facing +Z: UV.x sweeps 0..1 clockwise
# from the top (PI/2), so a fragment discard on UV.x > fill drains the ring clockwise
# from the top, exactly the anim block's countdown_ring effect.
static func _arc_mesh(r_in: float, r_out: float, segments: int = 72) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := _arc_point(r_in, a0)
		var p1 := _arc_point(r_out, a0)
		var p2 := _arc_point(r_in, a1)
		var p3 := _arc_point(r_out, a1)
		st.set_uv(Vector2(a0 / TAU, 0.0))
		st.add_vertex(p0)
		st.set_uv(Vector2(a0 / TAU, 1.0))
		st.add_vertex(p1)
		st.set_uv(Vector2(a1 / TAU, 0.0))
		st.add_vertex(p2)
		st.set_uv(Vector2(a1 / TAU, 0.0))
		st.add_vertex(p2)
		st.set_uv(Vector2(a0 / TAU, 1.0))
		st.add_vertex(p1)
		st.set_uv(Vector2(a1 / TAU, 1.0))
		st.add_vertex(p3)
	return st.commit()


static func _arc_point(r: float, a: float) -> Vector3:
	var phi := PI / 2.0 - a   # clockwise from the top
	return Vector3(cos(phi) * r, sin(phi) * r, 0.0)


static func _arc_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.16, 0.16, 1.0);
uniform float fill = 1.0;
void fragment() {
\tif (UV.x > fill) {
\t\tdiscard;
\t}
\tALBEDO = tint.rgb;
}"""
	return shader


func _build_arcs() -> void:
	_countdown_mat = ShaderMaterial.new()
	_countdown_mat.shader = _arc_shader()
	_countdown_mat.set_shader_parameter("tint", Color(1.0, 0.165, 0.165, 1.0))   # #FF2A2A
	_countdown_mat.set_shader_parameter("fill", 1.0)
	_countdown_arc = MeshInstance3D.new()
	_countdown_arc.name = "CountdownArc"
	_countdown_arc.mesh = _arc_mesh(RING_INNER, RING_OUTER)
	_countdown_arc.material_override = _countdown_mat
	_countdown_arc.position = Vector3(0.0, RING_Y, 0.1)
	_countdown_arc.visible = false
	add_child(_countdown_arc)
	_stillness_mat = ShaderMaterial.new()
	_stillness_mat.shader = _arc_shader()
	_stillness_mat.set_shader_parameter("tint", Color(0.25, 1.0, 0.42, 1.0))    # green
	_stillness_mat.set_shader_parameter("fill", 0.0)
	_stillness_arc = MeshInstance3D.new()
	_stillness_arc.name = "StillnessArc"
	_stillness_arc.mesh = _arc_mesh(ARC_INNER, ARC_OUTER)
	_stillness_arc.material_override = _stillness_mat
	_stillness_arc.position = Vector3(0.0, RING_Y, 0.12)
	_stillness_arc.visible = false
	add_child(_stillness_arc)


func _build_flash() -> void:
	var layer := CanvasLayer.new()
	layer.name = "FlashLayer"
	layer.layer = 128
	add_child(layer)
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.color = Color(1.0, 1.0, 1.0, 1.0)
	_flash.anchor_right = 1.0
	_flash.anchor_bottom = 1.0
	_flash.visible = false
	layer.add_child(_flash)


# One frame of view. row is the sim row (read-only); dt is seconds elapsed.
# The caller places this node at the enemy's feet; the view never writes sim state.
func sync(row: Dictionary, dt: float, cam_pos: Vector3 = Vector3.ZERO) -> void:
	if billboard == null:
		return
	var state := str(row.get("anim_state", "recover"))
	var state_t := float(row.get("anim_state_t", 0))
	_on_state_entered(state)
	_drive_frames(state)
	_drive_effects(state, state_t, row)
	if cam_pos != Vector3.ZERO:
		billboard.face_camera(cam_pos)
		_face_camera_node(_countdown_arc, cam_pos)
		_face_camera_node(_stillness_arc, cam_pos)
	_drive_flash(state, state_t)
	_prev_state = state


func _on_state_entered(state: String) -> void:
	if state == _prev_state:
		return
	match state:
		"spawn":
			AddressMeAudio.play_cue(self, "spawn_trumpet")
		"telegraph":
			AddressMeAudio.play_cue(self, "rumble_build")
		"attack":
			AddressMeAudio.play_cue(self, "explode_boom")


func _face_camera_node(node: Node3D, cam_pos: Vector3) -> void:
	if node == null:
		return
	var bp := global_position if is_inside_tree() else position
	var dx: float = cam_pos.x - bp.x
	var dz: float = cam_pos.z - bp.z
	if absf(dx) < 1e-9 and absf(dz) < 1e-9:
		return
	node.rotation.y = atan2(dx, dz)


# Frames: normal (cycle_00) for everything except attack (cycle_01, held).
func _drive_frames(state: String) -> void:
	var want_frame := 1 if state == "attack" else 0
	if billboard.frame_i != want_frame:
		billboard.frame_i = want_frame
		billboard._apply_frame(want_frame)
	# the billboard advances its own fps by wall clock in _process; keep the sheet's
	# static frames stable by re-holding the wanted frame each sync


func _drive_effects(state: String, state_t: float, row: Dictionary) -> void:
	var countdown_left := float(row.get("countdown_left", 0))
	var still_t := float(row.get("still_t", 0))
	var visible_body := state != "recover"
	billboard.visible = visible_body
	if _countdown_arc != null:
		_countdown_arc.visible = state == "telegraph"
	if _stillness_arc != null:
		_stillness_arc.visible = state == "telegraph"
	if not visible_body:
		_sprite_wrap.scale = Vector3.ONE
		_sprite_wrap.position = Vector3.ZERO
		billboard.modulate = Color(1.0, 1.0, 1.0, 1.0)
		return
	match state:
		"spawn":
			var k := clampf(state_t / SPAWN_TICKS, 0.15, 1.0)
			billboard.modulate = Color(k, k, k, 1.0)
			_sprite_wrap.scale = Vector3.ONE
			_sprite_wrap.position = Vector3.ZERO
		"telegraph":
			var t := clampf(state_t, 0.0, COUNTDOWN_TICKS)
			if t >= TINT_RED_AT:
				billboard.modulate = Color(1.0, 0.38, 0.32, 1.0)
			elif t >= TINT_AMBER_AT:
				billboard.modulate = Color(1.0, 0.76, 0.35, 1.0)
			else:
				billboard.modulate = Color(1.0, 1.0, 1.0, 1.0)
			var k2 := t / COUNTDOWN_TICKS
			var tremolo := sin(state_t * 0.32 * (1.0 + 5.0 * k2))
			_sprite_wrap.position = Vector3(tremolo * _shake_u * (0.3 + 0.7 * k2), 0.0, 0.0)
			_sprite_wrap.scale = Vector3.ONE
			if _countdown_mat != null:
				_countdown_mat.set_shader_parameter("fill", clampf(countdown_left / COUNTDOWN_TICKS, 0.0, 1.0))
			if _stillness_mat != null:
				_stillness_mat.set_shader_parameter("fill", clampf(still_t / STILL_TICKS, 0.0, 1.0))
		"leaves":
			var k3 := clampf(1.0 - state_t / LEAVES_TICKS, 0.0, 1.0)
			_sprite_wrap.scale = Vector3(k3, k3, k3)
			_sprite_wrap.position = Vector3.ZERO
			billboard.modulate = Color(1.0, 1.0, 1.0, 1.0)
		"attack":
			_sprite_wrap.scale = Vector3.ONE
			_sprite_wrap.position = Vector3.ZERO
			billboard.modulate = Color(1.0, 1.0, 1.0, 1.0)
		"recover":
			billboard.visible = false


func _drive_flash(state: String, state_t: float) -> void:
	if _flash == null:
		return
	_flash.visible = state == "attack" and state_t < ATTACK_FLASH_TICKS
