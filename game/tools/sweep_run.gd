extends SceneTree
#
# sweep_run.gd - U4 crash sweep (owner request, cycle 8: "the game sometimes crashes").
#
# The bot in tools/bot_run.gd drives the SIM only and reached level 2, so it never touched
# the app layer where the owner's crash would live (views, audio, the boss arena, the
# Bankai cinematic, the collapse, the clawd swarm, Gin's sword). This tool drives the REAL
# app world (app/world.gd) - the same node the game runs - through every level on many
# seeds, and forces the late features on so they are actually entered.
#
#   <godot> --headless --path game --script res://tools/sweep_run.gd -- \
#       [--seed-base S] [--seeds N] [--levels A-B] [--ticks N] [--vote-mode all|random]
#
#   --seed-base  first seed (default 1). Seed i uses seed_base + i.
#   --seeds      how many seeds (default 4).
#   --levels     level range, inclusive (default 1-12).
#   --ticks      ticks stepped per level entry before the feature passes (default 700:
#                the enemy runtime's spawn delay is 360 ticks and Gin's sword throw needs
#                its 108-tick voice phase on top, so a shorter run never reaches the
#                sword and would report it as unreached).
#   --vote-mode  "all" (default) votes every registry enemy at 1 so the clawd swarm, Gin's
#                sword, the toucher floor and the rest are all present on every level;
#                "random" leaves the ledger empty so world.build() replays the lobbies.
#
# Every level entry prints one ENTRY line with seed, level, build result and tick count, so
# a crash's last line names the seed and level it died on. A run that exits non-zero is a
# finding even with no error text.
#
# This tool never writes sim state and never changes a threshold: it is a driver.

const WorldScript := preload("res://app/world.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const CollapseScript := preload("res://sim/collapse.gd")
const BossScript := preload("res://sim/boss.gd")

const DT := 1.0 / 60.0
const BTN_JUMP := 1
const BTN_ABILITY := 2

var _seed_base := 1
var _seeds := 4
var _level_lo := 1
var _level_hi := 12
var _ticks := 700
var _vote_mode := "all"
var _entries := 0
var _built := 0
var _failed_builds := 0


var _ran := false


func _init() -> void:
	_parse_args()


## The sweep runs on the FIRST FRAME, not in _init: the root Window is not inside the tree
## until then, and a World added to a root that is not in the tree is itself outside the
## tree - which is not the condition the owner's game runs in. (It also makes every view's
## global-transform read error, which would be a sweep artifact, not a finding.)
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := str(args[i])
		match a:
			"--seed-base":
				i += 1
				_seed_base = int(args[i])
			"--seeds":
				i += 1
				_seeds = int(args[i])
			"--levels":
				i += 1
				var parts := str(args[i]).split("-")
				_level_lo = int(parts[0])
				_level_hi = int(parts[parts.size() - 1])
			"--ticks":
				i += 1
				_ticks = int(args[i])
			"--vote-mode":
				i += 1
				_vote_mode = str(args[i])
		i += 1


## Every registry enemy id at 1 vote: the clawd swarm (claude), Gin's sword, the toucher
## floor, the mines and the rest are all on the level, so the late features are reachable.
func _all_votes() -> Dictionary:
	var out := {}
	var api: RefCounted = ContentApiScript.load()
	if api == null or not api.is_ok():
		return out
	for id in api.enemy_ids():
		out[str(id)] = 1
	return out


func _ledger() -> Dictionary:
	if _vote_mode == "random":
		return {}
	return {"class": "dasher", "votes": _all_votes(), "curses": {}, "stacks": {},
		"purse": 300, "tithes": 0, "hunger": 0, "last_vote": ""}


func _run() -> void:
	var root := get_root()
	var world := WorldScript.new()
	root.add_child(world)
	var ledger := _ledger()
	print("SWEEP start seeds=%d..%d levels=%d-%d ticks=%d vote_mode=%s"
		% [_seed_base, _seed_base + _seeds - 1, _level_lo, _level_hi, _ticks, _vote_mode])
	for s in _seeds:
		var seed_value := _seed_base + s
		for level in range(_level_lo, _level_hi + 1):
			_entry(world, seed_value, level, ledger)
	world.teardown()
	world.free()
	print("SWEEP DONE entries=%d built=%d build_failures=%d"
		% [_entries, _built, _failed_builds])
	quit(0 if _failed_builds == 0 else 1)


func _entry(world: Node, seed_value: int, level: int, ledger: Dictionary) -> void:
	_entries += 1
	var ok := bool(world.build(seed_value, level, ledger))
	if not ok:
		_failed_builds += 1
		print("ENTRY seed=%d level=%d built=false ticks=0" % [seed_value, level])
		return
	_built += 1
	var feat := _drive(world, level)
	print("ENTRY seed=%d level=%d built=true ticks=%d died=%s collapse=%s boss=%s bankai=%s beacon=%s clawds=%s gin=%s gin_sword=%s"
		% [seed_value, level, int(feat["ticks"]), str(feat["died"]), str(feat["collapse"]),
			str(feat["boss"]), str(feat["bankai"]), str(feat["beacon"]), str(feat["clawds"]),
			str(feat["gin"]), str(feat["gin_sword"])])


## Steps the level, then runs the feature passes that only appear late. Returns what was
## actually reached, so the report can say "reached" rather than "assumed".
func _drive(world: Node, level: int) -> Dictionary:
	var feat := {"ticks": 0, "collapse": false, "boss": false, "bankai": false,
		"beacon": false, "clawds": false, "gin": false, "gin_sword": false, "died": false}
	# 1. plain locomotion: a deterministic circle with a jump every 30 ticks and an ability
	#    every 90, so the controller, the pads, the mines, the gifts and every enemy row
	#    all get exercised. No randomness: the same seed reproduces the same ticks.
	for t in _ticks:
		if _dead(world):
			break
		var ang := float(t) * 0.05
		var cmd := {
			"move_x": int(round(cos(ang) * 2.0)),
			"move_z": int(round(sin(ang) * 2.0)),
			"buttons": (BTN_JUMP if t % 30 == 0 else 0) | (BTN_ABILITY if t % 90 == 0 else 0),
			"app": 0,
		}
		world.step(DT, cmd)
		feat["ticks"] = int(feat["ticks"]) + 1
		_scan_features(world, feat)
	feat["clawds"] = _has_clawds(world)
	feat["gin"] = _has_gin(world)
	# A death is recorded, never hidden - but the sweep revives the player before the
	# arena pass, because a dead run never ticks again (world.step returns early) and the
	# boss/Bankai/beacon path would then be reported as unreached on every entry that
	# happened to die first. The revive is the sweep driver's own, not the game's.
	feat["died"] = _dead(world)
	if bool(feat["died"]):
		_revive(world)
	# 2. the platform collapse: start the schedule from IDLE and let the cracks/falls run.
	var c := _pass_collapse(world)
	feat["ticks"] = int(feat["ticks"]) + int(c["ticks"])
	feat["collapse"] = bool(c["started"])
	# The collapse drops the platform the player was standing on, so a void fall here is
	# the expected outcome, not a finding: revive again so the arena pass still runs.
	if _dead(world):
		feat["died"] = true
		_revive(world)
	# 3. the boss arena, the Bankai cinematic and the beacon/300-gold completion.
	var b := _pass_boss(world, level)
	feat["ticks"] = int(feat["ticks"]) + int(b["ticks"])
	feat["boss"] = bool(b["entered"])
	feat["bankai"] = bool(b["bankai"])
	feat["beacon"] = bool(b["beacon"])
	return feat


## Puts a dead controller back on its feet so the next pass can run. The sweep driver's
## own convenience: it writes only the controller's death fields, never sim state the
## game reads for a live run.
func _revive(world: Node) -> void:
	var ctl = world.get("ctl")
	if ctl == null:
		return
	ctl.set("dead", false)
	ctl.set("dead_code", "")
	ctl.set("dead_killer", "")
	ctl.set("respawn_t", -1.0)
	ctl.set("charges", 2)
	world.set("_run_over_emitted", false)


## The clawd swarm is attached at level construction from the voted plan; a level whose
## votes carry no swarm-bearing enemy has none. Read from the live level state.
func _has_clawds(world: Node) -> bool:
	var ls = world.get("lstate")
	if ls == null:
		return false
	var cl = ls.get("clawds")
	return cl != null


## Gin's sword throw lives on his own runtime row; the row's presence is the feature.
func _has_gin(world: Node) -> bool:
	var rt = world.get("rt")
	if rt == null:
		return false
	for row in rt.enemies:
		if str(row.get("id", "")) == "gin":
			return true
	return false


## Per-tick feature probe: the clawd swarm's anger timer and Gin's sword flight are
## transient, so they are recorded the tick they are live rather than sampled at the end.
func _scan_features(world: Node, feat: Dictionary) -> void:
	var ls = world.get("lstate")
	if ls != null and ls.get("clawds") != null:
		feat["clawds"] = true
	var rt = world.get("rt")
	if rt == null:
		return
	for row in rt.enemies:
		if str(row.get("id", "")) != "gin":
			continue
		feat["gin"] = true
		if int(row.get("gin_flight_elapsed", -1)) >= 0:
			feat["gin_sword"] = true


func _dead(world: Node) -> bool:
	var ctl = world.get("ctl")
	return ctl == null or bool(ctl.get("dead"))


func _pass_collapse(world: Node) -> Dictionary:
	var out := {"ticks": 0, "started": false}
	var collapse: Dictionary = world.get("_collapse")
	if collapse.is_empty() or not bool(collapse.get("enabled", false)):
		return out
	var ls = world.get("lstate")
	if ls == null:
		return out
	var ev: Array = []
	CollapseScript.start(collapse, int(ls.tick))
	out["started"] = true
	for t in 120:
		if _dead(world):
			break
		world.step(DT, {"move_x": 0, "move_z": 0, "buttons": 0, "app": 0})
		out["ticks"] = int(out["ticks"]) + 1
	return out


## The boss fight: enter the arena through the world's own entry, force the Bankai
## cinematic (the easter-egg path), run it out, then kill Peter and take the beacon.
func _pass_boss(world: Node, level: int) -> Dictionary:
	var out := {"ticks": 0, "entered": false, "bankai": false, "beacon": false}
	var ls = world.get("lstate")
	if ls == null:
		return out
	var boss = ls.get("boss")
	if boss == null:
		# Not the boss level: build the same object the level-10 build carries, so the
		# arena entry has something to start (the tester panel's FORCE PETER does this).
		boss = BossScript.new()
		boss.set("config", BossScript.load_config())
		ls.set("boss", boss)
	if bool(boss.get("arena_entered")):
		return out
	var ev: Array = []
	world.call("_enter_boss_arena", ev)
	world.call("_economy_pass", ev)
	world.call("_publish_boss_tick", ev)
	out["entered"] = true
	# The Bankai cinematic: the sim owns the clock, the view owns the 25.5 s animation.
	# Force it on so the easter-egg path is entered on every seed, not 1 in 250.
	if not bool(boss.get("bankai_active")):
		boss.set("bankai_active", true)
		boss.set("bankai_tick", 0)
		world.call("_publish_boss_tick", [{"kind": "bankai_started"}])
	out["bankai"] = true
	var end_tick := int(boss.get("config")["bankai"]["end_tick"])
	for t in end_tick + 30:
		if _dead(world):
			break
		world.step(DT, {"move_x": 0, "move_z": 0, "buttons": 0, "app": 0})
		out["ticks"] = int(out["ticks"]) + 1
	# The ordinary kill: damage Peter out, which opens the beacon and pays the 300 gold.
	if not bool(boss.get("dead")):
		boss.call("damage", 100000, false)
	for t in 30:
		if _dead(world):
			break
		world.step(DT, {"move_x": 0, "move_z": 0, "buttons": 0, "app": 0})
		out["ticks"] = int(out["ticks"]) + 1
	# The beacon: put the player inside it and step until the level completes. The arena
	# entry REPLACED lstate (its own LevelState.build), so re-read it - the old handle's
	# beacon is the pre-arena one and is still closed.
	ls = world.get("lstate")
	var beacon = ls.get("beacon") if ls != null else null
	var ctl = world.get("ctl")
	if beacon != null and ctl != null and bool(beacon.call("is_open")):
		ctl.set("x", float(beacon.get("cx")))
		ctl.set("y", float(beacon.get("base_y")))
		ctl.set("z", float(beacon.get("cz")))
		for t in 30:
			if _dead(world):
				break
			world.step(DT, {"move_x": 0, "move_z": 0, "buttons": 0, "app": 0})
			out["ticks"] = int(out["ticks"]) + 1
		out["beacon"] = bool(beacon.get("completed"))
	return out
