extends RefCounted
## T8 contract. One instance per arena. start(run_seed, level_no) returns entry events.
## tick(state, ctx) returns events at 60 Hz. state is LevelState, ctx carries tick,
## player_position and boss_position in world units. World owns movement and death dispatch.
## damage(amount, is_crit) takes final damage (the caller resolves crit math).
## projectiles() exposes the live ordered rows; GDScript needs a distinct backing field
## (_projectiles). Rows use attack, position, velocity, radius and height. Extend snapshot()
## with any new gameplay fields. All view notifications use the returned kind events.
## boss_projectile_hit_player carries attack and is lethal when dispatched by the caller.
## T8b owns attack flight/hits, boss_laugh, and bankai_started/hit/finished.
## bankai_rolled means the one roll was made; bankai_selected is its result.
## World sends arena_exited when the player takes the post-fight beacon.

const VoidRng := preload("res://terrain/void_rng.gd")
const DATA_PATH := "res://data/boss.json"

var active := false
var hp := 0
var hp_max := 0
var phase := "idle"
var attack_index := 0
var attack_tick := 0
var bankai_rolled := false
var bankai_selected := false
var bankai_active := false
var dead := false
var laugh_ticks := 0
var arena_entered := false
var config: Dictionary
var _projectiles: Array[Dictionary] = []
var _run_seed := 0


static func load_config() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))


func start(run_seed: int, level_no: int) -> Array[Dictionary]:
	if arena_entered:
		return []
	config = load_config()
	_run_seed = run_seed
	active = true
	arena_entered = true
	hp_max = int(config["hp"])
	hp = hp_max
	phase = "windup"
	bankai_rolled = true
	bankai_selected = _roll(VoidRng.mix(run_seed, level_no), float(config["bankai_chance"]))
	# TODO T8b: bankai_started, bankai_hit, bankai_finished.
	return [{"kind": "arena_entered"}, {"kind": "boss_spawned", "hp": hp, "hp_max": hp_max}]


func tick(state, ctx: Dictionary) -> Array[Dictionary]:
	if not active or dead or bankai_active:
		return []
	var attacks := ["bowling_ball", "green_fn"]
	var attack: String = attacks[attack_index]
	var events: Array[Dictionary] = []
	if attack_tick == 0:
		events.append({"kind": "boss_attack_windup", "attack": attack})
	attack_tick += 1
	if attack_tick >= int(config[attack]["windup_ticks"]):
		events.append_array(_spawn_attack(attack, state, ctx))
		attack_index = (attack_index + 1) % attacks.size()
		attack_tick = 0
	return events


func _spawn_attack(_attack: String, _state, _ctx: Dictionary) -> Array[Dictionary]:
	# TODO T8b: boss_projectile_spawned, boss_projectile_hit_player, boss_laugh.
	return []


func damage(amount: int, is_crit: bool) -> Array[Dictionary]:
	if not active or dead or amount <= 0:
		return []
	hp = maxi(0, hp - amount)
	var events: Array[Dictionary] = [{"kind": "boss_hp_changed", "hp": hp, "hp_max": hp_max, "is_crit": is_crit}]
	if hp == 0:
		dead = true
		active = false
		bankai_active = false
		phase = "dead"
		_projectiles.clear()
		events.append({"kind": "boss_died"})
	return events


func gift_is_crit(sim_tick: int) -> bool:
	return _roll(VoidRng.mix(_run_seed, sim_tick), float(config["crit_chance"]))


static func _roll(seed_value: int, probability: float) -> bool:
	return float(VoidRng.new(seed_value).u32()) / float(VoidRng.M32 + 1) < probability


func projectiles() -> Array[Dictionary]:
	return _projectiles


func snapshot() -> Dictionary:
	return {"active": active, "hp": hp, "hp_max": hp_max, "phase": phase,
		"attack_index": attack_index, "attack_tick": attack_tick, "projectiles": _projectiles,
		"bankai_rolled": bankai_rolled, "bankai_selected": bankai_selected,
		"bankai_active": bankai_active, "dead": dead, "laugh_ticks": laugh_ticks,
		"arena_entered": arena_entered, "run_seed": _run_seed, "config": config}
