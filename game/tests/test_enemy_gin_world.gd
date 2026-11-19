extends RefCounted
#
# W12-B - gin ichimaru through the REAL run loop: world.build() + world.step().
#
# test_enemy_gin.gd drives the behavior's tick() by hand (beh.tick); nothing
# there goes through rt.step or a real world, so nothing proves the void zone
# actually ends a run. This file does: a level-17 world with gin voted into
# the run (the lobby's carried ledger shape), stepped until the
# mark -> zone cycle runs through world.step(). Last Light is pre-spent
# (D-057) so the zone's kill is a real death, not a save.
#
#   KILL leg      - the player, parked on a real floor tile (the spawn sits on
#                   the monument cell, which the mark always cuts out of the
#                   patch, so the player is stepped onto an ordinary tile at
#                   build), is caught by the void zone: death code D-GIN,
#                   killer gin, and the four pre-kill cues logged by the
#                   world's own telegraph view in order
#                   (crack_rumble < shing == whoosh < zone_open).
#   SURVIVOR leg  - the OTHER half of the assertion, the negative control:
#                   the identical build, but once the mark lands the player
#                   is moved onto a floor tile outside the 5x5 patch. The
#                   zone opens and closes and the player is never harmed;
#                   all five cues fire in order (zone_close last).
#   ABSENT twin   - the same build with no votes at all: no enemy, no cue,
#                   never a death.
#
# Negative control (test_app_enemy_views.gd's pattern): every assertion set is
# ALSO run against the twin that lacks the thing; those failures are counted
# and printed. The test fails if any control passes.

const WorldScript := preload("res://app/world.gd")

const SEED := 1
const LEVEL := 17
const DT := 1.0 / 60.0
const KILL_MAX := 900        # spawn delay 360 + fade 30 + mark 120 + launch 18 = 528
const EXIT_MAX := 1400       # through the 600-tick zone plus the 30-tick fade back

var negative_failures := 0


func run() -> Array[String]:
	var f: Array[String] = []
	var neg := _leg(f)
	print("NEGATIVE CONTROL failures=%d per leg %s" % [neg, str({"gin": neg})])
	return f


# ---- the two world twins -----------------------------------------------------

func _ledger(votes: Dictionary) -> Dictionary:
	return {"class": "dasher", "votes": votes, "curses": {}, "stacks": {},
			"purse": 0, "tithes": 0, "hunger": 0, "last_vote": ""}


func _build(votes: Dictionary):
	var world = WorldScript.new()
	if not world.build(SEED, LEVEL, _ledger(votes)):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		world.teardown()
		world.free()


# The monument cell the level spawns the player onto (collision's default
# dais): the mark always cuts it out of the patch, so a run parked there is
# unkillable by construction. Read it off the collision world, not a literal.
func _dais_cell(world) -> Vector2i:
	var d: Array = world.rt.world.get("dais", [1, 1, 1])
	return Vector2i(int(d[0]), int(d[1]))


func _first_tile_away(world, from: Vector2i, chebyshev: int) -> Dictionary:
	for t in world.lv["tiles"]:
		var dx := absi(int(t[0]) - from.x)
		var dz := absi(int(t[1]) - from.y)
		if maxi(dx, dz) < chebyshev:
			continue
		return {"x": int(t[0]), "y": int(t[2]), "z": int(t[1])}
	return {}


func _park(world, tile: Dictionary) -> void:
	world.ctl.x = float(tile["x"]) + 0.5
	world.ctl.y = float(tile["y"]) * 0.5
	world.ctl.z = float(tile["z"]) + 0.5
	world.ctl.vx = 0.0
	world.ctl.vy = 0.0
	world.ctl.vz = 0.0
	world.ctl.cur_key = "%d,%d,%d" % [int(tile["x"]), int(tile["z"]), int(tile["y"])]


# Park the player on an ordinary floor tile (Chebyshev >= 2 from the monument),
# so the marked patch centres on a tile that is NOT cut out of it.
func _park_off_dais(world) -> bool:
	var dais: Vector2i = _dais_cell(world)
	var tile: Dictionary = _first_tile_away(world, dais, 2)
	if tile.is_empty():
		return false
	_park(world, tile)
	return true


# Move the player onto a floor tile outside the 5x5 patch (Chebyshev >= 3 from
# its centre). Called once the mark lands, when the patch is final.
func _park_outside(world, patch: Dictionary) -> bool:
	var centre := Vector2i(int(patch.get("cx", 0)), int(patch.get("cz", 0)))
	var tile: Dictionary = _first_tile_away(world, centre, 3)
	if tile.is_empty():
		return false
	_park(world, tile)
	return true


func _gin_row(world) -> Dictionary:
	for row in world.rt.enemies:
		if str(row.get("id", "")) == "gin":
			return row
	return {}


func _cue_tick(world, cue: String) -> int:
	for e in world.telegraph_view.cue_log:
		if str(e.get("cue", "")) == cue:
			return int(e.get("tick", -1))
	return -1


func _cue_seen(world, cue: String) -> bool:
	return _cue_tick(world, cue) >= 0


# The four cues the world logs before the kill tick must fire in order:
# crack_rumble (the mark) -> shing / whoosh (the launch) -> zone_open (the zone).
func _assert_pre_kill_cues(world, errs: Array[String]) -> void:
	var crack := _cue_tick(world, "crack_rumble")
	var shing := _cue_tick(world, "shing")
	var whoosh := _cue_tick(world, "whoosh")
	var open_ := _cue_tick(world, "zone_open")
	for pair in [["crack_rumble", crack], ["shing", shing], ["whoosh", whoosh], ["zone_open", open_]]:
		if int(pair[1]) < 0:
			errs.append("gin: %s never logged by the world's cue view" % str(pair[0]))
	if crack >= 0 and shing >= 0 and crack >= shing:
		errs.append("gin: crack_rumble (tick %d) not before shing (tick %d)" % [crack, shing])
	if shing >= 0 and open_ >= 0 and shing > open_:
		errs.append("gin: shing (tick %d) after zone_open (tick %d)" % [shing, open_])
	if whoosh >= 0 and open_ >= 0 and whoosh > open_:
		errs.append("gin: whoosh (tick %d) after zone_open (tick %d)" % [whoosh, open_])


# The kill expectations. Used twice: appended to the failures when the thing
# is present, counted (not appended) when the thing is absent.
func _kill_expect(world) -> Array[String]:
	var errs: Array[String] = []
	world.ctl.last_light_spent = true   # D-057: otherwise the save masks the kill
	if not _park_off_dais(world):
		errs.append("gin: no ordinary floor tile found away from the spawn monument")
		return errs
	var zone_seen := false
	var steps := 0
	while steps < KILL_MAX and not bool(world.ctl.dead):
		world.step(DT)
		steps += 1
		var row: Dictionary = _gin_row(world)
		if not row.is_empty() and str(row.get("phase", "")) == "void":
			zone_seen = true
	if not zone_seen and not bool(world.ctl.dead):
		errs.append("gin: the zone never opened within %d steps" % KILL_MAX)
	if not bool(world.ctl.dead):
		errs.append("gin: the void zone did not kill the parked player")
		return errs
	if str(world.ctl.dead_code) != "D-GIN":
		errs.append("gin: death code %s, want D-GIN" % str(world.ctl.dead_code))
	if str(world.ctl.dead_killer) != "gin":
		errs.append("gin: killer %s, want gin" % str(world.ctl.dead_killer))
	_assert_pre_kill_cues(world, errs)
	return errs
# The survivor expectations (the negative control half). move_out == true is
# the leg; move_out == false is the control twin re-check (the player left on
# the patch centre's own tile).
func _survivor_expect(world, move_out: bool) -> Array[String]:
	var errs: Array[String] = []
	world.ctl.last_light_spent = true
	if not _park_off_dais(world):
		errs.append("gin: no ordinary floor tile found away from the spawn monument")
		return errs
	var moved := false
	var zone_seen := false
	var steps := 0
	while steps < EXIT_MAX:
		world.step(DT)
		steps += 1
		if bool(world.ctl.dead):
			break
		var row: Dictionary = _gin_row(world)
		if not row.is_empty():
			var patch: Dictionary = row.get("patch", {})
			if move_out and not moved and patch.size() > 0:
				moved = _park_outside(world, patch)
			if zone_seen == false and str(row.get("phase", "")) == "void":
				zone_seen = true
		if _cue_seen(world, "zone_close"):
			break
	if move_out and not moved:
		errs.append("gin: the mark never landed (no patch ever set)")
	if bool(world.ctl.dead):
		errs.append("gin: the player outside the patch died (code %s)" % str(world.ctl.dead_code))
	if not zone_seen:
		errs.append("gin: the zone never opened within %d steps" % EXIT_MAX)
	if not _cue_seen(world, "zone_close"):
		errs.append("gin: zone_close never logged; the zone never fully cycled")
	# all five cues, in order, when the run survives the zone
	var crack := _cue_tick(world, "crack_rumble")
	var shing := _cue_tick(world, "shing")
	var whoosh := _cue_tick(world, "whoosh")
	var open_ := _cue_tick(world, "zone_open")
	var close_ := _cue_tick(world, "zone_close")
	for pair in [["crack_rumble", crack], ["shing", shing], ["whoosh", whoosh],
			["zone_open", open_], ["zone_close", close_]]:
		if int(pair[1]) < 0:
			errs.append("gin: %s never logged by the world's cue view" % str(pair[0]))
	if crack >= 0 and shing >= 0 and crack >= shing:
		errs.append("gin: crack_rumble (tick %d) not before shing (tick %d)" % [crack, shing])
	if shing >= 0 and open_ >= 0 and shing > open_:
		errs.append("gin: shing (tick %d) after zone_open (tick %d)" % [shing, open_])
	if whoosh >= 0 and open_ >= 0 and whoosh > open_:
		errs.append("gin: whoosh (tick %d) after zone_open (tick %d)" % [whoosh, open_])
	if open_ >= 0 and close_ >= 0 and open_ >= close_:
		errs.append("gin: zone_open (tick %d) not before zone_close (tick %d)" % [open_, close_])
	return errs


# The leg. Returns the negative-control failure count for the report line.
func _leg(f: Array[String]) -> int:
	var neg := 0
	# KILL twin: gin voted, the player parked on an ordinary tile
	var world = _build({"gin": 1})
	if world == null:
		f.append("gin: the held world failed to build")
	else:
		for line in _kill_expect(world):
			f.append(line)
		_drop(world)
	# SURVIVOR twin: same build, the player steps out once the mark lands
	world = _build({"gin": 1})
	if world == null:
		f.append("gin: the survivor world failed to build")
	else:
		for line in _survivor_expect(world, true):
			f.append(line)
		_drop(world)
	# ABSENT twin (negative control): no votes -> the kill expectations must FAIL
	world = _build({})
	if world == null:
		f.append("gin: the negative-control world failed to build")
	else:
		var neg_a: Array[String] = _kill_expect(world)
		_drop(world)
		neg += neg_a.size()
	# SAME-BUILD twin, player never steps out (negative control):
	# the survivor expectations must FAIL
	world = _build({"gin": 1})
	if world == null:
		f.append("gin: the outside negative-control world failed to build")
	else:
		var neg_b: Array[String] = _survivor_expect(world, false)
		_drop(world)
		neg += neg_b.size()
	if neg == 0:
		f.append("gin: NEGATIVE CONTROL passed with the thing absent - the assertions prove nothing")
	negative_failures += neg
	return neg
