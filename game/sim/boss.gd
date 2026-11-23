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
##
## T8b extensions to the T8a contract (all additive, none of the T8a fields changed):
##   - snapshot() also carries cooldown_tick and bankai_tick, so the attack cadence and
##     the cinematic clock are in the state hash and a replay reproduces both.
##   - boss_attack_windup carries player_position (the player's feet at the windup tick).
##     It is a view-only field: events are never hashed, so replays are unaffected. The
##     green_fn ground marker needs it and the view cannot read the controller.
##   - new event kinds: boss_projectile_spawned / _moved / _removed, boss_laugh,
##     bankai_started / bankai_hit / bankai_finished.
##   - the attack cadence gains a data-driven cooldown_ticks between attacks. Without it
##     the two attacks arrive one tick apart and a single jump clears both, which makes
##     the fight one dodge instead of two.
## Projectile rows keep the T8a shape (attack, position, velocity, radius, height) and add
## id, spawn_tick, age and life_ticks; the whole row is hashed through _projectiles.

const VoidRng := preload("res://terrain/void_rng.gd")
const ControllerScript := preload("res://sim/controller.gd")
const DATA_PATH := "res://data/boss.json"
const DT := 1.0 / 60.0

var active := false
var hp := 0
var hp_max := 0
var phase := "idle"
var attack_index := 0
var attack_tick := 0
var bankai_rolled := false
var bankai_selected := false
var bankai_active := false
var bankai_tick := 0
var cooldown_tick := 0
var dead := false
var laugh_ticks := 0
var arena_entered := false
var config: Dictionary
var _projectiles: Array[Dictionary] = []
var _run_seed := 0
var _player_half_width := 0.4
var _player_height := 1.8
var _next_projectile_id := 0
## The lane the CURRENT wind-up committed to. The bowling ball fixes its lane at the
## wind-up so the view's ground marker is the lane the ball will actually take; the
## green_fn commits nothing here (it aims at the player's position at release, per the
## owner's spec) and leaves this zero. Hashed through snapshot().
var _aim := Vector3.ZERO


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
	# The player's own body numbers, so the hit volumes are the controller's, not a copy.
	var body: Dictionary = ControllerScript.load_constants()
	_player_half_width = float(body["half_width"])
	_player_height = float(body["height"])
	bankai_rolled = true
	bankai_selected = _roll(VoidRng.mix(run_seed, level_no), float(config["bankai_chance"]))
	var events: Array[Dictionary] = [{"kind": "arena_entered"},
		{"kind": "boss_spawned", "hp": hp, "hp_max": hp_max}]
	# The easter egg: the roll is the sim's, the cinematic is the view's. The sim owns the
	# clock (bankai_tick) and the kill; the view owns the 25.5 s animation and its signals.
	if bankai_selected:
		bankai_active = true
		bankai_tick = 0
		events.append({"kind": "bankai_started"})
	return events


func tick(state, ctx: Dictionary) -> Array[Dictionary]:
	if not active and not bankai_active:
		return []
	if bankai_active:
		return _tick_bankai()
	if dead:
		return []
	if laugh_ticks > 0:
		laugh_ticks -= 1
	var events: Array[Dictionary] = _tick_projectiles(ctx)
	if cooldown_tick > 0:
		cooldown_tick -= 1
		return events
	var attacks := ["bowling_ball", "green_fn"]
	var attack: String = attacks[attack_index]
	if attack_tick == 0:
		_aim = _lane_for(ctx) if attack == "bowling_ball" else Vector3.ZERO
		events.append({"kind": "boss_attack_windup", "attack": attack,
			"player_position": ctx["player_position"], "aim": _aim})
	attack_tick += 1
	if attack_tick >= int(config[attack]["windup_ticks"]):
		events.append_array(_spawn_attack(attack, state, ctx))
		attack_index = (attack_index + 1) % attacks.size()
		attack_tick = 0
		cooldown_tick = int(config["cooldown_ticks"])
	return events


## The arena floor in world units. The arena is one flat platform at arena.floor_height
## tiles, and LevelState.HU is the tile-to-world scale.
func floor_y() -> float:
	return float(config["arena"]["floor_height"]) * 0.5


## The bowling ball's lane, fixed at the wind-up: flat, from Peter to where the player
## stood when he wound up. Committing here (not at the release) is what lets the view
## draw a marker that is the truth rather than a guess.
func _lane_for(ctx: Dictionary) -> Vector3:
	var boss_pos: Vector3 = ctx["boss_position"]
	var player_pos: Vector3 = ctx["player_position"]
	var flat := Vector3(player_pos.x - boss_pos.x, 0.0, player_pos.z - boss_pos.z)
	if flat.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return flat.normalized()


func _spawn_attack(attack: String, _state, ctx: Dictionary) -> Array[Dictionary]:
	var cfg: Dictionary = config[attack]
	var boss_pos: Vector3 = ctx["boss_position"]
	var player_pos: Vector3 = ctx["player_position"]
	var floor := floor_y()
	var row := {"attack": attack, "radius": float(cfg["radius_u"]),
		"height": float(cfg["height_u"]), "id": _next_projectile_id,
		"spawn_tick": int(ctx["tick"]), "age": 0, "life_ticks": int(cfg["life_ticks"])}
	_next_projectile_id += 1
	if attack == "bowling_ball":
		# A ground roll: the ball sits on the floor and travels flat, so the only way past
		# it is sideways or over the top. Its centre is half its height up, which puts the
		# top at floor + height_u - the height the player's feet must beat.
		var from := Vector3(boss_pos.x, floor + float(cfg["height_u"]) * 0.5, boss_pos.z)
		row["position"] = from
		row["velocity"] = _aim * float(cfg["speed_u_per_s"])
	else:
		# The three-pointer: aimed at the player's body centre AT RELEASE, so it is exact
		# where they stood and stale the moment they move. Fast, flat, and dodgeable by
		# stepping off the line during the flight.
		var aim_y := floor + float(cfg["aim_height_u"])
		var from := Vector3(boss_pos.x, aim_y, boss_pos.z)
		var aim := Vector3(player_pos.x - from.x,
			player_pos.y + _player_height * 0.5 - aim_y, player_pos.z - from.z)
		if aim.length_squared() < 0.0001:
			aim = Vector3(0.0, 0.0, 1.0)
		row["position"] = from
		row["velocity"] = aim.normalized() * float(cfg["speed_u_per_s"])
	_projectiles.append(row)
	return [{"kind": "boss_projectile_spawned", "attack": attack, "id": row["id"],
		"position": row["position"], "velocity": row["velocity"],
		"radius": row["radius"], "height": row["height"]}]


## Advances every live projectile one tick, tests it against the player and expires it.
## A hit is lethal by contract: the caller dispatches boss_projectile_hit_player through
## the controller's death path, and Peter laughs.
func _tick_projectiles(ctx: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if _projectiles.is_empty():
		return events
	var player: Vector3 = ctx["player_position"]
	var live: Array[Dictionary] = []
	for row in _projectiles:
		var from: Vector3 = row["position"]
		var to: Vector3 = from + (row["velocity"] as Vector3) * DT
		row["position"] = to
		row["age"] = int(row["age"]) + 1
		if _projectile_hits(row, from, to, player):
			events.append({"kind": "boss_projectile_hit_player", "attack": row["attack"],
				"id": row["id"]})
			events.append({"kind": "boss_laugh"})
			laugh_ticks = int(config["laugh_ticks"])
			continue
		if int(row["age"]) >= int(row["life_ticks"]):
			events.append({"kind": "boss_projectile_removed", "id": row["id"]})
			continue
		live.append(row)
		events.append({"kind": "boss_projectile_moved", "id": row["id"], "position": to})
	_projectiles = live
	return events


## The bowling ball is a horizontal cylinder on the floor: the player clears it by getting
## their feet above its top. The green_fn is a sphere against the player's body box.
func _projectile_hits(row: Dictionary, from: Vector3, to: Vector3, player: Vector3) -> bool:
	var radius := float(row["radius"])
	if str(row["attack"]) == "bowling_ball":
		var top := float((row["position"] as Vector3).y) + float(row["height"]) * 0.5
		if player.y >= top:
			return false
		var a := Vector2(from.x, from.z)
		var b := Vector2(to.x, to.z)
		var p := Vector2(player.x, player.z)
		return Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) \
			<= radius + _player_half_width
	var centre := player + Vector3(0.0, _player_height * 0.5, 0.0)
	return Geometry3D.get_closest_point_to_segment(centre, from, to).distance_to(centre) \
		<= radius + _player_half_width


## The Bankai clock. The sim owns the timing so a replay reproduces the kill exactly; the
## view's cinematic runs on render time and only follows along. hit_tick is the cinematic's
## first target_hit (21.0 s), end_tick its TOTAL_DURATION (25.5 s).
func _tick_bankai() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	bankai_tick += 1
	if not dead and bankai_tick >= int(config["bankai"]["hit_tick"]):
		events.append({"kind": "bankai_hit"})
		events.append_array(_die())
	if bankai_tick >= int(config["bankai"]["end_tick"]):
		bankai_active = false
		events.append({"kind": "bankai_finished"})
	return events


## The Bankai kill: the gifts reach Peter and he dies outright, whatever his HP was.
func _die() -> Array[Dictionary]:
	hp = 0
	dead = true
	active = false
	phase = "dead"
	_projectiles.clear()
	return [{"kind": "boss_hp_changed", "hp": 0, "hp_max": hp_max, "is_crit": false},
		{"kind": "boss_died"}]


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
		"cooldown_tick": cooldown_tick, "next_projectile_id": _next_projectile_id,
		"aim": _aim,
		"bankai_rolled": bankai_rolled, "bankai_selected": bankai_selected,
		"bankai_active": bankai_active, "bankai_tick": bankai_tick,
		"dead": dead, "laugh_ticks": laugh_ticks,
		"arena_entered": arena_entered, "run_seed": _run_seed, "config": config}
