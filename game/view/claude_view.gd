extends Node3D
#
# claude view (ticket T-040; ENEMIES.md "Cadence -> Claude", DESIGN.md section 5.11,
# the T-083 anim block in content/enemies/claude/sprites.json - read, never re-declared).
#
# View layer only: it READS the behavior's row dictionary and never writes sim state.
# The sim row carries everything this view speaks with:
#   "anim_state"        - one of the anim block state keys (spawn / idle /
#                         telegraph_drums / attack_drums / telegraph_strings /
#                         attack_strings / attack_wind / deadline)
#   "anim_state_t"      - ticks spent in the state
#   "beat_pos"          - float beats since the music started (the metronome reads it)
#   "agitation"         - 0..100; >= 100 draws the deadline's red tint
#   "rings"             - live drum rings {"x", "y", "z", "r"} each
#   "sweeps"            - live beams {"ox","oy","oz","dx","dz","deg"}
#   "shots"             - live wind shots {"x","y","z","dx","dy","dz","life"}
#   "plushies"          - clawd Crab stand-ins {"x","y","z","born"}
#   "str_dx" / "str_dz" - the frozen sweep direction (the telegraph line's angle)
#   "str_tel_left"      - ticks left of the 1-beat strings telegraph
#   "last_*_tick"       - the audio triggers (drum / sweep / shot / pickup)
#
# Frames and per-state effects come through game/view/enemy_anim.gd (T-084's shared
# player): this node duck-types its view contract (set_stage / set_stage_frame /
# set_effect / set_texture) and applies the uniform contract {flash, tint, scale_pulse,
# shake, alpha} to a sprite wrap. The anim block's frame lists are the per-state textures:
# the eight logo states show their own distinct real frame (spawn_00, telegraph_drums_00,
# attack_drums_00, telegraph_strings_00, attack_strings_00, attack_wind_00, deadline_00,
# idle = idle_00), swapped here on set_stage / set_stage_frame. The plushie_idle row's
# 3-frame loop (6 fps, 10 ticks per frame) is rendered on the PLUSHIE billboards - the body
# only ever shows idle_00 (sprites/idle_00.png, the real Claude logo).
#
# BILLBOARDING / TRANSPARENCY: the sprite always faces the camera (billboard.gd's
# Y-rotation face_camera); the alpha scissor discards the transparent padding.

const BillboardScript := preload("res://view/billboard.gd")
const EnemyAnimScript := preload("res://view/enemy_anim.gd")
const ClaudeAudio := preload("res://view/audio/claude_audio.gd")

const SHEET_REL := "res://content/enemies/claude/sprites.json"
const FOLDER_REL := "res://content/enemies/claude"
const RED := Color(1.0, 0.164706, 0.164706)   # #FF2A2A, the game's hazard red
const BAND_SEGMENTS := 32
const BAND_ALPHA := 0.35
const METRONOME_DEG_PER_BEAT := 15.0          # the anim block's idle effect
const METRONOME_PULSE := 0.06                 # scale pulse 1.0 -> 1.06 per beat
const SHOT_RADIUS := 0.25                     # the 0.5 u notification dot
const PLUSHIE_TICKS_PER_FRAME := 10.0         # 6 fps (the plushie_idle row)
const PLUSHIE_BOB_U := 0.1
const PLUSHIE_POP_TICKS := 9                  # collected pop
const PLUSHIE_SCALE := 0.6                    # the plushie stand-in's body height (u)

var billboard = null                  # the body's Sprite3D (billboard.gd)
var anim_player = null                # the T-084 shared animation player
var _state_texs: Dictionary = {}      # state id -> [Texture2D] (the anim block's frames)
var _wrap: Node3D = null              # metronome rotation / shake / pulse live here
var _bands: Array = []                # drum ring bands ([MeshInstance3D])
var _band_mats: Array = []
var _strings_line: MeshInstance3D = null
var _strings_mat: StandardMaterial3D = null
var _beams: Array = []                # sweep beams
var _beam_mats: Array = []
var _shot_root: Node3D = null
var _shot_mat: StandardMaterial3D = null
var _plushie_root: Node3D = null
var _plushie_texs: Array = []
var _last_drum := -1
var _last_sweep := -1
var _last_shot := -1
var _last_pickup := -1
var _state := ""


## Parses sprites.json, builds the billboarded body (2.0 u tall, feet at the origin)
## and binds the T-084 animation player. folder_dir is the enemy folder's res:// path.
func setup(sheet_path: String = SHEET_REL, folder: String = FOLDER_REL) -> void:
	for child in get_children():
		child.free()
	var doc: Dictionary = {}
	if FileAccess.file_exists(sheet_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(sheet_path))
		if parsed is Dictionary:
			doc = parsed
	_wrap = Node3D.new()
	_wrap.name = "SpriteWrap"
	add_child(_wrap)
	billboard = BillboardScript.new()
	_wrap.add_child(billboard)
	if not doc.is_empty():
		billboard.setup_from_sheet(doc, folder)
	anim_player = EnemyAnimScript.new()
	anim_player.setup("claude", doc, folder)
	anim_player.bind_view(self)
	_cache_state_frames(folder)
	_build_bands()
	_build_strings_line()
	_build_beams()
	_build_shots()
	_build_plushies(folder)


## --- the enemy_anim.gd view contract (duck-typed; never stores sim state) ---------


func set_stage(state_id: String) -> void:
	_state = state_id
	_apply_state_texture(state_id, 0)


func set_stage_frame(frame_i: int) -> void:
	_apply_state_texture(_state, frame_i)


## Loads the anim block's per-state frames once (folder is the enemy folder's res:// path).
func _cache_state_frames(folder: String) -> void:
	_state_texs.clear()
	var states: Dictionary = (anim_player.doc as Dictionary).get("anim", {}).get("states", {})
	for state_id in states.keys():
		var texs: Array = []
		for p in states[state_id].get("frames", []):
			var full := (folder + "/") + str(p)
			texs.append(load(full) if ResourceLoader.exists(full) else null)
		_state_texs[state_id] = texs


## Points the billboard at the state's frame_i texture (keeps the current texture when the
## file is missing/unimportable - the billboard never blanks out).
func _apply_state_texture(state_id: String, frame_i: int) -> void:
	var texs: Array = _state_texs.get(state_id, [])
	if texs.is_empty() or billboard == null:
		return
	var t = texs[clampi(frame_i, 0, texs.size() - 1)]
	if t != null:
		billboard.texture = t


func set_effect(k: String, v) -> void:
	if k == "alpha":
		var c: Color = billboard.modulate
		c.a = float(v)
		billboard.modulate = c
	elif k == "tint":
		billboard.modulate = v
	elif k == "scale_pulse":
		var s: float = float(v)
		_wrap.scale = Vector3(s, s, s)
	elif k == "shake":
		if v is Vector2:
			_wrap.position = Vector3(v.x, 0.0, v.y)
	elif k == "flash":
		var f: float = clampf(v.a if v is Color else float(v), 0.0, 1.0)
		var c2: Color = billboard.modulate
		billboard.modulate = Color(lerpf(c2.r, 1.0, f), lerpf(c2.g, 1.0, f), lerpf(c2.b, 1.0, f), c2.a)


func set_texture(tex) -> void:
	billboard.texture = tex


## --- builders ---------------------------------------------------------------------


func _band_material(alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(RED.r, RED.g, RED.b, alpha)
	m.emission_enabled = true
	m.emission = RED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_fog = true
	return m


# Open cylinder, unit radius, y in [0, height] - only the side wall (the band).
static func _open_cylinder(segments: int, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := Vector3(cos(a0), 0.0, sin(a0))
		var p1 := Vector3(cos(a1), 0.0, sin(a1))
		var p2 := Vector3(cos(a0), height, sin(a0))
		var p3 := Vector3(cos(a1), height, sin(a1))
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p2)
		st.add_vertex(p1)
		st.add_vertex(p3)
	return st.commit()


func _build_bands() -> void:
	for i in range(2):   # a drums bar can hold two rings at once (72 ticks apart, 90 live)
		var band := MeshInstance3D.new()
		band.mesh = _open_cylinder(BAND_SEGMENTS, 1.0)
		var m := _band_material(BAND_ALPHA)
		band.material_override = m
		band.visible = false
		add_child(band)
		_bands.append(band)
		_band_mats.append(m)


func _build_strings_line() -> void:
	_strings_line = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.06, 0.06)
	_strings_line.mesh = box
	_strings_mat = _band_material(0.8)
	_strings_line.material_override = _strings_mat
	_strings_line.visible = false
	add_child(_strings_line)


func _build_beams() -> void:
	for i in range(2):   # Deadline chains sweeps; two can overlap
		var beam := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(24.0, 1.0, 1.5)   # length x height band x width
		beam.mesh = box
		var m := _band_material(0.5)
		beam.material_override = m
		beam.visible = false
		add_child(beam)
		_beams.append(beam)
		_beam_mats.append(m)


func _build_shots() -> void:
	_shot_root = Node3D.new()
	_shot_root.name = "Shots"
	add_child(_shot_root)
	_shot_mat = StandardMaterial3D.new()
	_shot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shot_mat.albedo_color = Color(1, 1, 1)
	_shot_mat.emission_enabled = true
	_shot_mat.emission = Color(1, 1, 1)
	_shot_mat.disable_fog = true


func _build_plushies(folder: String) -> void:
	_plushie_root = Node3D.new()
	_plushie_root.name = "Plushies"
	add_child(_plushie_root)
	# the plushie_idle row's 3 frames (the only 3-frame set in the sheet; the clawd Crab
	# plushie sprite was never fetched - TBD.md row 26 - so the TBD magenta plushie_00..02
	# placeholders stand in)
	var states: Dictionary = (anim_player.doc as Dictionary).get("anim", {}).get("states", {})
	var paths: Array = (states.get("plushie_idle", {}) as Dictionary).get("frames", [])
	for p in paths:
		var full := (folder + "/") + str(p)
		_plushie_texs.append(load(full) if ResourceLoader.exists(full) else null)


## --- one frame of view -------------------------------------------------------------

## row is the sim row (read-only); dt is seconds elapsed; cam_pos points the billboard.
## The caller places this node at the enemy's FEET.
func sync(row: Dictionary, dt: float, cam_pos: Vector3 = Vector3.ZERO) -> void:
	if billboard == null:
		return
	var ticks := maxi(int(round(dt * 60.0)), 1)
	_sync_state(row,ticks)
	_sync_metronome(row)
	_sync_bands(row)
	_sync_strings(row)
	_sync_beams(row)
	_sync_shots(row)
	_sync_plushies(row)
	_sync_audio(row)
	if cam_pos != Vector3.ZERO:
		billboard.face_camera(cam_pos)


func _sync_state(row: Dictionary, ticks: int) -> void:
	var state := str(row.get("anim_state", "idle"))
	if state != _state or anim_player.state_id != state:
		_state = state
		anim_player.on_state_changed(state)
	for _i in range(ticks):
		anim_player.sim_tick()


## The idle metronome: the logo rotates 15 deg per beat IN STEPS and pulses 1.0 -> 1.06
## on every beat (the anim block's idle effect; beat = row["beat_pos"], sim-driven).
func _sync_metronome(row: Dictionary) -> void:
	var beat_pos := float(row.get("beat_pos", 0.0))
	var beat := floorf(beat_pos)
	var frac: float = beat_pos - beat
	_wrap.rotation.y = beat * METRONOME_DEG_PER_BEAT * 0.017453292519943295
	var s := 1.0
	if str(row.get("anim_state", "")) == "idle" or str(row.get("anim_state", "")) == "deadline":
		s = 1.0 + METRONOME_PULSE * (1.0 - frac)
	# the deadline's red face: agitation 100 tints the logo until a plushie is collected
	if float(row.get("agitation", 0.0)) >= 100.0:
		var c: Color = billboard.modulate
		billboard.modulate = Color(lerpf(c.r, 1.0, 0.45), c.g * 0.4, c.b * 0.4, c.a)
	_wrap.scale = _wrap.scale * s


func _sync_bands(row: Dictionary) -> void:
	var rings: Array = row.get("rings", [])
	for i in range(_bands.size()):
		var band: MeshInstance3D = _bands[i]
		if i >= rings.size():
			band.visible = false
			continue
		var ring: Dictionary = rings[i]
		var r: float = maxf(float(ring.get("r", 0.0)), 0.05)
		band.visible = true
		band.scale = Vector3(r, 1.0, r)
		band.position = Vector3(float(ring.get("x", 0.0)) - position.x,
				float(ring.get("y", 0.0)) - position.y,
				float(ring.get("z", 0.0)) - position.z)


## The 1-beat strings telegraph: the red 24 u line at the sweep's starting angle.
func _sync_strings(row: Dictionary) -> void:
	if _strings_line == null:
		return
	var left := int(row.get("str_tel_left", 0))
	var active := str(row.get("anim_state", "")) == "telegraph_strings" and left > 0
	if not active:
		_strings_line.visible = false
		return
	var dx := float(row.get("str_dx", 0.0))
	var dz := float(row.get("str_dz", 1.0))
	var mid := float(row.get("y", 0.0)) + 1.0   # the 0.5-1.5 u band's mid-height
	_strings_line.visible = true
	_strings_line.scale = Vector3(24.0, 1.0, 1.0)
	_strings_line.position = Vector3(float(row.get("x", 0.0)) + dx * 12.0 - position.x,
			mid - position.y,
			float(row.get("z", 0.0)) + dz * 12.0 - position.z)
	_strings_line.rotation.y = atan2(dx, dz)


## The sweeping beams: one stretched box per live sweep, X along the frozen-origin ray.
func _sync_beams(row: Dictionary) -> void:
	var sweeps: Array = row.get("sweeps", [])
	for i in range(_beams.size()):
		var beam: MeshInstance3D = _beams[i]
		if i >= sweeps.size():
			beam.visible = false
			continue
		var s: Dictionary = sweeps[i]
		var dx := float(s.get("dx", 1.0))
		var dz := float(s.get("dz", 0.0))
		beam.visible = true
		beam.position = Vector3(float(s.get("ox", 0.0)) + dx * 12.0 - position.x,
				float(s.get("oy", 0.0)) + 1.0 - position.y,
				float(s.get("oz", 0.0)) + dz * 12.0 - position.z)
		beam.rotation.y = atan2(dx, dz)


## The wind shots: a white 0.5 u dot with a red rim and a short trail, one mesh per shot
## (rebuilt each sync - a bar holds at most ~8 live shots at 240-tick lives).
func _sync_shots(row: Dictionary) -> void:
	if _shot_root == null:
		return
	for c in _shot_root.get_children():
		c.free()
	var shots: Array = row.get("shots", [])
	for s in shots:
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = SHOT_RADIUS
		sphere.height = SHOT_RADIUS * 2.0
		mi.mesh = sphere
		mi.material_override = _shot_mat
		mi.position = Vector3(float(s.get("x", 0.0)) - position.x,
				float(s.get("y", 0.0)) - position.y,
				float(s.get("z", 0.0)) - position.z)
		_shot_root.add_child(mi)
		# the trail: a short stretched box behind the shot, along its velocity
		var trail := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.1, 0.1, 0.6)
		trail.mesh = box
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.albedo_color = Color(RED.r, RED.g, RED.b, 0.4)
		tm.disable_fog = true
		trail.material_override = tm
		var d := Vector3(float(s.get("dx", 0.0)), float(s.get("dy", 0.0)), float(s.get("dz", 1.0)))
		trail.position = mi.position - d * 0.4
		trail.look_at_from_position(trail.position, mi.position)
		_shot_root.add_child(trail)


## The clawd Crab plushies (TBD stand-in frames), pending a 9-tick pop at the last
## pickup: bobbing +-0.1 u, soft white glow, 6 fps / 10 ticks per frame, sim-driven.
func _sync_plushies(row: Dictionary) -> void:
	if _plushie_root == null:
		return
	for c in _plushie_root.get_children():
		c.free()
	var age := int(row.get("age", 0))
	var t := float(age) / 60.0
	var pop_age := -1
	if row.get("last_pickup_tick", -1) is int and int(row.get("last_pickup_tick", -1)) >= 0:
		pop_age = age - int(row.get("last_pickup_tick", -1))
	for p in row.get("plushies", []):
		var born := int(p.get("born", 0))
		var frame := int(float(age - born) / PLUSHIE_TICKS_PER_FRAME) % maxi(_plushie_texs.size(), 1)
		var spr := Sprite3D.new()
		if frame < _plushie_texs.size() and _plushie_texs[frame] != null:
			spr.texture = _plushie_texs[frame]
		spr.pixel_size = 0.01
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.alpha_scissor_threshold = 0.5
		var bob: float = sin(t * TAU) * PLUSHIE_BOB_U
		spr.position = Vector3(float(p.get("x", 0.0)) - position.x,
				float(p.get("y", 0.0)) + PLUSHIE_SCALE * 0.5 + bob - position.y,
				float(p.get("z", 0.0)) - position.z)
		var s: float = PLUSHIE_SCALE / 2.0   # the 2.0 u logo frames shrink to the plushie
		spr.scale = Vector3(s, s, s)
		_plushie_root.add_child(spr)
	if pop_age >= 0 and pop_age <= PLUSHIE_POP_TICKS and row.has("last_pickup_pos"):
		var pp: Dictionary = row["last_pickup_pos"]
		var pop := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		var k := float(pop_age) / float(PLUSHIE_POP_TICKS)
		sphere.radius = 0.2 + 0.5 * k
		sphere.height = sphere.radius * 2.0
		pop.mesh = sphere
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.albedo_color = Color(1, 1, 1, 1.0 - k)
		pm.disable_fog = true
		pop.material_override = pm
		pop.position = Vector3(float(pp.get("x", 0.0)) - position.x,
				float(pp.get("y", 0.0)) + 0.5 - position.y,
				float(pp.get("z", 0.0)) - position.z)
		_plushie_root.add_child(pop)


## The audio triggers: one shot per sim event, read off the row's tick stamps.
func _sync_audio(row: Dictionary) -> void:
	if int(row.get("last_drum_tick", -1)) != _last_drum:
		_last_drum = int(row.get("last_drum_tick", -1))
		if _last_drum >= 0:
			ClaudeAudio.play(self, ClaudeAudio.CUE_UI_CHIME, 1.0)
	if int(row.get("last_sweep_tick", -1)) != _last_sweep:
		_last_sweep = int(row.get("last_sweep_tick", -1))
		if _last_sweep >= 0:
			ClaudeAudio.play(self, ClaudeAudio.CUE_KEYSTROKE_TICK, 0.9)
	if int(row.get("last_shot_tick", -1)) != _last_shot:
		_last_shot = int(row.get("last_shot_tick", -1))
		if _last_shot >= 0:
			ClaudeAudio.play(self, ClaudeAudio.CUE_NOTIFICATION_PING, 0.8)
	if int(row.get("last_pickup_tick", -1)) != _last_pickup:
		_last_pickup = int(row.get("last_pickup_tick", -1))
		if _last_pickup >= 0:
			ClaudeAudio.play(self, ClaudeAudio.CUE_SQUEAK_POP, 1.0)
