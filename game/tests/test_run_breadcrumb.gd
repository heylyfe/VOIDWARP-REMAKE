extends RefCounted
#
# CRASH BREADCRUMB test (U4, cycle 8). The owner says the game "sometimes crashes" and a
# crash leaves nothing they can send back. app/run_breadcrumb.gd writes ONE small file,
# user://last_run.txt, with the last tick, level, seed and phase - at every level start
# and refreshed once a second (plus on every phase edge), never per tick.
#
#   leg A  a level start writes the file with the right fields: version, seed, level, tick
#          and phase=black. The values are the world's own, not invented.
#   leg B  the refresh is throttled: 30 ticks in, no second write; at tick 60, one write;
#          a phase edge writes immediately regardless of the throttle.
#   leg C  the phase follows the run: the beacon opening turns it to "gold", a dead
#          controller to "dead".
#   leg D  VIEW-ONLY, proved directly: the same level built twice and stepped the same 120
#          ticks, once with the breadcrumb on and once off, produces the SAME state hash.
#          (The gate's replay and state-hash tests are the second, independent proof.)
#
# The test fails if the file is not written, if a field is wrong, if the throttle is gone
# (a write per tick), or if the hash moves.

const WorldScript := preload("res://app/world.gd")
const BreadcrumbScript := preload("res://app/run_breadcrumb.gd")
const StateHashScript := preload("res://sim/state_hash.gd")

const DT := 1.0 / 60.0
const TEST_PATH := "user://u4_breadcrumb_test.txt"
const SEED := 3
const LEVEL := 2


## state_hash.gd's dump() reads these member names; this holder lets the test hash a live
## world without touching a single sim file (the same shape the tester panel uses).
class LiveRunState extends RefCounted:
	var run_seed: int = 0
	var players: int = 1
	var content_ids: Array = []
	var level_number: int = 0
	var run_votes: Dictionary = {}
	var run_hunger: int = 0
	var level: RefCounted = null
	var rng: Dictionary = {}


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_a_level_start(f)
	_leg_b_throttle(f)
	_leg_c_phase(f)
	_leg_d_view_only(f)
	return f


func _cleanup() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _new_world() -> Node:
	var w = WorldScript.new()
	w.breadcrumb_path = TEST_PATH
	return w


## Leg A: the level start writes the four fields.
func _leg_a_level_start(f: Array[String]) -> void:
	_cleanup()
	var w = _new_world()
	if not w.build(SEED, LEVEL):
		f.append("leg A: the world failed to build")
		w.free()
		return
	if not FileAccess.file_exists(TEST_PATH):
		f.append("leg A: the level start wrote no breadcrumb file")
		w.teardown()
		w.free()
		return
	var fields: Dictionary = w.breadcrumb.read_fields()
	if str(fields.get("version", "")) != "1":
		f.append("leg A: version is %s, expected 1" % str(fields.get("version", "")))
	# The owner's spec: the file carries the build and the UTC time of the write (D-U4-2).
	if str(fields.get("build", "")) != BreadcrumbScript.BUILD_TAG:
		f.append("leg A: build is %s, expected %s"
			% [str(fields.get("build", "")), BreadcrumbScript.BUILD_TAG])
	# Time.get_datetime_string_from_system(true) is "YYYY-MM-DDTHH:MM:SS", UTC, 19 chars.
	var utc := str(fields.get("utc", ""))
	var utc_ok := utc.length() == 19 and utc.substr(4, 1) == "-" and utc.substr(7, 1) == "-" \
		and utc.substr(10, 1) == "T" and utc.substr(13, 1) == ":" and utc.substr(16, 1) == ":"
	if not utc_ok:
		f.append("leg A: utc is '%s', expected an ISO-like UTC timestamp" % utc)
	if str(fields.get("seed", "")) != str(SEED):
		f.append("leg A: seed is %s, expected %d" % [str(fields.get("seed", "")), SEED])
	if str(fields.get("level", "")) != str(LEVEL):
		f.append("leg A: level is %s, expected %d" % [str(fields.get("level", "")), LEVEL])
	if str(fields.get("phase", "")) != "black":
		f.append("leg A: phase is %s, expected black" % str(fields.get("phase", "")))
	if not fields.has("tick"):
		f.append("leg A: the breadcrumb carries no tick")
	w.teardown()
	w.free()
	_cleanup()


## Leg B: the refresh is throttled to one write per REFRESH_TICKS, and a phase edge writes.
func _leg_b_throttle(f: Array[String]) -> void:
	_cleanup()
	var w = _new_world()
	if not w.build(SEED, LEVEL):
		f.append("leg B: the world failed to build")
		w.free()
		return
	var bc = w.breadcrumb
	var after_start: int = int(bc.write_count())
	# 30 ticks: under the 60-tick throttle, so no second write.
	for t in 30:
		w.step(DT, {"move_x": 0, "move_z": 0, "buttons": 0, "app": 0})
	if int(bc.write_count()) != after_start:
		f.append("leg B: the breadcrumb wrote inside the throttle window (%d -> %d)"
			% [after_start, int(bc.write_count())])
	# The refresh records the completed tick, so the write lands on tick 60.
	for t in 30:
		w.step(DT, {"move_x": 0, "move_z": 0, "buttons": 0, "app": 0})
	if int(bc.write_count()) != after_start + 1:
		f.append("leg B: the breadcrumb did not write at the 60-tick refresh (%d -> %d)"
			% [after_start, int(bc.write_count())])
	# A phase edge writes immediately, whatever the throttle says.
	var before_edge: int = int(bc.write_count())
	var wrote: bool = bc.refresh(SEED, LEVEL, int(w.lstate.tick), "gold")
	if not wrote or int(bc.write_count()) != before_edge + 1:
		f.append("leg B: a phase edge did not force a write")
	w.teardown()
	w.free()
	_cleanup()


## Leg C: the phase follows the run's own state.
func _leg_c_phase(f: Array[String]) -> void:
	_cleanup()
	var w = _new_world()
	if not w.build(SEED, LEVEL):
		f.append("leg C: the world failed to build")
		w.free()
		return
	if str(w._breadcrumb_phase()) != "black":
		f.append("leg C: a fresh level is not in the black phase")
	# The beacon opening is the gold phase.
	w.lstate.beacon.open(int(w.lstate.tick))
	if str(w._breadcrumb_phase()) != "gold":
		f.append("leg C: an open beacon is not the gold phase (%s)"
			% str(w._breadcrumb_phase()))
	# A dead controller is the dead phase.
	w.ctl.dead = true
	if str(w._breadcrumb_phase()) != "dead":
		f.append("leg C: a dead controller is not the dead phase (%s)"
			% str(w._breadcrumb_phase()))
	w._finish_tick()
	var fields: Dictionary = w.breadcrumb.read_fields()
	if fields.get("phase") != "over" or fields.get("tick") != str(w.lstate.tick):
		f.append("leg C: the breadcrumb did not persist the terminal phase and tick")
	w.teardown()
	w.free()
	_cleanup()


## Leg D: the breadcrumb is view-only - the state hash is identical with it on and off.
func _leg_d_view_only(f: Array[String]) -> void:
	_cleanup()
	var on = _new_world()
	var off = _new_world()
	off.breadcrumb_enabled = false
	if not on.build(SEED, LEVEL) or not off.build(SEED, LEVEL):
		f.append("leg D: a world failed to build")
		on.free()
		off.free()
		return
	for t in 120:
		var cmd := {"move_x": 1 if t % 2 == 0 else -1, "move_z": 1, "buttons": 0, "app": 0}
		on.step(DT, cmd)
		off.step(DT, cmd)
	var h_on := StateHashScript.sha256(_run_state(on))
	var h_off := StateHashScript.sha256(_run_state(off))
	if h_on != h_off:
		f.append("leg D: the breadcrumb moved the state hash (%s vs %s)" % [h_on, h_off])
	if int(on.lstate.tick) != int(off.lstate.tick):
		f.append("leg D: the breadcrumb moved the tick (%d vs %d)"
			% [int(on.lstate.tick), int(off.lstate.tick)])
	on.teardown()
	off.teardown()
	on.free()
	off.free()
	_cleanup()


func _run_state(w: Node) -> RefCounted:
	var out := LiveRunState.new()
	out.run_seed = int(w.get("_run_seed"))
	out.players = 1
	out.content_ids = []
	out.level_number = int(w.get("_level_number"))
	var ledger: Dictionary = w.call("run_ledger")
	out.run_votes = ledger.get("votes", {})
	out.run_hunger = int(ledger.get("hunger", 0))
	out.level = w.get("lstate")
	out.rng = {}
	return out
