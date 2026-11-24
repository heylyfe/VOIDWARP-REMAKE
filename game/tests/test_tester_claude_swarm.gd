extends RefCounted
#
# test_tester_claude_swarm.gd - cycle 8, U2b (D-T2-13): the tester-spawned clawd swarm.
#
# Terra's cycle-8 finding 1 (verbatim): "tester-spawned Claude lacks the swarm on a level
# that did not already vote for him." The panel spawns a bare enemy_runtime row; the swarm
# only ever attached from the voted plan at world.build() (the D-T4-2 leg), so
# ClawdsScript.tick skipped a null lv.clawds and no anger timer ever ran. The fix this
# suite pins is the app-layer entry point world.tester_spawn_enemy(id, at): it spawns
# the row the panel's own path produces AND queues the swarm attach as a WORLD tick job
# (D-T2-13), through the same placement/create/view-setup steps build() itself uses.
#
# Everything here runs the REAL world and the REAL sim - WorldScript.build() levels, real
# world.step() ticks, no stub. Legs:
#   A  outside a live level the entry returns false and changes nothing;
#   B  the spine: a level whose votes carry NO swarm-bearing entry (empty votes, so the
#      level plans no enemy of its own), one tester spawn of the swarm owner, and after
#      ONE tick the swarm EXISTS - non-null, the body count the owner's own clawd_cfg
#      asks for on this level's tile count, spot-for-spot the placement the same pure
#      attach() produces on a duplicate Level dict, and NOT attached before that tick
#      (the attach is queued, not immediate);
#   C  it REALLY ticks, not the null guard's skip: the anger timer climbs EXACTLY one
#      tick per tick; a clawd pickup is OBSERVED through the real clawds.tick (the
#      clawd_collected event in the world's own last_events, the spot taken, remaining
#      down, the timer calmed to 0), then the timer climbs again;
#   D  idempotence: a second owner spawn adds the second body but leaves the swarm
#      OBJECT, its spots and its body count untouched - no job is even queued;
#   E  two registry ids that own no swarm still spawn normally through the entry and
#      never disturb the swarm (ids picked from the live registry, not hardcoded).
#
# tests/ may name content ids (the boundary scan forbids them only in terrain/sim/core/app);
# this suite names the swarm owner because it is exactly the id the ticket names.

const WorldScript := preload("res://app/world.gd")
const ClawdsScript := preload("res://sim/clawds.gd")
const EventsScript := preload("res://sim/events.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const ClaudeScript := preload("res://content/enemies/claude/enemy.gd")

const SWARM_ID := "claude"   # the only roster module that declares clawd_cfg()
const SEED := 7419           # this suite's own scratch seed, distinct from every other run's
const LEVEL := 1
const DT := 1.0 / 60.0
const ANGER_TICKS := 5       # trailing calm ticks in leg C's climb, after the first


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_outside_live_level(f)
	var world = _build(f)
	if world != null:
		_leg_spawn_attach(f, world)
		_leg_really_ticks(f, world)
		_leg_idempotence(f, world)
		_leg_non_swarm_ids(f, world)
		_drop(world)
	return f


# ---- scaffolding ------------------------------------------------------------------------------


## The ledger shape every world test here uses (the app's own handover shape): the run
## carries EMPTY votes, so the level plans no enemy of its own and no voted module can
## attach a swarm - the exact repro the ticket states.
func _ledger() -> Dictionary:
	return {"class": "athletic", "votes": {}, "curses": {}, "stacks": {}, "purse": 0}


func _root() -> Node:
	var ml := Engine.get_main_loop()
	return (ml as SceneTree).root if ml is SceneTree else null


## A REAL level inside the tree, built from the empty-vote ledger. null on failure.
func _build(f: Array[String]):
	var world = WorldScript.new()
	var root := _root()
	if root != null:
		root.add_child(world)
	if not world.build(SEED, LEVEL, _ledger()):
		f.append("world: build(seed=%d, level=%d) failed - the suite cannot run its spine"
			% [SEED, LEVEL])
		_drop(world)
		return null
	return world


func _drop(world) -> void:
	world.teardown()
	if world.get_parent() != null:
		world.get_parent().remove_child(world)
	world.free()


## The first row index carrying this id, or -1.
func _row_of(world, id: String) -> int:
	for i in world.rt.enemies.size():
		if str(world.rt.enemies[i]["id"]) == id:
			return i
	return -1


## A valid standable world point: the top of the tile FARTHEST from the player's spawn
## (the runtime's support pass keeps any real tile; far keeps the spawn away from the
## probe bodies and the probe bodies away from the pickup exercise).
func _far_tile_point(world) -> Vector3:
	var tiles: Array = world.lv["tiles"]
	var px := float(world.ctl.x)
	var pz := float(world.ctl.z)
	var best := 0
	var best_d := -1.0
	for i in tiles.size():
		var t: Array = tiles[i]
		var dx := float(int(t[0])) + 0.5 - px
		var dz := float(int(t[1])) + 0.5 - pz
		var d := dx * dx + dz * dz
		if d > best_d:
			best_d = d
			best = i
	var t: Array = tiles[best]
	return Vector3(float(int(t[0])) + 0.5, float(int(t[2])) * 0.5, float(int(t[1])) + 0.5)


## Spot-for-spot equality of two placement lists (each entry [x, z, y] tile coords).
func _same_spots(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var pa: Array = a[i]
		var pb: Array = b[i]
		if pa.size() != pb.size():
			return false
		for j in pa.size():
			if int(pa[j]) != int(pb[j]):
				return false
	return true


# ---- leg A: outside a live level the entry changes nothing ------------------------------------


func _leg_outside_live_level(f: Array[String]) -> void:
	var world = WorldScript.new()
	if world.tester_spawn_enemy(SWARM_ID, Vector3(0.0, 0.0, 0.0)):
		f.append("dead: tester_spawn_enemy returned true on an unbuilt world with no level - "
			+ "the contract says false, change nothing")
	if world.lstate != null or world.rt != null:
		f.append("dead: the unbuilt world grew level state by itself")
	if not world._tester_jobs.is_empty():
		f.append("dead: the refused spawn left a queued job behind on the unbuilt world")
	world.free()


# ---- leg B: the spawn + the queued attach -----------------------------------------------------


func _leg_spawn_attach(f: Array[String], world) -> void:
	# the repro's ground truth: no votes -> no planned rows, no swarm on the level
	if world.lstate.clawds != null:
		f.append("spawn: the empty-vote level carries a swarm before any tester spawn")
	if not world.rt.enemies.is_empty():
		f.append("spawn: the empty-vote level planned %d rows on its own - the repro is "
			+ "not the one the ticket states" % world.rt.enemies.size())
	var rows_before: int = world.rt.enemies.size()
	var pos := _far_tile_point(world)
	if not world.tester_spawn_enemy(SWARM_ID, pos):
		f.append("spawn: tester_spawn_enemy(claude) refused a spawn on a LIVE level")
	var idx := _row_of(world, SWARM_ID)
	if idx < 0:
		f.append("spawn: no claude row reached the runtime (rows %d -> %d)"
			% [rows_before, world.rt.enemies.size()])
		return
	if rows_before + 1 != world.rt.enemies.size():
		f.append("spawn: the entry added %d rows, want exactly 1"
			% [world.rt.enemies.size() - rows_before])
	# the row shape is the tester's own: the module's behavior, the registry cfg stamped
	# with votes 1 and this level's number (the panel's _cfg_for call shape)
	var row: Dictionary = world.rt.enemies[idx]
	var cfg: Dictionary = row["cfg"]
	if str(cfg.get("id", "")) != SWARM_ID:
		f.append("spawn: the row cfg id is %s, want %s" % [str(cfg.get("id", "")), SWARM_ID])
	if int(cfg.get("votes", -1)) != 1:
		f.append("spawn: the row cfg carries votes %d, want 1 (the panel's own shape)"
			% int(cfg.get("votes", -1)))
	if int(cfg.get("level_number", -1)) != LEVEL:
		f.append("spawn: the row cfg carries level_number %d, want %d"
			% [int(cfg.get("level_number", -1)), LEVEL])
	var module_cfg: Dictionary = ClaudeScript.cfg()
	for key in ["base_speed", "preferred_kind", "death_code"]:
		if str(cfg.get(key, "")) != str(module_cfg.get(key, "")):
			f.append("spawn: row cfg %s is %s, the module's own cfg says %s"
				% [key, str(cfg.get(key, "")), str(module_cfg.get(key, ""))])
	if str(row.get("name", "")) == "":
		f.append("spawn: the row carries no display name")
	# the attach is QUEUED: before the first tick the level still has no swarm
	if world.lstate.clawds != null:
		f.append("spawn: the swarm attached IMMEDIATELY, not through a queued tick job")
	# one real tick: the world's own queue drains at its top, then this same tick's
	# ClawdsScript.tick sees the swarm
	world.step(DT)
	var sw = world.lstate.clawds
	if sw == null:
		f.append("spawn: one tick past the tester spawn the level STILL carries no swarm "
			+ "(clawds.gd's null guard would skip every tick)")
		return
	# the body count the owner's own clawd_cfg asks for on this level's tile count
	var clawd_cfg: Dictionary = ClaudeScript.clawd_cfg()
	var want: int = ClawdsScript.count_for_tiles(ClawdsScript.resolve_cfg(clawd_cfg),
		(world.lv["tiles"] as Array).size())
	if sw.count() != want:
		f.append("spawn: the swarm holds %d clawds, the module's clawd_cfg asks for %d "
			+ "on this level's %d tiles"
			% [sw.count(), want, (world.lv["tiles"] as Array).size()])
	if sw.remaining() != sw.count():
		f.append("spawn: %d of the clawds are already taken with no player walk"
			% [sw.count() - sw.remaining()])
	# the placement is the same PURE function build() binds: a duplicate Level dict,
	# attach()'d again, must produce the same spots spot-for-spot
	var dup: Dictionary = world.lv.duplicate(true)
	ClawdsScript.attach(dup, clawd_cfg)
	if not _same_spots((dup["clawds"] as Dictionary)["spots"], sw.spots):
		f.append("spawn: the tester attach placed different spots than the build-time "
			+ "placement path produces for the same Level dict")
	# the view-setup path ran on the swarm: the level-wide view exists and drew the bodies
	if world.clawd_view == null:
		f.append("spawn: the level-wide clawd view is missing after the attach tick")
	else:
		var vroot = world.clawd_view.get("_root")
		if vroot == null or vroot.get_child_count() < 1:
			f.append("spawn: the clawd view drew nothing for the attached swarm")
	# the same tick already ticked it: the anger timer moved on the tick the swarm was
	# attached, the null guard's skip signature would leave it at 0
	if sw.anger_ticks != 1:
		f.append("spawn: the attach tick left anger_ticks at %d, want 1 (the tick really "
			+ "ran - anything else is the null guard's skip)" % sw.anger_ticks)


# ---- leg C: the swarm really ticks - anger climb, pickup, resumption ---------------------------


func _leg_really_ticks(f: Array[String], world) -> void:
	var sw = world.lstate.clawds
	if sw == null:
		return   # leg B already reported the missing swarm
	# the player's spot, snapshotted BEFORE the climb: the climb's own assertions prove
	# it is clear of every untaken clawd (any pickup would stall the timer and drop
	# remaining), so restoring it after the pickup resumes a provably calm climb
	var home := Vector3(float(world.ctl.x), float(world.ctl.y), float(world.ctl.z))
	# the calm climb: ANGER_TICKS real ticks, no pickup (the player stands at the snapshot)
	# - each step climbed the timer exactly once, to 1 from the attach tick + ANGER_TICKS
	for _i in ANGER_TICKS:
		world.step(DT)
	if sw.anger_ticks != 1 + ANGER_TICKS:
		f.append("tick: after %d calm ticks anger_ticks is %d, want %d - the timer is not "
			+ "advancing once per tick" % [ANGER_TICKS, sw.anger_ticks, 1 + ANGER_TICKS])
	if sw.remaining() != sw.count():
		f.append("tick: %d clawds vanished with the player never leaving the spawn"
			% [sw.count() - sw.remaining()])
	# the pickup: stand the player ON an untaken spot, step once, and the real
	# clawds.tick collects it (pickup pass first, timer calmed, event in the world's
	# own list)
	var spot := -1
	for i in sw.spots.size():
		if not sw.is_taken(i):
			spot = i
			break
	if spot < 0:
		f.append("tick: no untaken clawd to pick up")
		return
	var before_taken: int = sw.count() - sw.remaining()
	var p: Vector3 = sw.spot_pos(spot)
	world.ctl.x = p.x
	world.ctl.y = p.y - 0.9    # clawds.gd's own test point: feet + 0.9 u
	world.ctl.z = p.z
	world.step(DT)
	var got_event := false
	for e in world.last_events:
		if e is Dictionary and str(e.get("type", "")) == EventsScript.EV_CLAWD_COLLECTED:
			got_event = true
			if int(e.get("clawd", -1)) != spot:
				f.append("tick: the pickup event names clawd %d, the player stood on %d"
					% [int(e.get("clawd", -1)), spot])
			if int(e.get("remaining", -1)) != sw.remaining():
				f.append("tick: the pickup event's remaining is stale (%d vs %d)"
					% [int(e.get("remaining", -1)), sw.remaining()])
	if not got_event:
		f.append("tick: no clawd_collected event in the world's own events after standing "
			+ "on the spot - the pickup pass never ran")
	if not sw.is_taken(spot):
		f.append("tick: spot %d is not taken after standing on it" % spot)
	var taken_now: int = sw.count() - sw.remaining()
	if taken_now < before_taken + 1:
		f.append("tick: remaining did not drop (taken %d -> %d)" % [before_taken, taken_now])
	if sw.anger_ticks != 0:
		f.append("tick: the pickup left anger_ticks at %d, want 0 (collecting CALMS)"
			% sw.anger_ticks)
	# the resumption: back at the proven-clear snapshot, the timer climbs again
	world.ctl.x = home.x
	world.ctl.y = home.y
	world.ctl.z = home.z
	world.step(DT)
	world.step(DT)
	if sw.anger_ticks != 2:
		f.append("tick: after the pickup the timer resumed to %d, want 2 ticks" % sw.anger_ticks)


# ---- leg D: idempotence - a second owner spawn never duplicates the swarm ----------------------


func _leg_idempotence(f: Array[String], world) -> void:
	var sw = world.lstate.clawds
	if sw == null:
		return   # leg B already reported the missing swarm
	var count_before: int = sw.count()
	var taken_before: int = sw.count() - sw.remaining()
	var spots_before: Array = sw.spots.duplicate(true)
	var rows_before: int = world.rt.enemies.size()
	var pos := _far_tile_point(world)
	if not world.tester_spawn_enemy(SWARM_ID, pos):
		f.append("again: the second tester spawn of the owner was refused")
	if rows_before + 1 != world.rt.enemies.size():
		f.append("again: the second spawn added %d rows, want exactly 1"
			% [world.rt.enemies.size() - rows_before])
	# a claude row (still) exists - the spawn half worked; the swarm half did nothing
	var clones := 0
	for row in world.rt.enemies:
		if str(row["id"]) == SWARM_ID:
			clones += 1
	if clones != 2:
		f.append("again: %d owner rows on the runtime, want 2" % clones)
	if not world._tester_jobs.is_empty():
		f.append("again: the second spawn queued a swarm job even though the swarm exists")
	world.step(DT)
	if world.lstate.clawds != sw:
		f.append("again: the second spawn REPLACED the swarm object")
	if sw.count() != count_before:
		f.append("again: the body count changed %d -> %d" % [count_before, sw.count()])
	if sw.count() - sw.remaining() != taken_before:
		f.append("again: the taken count changed %d -> %d"
			% [taken_before, sw.count() - sw.remaining()])
	if not _same_spots(spots_before, sw.spots):
		f.append("again: the spots changed on the second spawn")


# ---- leg E: non-swarm registry ids still spawn normally ---------------------------------------


func _leg_non_swarm_ids(f: Array[String], world) -> void:
	var sw = world.lstate.clawds
	if sw == null:
		return   # leg B already reported the missing swarm
	var count_before: int = sw.count()
	var api = world._api
	if api == null:
		f.append("plain: the world's content registry is down")
		return
	var picked: Array[String] = []
	for id in api.enemy_ids():
		if str(id) == SWARM_ID:
			continue
		var K = load("res://content/enemies/%s/enemy.gd" % str(id))
		if K != null and K.has_method("clawd_cfg"):
			continue   # a second swarm owner would be one more day's ticket
		picked.append(str(id))
		if picked.size() == 2:
			break
	if picked.size() < 2:
		f.append("plain: the registry offered fewer than two non-swarm ids")
		return
	for id in picked:
		var rows_before: int = world.rt.enemies.size()
		var pos := _far_tile_point(world)
		if not world.tester_spawn_enemy(id, pos):
			f.append("plain: tester_spawn_enemy(%s) was refused on a live level" % id)
			continue
		if _row_of(world, id) < 0:
			f.append("plain: %s never reached the runtime (rows %d -> %d)"
				% [id, rows_before, world.rt.enemies.size()])
		world.step(DT)
		if world.lstate.clawds != sw:
			f.append("plain: spawning %s replaced the swarm object" % id)
		if sw.count() != count_before:
			f.append("plain: spawning %s changed the swarm body count to %d"
				% [id, sw.count()])
		if not world._tester_jobs.is_empty():
			f.append("plain: spawning %s queued a tick job (want none)" % id)
