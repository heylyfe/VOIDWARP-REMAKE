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
# T-020: gift slots + the beacon state machine, built once from the Level dict.
const GiftsScript := preload("res://sim/gifts.gd")
const BeaconScript := preload("res://sim/beacon.gd")
# T-021: the tripmine entity (occupies the Level.gifts occ == 1 slots).
const MinesScript := preload("res://sim/mines.gd")
# T-053: the scripted-upgrade engine, built from role keys (D-T053-1) supplied by
# the caller - sim never names an upgrade id, so the id -> role aggregation lives
# outside sim (content scripts + the app/shop wiring).
const UpgradesScript := preload("res://sim/upgrades.gd")

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
## T-020: gift-slot state (two bitsets by slot id + phase) and the beacon
## state machine, both pure functions of the Level dict and the inputs.
var gifts: RefCounted = null
var beacon: RefCounted = null
## T-021: the tripmine set (exactly the occ == 1 slots) + consumed bitset.
var mines: RefCounted = null
## T-053: the scripted-upgrade state, built from ROLE keys (D-T053-1) supplied by
## the caller; null when no scripted upgrade is owned.
var upgrades: RefCounted = null


## level_number is 1-based (the run's current level). player_count in 1..8 (TERRAIN_SPEC.md spawns).
## run_seed feeds the defuse roll (D-051); defaults to 0 so existing callers
## (which have no run to seed from) stay valid. p_upgrade_roles carries the
## scripted-upgrade roles aggregated OUTSIDE sim (D-T053-1); default {} = none owned.
static func build(level: Dictionary, p_level_number: int, p_player_count: int,
		p_run_seed: int = 0, p_upgrade_roles: Dictionary = {}) -> RefCounted:
	var st := new()
	st.level_dict = level
	st.level_hash = VoidGenScript.level_hash(level) if not level.is_empty() else ""
	_build_columns(st, level)
	_spawn_players(st, level, p_player_count)
	st.gifts = GiftsScript.create(level)
	st.beacon = BeaconScript.create(level)
	st.mines = MinesScript.create(level, p_level_number, p_run_seed)
	st.upgrades = UpgradesScript.create(p_upgrade_roles)
	if st.upgrades != null:
		# Skeleton Key (D-T053-4): the beacon-open condition becomes the 90 % quota.
		if st.upgrades.has(UpgradesScript.ROLE_SKELETON_QUOTA):
			st.gifts.black_quota = UpgradesScript.skeleton_threshold(st.gifts.total_real)
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
