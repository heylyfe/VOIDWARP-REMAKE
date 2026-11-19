extends Node3D
#
# Diegetic danger text (ticket T-025; DESIGN.md section 14).
#
# `THE <ENEMY> SHALL <VERB>` in #FF2A2A floats at each enemy's spawn point for
# 4.0 s when it appears (carried over from the old build's look). It is the
# world-space half of the HUD: billboarded Label3D, unshaded, fog-exempt, no
# depth test - it reads across the level through the fog, like the straggler
# beam. It is fed by the enemy_spawn event from sim/enemy_runtime.gd
# ({"e":"enemy_spawn", "id", "name", "x", "y", "z", ...}).
#
# The spawn lines (the only per-enemy text stated anywhere - research/fable-
# tickets.md, the T-027 spawn-line row): THE KIWI CAT SHALL FOLLOW, ... A TBD
# enemy shows TBD SHALL ARRIVE. The line for an unknown id is therefore the TBD
# line, never a guess. The lines ship in each enemy's enemy.json (spawn_line)
# and are read through core/roster.gd - this file holds no roster table.
#
# This element and billboard.gd's spawn_text are deliberately separate: section 14
# wants the danger line in #FF2A2A for 4.0 s; D-T027-7 pinned the billboard name
# label at 1.5 s. Both fire on the same event.

const RosterScript := preload("res://core/roster.gd")
const DANGER_COLOR := Color(1.0, 0.1647, 0.1647)   # #FF2A2A
const TTL := 4.0
const HEIGHT := 2.0   # u above the spawn point (sprite stand + clear)
const TBD_LINE := "TBD SHALL ARRIVE"

var driven := false   # true: the owner calls advance() each sim step (world.gd)
var _lines: Array = []   # [{"label": Label3D, "t": seconds alive}]


## Normalise an enemy id for the table: lower case, "?!"/"!" stripped, spaces -> underscores.
static func normalize_id(id: String) -> String:
	var s := id.to_lower().replace("?!", "").replace("!", "").replace(" ", "_")
	return s


## The exact line for an enemy id; unknown ids get the TBD line. Lines ship in the
## enemies' own enemy.json (spawn_line) and are read through core/roster.gd.
static func spawn_line(id: String) -> String:
	return str(RosterScript.spawn_lines().get(normalize_id(id), TBD_LINE))


## Fire on an enemy_spawn event: raises the line at the spawn point for 4.0 s.
func on_enemy_spawn(ev: Dictionary) -> void:
	var id := str(ev.get("id", ""))
	var label := Label3D.new()
	label.text = spawn_line(id)
	label.font_size = 64
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = DANGER_COLOR
	label.outline_size = 12
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.position = Vector3(float(ev.get("x", 0.0)), float(ev.get("y", 0.0)) + HEIGHT, float(ev.get("z", 0.0)))
	add_child(label)
	_lines.append({"label": label, "t": 0.0})


## Ages every raised line by dt seconds and frees the ones past TTL. The world's view
## pass drives it from the fixed sim step (deterministic, and safe outside the tree -
## a tween cannot be created there); _process drives it when no one else does.
func advance(dt: float) -> void:
	var keep: Array = []
	for l in _lines:
		l["t"] = float(l["t"]) + maxf(dt, 0.0)
		var label: Label3D = l["label"]
		if float(l["t"]) >= TTL:
			remove_child(label)
			label.queue_free()
		else:
			keep.append(l)
	_lines = keep


func _process(delta: float) -> void:
	if not driven:
		advance(delta)


## The live line count and texts (tests and the HUD-less probe read these).
func line_count() -> int:
	return _lines.size()


func line_texts() -> Array:
	var out: Array = []
	for l in _lines:
		out.append((l["label"] as Label3D).text)
	return out
