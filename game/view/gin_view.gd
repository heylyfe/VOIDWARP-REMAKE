extends Node3D
#
# gin ichimaru view (ticket T-041; ENEMIES.md "Voidbreaker -> gin ichimaru", DESIGN.md
# section 5.12, the T-083 anim block in content/enemies/gin/sprites.json - read here,
# never re-declared).
#
# View layer only: it READS the behavior's row dictionary and never writes sim state.
# The row carries everything this file speaks with:
#   "anim_state"   - one of the anim block state ids (spawn / telegraph / attack_launch /
#                    attack_void_zone / recover)
#   "anim_state_t" - ticks spent in the state
#   "patch"        - {cells, cx, cz}: the marked 5x5 (the sim declares it, the view draws it)
#
# Frames, per the anim block (read at setup, never re-derived from the PNGs):
#   spawn (30, gin_idle_00, fade 0 -> 1) -> telegraph (120, gin_idle_00 held, the
#   patch_mark effect: outline #FF2A2A blinking 2 Hz then 4 Hz, cracks reaching the
#   edge on tick 120) -> attack_launch (18, gin_launch_00, 5 white spear streaks,
#   view-layer only - never simulated) -> attack_void_zone (600, no frames: the tiles
#   vanish, a dark column with a red rim marks the lethal volume) -> recover (loop,
#   the tiles fade back over 30 ticks).
#
# BILLBOARDING / TRANSPARENCY hard rules: the sprite always faces the camera
# (billboard.gd, unchanged); the sprite shader discards alpha < 0.5; the arcs and
# ribbons are opaque-with-angle-discard, fog-exempt, unshaded.

const BillboardScript := preload("res://view/billboard.gd")
const AssetLoadScript := preload("res://view/asset_load.gd")   # U4: fail-soft loads (text/scene/texture/stream)
const GinAudio := preload("res://view/audio/gin_audio.gd")
const GinOverlay := preload("res://view/gin_overlay.gd")

const SHEET_REL := "res://content/enemies/gin/sprites.json"
const FOLDER_REL := "res://content/enemies/gin"

const TELEGRAPH_TICKS := 120.0    # the mark (binding, section 1.12)
const LAUNCH_TICKS := 18.0        # the spear flight (view-layer only)
const VOID_TICKS := 600.0         # the void zone (10 s)
const FADE_BACK_TICKS := 30.0     # the tiles fade back (0.5 s)

const STATE_SPAWN := "spawn"
const STATE_TELEGRAPH := "telegraph"
const STATE_LAUNCH := "attack_launch"
const STATE_VOID := "attack_void_zone"
const STATE_RECOVER := "recover"

var billboard = null              # BillboardScript instance (the PNG enemy)
var _anim_block: Dictionary = {}
var _prev_state := ""
var _zone_mat: ShaderMaterial = null
var _column: MeshInstance3D = null
var _overlay: CanvasLayer
var _sword: Sprite3D
var _second_sword: Sprite3D
var _last_voice_tick := -1


func setup(sheet_path: String = SHEET_REL, folder: String = FOLDER_REL) -> void:
	for child in get_children():
		child.free()
	var doc: Dictionary = {}
	var parsed = JSON.parse_string(AssetLoadScript.text(sheet_path))
	if parsed is Dictionary:
		doc = parsed
	_anim_block = doc.get("anim", {})
	billboard = BillboardScript.new()
	add_child(billboard)


## Reads the sim row (never writes it) and drives every sprite + VFX off it.
func update_from_row(row: Dictionary) -> void:
	var state := str(row.get("anim_state", STATE_RECOVER))
	if state == _prev_state:
		return
	_prev_state = state
	match state:
		STATE_TELEGRAPH:
			GinAudio.play_cue(self, "crack_rumble")
		STATE_LAUNCH:
			GinAudio.play_cue(self, "shing")
			GinAudio.play_cue(self, "whoosh")
		STATE_VOID:
			GinAudio.play_cue(self, "zone_open")
		STATE_RECOVER:
			GinAudio.play_cue(self, "zone_close")


## The anim block the view was set up with (the test asserts the view never
## re-derives a timing the block already carries).
func anim_block() -> Dictionary:
	return _anim_block


func update_sword_attack(row: Dictionary) -> void:
	if _overlay == null:
		billboard.hide()
		_overlay = GinOverlay.new()
		add_child(_overlay)
		_sword = _make_sword()
		_second_sword = _make_sword()
	var phase := str(row["phase"])
	_overlay.present(phase, row)
	_sync_sword(_sword, "gin_sword_pos", row, phase)
	_sync_sword(_second_sword, "gin_second_pos", row, phase)
	var voice_tick := int(row.get("gin_voice_tick", -1))
	if phase == "voice" and voice_tick != _last_voice_tick:
		_last_voice_tick = voice_tick
		_overlay.play_voice()


func _make_sword() -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _overlay.sword_texture
	sprite.rotation.x = -PI / 2.0
	if sprite.texture != null:
		sprite.pixel_size = 1.0 / float(sprite.texture.get_width())
	add_child(sprite)
	return sprite


func _sync_sword(sprite: Sprite3D, key: String, row: Dictionary, phase: String) -> void:
	sprite.visible = phase == "sword" and row.has(key)
	if not sprite.visible:
		return
	var point: Vector3 = row[key]
	var heading := point - (sprite.position + position)
	var cfg: Dictionary = row["cfg"]["sword_attack"]
	var clearance := float(cfg["twin_clearance_u"] if row.has("gin_second_pos") else cfg["clearance_u"])
	sprite.position = point - position + Vector3.UP * clearance / 2.0
	if not Vector2(heading.x, heading.z).is_zero_approx():
		sprite.rotation.y = -atan2(heading.z, heading.x)
