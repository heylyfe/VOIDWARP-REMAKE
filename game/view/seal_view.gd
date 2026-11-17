extends Node3D
#
# seal view (ticket T-038; ENEMIES.md hard rules; DESIGN.md section 5.9; the T-083 anim
# block in sprites.json). View layer only: reads sim EVENTS (the enemy_spawn / dash_line /
# bark telegraph ticks), never writes sim state; every effect is driven by the sim tick
# counter the caller passes to step(), never by a wall clock.
#
# Wired to the anim block (sprites.json -> anim). Frames are REAL art derived procedurally
# from babehseal.webp by game/tools/art/seal.gd (D-ART-SEAL-1, 2026-11-17):
#   spawn     30-tick fade: alpha 0 -> 1, scale 0.8 -> 1.0 (spawn_blocks_contact_ticks = 30)
#   idle_flap idle_00 <-> idle_01 at the table's 9 ticks per frame (seal_02/03)
#   telegraph "dash_line": the mouth-open frame held (telegraph_00 = spec seal_01) for
#             45 ticks and the dashed red 3D line (#FF2A2A, dash_segment_u 0.5) drawn along
#             the fixed dash line, brightening across the 45 ticks; flipper-flap audio at
#             the block's flap_audio_hz (6.6 Hz, i.e. every 9 ticks)
#   attack    dash_00 held (spec seal_01 mouth-open, lunged pose); the bark plays on tick 0
#   recover   recover_00 held for 45 ticks
# Frames are real art derived from babehseal.webp (game/tools/art/seal.gd, D-ART-SEAL-1);
# the anim block in sprites.json is the frame source of truth.

const BillboardScript := preload("res://view/billboard.gd")
const SealAudio := preload("res://view/audio/seal_audio.gd")

const SEG_U := 0.5                  # dash_segment_u (anim block telegraph effect params)
const GAP_U := 0.4                  # the gap between dashes (draw contract, D-T-038-6)
const SEG_THICK := 0.08             # u, the dash cross-section

var billboard: Sprite3D = null
var anim: Dictionary = {}
var world_height := 0.6

var _base_scale := Vector3.ONE
var _spawn_left := 0
var _spawn_total := 30
var _state := "idle"                # idle | telegraph | attack | recover
var _state_left := 0                # ticks remaining in telegraph/attack/recover
var _attack_frame_ticks := 0
var _attack_ticks_per_frame := 4.0
var _attack_frame := 0
var _flap_audio_left := 0           # ticks until the next flipper-flap cue
var _flap_audio_period := 9         # 9 ticks per frame = 6.6 Hz (anim block)
var _line_root: Node3D = null
var _line_mat: StandardMaterial3D = null
var _line_total := 45               # telegraph brightening span (ticks)


## Parses sprites.json, builds the billboarded PNG sprite (body = world_height u tall, feet
## on the origin, BILLBOARDING + TRANSPARENCY rules live in billboard.gd) and caches the
## anim-block parameters. folder_dir is the enemy folder's res:// path.
func setup(folder_dir: String = "res://content/enemies/seal") -> void:
	var text := FileAccess.get_file_as_string(folder_dir.path_join("sprites.json"))
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		push_warning("seal_view: sprites.json unreadable at %s" % folder_dir)
		doc = {}
	anim = (doc as Dictionary).get("anim", {})
	var states: Dictionary = (anim.get("states", {}))
	world_height = float((doc as Dictionary).get("world_height", 0.6))
	_spawn_total = int((states.get("spawn", {})).get("total_ticks", 30))
	_line_total = int((states.get("telegraph", {})).get("total_ticks", 45))
	_attack_ticks_per_frame = float((states.get("attack", {})).get("ticks_per_frame", 4.0))
	_attack_textures = _load_frames(folder_dir, (states.get("attack", {})).get("frames", []))
	_spawn_tex = _load_frames(folder_dir, (states.get("idle_flap", {})).get("frames", ["sprites/idle_00.png"]))
	_telegraph_tex = _load_frames(folder_dir, (states.get("telegraph", {})).get("frames", ["sprites/telegraph_00.png"]))
	_recover_tex = _load_frames(folder_dir, (states.get("recover", {})).get("frames", ["sprites/recover_00.png"]))
	billboard = BillboardScript.new()
	add_child(billboard)
	billboard.setup_from_sheet(doc, folder_dir)
	billboard.world_height = world_height
	_base_scale = billboard.scale


var _attack_textures: Array = []   # attack frames (dash_00), loaded from the block
var _spawn_tex: Array = []          # idle frames (idle_00 base held)
var _telegraph_tex: Array = []      # telegraph frames (telegraph_00 = spec seal_01 mouth open)
var _recover_tex: Array = []        # recover frames (recover_00, the stretched seal_00)


func _load_frames(folder_dir: String, frames: Array) -> Array:
	var out: Array = []
	for f in frames:
		var full := folder_dir.path_join(str(f))
		out.append(load(full) if ResourceLoader.exists(full) else null)
	return out


## The spawn fade restarts (the sim's enemy_spawn event for this enemy).
func on_spawn() -> void:
	_spawn_left = _spawn_total


## A sim telegraph event for this enemy. "dash_line": fix and draw the red dashed 3D line
## from the event's dash_line parameter ([x0,y0,z0, x1,y1,z1]) and enter the 45-tick
## telegraph (mouth-open frame held). "bark": the dash begins - drop the line, enter the
## 60-tick attack (flap overlay at ticks_per_frame) and play the bark audio cue.
func on_telegraph(kind: String, ticks: int = -1, shape: Dictionary = {}) -> void:
	match kind:
		"dash_line":
			_state = "telegraph"
			_state_left = ticks if ticks > 0 else _line_total
			_start_line(shape.get("dash_line", []))
			# telegraph holds the mouth-open frame (telegraph_00 = spec seal_01)
			_hold_first_frame()
		"bark":
			_state = "attack"
			_state_left = int((((anim.get("states", {})).get("attack", {})).get("total_ticks", 60)))
			_attack_frame = 0
			_attack_frame_ticks = 0
			_clear_line()
			SealAudio.play(self, SealAudio.CUE_BARK, 1.0)
			_apply_attack_frame()


## One sim tick of view state: spawn fade, state timers, flipper-flap cadence, the line's
## brightening. dt_ticks is the sim tick count (1 at 60 Hz) - the caller drives this from
## the sim, not from _process.
func step(dt_ticks: int = 1) -> void:
	if billboard == null:
		return
	var step_ticks := maxi(dt_ticks, 1)
	# flipper-flap audio cadence (9 ticks per frame, 6.6 Hz) while flapping or telegraphing
	if _state == "idle" or _state == "telegraph":
		_flap_audio_left -= step_ticks
		if _flap_audio_left <= 0:
			SealAudio.play(self, SealAudio.CUE_FLIPPER_FLAP, 0.8)
			_flap_audio_left = _flap_audio_period
	# state timers
	match _state:
		"telegraph":
			_state_left = maxi(_state_left - step_ticks, 0)
			_brighten_line(_state_left)
			if _state_left == 0:
				_state = "attack"   # no bark event arrived (view-only fallback)
				_state_left = 60
				_attack_frame = 0
				_attack_frame_ticks = 0
				_clear_line()
				SealAudio.play(self, SealAudio.CUE_BARK, 1.0)
		"attack":
			_state_left = maxi(_state_left - step_ticks, 0)
			_attack_frame_ticks += step_ticks
			var frame := int(float(_attack_frame_ticks) / _attack_ticks_per_frame)
			if frame != _attack_frame:
				_attack_frame = frame
				_apply_attack_frame()
			if _state_left == 0:
				_state = "recover"
				_state_left = int((((anim.get("states", {})).get("recover", {})).get("total_ticks", 45)))
				_hold_first_frame()
		"recover":
			_state_left = maxi(_state_left - step_ticks, 0)
			if _state_left == 0:
				_state = "idle"
	# spawn fade: alpha 0 -> 1, scale 0.8 -> 1.0 over the first _spawn_total ticks
	var fade := 1.0
	var scale_mul := 1.0
	if _spawn_left > 0:
		_spawn_left = maxi(_spawn_left - step_ticks, 0)
		var done := 1.0 - float(_spawn_left) / float(maxi(_spawn_total, 1))
		fade = done
		scale_mul = 0.8 + 0.2 * done
	billboard.modulate = Color(1.0, 1.0, 1.0, fade)
	billboard.scale = _base_scale * scale_mul


func _apply_attack_frame() -> void:
	if _attack_textures.is_empty() or billboard == null:
		return
	billboard.texture = _attack_textures[_attack_frame % _attack_textures.size()]


func _hold_first_frame() -> void:
	if billboard == null:
		return
	var held := _spawn_tex
	if _state == "telegraph":
		held = _telegraph_tex
	elif _state == "recover":
		held = _recover_tex
	if held.is_empty() or held[0] == null:
		return
	billboard.texture = held[0]


## Builds the dashed red 3D telegraph line: dashes of SEG_U spaced GAP_U apart along the
## fixed 3D segment [dash_line[0..2] -> dash_line[3..5]], each a thin box aligned with the
## line (not flattened onto the ground - DESIGN.md section 5.9). One shared additive
## material; brightening runs by re-alphaing it in _brighten_line().
func _start_line(points: Array) -> void:
	_clear_line()
	if points.size() < 6:
		return
	var a := Vector3(float(points[0]), float(points[1]), float(points[2]))
	var b := Vector3(float(points[3]), float(points[4]), float(points[5]))
	var dir := b - a
	var seg_len := dir.length()
	if seg_len < 1e-6:
		return
	dir = dir.normalized()
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_line_mat.albedo_color = Color(1.0, 0.164706, 0.164706, 0.35)   # #FF2A2A @ 35%
	_line_mat.disable_fog = true
	_line_mat.disable_receive_shadows = true
	_line_mat.emission_enabled = true
	_line_mat.emission = Color(1.0, 0.164706, 0.164706)
	_line_root = Node3D.new()
	add_child(_line_root)
	# basis with X along the line (boxes are SEG_U long on X)
	var x_axis := dir
	var up := Vector3.UP
	if absf(x_axis.dot(up)) > 0.9:
		up = Vector3(1.0, 0.0, 0.0)
	var z_axis := x_axis.cross(up).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	var pitch := SEG_U + GAP_U
	var n := int(floor((seg_len - SEG_U) / pitch)) + 1
	for i in range(maxi(n, 0)):
		var off := float(i) * pitch + SEG_U * 0.5
		mi_new(_line_root, basis, a + dir * off, SEG_U).material_override = _line_mat


static func mi_new(parent: Node3D, basis: Basis, pos: Vector3, length_u: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length_u, SEG_THICK, SEG_THICK)
	mi.mesh = box
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	return mi


## Brightens the dashes across the telegraph: alpha 0.35 -> 0.95 over the ticks (DESIGN.md
## section 5.9 "brightening over the 45 ticks"; the anim block's brightens_over_ticks).
func _brighten_line(ticks_left: int) -> void:
	if _line_mat == null:
		return
	var total := float(maxi(_line_total, 1))
	var progress := clampf(1.0 - float(ticks_left) / total, 0.0, 1.0)
	var mat := _line_mat
	var c := mat.albedo_color
	c.a = 0.35 + 0.60 * progress
	mat.albedo_color = c


## Drops the dashes (dash started, or the view resets).
func _clear_line() -> void:
	if _line_root != null:
		_line_root.queue_free()
		_line_root = null
	_line_mat = null


