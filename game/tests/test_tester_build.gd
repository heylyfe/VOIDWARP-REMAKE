extends RefCounted
#
# test_tester_build.gd - cycle 7, track T2: the TESTER build's compile-out guarantee.
#
# The owner's words: "tester build with debug panel (owner only, never in public releases)".
# What this suite pins, point by point:
#   (a) the three public export presets (0 Windows Desktop / 1 Linux / 2 macOS) exclude
#       view/tester/* (exclude_filter) and carry NO custom feature tag;
#   (b) a "Tester" preset exists with custom_features="tester"; its panel is fully
#       loadable and F10 togglable headless (the whole layout is _init-built);
#   (c) NO public code path preloads the panel - not one preload() of a res://view/tester
#       path anywhere in the tree, and the only load() lives in app.gd BEHIND the
#       OS.has_feature("tester") gate, marked TESTER (view/tester itself may reference its
#       own script; tests/ may; nothing else may);
#   (d) sim/ does not know the tester panel exists at all (no sim file mentions it), and
#       world.gd's single tester helper is present but inert;
#   (e) the CI matrix (.github/workflows/build.yml) cannot pick the Tester preset up: the
#       three public presets are named by hand and no line sets preset: Tester;
#   (f) tools/build_tester.ps1 exists and never uploads / creates a release;
#   (g) the tester run-log header flag: run_started's additive extra payload reaches the
#       run_start record (the public default stays byte-identical: type + seed + class).
#
# Sim behaviour is NOT re-asserted here (the brief's "unchanged and green" is the whole
# suite running green - the sim fixtures are the replay suite's own); this file only
# guards the tester build's packaging and the two app-layer additions.

const DIRS_NO_PRELOAD: Array[String] = [
	"res://terrain", "res://sim", "res://core", "res://app",
	"res://view", "res://content", "res://tools",
]
const PRELOAD_RE := "preload\\([^)]*view/tester"
const RUN_LOG_SCRIPT := preload("res://app/run_log.gd")


func run() -> Array[String]:
	var f: Array[String] = []
	_test_export_presets(f)
	_test_panel_headless(f)
	_test_no_public_preload(f)
	_test_app_gate(f)
	_test_sim_ignores_tester(f)
	_test_matrix_cannot_pick_tester(f)
	_test_build_tester_script(f)
	_test_run_log_tester_header(f)
	return f


# ---- (a)/(b): export_presets.cfg ---------------------------------------------------------------


## Splits export_presets.cfg into blocks: preset headers -> the text up to the next
## header. Key=value pairs are matched on whole lines (name=...), so comments and
## option values cannot satisfy a check by accident. _block_value returns null when the
## key is absent (an empty value "" is present and meaningful here, e.g. exclude_filter="").
static func _preset_blocks(text: String) -> Dictionary:
	var out := {}
	var header := ""
	for line in text.split("\n", false):
		var t := line.strip_edges()
		if t.begins_with("[preset.") and t.ends_with("]"):
			header = t.replace("[", "").replace("]", "")
			out[header] = ""
		elif header != "":
			out[header] = str(out[header]) + line + "\n"
	return out


static func _block_value(block: String, key: String):
	for line in block.split("\n", false):
		if line.strip_edges().begins_with(key + "="):
			return line.strip_edges().substr((key + "=").length())
	return null


func _test_export_presets(f: Array[String]) -> void:
	var text := FileAccess.get_file_as_string("res://export_presets.cfg")
	if text == "":
		f.append("tester: export_presets.cfg unreadable")
		return
	var blocks := _preset_blocks(text)
	if not blocks.has("preset.0") or not blocks.has("preset.1") or not blocks.has("preset.2"):
		f.append("tester: the three public presets are not preset.0/1/2 in export_presets.cfg")
		return
	var public_names := {"preset.0": "Windows Desktop", "preset.1": "Linux", "preset.2": "macOS"}
	for pid in public_names.keys():
		var block: String = blocks.get(pid, "")
		if _block_value(block, "platform") == null or \
				str(_block_value(block, "platform")).find(public_names[pid]) < 0:
			f.append("tester: preset order changed (%s no longer %s)" % [pid, public_names[pid]])
		var exc = _block_value(block, "exclude_filter")
		if exc == null:
			f.append("tester: %s has no exclude_filter line" % pid)
		elif not str(exc).contains("view/tester/"):
			f.append("tester: %s exclude_filter does not cover view/tester/ (got %s)"
					% [pid, exc])
		var feats = _block_value(block, "custom_features")
		if feats != null and str(feats).find("tester") >= 0:
			f.append("tester: %s leaks the tester feature tag (custom_features=%s)" % [pid, feats])
	# the Tester preset itself: exists, tagged, exports under out/tester
	var tester_block: String = ""
	for pid in blocks.keys():
		var block: String = blocks.get(pid, "")
		var nm := str(_block_value(block, "name")).trim_prefix("\"").trim_suffix("\"")
		if nm == "Tester":
			tester_block = block
			break
	if tester_block == "":
		f.append("tester: no export preset named \"Tester\" (the feature-tag preset is missing)")
		return
	var feats := str(_block_value(tester_block, "custom_features"))
	var fclean := feats.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if fclean != "tester":
		f.append("tester: the Tester preset's custom_features is not \"tester\" (got %s)" % feats)
	if not str(_block_value(tester_block, "export_path")).contains("out/tester"):
		f.append("tester: the Tester preset does not export under out/tester")


# ---- (b): the panel constructs and toggles headless -------------------------------------------


func _test_panel_headless(f: Array[String]) -> void:
	var PanelScript = load("res://view/tester/debug_panel.gd")
	if PanelScript == null:
		f.append("tester: debug_panel.gd does not load")
		return
	var panel = PanelScript.new()
	panel.setup(null)
	# the whole layout is _init-built: the widgets must exist with no app and no scene tree
	if panel._layer == null or panel._content == null or panel._upgrade_pick == null:
		f.append("tester: the panel built without its dropdowns/layer (headless _init)")
	if panel._status_line == null or panel._meta_line == null or panel._hash_line == null:
		f.append("tester: the panel built without its status/hash lines (headless _init)")
	if panel.is_open():
		f.append("tester: the panel starts open - it must start closed")
	panel.open()
	if not panel.is_open():
		f.append("tester: panel.open() does not open the panel")
	panel.close()
	if panel.is_open():
		f.append("tester: panel.close() does not close the panel")
	# the pure probe: has_method order on instances, has_static_method on Scripts
	var CollapseK: Script = load("res://sim/collapse.gd")
	var probe: Dictionary = panel._first_matching([panel], ["_toggle_god"])
	if probe.is_empty() or str(probe.get("method", "")) != "_toggle_god":
		f.append("tester: _first_matching does not find an instance method")
	var sprobe: Dictionary = panel._first_matching([CollapseK], ["hub_piece"])
	if sprobe.is_empty() or str(sprobe.get("method", "")) != "hub_piece":
		f.append("tester: _first_matching does not find a static method on a Script")
	var none: Dictionary = panel._first_matching([panel, CollapseK], ["no_such_method_at_all"])
	if not none.is_empty():
		f.append("tester: _first_matching invented a method that does not exist")
	panel.free()


# ---- (c): no public code path preloads the panel ----------------------------------------------


## Every .gd under the given roots, res:// paths, recursive.
static func _scan_gd(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	_scan_dir(dir, root, out)
	return out


static func _scan_dir(dir: DirAccess, root: String, out: Array[String]) -> void:
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := root + "/" + name
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan_dir(DirAccess.open(path), path, out)
		elif name.ends_with(".gd"):
			out.append(path)
		name = dir.get_next()
	dir.list_dir_end()


func _test_no_public_preload(f: Array[String]) -> void:
	for root in DIRS_NO_PRELOAD:
		for path in _scan_gd(root):
			if root == "res://view" and path.begins_with("res://view/tester/"):
				continue   # the tester folder may reference its own script
			var text := FileAccess.get_file_as_string(path)
			if text == "":
				f.append("tester: unreadable script %s" % path)
				continue
			if text.contains("view/tester/"):
				# the ONLY allowed reference outside view/tester itself: this file and
				# app.gd's guarded load() - and neither may PRELOAD it
				if not (path == "res://app/app.gd" or path == "res://tests/test_tester_build.gd"):
					f.append("tester: %s references the tester panel from public code" % path)
			if text.contains("preload(") and text.contains("view/tester/"):
				f.append("tester: %s PRELOADS the tester panel - it must be load()-only" % path)


# ---- (d): app gate + sim ignorance --------------------------------------------------------------


func _test_app_gate(f: Array[String]) -> void:
	var text := FileAccess.get_file_as_string("res://app/app.gd")
	if text == "":
		f.append("tester: app.gd unreadable")
		return
	if not text.contains("OS.has_feature(\"tester\")"):
		f.append("tester: app.gd lost the OS.has_feature(\"tester\") gate")
	var gate_at := text.find("OS.has_feature(\"tester\")")
	var load_at := text.find("load(\"res://view/tester/debug_panel.gd\")")
	if load_at < 0:
		f.append("tester: app.gd no longer loads the panel behind the gate")
	elif gate_at < 0 or gate_at > load_at:
		f.append("tester: the feature-tag gate must precede the panel load")
	if text.contains("preload(\"res://view/tester"):
		f.append("tester: app.gd PRELOADS the panel - the public build would bake it in")
	if not text.contains("\"tester\": true"):
		f.append("tester: app.gd no longer flags tester runs in the run-log header")


func _test_sim_ignores_tester(f: Array[String]) -> void:
	for path in _scan_gd("res://sim"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains("tester"):
			f.append("tester: sim file %s mentions \"tester\" - the sim must not know it exists"
					% path)
	var wtext := FileAccess.get_file_as_string("res://app/world.gd")
	if not wtext.contains("func apply_tester_upgrade_stack"):
		f.append("tester: world.gd lost apply_tester_upgrade_stack (the panel's give-upgrade path)")


# ---- (e): the CI matrix cannot pick the Tester preset up ----------------------------------------


func _test_matrix_cannot_pick_tester(f: Array[String]) -> void:
	var text := FileAccess.get_file_as_string("res://../.github/workflows/build.yml")
	if text == "":
		f.append("tester: .github/workflows/build.yml unreadable")
		return
	if text.contains("preset: Tester"):
		f.append("tester: build.yml names the Tester preset - it must never be built in CI")
	var matrix_ok: bool = text.contains("preset: Linux") and text.contains("preset: Windows Desktop") \
			and text.contains("preset: macOS")
	if not matrix_ok:
		f.append("tester: build.yml's matrix no longer names the three public presets")
	# every "Tester" mention in the workflow must be a comment (the guard line itself)
	for line in text.split("\n", false):
		if line.contains("Tester") and not line.strip_edges().begins_with("#"):
			f.append("tester: build.yml mentions Tester outside a comment: %s"
					% line.strip_edges())


# ---- (f): the tester build script exists and never uploads --------------------------------------


func _test_build_tester_script(f: Array[String]) -> void:
	var text := FileAccess.get_file_as_string("res://../tools/build_tester.ps1")
	if text == "":
		f.append("tester: tools/build_tester.ps1 unreadable or missing")
		return
	if not text.contains("--export-release \"Tester\""):
		f.append("tester: build_tester.ps1 does not export the Tester preset")
	for banned in ["upload-artifact", "gh release", "gh -R", "release upload"]:
		if text.contains(banned):
			f.append("tester: build_tester.ps1 contains %s - the tester exe is never uploaded"
					% banned)
	if not text.contains("out\\tester"):
		f.append("tester: build_tester.ps1 does not write under game\\out\\tester")


# ---- (g): the tester run-log header flag ----------------------------------------------------------


func _test_run_log_tester_header(f: Array[String]) -> void:
	var dir := "user://tester_test_t2"
	var path := "%s/1234_0.jsonl" % dir
	DirAccess.make_dir_recursive_absolute(dir)
	var lg := RUN_LOG_SCRIPT.new()
	lg.dir_base = dir
	lg.run_started(1234, "dasher", 0, {"tester": true})
	lg.run_finished(2, 30)
	lg.close()
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		f.append("tester: the run log for the header test was not written")
		return
	var first: Variant = JSON.parse_string(text.split("\n", true)[0])
	if not (first is Dictionary):
		f.append("tester: the run log's first line is not a record")
		return
	var rec: Dictionary = first
	if str(rec.get("type", "")) != "run_start":
		f.append("tester: the first record is not run_start (got %s)" % str(rec.get("type")))
	var payload: Dictionary = rec.get("payload", {})
	if not payload.get("tester", false):
		f.append("tester: run_start's payload does not carry the tester flag")
	if int(payload.get("seed", -1)) != 1234 or str(payload.get("class", "")) != "dasher":
		f.append("tester: run_start's seed/class were disturbed by the extra payload")
	DirAccess.remove_absolute(path)

