extends RefCounted
#
# Records + run-end wiring test (DESIGN.md section 9): best level and best purse are
# recorded locally, persist across app restarts (user://records.json), and only ever
# ratchet UP - a worse run never lowers them. Also proves the run-end wiring writes the
# run telemetry log (T-080) instead of leaving RunLog uninstantiated.
#
# Registered like every other test: extends RefCounted, run() -> Array[String], preloads by
# path (no class_name). The app node is NOT added to the SceneTree (headless harness); the
# test calls _ready() itself, like test_app_flow.gd. Scratch files live in user:// and are
# removed at the end (the player's real user://records.json is never touched).

const RecordsScript := preload("res://core/records.gd")
const AppScript := preload("res://app/app.gd")

const SCRATCH := "user://test_records_scratch.json"
const APP_SCRATCH := "user://test_records_app_scratch.json"
const TEST_SEED := 0x5EEDC0DE   # unique scratch seed so the telemetry file cannot collide
const TEST_SEED_2 := 0x5EEDC0DF


func run() -> Array[String]:
	var failures: Array[String] = []

	# ---- unit: a strong run ratchets the records, persists across reloads
	_rm(SCRATCH)
	var rec := RecordsScript.new()
	rec.load_from(SCRATCH)
	if rec.get_best_level() != 0 or rec.get_best_purse() != 0:
		failures.append("fresh scratch not zeroed: level %d purse %d" % [rec.get_best_level(), rec.get_best_purse()])
	rec.record_run(5, 300)
	var reloaded := RecordsScript.new()
	reloaded.load_from(SCRATCH)
	if reloaded.get_best_level() < 5:
		failures.append("best_level %d, want >= 5" % reloaded.get_best_level())
	if reloaded.get_best_purse() < 300:
		failures.append("best_purse %d, want >= 300" % reloaded.get_best_purse())

	# ---- a worse run does not lower them
	reloaded.record_run(2, 50)
	if reloaded.get_best_level() != 5 or reloaded.get_best_purse() != 300:
		failures.append("worse run lowered the records: level %d purse %d" % [reloaded.get_best_level(), reloaded.get_best_purse()])
	var persisted := RecordsScript.new()
	persisted.load_from(SCRATCH)
	if persisted.get_best_level() != 5 or persisted.get_best_purse() != 300:
		failures.append("records not persisted across restarts: level %d purse %d" % [persisted.get_best_level(), persisted.get_best_purse()])

	# ---- a corrupt file never blocks boot; defaults come back
	var f := FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var corrupt := RecordsScript.new()
	corrupt.load_from(SCRATCH)
	if corrupt.get_best_level() != 0 or corrupt.get_best_purse() != 0:
		failures.append("corrupt file did not fall back to zeros: level %d purse %d" % [corrupt.get_best_level(), corrupt.get_best_purse()])

	# ---- app wiring: a run that ends at level 5 with 300 gold ratchets the app's records
	_rm(APP_SCRATCH)
	var app = AppScript.new()
	app.records_path = APP_SCRATCH
	app._ready()
	app._seed = TEST_SEED
	app._state = "WORLD"   # pretend a run is in progress at level 5
	app._run_level_reached = 5
	app._run_purse = 300
	app._run_class = "test_class"
	app._end_run()
	if app.best_level() < 5:
		failures.append("app best_level %d after a level-5 run, want >= 5" % app.best_level())
	if app.best_purse() < 300:
		failures.append("app best_purse %d after a 300-gold run, want >= 300" % app.best_purse())
	# the run telemetry log was actually written (T-080: RunLog is instantiated at run end)
	var log_path := "user://runs/%d_0.jsonl" % TEST_SEED
	if not FileAccess.file_exists(log_path):
		failures.append("run telemetry log %s was not written at run end" % log_path)
	var app2 = AppScript.new()
	app2.records_path = APP_SCRATCH
	app2._ready()
	if app2.best_level() < 5 or app2.best_purse() < 300:
		failures.append("app records not readable after restart: level %d purse %d" % [app2.best_level(), app2.best_purse()])
	# a worse run through the same path does not lower them
	app2._seed = TEST_SEED_2
	app2._state = "WORLD"
	app2._run_recorded = false
	app2._run_level_reached = 1
	app2._run_purse = 0
	app2._end_run()
	if app2.best_level() < 5 or app2.best_purse() < 300:
		failures.append("a worse run lowered the app records: level %d purse %d" % [app2.best_level(), app2.best_purse()])
	app2.free()
	app.free()

	# ---- scratch cleanup (the player's user://records.json is never touched)
	_rm(SCRATCH)
	_rm(APP_SCRATCH)
	_rm("user://runs/%d_0.jsonl" % TEST_SEED)
	_rm("user://runs/%d_0.jsonl" % TEST_SEED_2)
	return failures


func _rm(p: String) -> void:
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
