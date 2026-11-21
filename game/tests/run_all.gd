extends SceneTree
#
# Headless test runner (FLEET_PACK.md section 4, ticket T-001):
#   <godot> --headless --path game --script res://tests/run_all.gd
#
# Discovers res://tests/test_*.gd and runs each one's `func run() -> Array[String]`:
# an empty array = the test passed, otherwise each string is one failure message.
# Prints "TESTS n passed m failed"; exit code is 1 when m > 0, else 0.
#
# Conventions every discovered test must follow:
#   - extends RefCounted, no class_name (a global class_name does not resolve under
#     --headless --script);
#   - refer to other scripts with preload("res://...") / load("res://..."), never by a bare
#     class name and never by uid://.
#
# test_terrain_parity.gd is deliberately NOT discovered here: it is a standalone SceneTree
# script with no run() function; tools/gate.ps1 runs it as its own step 2.
# test_beacon_audio_export.gd is the same shape for a different reason: it mounts a real
# exported pack (ProjectSettings.load_resource_pack) to prove the beacon cue survives the
# export, so it needs an export to point at and cannot run inside the suite. Its in-suite
# counterpart is test_beacon_audio.gd's export-guard leg.

const TESTS_DIR := "res://tests"
const EXCLUDED := ["test_terrain_parity.gd", "test_beacon_audio_export.gd"]


var _ran := false


# The suite runs on the first frame, not in _init/_initialize: the root Window is not
# inside the tree until then, and a test that hosts a real Node (an audio player, a view)
# needs a live tree. _process returns true to quit.
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var paths: Array[String] = []
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		print("ERROR: cannot open %s (DirAccess error %d)" % [TESTS_DIR, DirAccess.get_open_error()])
		print("TESTS 0 passed 1 failed")
		quit(1)
		return true
	for f in dir.get_files():
		if not f.begins_with("test_") or not f.ends_with(".gd"):
			continue
		if EXCLUDED.has(f):
			continue
		paths.append(TESTS_DIR + "/" + f)
	paths.sort()

	var passed := 0
	var failed := 0
	for p in paths:
		var failures := _run_one(p)
		if failures.is_empty():
			passed += 1
			print("PASS %s" % p)
		else:
			failed += 1
			for msg in failures:
				print("FAIL %s: %s" % [p.get_file(), msg])
	print("TESTS %d passed %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return true


func _run_one(path: String) -> Array[String]:
	var failures: Array[String] = []
	var script = load(path)
	if script == null or not (script as Script).can_instantiate():
		failures.append("script failed to load")
		return failures
	var inst = script.new()
	if inst == null or not inst.has_method("run"):
		failures.append("exposes no run() -> Array[String]")
		return failures
	var result = inst.call("run")
	if result is Array or result is PackedStringArray:
		for item in result:
			failures.append(str(item))
	else:
		failures.append("run() did not return an array (got %s)" % type_string(typeof(result)))
	return failures