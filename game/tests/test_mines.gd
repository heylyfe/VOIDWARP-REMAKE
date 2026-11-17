extends RefCounted
#
# A6 (FLEET_PACK.md, ticket T-021): the tripmine.
#   - mine set = EXACTLY the Level.gifts occ == 1 slots (no other placement);
#   - contact: the player's centre within 0.9 u horizontal, at ANY height;
#   - the contact ladder in the fixed order: defuse roll -> Subspacial Barrier
#     shield -> Last Light -> death (D-058), the death carrying D-MINE;
#   - determinism: same seed + same slot id -> same outcome (1,000 seeds);
#   - kill tests run with Last Light ALREADY SPENT or otherwise moot (D-057).

const MinesScript := preload("res://sim/mines.gd")
const DeathScript := preload("res://sim/death.gd")
const BeaconScript := preload("res://sim/beacon.gd")
const Util := preload("res://tests/sim_testutil.gd")


func run() -> Array[String]:
	var f: Array[String] = []
	_test_contact_geometry(f)
	_test_ladder(f)
	_test_blast(f)
	_test_determinism(f)
	_test_screen_data(f)
	return f


# ---- helpers -------------------------------------------------------------------

## A mines state over n slots (slot id i at world x = i*10 + 0.5), all live mines.
static func _state(n: int, run_seed: int = 0) -> RefCounted:
	var occs: Array = []
	for i in n:
		occs.append(1)
	return MinesScript.create(_level(occs), 1, run_seed)


## A mixed slot table: occs[i] == 1 -> mine, else a plain gift slot.
static func _level(occs: Array) -> Dictionary:
	var slots: Array = []
	for i in occs.size():
		slots.append({"id": i, "x": i * 10, "z": 0, "y": 0, "piece": 0, "tier": 0, "occ": occs[i]})
	return {"gifts": slots}


static func _ctl() -> RefCounted:
	var ctl = ControllerScript.new()
	ctl.setup("dasher", ControllerScript.load_constants())
	return ctl


## Runs one contact resolution: returns the outcome string of mines.gd
## ("defused" | "shielded" | "last_light" | "death") via the returned events
## (the caller inspects). world: the blast/Last Light world context.
static func _contact(m, ctl, w: Dictionary, stacks: int = 3) -> Array:
	var holder := {"mines": m, "players": [{"x": 0.0, "y": 0.0, "z": 0.0}], "beacon": m.beacon}
	MinesScript.tick(holder, [ctl], w, [stacks], 7, [])
	return holder


# ---- the mine set (Level.gifts occ == 1) ---------------------------------------
