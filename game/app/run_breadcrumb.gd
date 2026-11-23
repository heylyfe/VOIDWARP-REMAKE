extends RefCounted
#
# app/run_breadcrumb.gd - the crash breadcrumb (U4, cycle 8).
#
# The owner says the game "sometimes crashes". A crash leaves nothing the owner can send
# back: the telemetry log (app/run_log.gd) is per-run JSONL and may be mid-write, and
# godot.log is not where a player looks. So this writes ONE small file,
# user://last_run.txt, holding the last tick, level, seed and phase - written at every
# level start and refreshed cheaply as the run progresses.
#
# "Cheaply" is the whole design: a write per tick would be a real cost and a real
# stutter, so refresh() writes only when REFRESH_TICKS have passed or the phase changed.
# At 60 Hz that is one small file write per second, plus one per phase edge.
#
# VIEW-ONLY, and provably so: nothing here reads or writes simulation state, no RNG is
# drawn, no tick is consumed, no event is appended. The four values are copied out of the
# world's own fields. The replay and state-hash tests stay green with the breadcrumb on -
# that is the proof (game/tests/test_replay.gd, game/tests/test_state_hash.gd).
#
# Format: one key per line, stable order, so a human can read it and a test can parse it.
#   version=1
#   seed=<the run's seed>
#   level=<the level number>
#   tick=<the level's own tick>
#   phase=<black|gold|arena|dead|over|lobby>
#
# The file's mtime is the "when" - no wall clock is written, so the content is a pure
# function of the run's own state and a test can assert it exactly.

const VERSION := 1
## One write per second at the sim's fixed 60 Hz step, plus one per phase edge.
const REFRESH_TICKS := 60

var path := "user://last_run.txt"
var _last_tick := -1
var _last_phase := ""
var _writes := 0


static func create(p_path: String = "user://last_run.txt") -> RefCounted:
	var b := new()
	b.path = p_path
	return b


## A level start: always writes, and re-arms the throttle.
func level_start(seed_value: int, level: int, tick: int, phase: String) -> void:
	write(seed_value, level, tick, phase)


## The cheap refresh: writes only when REFRESH_TICKS have passed or the phase changed.
## Returns true when it wrote (the test seam reads it).
func refresh(seed_value: int, level: int, tick: int, phase: String) -> bool:
	if phase == _last_phase and _last_tick >= 0 and tick - _last_tick < REFRESH_TICKS:
		return false
	write(seed_value, level, tick, phase)
	return true


## The unconditional write. Never throws: a read-only or full user:// must not crash the
## game, so a failed open is reported once and the breadcrumb goes quiet.
func write(seed_value: int, level: int, tick: int, phase: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		if _writes == 0:
			push_warning("run_breadcrumb: cannot write %s (error %d); the breadcrumb is off"
				% [path, FileAccess.get_open_error()])
		return
	f.store_line("version=%d" % VERSION)
	f.store_line("seed=%d" % seed_value)
	f.store_line("level=%d" % level)
	f.store_line("tick=%d" % tick)
	f.store_line("phase=%s" % phase)
	f.close()
	_last_tick = tick
	_last_phase = phase
	_writes += 1


## How many times this instance has written (the test seam).
func write_count() -> int:
	return _writes


## The file's fields as a Dictionary, or {} when it is absent. The test seam.
func read_fields() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var out := {}
	for line in text.split("\n", false):
		var at := line.find("=")
		if at <= 0:
			continue
		out[line.substr(0, at)] = line.substr(at + 1)
	return out
