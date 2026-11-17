extends RefCounted
#
# RunState (DESIGN.md section 13 rule 1; ticket T-010): the root of the state tree. One run's
# identity (seed, player count, content set), the current LevelState, and the run's RNG sub-streams
# (same Mulberry32 as the terrain, D-T010-3). No autoloads, no static mutable variables: everything
# lives on instances, everything is a function of the synced inputs (seed + per-tick PlayerInput),
# so a future netcode layer syncs exactly those (T-010 THE OWNER'S SPEC).

const VoidRngScript := preload("res://terrain/void_rng.gd")
const LevelStateScript := preload("res://sim/level_state.gd")

## Sim sub-stream base + ids (D-T010-3 [CONTESTABLE]). Deliberately disjoint from the terrain
## phase streams PLAN=1..MINE=5 (TERRAIN_SPEC.md section 3 rule 5). Fixed insertion order:
## iteration for reseeding/hashing walks this array, never the dictionary.
const STREAMS := [
	["world", 1],
	["fx", 2],
	["enemy_ai", 3],
	["loot", 4],
]
const STREAM_BASE := 900


var run_seed: int = 0
var level_number: int = 0  # the level currently simulated (1-based); 0 = no level loaded yet
var players: int = 1
var content_ids: Array = []  # sorted content ids (the "content set" input, DESIGN.md section 13)
var level: RefCounted = null  # LevelState or null between levels
var rng: Dictionary = {}  # stream name -> VoidRng instance (lookup only, never iterated directly)


static func new_run(p_run_seed: int, p_players: int, p_content_ids: Array) -> RefCounted:
	var rs := new()
	rs.run_seed = p_run_seed
	rs.players = p_players
	rs.content_ids = p_content_ids.duplicate()
	rs.content_ids.sort()
	rs.rng = {}
	for s in STREAMS:
		rs.rng[s[0]] = VoidRngScript.new(_stream_seed(p_run_seed, s[1], 0))
	return rs


## Loads the next level (engine caller produces the Level dict via terrain/voidgen.gd generate()).
## Re-seeds every sim sub-stream from (run_seed, stream id, level_number) so nothing leaks between
## levels (D-T010-3). Never re-generates terrain here: terrain is a pure input, not sim state.
func load_level(level_dict: Dictionary, p_level_number: int) -> void:
	level_number = p_level_number
	for s in STREAMS:
		(rng[s[0]] as RefCounted).s = _stream_seed(run_seed, s[1], level_number)
	level = LevelStateScript.build(level_dict, level_number, players, run_seed)


static func _stream_seed(p_run_seed: int, stream_id: int, p_level_number: int) -> int:
	return VoidRngScript.mix(VoidRngScript.mix(p_run_seed, STREAM_BASE + stream_id), p_level_number)
