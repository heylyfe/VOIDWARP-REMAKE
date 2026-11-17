extends Node3D
#
# kiwi cat view (ticket T-030; ENEMIES.md hard rules; DESIGN.md section 5.1; the T-083
# anim block in sprites.json). View layer only: reads sim EVENTS (the enemy_spawn / meow
# telegraph ticks), never writes sim state; every effect is driven by the sim tick counter
# the caller passes to step(), never by a wall clock.
#
# Wired to the anim block (sprites.json -> anim):
#   spawn       30-tick fade: alpha 0 -> 1, scale 0.8 -> 1.0, first idle frame
#   idle_chase  bob +-0.08 u at 1.0 Hz (the sheet's single frame loops)
#   telegraph   "meow": scale pulse 1.0 -> 1.12 -> 1.0 across the 12-tick cue
#   attack      none - contact kills on the tick the cylinders overlap; no wind-up exists
# The frame set is the T-016 TBD placeholder for the real kiwicat.png (TBD.md row 1);
# dropping the real art in changes nothing here.

const BillboardScript := preload("res://view/billboard.gd")

const TICKS_PER_SECOND := 60.0
const TAU := 6.283185307179586

var billboard: Sprite3D = null
var anim: Dictionary = {}
var world_height := 1.0

var _base_scale := Vector3.ONE
var _spawn_left := 0            # spawn fade ticks remaining
var _spawn_total := 30
var _bob_t := 0.0               # seconds into the bob cycle
var _meow_left := 0             # scale-pulse ticks remaining
var _meow_total := 12


## Parses sprites.json, builds the billboarded PNG sprite (body = world_height u tall,
## feet on the origin, BILLBOARDING + TRANSPARENCY rules live in billboard.gd) and caches
## the anim-block effect parameters. folder_dir is the enemy folder's res:// path.
func setup(folder_dir: String = "res://content/enemies/kiwi_cat") -> void:
	var text := FileAccess.get_file_as_string(folder_dir.path_join("sprites.json"))
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		push_warning("kiwi_cat_view: sprites.json unreadable at %s" % folder_dir)
		doc = {}
	anim = (doc as Dictionary).get("anim", {})
	world_height = float((doc as Dictionary).get("world_height", 1.0))
	_spawn_total = int(((anim.get("states", {})).get("spawn", {})).get("total_ticks", 30))
	_meow_total = int(((anim.get("states", {})).get("telegraph", {})).get("total_ticks", 12))
	billboard = BillboardScript.new()
	add_child(billboard)
	billboard.setup_from_sheet(doc, folder_dir)
	billboard.world_height = world_height
	_base_scale = billboard.scale


## The spawn fade restarts (the sim's enemy_spawn event for this enemy).
func on_spawn() -> void:
	_spawn_left = _spawn_total


## A sim telegraph event for this enemy (kind "meow") starts the 12-tick scale pulse.
func on_telegraph(kind: String, ticks: int = -1) -> void:
	if kind != "meow":
		return
	_meow_left = ticks if ticks > 0 else _meow_total


## One sim tick of view state: spawn fade, bob and the meow pulse. dt_ticks is the sim
## tick count (1 at 60 Hz) - the caller drives this from the sim, not from _process.
func step(dt_ticks: int = 1) -> void:
	if billboard == null:
		return
	_bob_t += float(dt_ticks) / TICKS_PER_SECOND
	# bob: +- amplitude at hz, phase 0 at spawn
	var idle: Dictionary = ((anim.get("states", {})).get("idle_chase", {})).get("effect", {})
	var bob_amp := float((idle.get("params", {})).get("amplitude_u", 0.08))
	var bob_hz := float((idle.get("params", {})).get("hz", 1.0))
	billboard.position.y = bob_amp * sin(_bob_t * TAU * bob_hz)
	# spawn fade: alpha 0 -> 1, scale 0.8 -> 1.0 over the first _spawn_total ticks
	var fade := 1.0
	var scale_mul := 1.0
	if _spawn_left > 0:
		_spawn_left = maxi(_spawn_left - dt_ticks, 0)
		var done := 1.0 - float(_spawn_left) / float(maxi(_spawn_total, 1))
		fade = done
		scale_mul = 0.8 + 0.2 * done
	# meow scale pulse 1.0 -> 1.12 -> 1.0 (sin envelope over the cue)
	var pulse := 1.0
	if _meow_left > 0:
		_meow_left = maxi(_meow_left - dt_ticks, 0)
		var progress := 1.0 - float(_meow_left) / float(maxi(_meow_total, 1))
		var peak := float((((anim.get("states", {})).get("telegraph", {}))
				.get("effect", {})).get("params", {}).get("peak", 1.12))
		pulse = 1.0 + (peak - 1.0) * sin(progress * PI)
	billboard.modulate = Color(1.0, 1.0, 1.0, fade)
	billboard.scale = _base_scale * (scale_mul * pulse)

