extends Node3D
#
# claude view - the CYCLE 7 REVAMP (track T4; D-T4-1, D-T4-8).
#
# The owner's words (CYCLE7_BRIEF.md T4): "Claude does NOTHING by himself: no attack, no movement." So this view
# is the BODY and nothing else: the billboarded logo, the spawn fade, the idle metronome, and the anger tint.
# The old kit's rings, beams, wind shots and plushie billboards are gone with the attacks they drew; the clawd
# swarm has its own level-wide node (view/clawd_view.gd) because it is not one body's property.
#
# View layer only: it READS the behavior's row dictionary and never writes sim state. The row carries:
#   "anim_state"    - "spawn" or "idle" (the only two states the revamped behavior emits; the sheet's other
#                     seven states stay as dormant art data, D-T4-1)
#   "anim_state_t"  - ticks spent in the state
#   "age"           - ticks since the spawn
# The anger timer is NOT on the row (it lives in sim/clawds.gd, D-T4-2); the caller feeds it through
# set_anger(), and the warning cues are played from the sim's clawd_warning event through on_warning().
#
# Frames and per-state effects come through game/view/enemy_anim.gd (T-084's shared player): this node
# duck-types its view contract (set_stage / set_stage_frame / set_effect / set_texture) and applies the uniform
# contract {flash, tint, scale_pulse, shake, alpha} to a sprite wrap.
#
# BILLBOARDING / TRANSPARENCY: the sprite always faces the camera (billboard.gd's Y-rotation face_camera); the
# alpha scissor discards the transparent padding.

const BillboardScript := preload("res://view/billboard.gd")
const EnemyAnimScript := preload("res://view/enemy_anim.gd")
const ClaudeAudio := preload("res://view/audio/claude_audio.gd")

const SHEET_REL := "res://content/enemies/claude/sprites.json"
const FOLDER_REL := "res://content/enemies/claude"
const RED := Color(1.0, 0.164706, 0.164706)   # #FF2A2A, the game's hazard red
const METRONOME_DEG_PER_BEAT := 15.0          # the anim block's idle effect
const METRONOME_PULSE := 0.06                 # scale pulse 1.0 -> 1.06 per beat
const BEAT_TICKS := 36                        # 100 BPM at 60 Hz: the idle metronome's own cosmetic beat
const WARNING_FLASH_TICKS := 30               # the red flash a warning leaves on the logo

var billboard = null                  # the body's Sprite3D (billboard.gd)
var anim_player = null                # the T-084 shared animation player
var _state_texs: Dictionary = {}      # state id -> [Texture2D] (the anim block's frames)
var _wrap: Node3D = null              # metronome rotation / shake / pulse live here
var _state := ""
var _anger := 0.0                     # 0..1, the caller's anger fraction (sim/clawds.gd)
var _flash := 0                     # ticks left of the warning flash
var _last_warned := 0


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
	_anger = 0.0
	_flash = 0
	_last_warned = 0


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


## --- the anger feed (D-T4-8) ------------------------------------------------------


## The caller's anger fraction 0..1 (sim/clawds.gd anger_ticks / kill_ticks). The logo reddens with it.
func set_anger(fraction: float) -> void:
	_anger = clampf(fraction, 0.0, 1.0)


## A warning fired this tick (the sim's clawd_warning event): flash the logo and play the cue.
func on_warning(level: int) -> void:
	_flash = WARNING_FLASH_TICKS
	_last_warned = level
	ClaudeAudio.play(self, ClaudeAudio.cue_for_level(level), 1.0)


## --- one frame of view -------------------------------------------------------------

## row is the sim row (read-only); dt is seconds elapsed; cam_pos points the billboard.
## The caller places this node at the enemy's FEET.
func sync(row: Dictionary, dt: float, cam_pos: Vector3 = Vector3.ZERO) -> void:
	if billboard == null:
		return
	var ticks := maxi(int(round(dt * 60.0)), 1)
	_sync_state(row, ticks)
	_sync_metronome(row)
	_sync_anger()
	if cam_pos != Vector3.ZERO:
		billboard.face_camera(cam_pos)


func _sync_state(row: Dictionary, ticks: int) -> void:
	var state := str(row.get("anim_state", "idle"))
	if state != _state or anim_player.state_id != state:
		_state = state
		anim_player.on_state_changed(state)
	for _i in range(ticks):
		anim_player.sim_tick()


## The idle metronome: the logo rotates 15 deg per beat IN STEPS and pulses 1.0 -> 1.06 on every beat. The beat
## is the view's own cosmetic clock (the behavior has no music any more, D-T4-1): 36 ticks at 60 Hz, driven by
## the row's age so it stays sim-derived and never reads a wall clock.
func _sync_metronome(row: Dictionary) -> void:
	var beat_pos := float(int(row.get("age", 0))) / float(BEAT_TICKS)
	var beat := floorf(beat_pos)
	var frac: float = beat_pos - beat
	_wrap.rotation.y = beat * METRONOME_DEG_PER_BEAT * 0.017453292519943295
	var s := 1.0
	if str(row.get("anim_state", "")) == "idle":
		s = 1.0 + METRONOME_PULSE * (1.0 - frac)
	_wrap.scale = _wrap.scale * s


## The anger tint: the logo reddens toward the kill, and a warning leaves a 30-tick flash on top.
func _sync_anger() -> void:
	var k := _anger
	if _flash > 0:
		_flash -= 1
		k = maxf(k, 0.75)
	if k <= 0.0:
		return
	var c: Color = billboard.modulate
	billboard.modulate = Color(lerpf(c.r, RED.r, k * 0.45), lerpf(c.g, RED.g, k * 0.6),
			lerpf(c.b, RED.b, k * 0.6), c.a)
