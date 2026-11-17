extends RefCounted
#
# LevelState (DESIGN.md section 13 rule 1; ticket T-010): one level's slice of the state tree.
# Holds the Level object (TERRAIN_SPEC.md section 8.1) as produced by terrain/voidgen.gd, the
# per-level tick, the player rows, and a ground-height column map built ONCE from the tiles
# (dictionary for lookup only — never iterated, TERRAIN_SPEC.md section 3 rule 3).
#
# The level dict is treated as read-only shared data: it is a pure function of the seed, so it is
# part of "the world" and NOT hashed row by row — its canonical hash (same SHA-256 as the terrain
# parity lock) is stored once and enters the state dump as a single line.

const VoidGenScript := preload("res://terrain/voidgen.gd")

## Height (world u) of a tile's top surface; HU = 0.5 u (TERRAIN_SPEC.md section 4).
const HU := 0.5


var level_dict: Dictionary = {}
var level_hash: String = ""
var tick: int = 0
## Vector2i cell -> float world height of the top of the highest tile in that column. Ramps count
## only as their LOW edge height in the T-010 scaffold (D-T010-4).
var columns: Dictionary = {}
## Player rows, one Dictionary per player index (insertion-ordered, read by sim.gd and the dump).
var players: Array = []


## level_number is 1-based (the run's current level). player_count in 1..8 (TERRAIN_SPEC.md spawns).
static func build(level: Dictionary, p_level_number: int, p_player_count: int) -> RefCounted:
	var st := new()
	st.level_dict = level
	st.level_hash = VoidGenScript.level_hash(level) if not level.is_empty() else ""
	_build_columns(st, level)
	_spawn_players(st, level, p_player_count)
	return st


static func _build_columns(st: RefCounted, level: Dictionary) -> void:
	st.columns = {}
	if level.is_empty():
		return
	for t in level["tiles"]:
		var h: float = float(t[2]) * HU
		var key := Vector2i(int(t[0]), int(t[1]))
		if not st.columns.has(key) or float(st.columns[key]) < h:
			st.columns[key] = h


static func _spawn_players(st: RefCounted, level: Dictionary, p_player_count: int) -> void:
	st.players = []
	if level.is_empty():
		return
	var spawns: Array = level["spawns"]
	for i in p_player_count:
		st.players.append(_spawn_row(spawns[i % spawns.size()]))


static func _spawn_row(spawn: Array) -> Dictionary:
	# Spawn tile [x, z, y] -> world centre of the tile, feet on the top surface.
	return {
		"x": float(int(spawn[0])) + 0.5,
		"y": float(int(spawn[2])) * HU,
		"z": float(int(spawn[1])) + 0.5,
		"vx": 0.0,
		"vy": 0.0,
		"vz": 0.0,
		"grounded": true,
		"prev_buttons": 0,
	}


## Ground height of the column containing world (x, z); null when the column has no tile (void).
func ground_at(wx: float, wz: float) -> Variant:
	return columns.get(Vector2i(floor_i(wx), floor_i(wz)))


## floor() without floor(): comparisons and int truncation only (DESIGN.md section 13 rule 5).
static func floor_i(v: float) -> int:
	var i := int(v)
	if v < 0.0 and float(i) != v:
		i -= 1
	return i
