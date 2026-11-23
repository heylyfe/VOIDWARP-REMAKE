extends RefCounted
#
# T8b: Peter Griffin's two attacks, his laugh and the Bankai easter egg.
#
# The framework worker's test_boss_framework.gd already covers the HP/crit math, the win
# flow (300 gold + beacon) and the arena teleport. Nothing here repeats those; this file
# owns the attack half:
#
#   1. the windows, ARITHMETIC from data/boss.json and data/player.json - never brute
#      forced. The bowling ball's hit window must fit inside a normal jump's airtime and
#      the ball must sit under the jump apex; the green_fn's windup-to-arrival must clear
#      the owner's 400 ms floor and leave room for a sideways dodge; and the two attacks
#      must not arrive within one jump of each other.
#   2. the bowling ball against the REAL controller: a bot that jumps when the ball is
#      close clears it, a bot that stands still is hit.
#   3. the green_fn against the REAL controller: a bot that strafes after the release
#      clears it, a bot that stands still is hit.
#   4. any hit kills the player and Peter laughs (through the real World dispatch).
#   5. the Bankai roll is deterministic across seeds and replays, and the kill path
#      insta-kills Peter at the cinematic's own hit tick.
#   6. the arena state hash is deterministic across a REAL record/replay - run one records
#      its command stream, run two replays it verbatim - for both an ordinary fight and a
#      Bankai fight, so the Bankai clock and the death are inside the hashed span.
#
# The window arithmetic in (1) is a claim about the DATA. _measured_windows then runs the
# real sim against a stationary player and asserts the measured wind-up-to-arrival tick
# count matches the data, so the claim is checked against the shipped code and not just
# against itself.
#
# Every loop is bounded. The attack legs run the boss and the controller directly (no
# World) so one attack can be isolated from the other; the death and hash legs use the
# real World so the dispatch under test is the shipped one.

const World := preload("res://app/world.gd")
const Boss := preload("res://sim/boss.gd")
const BossArena := preload("res://terrain/boss_arena.gd")
const Collision := preload("res://sim/collision.gd")
const Controller := preload("res://sim/controller.gd")
const RunState := preload("res://sim/run_state.gd")
const StateHash := preload("res://sim/state_hash.gd")

const DT := 1.0 / 60.0
const SEED := 17
const IDLE := {"buttons": 0}
const BTN_JUMP := 1
## How close (in ticks) the bowling ball must be before the bot jumps. The jump's
## above-the-ball span is ticks 2.4..42.6 of a 45-tick airtime, so 20 is comfortably inside.
const JUMP_LEAD_TICKS := 20


func run() -> Array[String]:
	var f: Array[String] = []
	_windows(f)
	_measured_windows(f)
	_bowling_ball(f)
	_green_fn(f)
	_hit_kills_and_laughs(f)
	_bankai(f)
	_record_and_replay(f, false)
	_record_and_replay(f, true)
	return f


# ---- 1. the windows, from the data ------------------------------------------------

func _windows(f: Array[String]) -> void:
	var cfg := Boss.load_config()
	var arena: Dictionary = cfg["arena"]
	var body := Controller.load_constants()
	var dist := absf(float(arena["spawn_z"]) - float(arena["boss_z"]))
	var gravity := float(body["gravity"])
	var jump_v := float(body["jump_velocity"])
	var half_w := float(body["half_width"])
	var run_speed := float(body["run_speed"])
	# EVERY number below is in TICKS. The first version of this test added a flight time in
	# SECONDS to a wind-up in TICKS and then multiplied by DT, so it never established the
	# wind-up-to-arrival timing it claimed. Ticks throughout, and _measured_windows then
	# checks the same numbers against the real sim.
	var airtime := 2.0 * jump_v / gravity * 60.0
	var apex := jump_v * jump_v / (2.0 * gravity)

	# Travel is measured to CONTACT, not to the player's centre: the projectile hits when its
	# leading edge meets the player's near edge, so the distance covered is
	# dist - (radius + half_width). That is the shorter, honest window.
	var bb: Dictionary = cfg["bowling_ball"]
	var bb_reach := float(bb["radius_u"]) + half_w
	var bb_flight := (dist - bb_reach) / float(bb["speed_u_per_s"]) * 60.0
	var bb_window := float(bb["windup_ticks"]) + bb_flight
	var bb_hit := 2.0 * bb_reach / float(bb["speed_u_per_s"]) * 60.0
	if bb_window < 24.0:
		f.append("bowling ball: %.0f ticks (%.0f ms) from wind-up to arrival is under 400 ms"
			% [bb_window, bb_window * 1000.0 / 60.0])
	if airtime < bb_hit * 2.0:
		f.append("bowling ball: a %.1f-tick jump does not cover the %.1f-tick hit window twice"
			% [airtime, bb_hit])
	if float(bb["height_u"]) >= apex:
		f.append("bowling ball: %.2f u tall is not under the %.2f u jump apex"
			% [float(bb["height_u"]), apex])

	var gf: Dictionary = cfg["green_fn"]
	var gf_reach := float(gf["radius_u"]) + half_w
	var gf_flight := (dist - gf_reach) / float(gf["speed_u_per_s"]) * 60.0
	var gf_window := float(gf["windup_ticks"]) + gf_flight
	if gf_window < 24.0:
		f.append("green_fn: %.0f ticks (%.0f ms) from wind-up to arrival is under the 400 ms floor"
			% [gf_window, gf_window * 1000.0 / 60.0])
	var dodge := gf_reach / run_speed * 60.0
	if dodge * 2.0 >= gf_flight:
		f.append("green_fn: the %.1f-tick sideways dodge does not fit the %.1f-tick flight"
			% [dodge, gf_flight])

	# The two attacks must not land inside one jump, or the fight is a single dodge.
	var bb_arrive := float(bb["windup_ticks"]) + bb_flight
	var gap := float(cfg["cooldown_ticks"])
	var gf_arrive := float(bb["windup_ticks"]) + gap + float(gf["windup_ticks"]) + gf_flight
	if gf_arrive - bb_arrive <= airtime:
		f.append("attacks arrive %.0f ticks apart; a %.0f-tick jump covers both"
			% [gf_arrive - bb_arrive, airtime])


## The arithmetic above is a claim about the DATA. This leg measures the same numbers off
## the real sim: the boss runs against a stationary player and, per attack, the tick the
## wind-up event fired and the tick the hit landed are recorded. The measured window must
## match the data and clear the 400 ms floor.
func _measured_windows(f: Array[String]) -> void:
	var rig := _rig()
	if rig.is_empty():
		f.append("measured windows: the arena rig failed to build")
		return
	var boss: RefCounted = rig["boss"]
	var ctl: RefCounted = rig["ctl"]
	var w: Dictionary = rig["w"]
	var boss_pos: Vector3 = rig["boss_pos"]
	var cfg: Dictionary = boss.config
	var dist := absf(float(cfg["arena"]["spawn_z"]) - float(cfg["arena"]["boss_z"]))
	var windup_at := {}
	var measured := {}
	for i in 400:
		ctl.step(DT, IDLE, w)
		var feet := Vector3(ctl.x, ctl.y, ctl.z)
		var ev: Array = boss.tick(null, {"tick": i + 1, "player_position": feet,
			"boss_position": boss_pos})
		for e in ev:
			var kind := str(e["kind"])
			var attack := str(e.get("attack", ""))
			if kind == "boss_attack_windup":
				windup_at[attack] = i + 1
			elif kind == "boss_projectile_hit_player" and windup_at.has(attack):
				if not measured.has(attack):
					measured[attack] = (i + 1) - int(windup_at[attack])
	for attack in ["bowling_ball", "green_fn"]:
		if not measured.has(attack):
			f.append("measured windows: %s never reached a stationary player" % attack)
			continue
		var ticks := float(measured[attack])
		var reach := float(cfg[attack]["radius_u"]) + float(Controller.load_constants()["half_width"])
		var flight := (dist - reach) / float(cfg[attack]["speed_u_per_s"]) * 60.0
		var want := float(cfg[attack]["windup_ticks"]) + flight
		if absf(ticks - want) > 2.0:
			f.append("measured windows: %s took %.0f ticks from wind-up to arrival, the data says %.0f"
				% [attack, ticks, want])
		if ticks < 24.0:
			f.append("measured windows: %s arrived %.0f ticks after the wind-up, under 400 ms"
				% [attack, ticks])


## A seed whose fight is NOT the easter egg, so the attack legs see attacks. The roll is
## 1/1000, so the first candidate almost always works; the loop is bounded either way.
static func _plain_seed() -> int:
	for s in 64:
		var probe := Boss.new()
		probe.start(SEED + s, 10)
		if not probe.bankai_selected:
			return SEED + s
	return SEED


## Boss + real controller + the arena's own collision world, with no World around them so
## one attack can be isolated from the other.
func _rig() -> Dictionary:
	var boss := Boss.new()
	boss.start(_plain_seed(), 10)
	var cfg: Dictionary = boss.config
	var lv: Dictionary = BossArena.build({}, cfg)
	var w: Dictionary = Collision.make_world(lv["tiles"], [], [], {"dais": lv["arena_spawn"]})
	var ctl := Controller.new()
	ctl.place(w)
	var tile: Array = lv["arena_boss"]
	var boss_pos := Vector3(float(tile[0]) + 0.5,
		float(tile[2]) * 0.5 + float(cfg["arena"]["boss_height_u"]),
		float(tile[1]) + 0.5)
	return {"boss": boss, "ctl": ctl, "w": w, "boss_pos": boss_pos}


# ---- 2. the bowling ball against the real controller ------------------------------

## True when a live bowling ball is within JUMP_LEAD_TICKS of the player.
static func _ball_close(boss: RefCounted, feet: Vector3) -> bool:
	for row in boss.projectiles():
		if str(row["attack"]) != "bowling_ball":
			continue
		var pos: Vector3 = row["position"]
		var speed := (row["velocity"] as Vector3).length()
		if speed <= 0.0:
			continue
		var flat := Vector2(feet.x - pos.x, feet.z - pos.z)
		if flat.length() / speed <= float(JUMP_LEAD_TICKS) * DT:
			return true
	return false


## Runs the fight until a bowling ball hits or the bound expires. Returns true when the
## ball connected. `jump` is the bot: it presses JUMP when the ball is close.
func _ball_run(f: Array[String], jump: bool) -> bool:
	var rig := _rig()
	if rig.is_empty():
		f.append("bowling ball: the arena rig failed to build")
		return false
	var boss: RefCounted = rig["boss"]
	var ctl: RefCounted = rig["ctl"]
	var w: Dictionary = rig["w"]
	var boss_pos: Vector3 = rig["boss_pos"]
	for i in 240:
		var feet := Vector3(ctl.x, ctl.y, ctl.z)
		var buttons := BTN_JUMP if jump and _ball_close(boss, feet) else 0
		ctl.step(DT, {"buttons": buttons}, w)
		feet = Vector3(ctl.x, ctl.y, ctl.z)
		var ev: Array = boss.tick(null, {"tick": i + 1, "player_position": feet,
			"boss_position": boss_pos})
		for e in ev:
			if str(e["kind"]) == "boss_projectile_hit_player" \
					and str(e["attack"]) == "bowling_ball":
				return true
	return false


func _bowling_ball(f: Array[String]) -> void:
	if _ball_run(f, true):
		f.append("bowling ball: a well-timed jump did not clear the ball")
	if not _ball_run(f, false):
		f.append("bowling ball: standing still was not hit")


# ---- 3. the green_fn against the real controller ----------------------------------

## Runs the fight until a green_fn hits or the bound expires. `dodge` is the bot: it
## strafes sideways from the moment the shot is released.
func _green_run(f: Array[String], dodge: bool) -> bool:
	var rig := _rig()
	if rig.is_empty():
		f.append("green_fn: the arena rig failed to build")
		return false
	var boss: RefCounted = rig["boss"]
	var ctl: RefCounted = rig["ctl"]
	var w: Dictionary = rig["w"]
	var boss_pos: Vector3 = rig["boss_pos"]
	var released := false
	for i in 300:
		var move_x := 1 if dodge and released else 0
		ctl.step(DT, {"buttons": 0, "move_x": move_x, "move_z": 0}, w)
		var feet := Vector3(ctl.x, ctl.y, ctl.z)
		var ev: Array = boss.tick(null, {"tick": i + 1, "player_position": feet,
			"boss_position": boss_pos})
		for e in ev:
			var kind := str(e["kind"])
			if kind == "boss_projectile_spawned" and str(e["attack"]) == "green_fn":
				released = true
			if kind == "boss_projectile_hit_player" and str(e["attack"]) == "green_fn":
				return true
	return false


func _green_fn(f: Array[String]) -> void:
	if _green_run(f, true):
		f.append("green_fn: a sideways dodge did not clear the shot")
	if not _green_run(f, false):
		f.append("green_fn: standing still was not hit")


# ---- 4. any hit kills, and Peter laughs -------------------------------------------

## Enters the level-10 arena through the real World (the framework's own flow: collect
## every black gift but the last, then take the last one). Fixture only - the assertions
## about the teleport and the win flow belong to test_boss_framework.gd.
func _arena(f: Array[String], seed_value: int = -1) -> Node3D:
	var world := World.new()
	world.atmosphere = false
	if seed_value < 0:
		seed_value = _plain_seed()
	if not world.build(seed_value, 10, {"class": "dasher", "votes": {}, "curses": {},
			"stacks": {}, "purse": 35}):
		f.append("level 10 failed to build")
		world.free()
		return null
	var gifts: RefCounted = world.lstate.gifts
	var slots: Array[int] = []
	for i in gifts.slots.size():
		if gifts.is_real(i):
			slots.append(i)
	var final_id: int = slots.pop_back()
	for i in slots:
		gifts.collect(i, 0, 0, [])
	world.step(DT, IDLE)
	var slot: Vector3 = gifts.slot_pos(final_id)
	world.ctl.x = slot.x
	world.ctl.y = slot.y - 1.0
	world.ctl.z = slot.z
	world.ctl.vy = 0.0
	world.step(DT, IDLE)
	if not world.lstate.boss.arena_entered:
		f.append("the last black gift did not enter the boss arena")
		world.free()
		return null
	return world


func _hit_kills_and_laughs(f: Array[String]) -> void:
	var world := _arena(f)
	if world == null:
		return
	var boss: RefCounted = world.lstate.boss
	var deaths: Array[Dictionary] = []
	world.run_over.connect(func(info: Dictionary) -> void: deaths.append(info))
	var laughed := false
	for i in 300:
		world.step(DT, IDLE)
		for e in world.last_events:
			if str(e.get("kind", "")) == "boss_laugh":
				laughed = true
		if world.ctl.dead:
			break
	if not world.ctl.dead:
		f.append("a real boss attack did not kill a standing player")
	elif deaths.size() != 1 or str(deaths[0]["killer"]) != "Peter Griffin":
		f.append("the boss hit did not produce exactly one Peter Griffin death")
	if not laughed:
		f.append("the boss hit did not fire boss_laugh")
	if int(boss.laugh_ticks) <= 0:
		f.append("boss_laugh did not arm laugh_ticks")
	world.free()


# ---- 5. the Bankai easter egg -----------------------------------------------------

## The event stream of a whole Bankai fight, as strings, for the replay comparison.
func _bankai_trace(seed_value: int) -> Array[String]:
	var trace: Array[String] = []
	var boss := Boss.new()
	boss.start(seed_value, 10)
	var end_tick := int(boss.config["bankai"]["end_tick"])
	for i in end_tick + 5:
		var ev: Array = boss.tick(null, {"tick": i + 1, "player_position": Vector3.ZERO,
			"boss_position": Vector3.ZERO})
		for e in ev:
			trace.append("%d:%s" % [i + 1, str(e["kind"])])
		if i % 60 == 0:
			trace.append("h%d:%d" % [i, boss.hp])
	return trace


func _bankai(f: Array[String]) -> void:
	var seed_value := _bankai_seed()
	if seed_value < 0:
		f.append("no seed in 4096 selected the Bankai")
		return
	# the roll is deterministic across seeds and replays
	for s in 64:
		var a := Boss.new()
		var b := Boss.new()
		a.start(s, 10)
		b.start(s, 10)
		if a.bankai_selected != b.bankai_selected or a.bankai_active != b.bankai_active:
			f.append("seed %d changed its Bankai roll or activation in replay" % s)
			return
	var first := _bankai_trace(seed_value)
	var second := _bankai_trace(seed_value)
	if first.is_empty() or first != second:
		f.append("the Bankai fight did not replay identically")
		return
	# the kill path
	var boss := Boss.new()
	boss.start(seed_value, 10)
	var full := int(boss.config["hp"])
	if not boss.bankai_active or boss.hp != full:
		f.append("a selected Bankai did not start active at full HP")
		return
	var hit_tick := int(boss.config["bankai"]["hit_tick"])
	var end_tick := int(boss.config["bankai"]["end_tick"])
	var killed_at := -1
	var finished_at := -1
	for i in end_tick + 5:
		var ev: Array = boss.tick(null, {"tick": i + 1, "player_position": Vector3.ZERO,
			"boss_position": Vector3.ZERO})
		for e in ev:
			var kind := str(e["kind"])
			if kind == "bankai_hit":
				killed_at = i + 1
			if kind == "bankai_finished":
				finished_at = i + 1
	if killed_at != hit_tick:
		f.append("the Bankai killed at tick %d, want %d" % [killed_at, hit_tick])
	if not boss.dead or boss.hp != 0:
		f.append("the Bankai did not insta-kill Peter from %d HP" % full)
	if finished_at != end_tick:
		f.append("the Bankai finished at tick %d, want %d" % [finished_at, end_tick])


# ---- 6. a real record/replay ------------------------------------------------------

## A seed whose fight IS the easter egg. The roll is 1/1000, so this scans a bounded range
## and gives up rather than looping forever.
static func _bankai_seed() -> int:
	for s in 4096:
		var probe := Boss.new()
		probe.start(s, 10)
		if probe.bankai_selected:
			return s
	return -1


## A REAL record/replay, the shape the replay system itself uses (see test_replay.gd): run
## one records every command it issued, run two feeds that captured stream back verbatim,
## and the state hash must agree at every checkpoint. Two scripted runs regenerating the
## same formula is not the same proof - this one replays the recorded stream, so a command
## that is not captured, or a sim field that is not hashed, shows up as a divergence.
func _record_and_replay(f: Array[String], bankai: bool) -> void:
	var recorded: Array = []
	var first := _replay_run(f, bankai, recorded, true)
	if first.is_empty():
		return
	var second := _replay_run(f, bankai, recorded, false)
	if first != second:
		f.append("the %s boss fight diverged when its recorded commands were replayed"
			% ("Bankai" if bankai else "ordinary"))


## One leg of the pair. `record` true captures the command stream; false replays it. The
## zig-zag keeps the player alive through several attack cycles, so the hash covers live
## projectiles, the cooldown and the attack index, not just the arena entry. The Bankai leg
## runs past the kill tick so the Bankai clock and the death are inside the hashed span.
func _replay_run(f: Array[String], bankai: bool, recorded: Array, record: bool) -> Array[String]:
	var trace: Array[String] = []
	var seed_value := _bankai_seed() if bankai else _plain_seed()
	if seed_value < 0:
		f.append("no seed in 4096 selected the Bankai")
		return trace
	var world := _arena(f, seed_value)
	if world == null:
		return trace
	var state := RunState.new_run(seed_value, 1, [])
	state.level_number = 10
	state.level = world.lstate
	var span := 240
	if bankai:
		span = int(world.lstate.boss.config["bankai"]["hit_tick"]) + 30
	for i in span:
		var command: Dictionary
		if record:
			var move_x := 1 if (i / 60) % 2 == 0 else -1
			command = {"buttons": 0, "move_x": move_x, "move_z": 0}
			recorded.append(command.duplicate())
		else:
			if i >= recorded.size():
				f.append("the recorded command stream ran out at tick %d" % i)
				break
			command = recorded[i]
		world.step(DT, command)
		if i % 30 == 0:
			trace.append(StateHash.sha256(state))
		if world.ctl.dead:
			break
	trace.append(StateHash.sha256(state))
	world.free()
	return trace
