extends RefCounted
#
# Drop-in proof (FLEET_PACK section 4 gate step 6; ticket T-013).
#
# THE extensibility proof (DESIGN.md section 12): new content is a new folder/file under
# content/ and NOTHING ELSE. This test
#   1. boots the registry on the shipped content and asserts the fixture ids are absent;
#   2. copies the four fixtures (one enemy, one curse, one upgrade, one biome) from
#      tests/fixtures/dropin/ into content/ - the only place the test ever writes;
#   3. re-boots: ok=true, all four fixtures registered in id order, and functional reads
#      (entry by id, curse eligibility, content ids for RunState, modifier math) work on them;
#   4. corrupts one copied file (invalid JSON) and re-boots: the registry REFUSES THE BOOT and
#      every refusal line names the offending file; same for a schema violation (valid JSON,
#      wrong type) - the offending file name appears again;
#   5. removes everything it copied and re-boots: clean again.
# Zero edits outside content/: step 2/4 wrote only under content/, step 5 deleted it again.
# A drop-in upgrade is NOT auto-sold in the shop: data/upgrade_pools.json (a data file, not a
# core file) lists what each bracket sells - that edit is a data edit, never a core edit.

const RegistryScript := preload("res://core/registry.gd")
const ContentApiScript := preload("res://core/content_api.gd")

# fixture source -> destination under res://content/. The enemy is a folder (enemy.json).
const COPIES: Array = [
	["res://tests/fixtures/dropin/curses/test_curse.json", "res://content/curses/test_curse.json"],
	["res://tests/fixtures/dropin/upgrades/test_upgrade.json", "res://content/upgrades/test_upgrade.json"],
	["res://tests/fixtures/dropin/biomes/test_biome.json", "res://content/biomes/test_biome.json"],
	["res://tests/fixtures/dropin/enemies/test_dummy/enemy.json", "res://content/enemies/test_dummy/enemy.json"],
]
const FIXTURE_IDS := ["test_curse", "test_upgrade", "test_biome", "test_dummy"]


func run() -> Array[String]:
	var failures: Array[String] = []

	# 1. The fixtures are NOT already part of the shipped content.
	var before: RefCounted = ContentApiScript.load()
	if not _check(failures, before.call("is_ok"), "pre-copy boot failed: %s" % _joined(before.call("boot_errors"))):
		return failures
	for id in FIXTURE_IDS:
		_check(failures, (before.call("curse", id) as Dictionary).is_empty(), "%s already exists before the drop-in" % id)

	# 2. Drop the fixtures in. This (and only this) is what "a drop-in" means: files under
	#    content/, nothing else.
	for pair in COPIES:
		_copy(str(pair[0]), str(pair[1]), failures)

	# 3. Re-boot: green, all four present.
	var after: RefCounted = ContentApiScript.load()
	if not _check(failures, after.call("is_ok"), "post-drop-in boot failed: %s" % _joined(after.call("boot_errors"))):
		_cleanup(failures)
		return failures
	_check(failures, (after.call("curse_ids") as Array).has("test_curse"), "test_curse missing after the drop-in")
	_check(failures, (after.call("upgrade_ids") as Array).has("test_upgrade"), "test_upgrade missing after the drop-in")
	_check(failures, (after.call("biome_ids") as Array).has("test_biome"), "test_biome missing after the drop-in")
	_check(failures, (after.call("enemy_ids") as Array).has("test_dummy"), "test_dummy missing after the drop-in")
	var dropped_ids: Array = after.call("content_ids")
	_check(failures, (dropped_ids as Array).has("curse:test_curse"), "content_ids lacks curse:test_curse (the RunState content set, DESIGN.md section 13)")
	_check(failures, (dropped_ids as Array).has("enemy:test_dummy"), "content_ids lacks enemy:test_dummy")

	# 4a. Functional reads on the drop-ins (offered + selectable).
	var curse_data: Dictionary = after.call("curse", "test_curse")
	_check(failures, str(curse_data.get("name", "")) == "Test Curse", "test_curse entry data did not survive the drop-in verbatim")
	_check(failures, (after.call("eligible_curses", 1, {}) as Array).has("test_curse"), "drop-in curse is not offered (eligible) at its min_level 1")
	# 4b. Functional modifier math on the fixture modifiers (1 stack x1.1, 2 stacks x1.21).
	var mods: Array = curse_data.get("modifiers", [])
	var one: Dictionary = after.call("apply_modifiers", {}, mods, {})
	_check(failures, is_equal_approx(float(one.get("pickup_radius", 0.0)), 1.1), "fixture curse modifier at 1 stack gave %s, expected x1.1" % str(one.get("pickup_radius")))
	var two_mods: Array = after.call("mods_for_stacks", mods, 2)
	var two: Dictionary = after.call("apply_modifiers", {}, two_mods, {})
	_check(failures, is_equal_approx(float(two.get("pickup_radius", 0.0)), 1.1 * 1.1), "fixture curse modifier at 2 stacks gave %s, expected x1.21" % str(two.get("pickup_radius")))
	var enemy_data: Dictionary = after.call("enemy", "test_dummy")
	_check(failures, int(enemy_data.get("min_level", 99)) == 1 and str(enemy_data.get("vote_effect", "")) == "spawn", "test_dummy entry data did not survive the drop-in verbatim")
	# 4c. A drop-in upgrade stays OUT of the shop pool: the pool is data/upgrade_pools.json
	# (a data edit, deliberately never a core edit). Documented behavior, asserted here.
	_check(failures, not (after.call("shop_pool", 9) as Array).has("test_upgrade"), "test_upgrade sold without a pool/data edit")

	# 5. Refusals (broken JSON + schema violation, each named) + full cleanup.
	_refusals(failures)
	return failures


# 5. Malformed JSON in a drop-in file: the boot is REFUSED and the refusal names the file.
#    (The probe below writes only under content/.) THE boot-refusal proof, FLEET_PACK step 6.
func _refusals(failures: Array[String]) -> void:
	var broken := '{"id": "test_curse", "severity": '  # not valid JSON
	_write_raw("res://content/curses/test_curse.json", broken)
	var refused: RefCounted = ContentApiScript.load()
	_check(failures, not refused.call("is_ok"), "boot accepted a broken-JSON content file")
	var lines: Array = refused.call("boot_errors")
	_check(failures, _any_mentions(str(lines), "test_curse.json"), "refusal lines name no file (wanted test_curse.json): %s" % str(lines))
	# A WELL-formed file that violates the SCHEMA is refused with the file name too:
	# severity must be the mild/harsh/brutal enum, not the table's M/H/B letter or a number.
	_write_raw("res://content/curses/test_curse.json", '{"id": "test_curse", "name": "Test Curse", "severity": 7, "min_level": 1, "requires_enemy": null, "max_stacks": 2, "modifiers": [], "hooks": []}')
	var schema_refused: RefCounted = ContentApiScript.load()
	_check(failures, not schema_refused.call("is_ok"), "boot accepted a schema-violating content file (severity 7)")
	var schema_lines: Array = schema_refused.call("boot_errors")
	_check(failures, _any_mentions(str(schema_lines), "test_curse.json"), "schema refusal lines name no file (wanted test_curse.json): %s" % str(schema_lines))
	_check(failures, _any_mentions(str(schema_lines), "severity"), "schema refusal does not point at the offending key: %s" % str(schema_lines))
	# Restore the good file, then remove everything the test copied.
	_copy("res://tests/fixtures/dropin/curses/test_curse.json", "res://content/curses/test_curse.json", failures)
	var restored: RefCounted = ContentApiScript.load()
	_check(failures, restored.call("is_ok"), "boot stayed refused after the restore: %s" % _joined(restored.call("boot_errors")))
	_cleanup(failures)
	var final_boot: RefCounted = ContentApiScript.load()
	if _check(failures, final_boot.call("is_ok"), "boot failed after cleanup: %s" % _joined(final_boot.call("boot_errors"))):
		for id in FIXTURE_IDS:
			_check(failures, (final_boot.call("curse", id) as Dictionary).is_empty(), "%s still present after cleanup" % id)


func _cleanup(failures: Array[String]) -> void:
	# Reverse order: files first, then the now-empty test_dummy folder.
	for i in range(COPIES.size() - 1, -1, -1):
		var dst := str(COPIES[i][1])
		var dir := DirAccess.open(dst.get_base_dir())
		var name := dst.get_file()
		if dir == null:
			failures.append("cleanup: cannot open %s" % dst.get_base_dir())
			continue
		if dir.file_exists(name):
			var err: int = dir.call("remove", name)
			_check(failures, err == OK, "cleanup: cannot remove %s (error %d)" % [dst, err])
	var enemies := DirAccess.open("res://content/enemies")
	if enemies.dir_exists("test_dummy"):
		var err: int = enemies.call("remove", "test_dummy")
		_check(failures, err == OK, "cleanup: cannot remove the test_dummy folder (error %d)" % err)


func _copy(src: String, dst: String, failures: Array[String]) -> void:
	var dest_dir := DirAccess.open(dst.get_base_dir())
	if dest_dir == null:
		DirAccess.make_dir_recursive_absolute(_abs(dst.get_base_dir()))
	dest_dir = DirAccess.open(dst.get_base_dir())
	if dest_dir == null:
		failures.append("cannot prepare folder %s" % dst.get_base_dir())
		return
	var f := FileAccess.open(src, FileAccess.READ)
	if f == null:
		failures.append("cannot read fixture %s" % src)
		return
	var text := f.get_as_text()
	f.close()
	var out := FileAccess.open(dst, FileAccess.WRITE)
	if out == null:
		failures.append("cannot write %s" % dst)
		return
	out.store_string(text)
	out.close()


func _write_raw(dst: String, text: String) -> void:
	var out := FileAccess.open(dst, FileAccess.WRITE)
	if out == null:
		return
	out.store_string(text)
	out.close()


static func _abs(res_path: String) -> String:
	return ProjectSettings.globalize_path(res_path)


func _check(failures: Array[String], ok: bool, msg: String) -> bool:
	if not ok:
		failures.append(msg)
	return ok


func _joined(errors: Array) -> String:
	return " / ".join(errors)


func _any_mentions(text: String, needle: String) -> bool:
	return text.contains(needle)

