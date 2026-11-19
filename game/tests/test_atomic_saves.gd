extends RefCounted
#
# test_atomic_saves.gd (review cycle 2, BUG-4 / BUG-5): the disk stores split into two
# deliberately different write shapes, and level_clear never logs a negative duration.
#   - settings and records rewrite a whole JSON file in place, so a partial write really is
#     corruption there: they publish atomically (sibling .tmp, fully written and closed,
#     renamed over the destination). The destination is never left absent - the rename
#     moves the destination aside to .old first and restores it if the rename fails;
#   - the run log is append-only and is read WHILE it is being written (a report or a test
#     mid-run reads the records so far), so it writes its records directly to the destination
#     and does NOT publish atomically: a .tmp publish would hide the destination until close
#     and break that promise (DECISIONS.md D-C2-3). The price is a tolerated truncated tail:
#     a crash mid-run may leave the last line incomplete, and the loader tolerates that by
#     skipping an unparseable final line - it never republishes through a .tmp;
#   - the two shapes exist side by side on purpose: settings/records need the destination to
#     always hold one complete document, the run log needs the destination to always show
#     whatever records exist so far, even if imperfect.
# The legs:
#   - each store saves a value; the destination parses and holds it; no .tmp is left behind;
#   - overwriting a pre-existing good file still yields a parseable file with the new data
#     (rename-over-existing is the case that broke on Windows);
#   - a save whose .tmp write cannot start (a directory sits at the .tmp path, so the
#     FileAccess.open fails) returns false and leaves the OLD file fully intact;
#   - a crashed mid-write end state (a truncated .tmp left next to the destination) does
#     not corrupt the destination: the loader still reads the OLD good file;
#   - a mid-run reader of the run log sees the records so far, and no .tmp is left behind;
#   - a forced rename failure leaves the destination holding its OLD bytes: this process holds
#     the .tmp source open, which makes rename fail on demand, and the store's fallback moves
#     the destination aside to .old first and restores it (see _rename_over_fallback);
#   - level_complete without a preceding beacon_open logs black_ticks/gold_ticks == -1
#     (the explicit sentinel, never an arithmetic accident) and a well-defined total_ticks.
#
# Honest limit: this cannot kill the process mid-store_string, so a true mid-write crash is
# simulated by its observable end states (truncated .tmp + intact destination, and the
# unclosed RunLog case) rather than faked. The rename failure is not simulated either: it is
# forced for real, because this process holds the .tmp source open so the engine's rename
# fails on demand; a real antivirus lock is not emulatable here, so what is proven is the
# observable class - the destination is protected while the rename fails. Scratch files live
# under user:// and are removed at the end; the player's real user:// files are never touched.

const SettingsScript := preload("res://app/settings.gd")
const RecordsScript := preload("res://core/records.gd")
const LogScript := preload("res://app/run_log.gd")

const SETTINGS_SCRATCH := "user://test_atomic_settings.json"
const RECORDS_SCRATCH := "user://test_atomic_records.json"
const RUNS_DIR := "user://test_atomic_runs"
const RENAME_DEST := "user://test_atomic_rename_dest.json"
const RENAME_TMP := "user://test_atomic_rename_tmp.json"
const RUN_SEED := 0xA70A1C5


func run() -> Array[String]:
	var failures: Array[String] = []
	_rm_scratch()
	_settings(failures)
	_records(failures)
	_run_log(failures)
	_rename_over_fallback(failures)
	_recovery(failures)
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


# ---- forced rename failure: the destination is never absent -------------------------------

func _rename_over_fallback(failures: Array[String]) -> void:
	for entry in [[SettingsScript, "settings"], [RecordsScript, "records"]]:
		var label: String = entry[1]
		_rm(RENAME_DEST)
		_rm(RENAME_TMP)
		_rm(RENAME_DEST + ".old")
		var f := FileAccess.open(RENAME_DEST, FileAccess.WRITE)
		f.store_string("GOOD")
		f.close()
		var t := FileAccess.open(RENAME_TMP, FileAccess.WRITE)
		t.store_string("NEW")
		t.close()
		# Force the rename to fail on demand: this process holds the .tmp source open. On
		# this platform that failure also removes the destination as a side effect of the
		# attempt, which is exactly the class the .old side-move exists to survive.
		var hold := FileAccess.open(RENAME_TMP, FileAccess.READ)
		var ok: bool = entry[0]._rename_over(RENAME_TMP, RENAME_DEST)
		hold = null
		if ok:
			failures.append("%s: rename fallback unexpectedly succeeded with the source held open" % label)
		if not FileAccess.file_exists(RENAME_DEST):
			failures.append("%s: destination ABSENT after a failed rename" % label)
		elif FileAccess.get_file_as_string(RENAME_DEST) != "GOOD":
			failures.append("%s: destination does not hold the OLD bytes after a failed rename" % label)
		if not FileAccess.file_exists(RENAME_TMP):
			failures.append("%s: .tmp gone after a failed rename (nothing left recoverable)" % label)
		if FileAccess.file_exists(RENAME_DEST + ".old"):
			failures.append("%s: .old not restored to the destination after a failed rename" % label)
		# success path: the pre-existing destination is replaced and .old is cleaned up
		_rm(RENAME_TMP)
		var t2 := FileAccess.open(RENAME_TMP, FileAccess.WRITE)
		t2.store_string("NEWER")
		t2.close()
		ok = entry[0]._rename_over(RENAME_TMP, RENAME_DEST)
		if not ok:
			failures.append("%s: rename over a pre-existing destination failed" % label)
		if FileAccess.get_file_as_string(RENAME_DEST) != "NEWER":
			failures.append("%s: destination does not hold the NEW bytes after a successful rename" % label)
		if FileAccess.file_exists(RENAME_DEST + ".old"):
			failures.append("%s: .old left behind after a successful rename" % label)
		if FileAccess.file_exists(RENAME_TMP):
			failures.append("%s: .tmp left behind after a successful rename" % label)
		_rm(RENAME_DEST)
		_rm(RENAME_TMP)
		_rm(RENAME_DEST + ".old")


# ---- run log ----------------------------------------------------------------------------

# ---- recovery from the two-rename window ------------------------------------------------

## A crash between the two renames in _rename_over leaves the destination absent with the
## good bytes in .old (or the new bytes in .tmp). Reading only the destination would reset
## the player's settings and bests to defaults, and the next save would then overwrite the
## recoverable copy. This leg proves the fallback; the no-files case is the control, so a
## loader that always returned a stale value would fail here.
func _recovery(failures: Array[String]) -> void:
	var default_volume := SettingsScript.new().volume
	# settings: destination absent, good bytes in .old
	_rm(SETTINGS_SCRATCH)
	_rm(SETTINGS_SCRATCH + ".old")
	_rm(SETTINGS_SCRATCH + ".tmp")
	var s := SettingsScript.new()
	s.volume = 42
	s.fullscreen = true
	if not s.save_to(SETTINGS_SCRATCH):
		failures.append("recovery: the settings seed save failed")
	if DirAccess.rename_absolute(SETTINGS_SCRATCH, SETTINGS_SCRATCH + ".old") != OK:
		failures.append("recovery: could not move the settings destination aside")
	var r := SettingsScript.new()
	r.load_from(SETTINGS_SCRATCH)
	if r.volume != 42 or not r.fullscreen:
		failures.append("recovery: settings did not recover from .old (volume %d, want 42)" % r.volume)
	# settings: destination absent, good bytes in .tmp
	_rm(SETTINGS_SCRATCH + ".old")
	var t := SettingsScript.new()
	t.volume = 55
	if not t.save_to(SETTINGS_SCRATCH):
		failures.append("recovery: the settings .tmp seed save failed")
	if DirAccess.rename_absolute(SETTINGS_SCRATCH, SETTINGS_SCRATCH + ".tmp") != OK:
		failures.append("recovery: could not move the settings destination to .tmp")
	r = SettingsScript.new()
	r.load_from(SETTINGS_SCRATCH)
	if r.volume != 55:
		failures.append("recovery: settings did not recover from .tmp (volume %d, want 55)" % r.volume)
	# control: nothing on disk at all -> the default, not a stale value
	_rm(SETTINGS_SCRATCH + ".tmp")
	r = SettingsScript.new()
	r.load_from(SETTINGS_SCRATCH)
	if r.volume != default_volume:
		failures.append("recovery: the no-file control read volume %d, want the default %d"
			% [r.volume, default_volume])
	# records: destination absent, good bytes in .old
	_rm(RECORDS_SCRATCH)
	_rm(RECORDS_SCRATCH + ".old")
	_rm(RECORDS_SCRATCH + ".tmp")
	var rec := RecordsScript.new()
	rec.best_level = 7
	rec.best_purse = 900
	if not rec.save_to(RECORDS_SCRATCH):
		failures.append("recovery: the records seed save failed")
	if DirAccess.rename_absolute(RECORDS_SCRATCH, RECORDS_SCRATCH + ".old") != OK:
		failures.append("recovery: could not move the records destination aside")
	var rr := RecordsScript.new()
	rr.load_from(RECORDS_SCRATCH)
	if rr.best_level != 7 or rr.best_purse != 900:
		failures.append("recovery: records did not recover from .old (level %d purse %d, want 7/900)"
			% [rr.best_level, rr.best_purse])
	# control: nothing on disk -> zeros
	_rm(RECORDS_SCRATCH + ".old")
	rr = RecordsScript.new()
	rr.load_from(RECORDS_SCRATCH)
	if rr.best_level != 0 or rr.best_purse != 0:
		failures.append("recovery: the no-file control read level %d purse %d, want 0/0"
			% [rr.best_level, rr.best_purse])
	_rm(SETTINGS_SCRATCH + ".old")
	_rm(RECORDS_SCRATCH + ".old")


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
	_rm(RENAME_DEST)
	_rm(RENAME_DEST + ".old")
	_rm(RENAME_TMP)
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
