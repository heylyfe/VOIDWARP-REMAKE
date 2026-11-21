extends RefCounted
#
# test_depth_smoke.gd - the shipped sim builds AND TICKS at a depth no run has reached.
#
# WHY THIS EXISTS. The bot probe dies on level 11, so every end-to-end run the project
# has stops there. test_curse_crumbling.gd builds worlds at 15, 20 and 30 but only
# INSPECTS them (curse subscription, edge keys) - it never steps one. So "the game runs
# at level 20" was unproven, and the roster's level gate was only ever exercised against
# a synthetic level in test_enemy_gin.gd. This file closes that: it builds a real world
# through world.build() at four depths and steps it for 10 s of sim.
#
# WHAT IT PROVES, per depth:
#   1. world.build() succeeds and world.step() runs TICKS times without error;
#   2. the roster is non-empty and every spawned body's min_level <= the level - the
#      level gate is real, not decorative;
#   3. the beacon is SHUT at build time (no black gift is collected yet);
#   4. every live body's x/y/z is finite;
#   5. the roster grows with depth (DESIGN section 9 votes more bodies as the run goes
#      deeper), measured 6 bodies at level 12 and 21 at level 30 on these seeds.
#
# THE CONTROL IS LEVEL 1, and it is a real one: the same build, the same 600 ticks, the
# same assertions at a depth where the answer is known-good (1 body, kiwi_cat, min_level
# 1). If the harness itself broke - a build that silently failed, a step() that did not
# run, a roster read that returned nothing - level 1 fails with it, so a green level 30
# means something. The manual negative control for this file was run by setting
# SPAWN_PER_TICK to 0: every depth then reports "no enemy spawned in 600 ticks", which is
# the failure this file exists to catch.
#
# WHAT LEG 2 DOES *NOT* PROVE, measured rather than assumed: the spawn path does NOT
# re-check min_level. A ledger carrying {"gin": 1} at level 12 spawns gin, whose min_level
# is 17 (probed directly). The gate lives in sim/offers.gd enemy_candidates(), so it
# constrains what the LOBBY can vote, not what the runtime will spawn. Leg 2 therefore
# asserts a property of the shipped vote path - "normal play never produces a body above
# its min_level" - and not an invariant of the spawn rule. Disabling the offer gate
# changes no roster at any of these four depths, because the schedule never offers an
# over-level enemy there; that is why the gate is not this file's control.
#
# NOTHING HERE ASSERTS A BALANCE NUMBER. It is a smoke test for "the shipped sim survives
# being built and ticked at a depth no run has reached", not a difficulty measurement.
#
# The ledger passed to build() is EMPTY on purpose: world._resolve_run() uses a ledger's
# votes verbatim when the key is present, so an empty votes dict suppresses the vote and
# spawns nothing at all (measured: 0 bodies at every depth, including level 1). An empty
# ledger makes the world replay the lobbies before the level and vote for real.

const WorldScript := preload("res://app/world.gd")

const DT := 1.0 / 60.0
const TICKS := 600          # 10 s: past every spawn (4 bodies/tick) and every spawn fade
const DEPTHS := [[1, 1], [12, 1], [18, 7], [24, 42], [30, 12345]]
const CONTROL := 1          # the known-good depth: 1 body, kiwi_cat, min_level 1
const SHALLOW := 12         # the roster-growth comparison's shallow end
const DEEP := 30            # ...and its deep end


func run() -> Array[String]:
	var f: Array[String] = []
	var mins := _min_levels(f)
	if mins.is_empty():
		return f
	var rows_by_depth := {}
	for pair in DEPTHS:
		var lvl := int(pair[0])
		var sd := int(pair[1])
		var n := _one_depth(f, lvl, sd, mins)
		if n >= 0:
			rows_by_depth[lvl] = n
	# 5. depth adds bodies (DESIGN section 9: more votes the deeper the run goes)
	if rows_by_depth.has(SHALLOW) and rows_by_depth.has(DEEP):
		if int(rows_by_depth[DEEP]) <= int(rows_by_depth[SHALLOW]):
			f.append("depth: level %d spawned %d bodies, level %d only %d - depth adds nothing"
				% [DEEP, int(rows_by_depth[DEEP]), SHALLOW, int(rows_by_depth[SHALLOW])])
	return f


## Build, step and check one depth. Returns the roster size, or -1 when the build failed.
func _one_depth(f: Array[String], lvl: int, sd: int, mins: Dictionary) -> int:
	var world = WorldScript.new()
	if not world.build(sd, lvl, {}):
		f.append("depth L%d s%d: world.build failed" % [lvl, sd])
		world.free()
		return -1
	# 3. the beacon is shut before a single gift is collected
	if bool(world.lstate.beacon.is_open()):
		f.append("depth L%d s%d: the beacon is open at build time" % [lvl, sd])
	for i in TICKS:
		world.step(DT)
	var rows: Array = world.rt.enemies
	# 2. a roster exists at all
	if rows.is_empty():
		f.append("depth L%d s%d: no enemy spawned in %d ticks" % [lvl, sd, TICKS])
	var above := 0
	for e in rows:
		var eid := str(e.get("id", ""))
		var ml := int(mins.get(eid, -1))
		if ml < 0:
			f.append("depth L%d s%d: spawned %s, which has no enemy.json" % [lvl, sd, eid])
		elif ml > lvl:
			f.append("depth L%d s%d: spawned %s at min_level %d" % [lvl, sd, eid, ml])
		elif ml > SHALLOW:
			above += 1
		# 4. a body's position is a real number
		for k in ["x", "y", "z"]:
			if not is_finite(float(e.get(k, NAN))):
				f.append("depth L%d s%d: %s has a non-finite %s" % [lvl, sd, eid, k])
	# the control: level 1 is known-good, so a broken harness fails here too
	if lvl == CONTROL:
		if rows.size() != 1:
			f.append("depth L%d s%d: the control depth spawned %d bodies, want 1"
				% [lvl, sd, rows.size()])
		elif str((rows[0] as Dictionary).get("id", "")) != "kiwi_cat":
			f.append("depth L%d s%d: the control depth spawned %s, want kiwi_cat"
				% [lvl, sd, str((rows[0] as Dictionary).get("id", ""))])
	# 5. the deep end really does carry bodies the shallow end cannot (measured 21 vs 6)
	if lvl == DEEP and above == 0:
		f.append("depth L%d s%d: no body above min_level %d - depth adds no content"
			% [lvl, sd, SHALLOW])
	var n := rows.size()
	world.teardown()
	world.free()
	return n


## Every enemy's min_level, read from its own enemy.json (the same file the spawn rule reads).
func _min_levels(f: Array[String]) -> Dictionary:
	var out := {}
	var dir := DirAccess.open("res://content/enemies")
	if dir == null:
		f.append("depth: cannot open res://content/enemies")
		return out
	for d in dir.get_directories():
		var p := "res://content/enemies/%s/enemy.json" % d
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
		if not (doc is Dictionary):
			f.append("depth: %s is not a JSON object" % p)
			continue
		var j: Dictionary = doc
		out[str(j.get("id", d))] = int(j.get("min_level", 0))
	if out.size() != 12:
		f.append("depth: read %d enemy.json files, want 12" % out.size())
	return out
