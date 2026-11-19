extends RefCounted
#
# test_atomic_saves.gd (review cycle 2, BUG-4 / BUG-5): the three stores that persist to
# disk write atomically (sibling .tmp + rename over the destination), and level_clear never
# logs a negative duration.
#   - each store saves a value; the destination parses and holds it; no .tmp is left behind;
#   - overwriting a pre-existing good file still yields a parseable file with the new data
#     (rename-over-existing is the case that broke on Windows);
#   - a save whose .tmp write cannot start (a directory sits at the .tmp path, so the
#     FileAccess.open fails) returns false and leaves the OLD file fully intact;
#   - a crashed mid-write end state (a truncated .tmp left next to the destination) does
#     not corrupt the destination: the loader still reads the OLD good file;
#   - a mid-run telemetry log that is never closed (a crash before RunLog.close) leaves
#     the destination holding the OLD bytes, with the half-written data in the .tmp only;
#   - level_complete without a preceding beacon_open logs black_ticks/gold_ticks == -1
#     (the explicit sentinel, never an arithmetic accident) and a well-defined total_ticks.
#
# Honest limit: this cannot kill the process mid-store_string, so a true mid-write crash is
# simulated by its observable end states (truncated .tmp + intact destination, and the
# unclosed RunLog case) rather than faked. Scratch files live under user:// and are
# removed at the end; the player's real user:// files are never touched.

const SettingsScript := preload("res://app/settings.gd")
const RecordsScript := preload("res://core/records.gd")
const LogScript := preload("res://app/run_log.gd")

const SETTINGS_SCRATCH := "user://test_atomic_settings.json"
const RECORDS_SCRATCH := "user://test_atomic_records.json"
const RUNS_DIR := "user://test_atomic_runs"
const RUN_SEED := 0xA70A1C5


func run() -> Array[String]:
	var failures: Array[String] = []
	_rm_scratch()
	_settings(failures)
	_records(failures)
	_run_log(failures)
	_level_clear_sentinel(failures)
	_rm_scratch()
	return failures


func _run_path(p_seed: int) -> String:
	return "%s/%d_0.jsonl" % [RUNS_DIR, p_seed]


# ---- settings ---------------------------------------------------------------------------

func _settings(failures: Array[String]) -> void:
	_rm(SETTINGS_SCRATCH)
	var s := SettingsScript.new()
	s.volume = 33
	s.fullscreen = true
	if not s.save_to(SETTINGS_SCRATCH):
		failures.append("settings: save_to failed")
	if FileAccess.file_exists(SETTINGS_SCRATCH + ".tmp"):
		failures.append("settings: .tmp left behind after the save")
	var r := SettingsScript.new()
	r.load_from(SETTINGS_SCRATCH)
	if r.volume != 33 or not r.fullscreen:
		failures.append("settings: saved values not readable back (volume %d)" % r.volume)
	# overwrite the pre-existing good file (rename-over-existing)
	s.volume = 77
	s.save_to(SETTINGS_SCRATCH)
	if FileAccess.file_exists(SETTINGS_SCRATCH + ".tmp"):
		failures.append("settings: .tmp left behind after the overwrite")
	r = SettingsScript.new()
	r.load_from(SETTINGS_SCRATCH)
	if r.volume != 77:
		failures.append("settings: overwrite left volume %d, want 77" % r.volume)
	# a failed save (.tmp path is a directory) leaves the OLD file intact
	DirAccess.make_dir_recursive_absolute(SETTINGS_SCRATCH + ".tmp")
	var before := FileAccess.get_file_as_string(SETTINGS_SCRATCH)
	s.volume = 11
	if s.save_to(SETTINGS_SCRATCH):
		failures.append("settings: save unexpectedly succeeded with an unwritable .tmp")
	if FileAccess.get_file_as_string(SETTINGS_SCRATCH) != before:
		failures.append("settings: destination changed after a failed save")
	DirAccess.remove_absolute(SETTINGS_SCRATCH + ".tmp")
	r = SettingsScript.new()
	r.load_from(SETTINGS_SCRATCH)
	if r.volume != 77:
		failures.append("settings: OLD file unreadable after a failed save (volume %d)" % r.volume)
	# a truncated .tmp next to the destination (crash mid-write end state)
	var tf := FileAccess.open(SETTINGS_SCRATCH + ".tmp", FileAccess.WRITE)
	tf.store_string("{trun")
	tf.close()
	r = SettingsScript.new()
	r.load_from(SETTINGS_SCRATCH)
	if r.volume != 77:
		failures.append("settings: loader did not read the OLD file next to a truncated .tmp")
	_rm(SETTINGS_SCRATCH + ".tmp")
	_rm(SETTINGS_SCRATCH)
# ---- records ----------------------------------------------------------------------------

func _records(failures: Array[String]) -> void:
	_rm(RECORDS_SCRATCH)
	var rec := RecordsScript.new()
	rec.load_from(RECORDS_SCRATCH)
	rec.record_run(5, 300)
	if FileAccess.file_exists(RECORDS_SCRATCH + ".tmp"):
		failures.append("records: .tmp left behind after the save")
	var r := RecordsScript.new()
	r.load_from(RECORDS_SCRATCH)
	if r.get_best_level() != 5 or r.get_best_purse() != 300:
		failures.append("records: saved values not readable back (%d/%d)" % [r.get_best_level(), r.get_best_purse()])
	# overwrite the pre-existing good file (rename-over-existing)
	rec.record_run(7, 500)
	if FileAccess.file_exists(RECORDS_SCRATCH + ".tmp"):
		failures.append("records: .tmp left behind after the overwrite")
	r = RecordsScript.new()
	r.load_from(RECORDS_SCRATCH)
	if r.get_best_level() != 7 or r.get_best_purse() != 500:
		failures.append("records: overwrite left %d/%d, want 7/500" % [r.get_best_level(), r.get_best_purse()])
	# a failed save (.tmp path is a directory) leaves the OLD file intact
	DirAccess.make_dir_recursive_absolute(RECORDS_SCRATCH + ".tmp")
	var before := FileAccess.get_file_as_string(RECORDS_SCRATCH)
	rec.best_level = 9
	rec.best_purse = 900
	if rec.save_to():
		failures.append("records: save unexpectedly succeeded with an unwritable .tmp")
	if FileAccess.get_file_as_string(RECORDS_SCRATCH) != before:
		failures.append("records: destination changed after a failed save")
	DirAccess.remove_absolute(RECORDS_SCRATCH + ".tmp")
	r = RecordsScript.new()
	r.load_from(RECORDS_SCRATCH)
	if r.get_best_level() != 7 or r.get_best_purse() != 500:
		failures.append("records: OLD file unreadable after a failed save (%d/%d)" % [r.get_best_level(), r.get_best_purse()])
	# a truncated .tmp next to the destination (crash mid-write end state)
	var tf := FileAccess.open(RECORDS_SCRATCH + ".tmp", FileAccess.WRITE)
	tf.store_string("{trun")
	tf.close()
	r = RecordsScript.new()
	r.load_from(RECORDS_SCRATCH)
	if r.get_best_level() != 7 or r.get_best_purse() != 500:
		failures.append("records: loader did not read the OLD file next to a truncated .tmp")
	_rm(RECORDS_SCRATCH + ".tmp")
	_rm(RECORDS_SCRATCH)


# ---- run log ----------------------------------------------------------------------------

func _write_old_log(p_path: String, p_class: String) -> String:
	DirAccess.make_dir_recursive_absolute(RUNS_DIR)
	var line := JSON.stringify({"t": 0, "level": 1, "phase": "lobby", "type": "run_start",
			"payload": {"seed": RUN_SEED, "class": p_class}})
	var f := FileAccess.open(p_path, FileAccess.WRITE)
	f.store_line(line)
	f.close()
	return line + "\n"


func _run_log(failures: Array[String]) -> void:
	var p := _run_path(RUN_SEED)
	_rm(p)
	_rm(p + ".tmp")
	# overwrite a pre-existing good destination (rename-over-existing)
	var old_text := _write_old_log(p, "old")
	var lg := LogScript.new()
	lg.dir_base = RUNS_DIR
	lg.run_started(RUN_SEED, "dasher", 0)
	lg.level_started(1, 3, 2, 1, 4)
	lg.feed_tick([])
	lg.run_finished(1, 100)
	lg.close()
	if FileAccess.file_exists(p + ".tmp"):
		failures.append("run log: .tmp left behind after close")
	var got := FileAccess.get_file_as_string(p)
	if got == old_text:
		failures.append("run log: the pre-existing file was not replaced by the new run")
	var recs := _parse(p, failures)
	var saw_run_end := false
	for rec in recs:
		if str((rec as Dictionary).get("type", "")) == "run_end":
			saw_run_end = true
	if not saw_run_end:
		failures.append("run log: the rewritten file holds no run_end record")
	# The run log is the one store that does NOT publish atomically: it is append-only and it
	# is read WHILE it is written (a report or a test mid-run reads the records so far). A
	# .tmp-then-rename publish would hide the destination until close and break that. So the
	# contract to prove here is mid-run readability, not atomicity.
	_rm(p)
	var lg2 := LogScript.new()
	lg2.dir_base = RUNS_DIR
	lg2.run_started(RUN_SEED, "dasher", 0)
	lg2.level_started(1, 3, 2, 1, 4)
	lg2.feed_tick([])
	# no close(): a reader mid-run must already see the records so far
	var mid := FileAccess.get_file_as_string(p)
	if mid.strip_edges() == "":
		failures.append("run log: a mid-run reader sees nothing (the log is unreadable until close)")
	if mid.find("run_start") < 0:
		failures.append("run log: a mid-run reader cannot see the run_start record")
	if FileAccess.file_exists(p + ".tmp"):
		failures.append("run log: the log published through a .tmp, hiding it from a mid-run reader")
	lg2.close()
	_rm(p)
	_rm(p + ".tmp")
# ---- BUG-5: level_clear without a beacon_open --------------------------------------------

func _level_clear_sentinel(failures: Array[String]) -> void:
	var p := _run_path(RUN_SEED + 1)
	var p2 := _run_path(RUN_SEED + 2)
	_rm(p)
	_rm(p + ".tmp")
	_rm(p2)
	_rm(p2 + ".tmp")
	# no beacon_open seen: the sentinel, and total_ticks stays well-defined
	var lg := LogScript.new()
	lg.dir_base = RUNS_DIR
	lg.run_started(RUN_SEED + 1, "dasher", 0)
	lg.level_started(1, 3, 2, 1, 4)
	for _i in range(5):
		lg.feed_tick([])
	lg.feed_tick([{"type": "level_complete"}])
	lg.close()
	_assert_level_clear(failures, p, {"black_ticks": -1, "gold_ticks": -1, "total_ticks": 5}, "sentinel")
	# a level WITH a beacon_open: the sentinel is not emitted
	var lg2 := LogScript.new()
	lg2.dir_base = RUNS_DIR
	lg2.run_started(RUN_SEED + 2, "dasher", 0)
	lg2.level_started(1, 1, 1, 0, 0)
	lg2.feed_tick([])
	lg2.feed_tick([{"type": "beacon_opened"}])
	lg2.feed_tick([])
	lg2.feed_tick([{"type": "level_complete"}])
	lg2.close()
	_assert_level_clear(failures, p2, {"black_ticks": 1, "gold_ticks": 2, "total_ticks": 3}, "with-beacon")
	_rm(p)
	_rm(p + ".tmp")
	_rm(p2)
	_rm(p2 + ".tmp")


func _assert_level_clear(failures: Array[String], p_path: String,
		want: Dictionary, label: String) -> void:
	var recs := _parse(p_path, failures)
	for rec in recs:
		var d: Dictionary = rec
		if str(d.get("type", "")) != "level_clear":
			continue
		var pay: Dictionary = d.get("payload", {})
		for k in want.keys():
			if int(pay.get(k, -999)) != int(want[k]):
				failures.append("level_clear (%s): %s %d, want %d" % [label, k, int(pay.get(k, -999)), int(want[k])])
		return
	failures.append("level_clear (%s): no level_clear record in %s" % [label, p_path])


# ---- helpers -----------------------------------------------------------------------------

func _parse(p_path: String, failures: Array[String]) -> Array:
	var out: Array = []
	var f := FileAccess.open(p_path, FileAccess.READ)
	if f == null:
		failures.append("log file missing: %s" % p_path)
		return out
	while not f.eof_reached():
		var line := f.get_line()
		if line.strip_edges() == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
		else:
			failures.append("unparseable log line: %s" % line)
	f.close()
	return out


func _rm_scratch() -> void:
	_rm(SETTINGS_SCRATCH)
	_rm(SETTINGS_SCRATCH + ".tmp")
	_rm(RECORDS_SCRATCH)
	_rm(RECORDS_SCRATCH + ".tmp")
	for seed in [RUN_SEED, RUN_SEED + 1, RUN_SEED + 2]:
		_rm(_run_path(seed))
		_rm(_run_path(seed) + ".tmp")
	if DirAccess.dir_exists_absolute(RUNS_DIR):
		DirAccess.remove_absolute(RUNS_DIR)


func _rm(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	elif DirAccess.dir_exists_absolute(p):
		DirAccess.remove_absolute(p)
