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
#       run_start record (the public default stays byte-identical: type + seed + class);
#   (h) the cycle-8 ask (D-T2-10): the enemy dropdown carries EVERY registry enemy plus
#       the pinned Peter row, its popup is height-capped so a long list scrolls, every
#       row fits the panel column, and each entry spawns LIVE through the panel's own
#       path (enemy_runtime for registry ids, the boss arena entry for Peter). The ids
#       come from the registry itself - a new enemy added under content/enemies/ is
#       covered automatically, no name is hardcoded.
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
const AppScript := preload("res://app/app.gd")
const EnemyRuntimeScript := preload("res://sim/enemy_runtime.gd")
const SPAWN_SEED := 7311     # this leg's scratch seed (distinct from every other run's)
const SPAWN_DT := 1.0 / 60.0
const SPAWN_PETER_ID := "peter"   # the pinned boss row's metadata (debug_panel PETER_ID)


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
	_test_panel_enemy_list_and_spawn(f)
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
			# preload() is compile-time: no LINE anywhere may preload the panel
			for line in text.split("\n", false):
				if line.contains("preload(") and line.contains("view/tester/"):
					f.append("tester: %s preloads the tester panel on a line -"
							+ " it must be load()-only: %s"
							% [path, line.strip_edges()])


# ---- (d): app gate + sim ignorance --------------------------------------------------------------


func _test_sim_ignores_tester(f: Array[String]) -> void:
	for path in _scan_gd("res://sim"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains("tester"):
			f.append("tester: sim file %s mentions \"tester\" - the sim must not know it exists"
					% path)
	var wtext := FileAccess.get_file_as_string("res://app/world.gd")
	if not wtext.contains("func apply_tester_upgrade_stack"):
		f.append("tester: world.gd lost apply_tester_upgrade_stack (the panel's give-upgrade path)")
	# Terra review round 1: the granted stack's event hooks must go live the SAME level -
	# the dispatcher rebuild inside apply_tester_upgrade_stack (D-T2-5-amend).
	var rebuilt := false
	for line in wtext.split("\n", false):
		if str(line).contains("_upgrades = UpgradeRuntimeScript.new()"):
			rebuilt = true
	if not rebuilt:
		f.append("tester: world.gd no longer rebuilds the upgrade-hook dispatcher in apply_tester_upgrade_stack")
	# D-T2-9: the per-tick probe + the arena god guard exist on the world.
	if not wtext.contains("var tester_tick_hook"):
		f.append("tester: world.gd lost tester_tick_hook (the panel's tick probe, D-T2-9)")
	if not wtext.contains("var tester_god"):
		f.append("tester: world.gd lost tester_god (the arena god guard, D-T2-6-amend)")
	for guardline in ["boss_projectile_hit_player", "not tester_god"]:
		if not wtext.contains(guardline):
			f.append("tester: world.gd's arena kill path lost its god guard (%s)" % guardline)


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
	# D-T2-9: the world handoff that arms the probe before a world ever steps.
	if not text.contains("call(\"on_world_built\""):
		f.append("tester: app.gd lost the on_world_built handoff (the god-mode first-tick fix)")


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


# ---- (h): cycle 8, D-T2-10 - the list is registry-driven, complete, scrollable, spawnable ----


## The owner's cycle-8 ask. Boot the real app to a live WORLD level, host the real panel
## on the tree, then LOOP over the registry: every id enemy_ids() reports must (a) be in
## the panel's enemy dropdown and (b) spawn a LIVE body through the panel's own path -
## the OptionButton selection driving _spawn, exactly as a mouse pick does. The pinned
## Peter row must route to the boss machinery (the arena entry on the tick hook), never
## to the enemy runtime. A new enemy added under content/enemies/ is swept by the loop
## with no edit here; a hardcoded roster would defeat that.
func _test_panel_enemy_list_and_spawn(f: Array[String]) -> void:
	var scratch := "user://test_tester_spawn_records.json"
	var log_path := "user://runs/%d_0.jsonl" % SPAWN_SEED
	_rm(scratch)
	_rm(log_path)
	var tree = Engine.get_main_loop()
	var root: Window = (tree as SceneTree).root if tree is SceneTree else null
	if root == null:
		f.append("spawn: no SceneTree root to host the app (the headless driver changed)")
		return
	var app = AppScript.new()
	app.records_path = scratch
	app.start_run(SPAWN_SEED)
	root.add_child(app)
	app._ready()
	app._menu.play_requested.emit()
	if app._class_altar != null and app._class_altar.is_open():
		app._class_altar.skip()
	var loading = app._loading
	var guard := 0
	while app.state() == "LOADING" and loading != null and guard < 400:
		loading.advance(0.25)
		guard += 1
	if app.state() != "WORLD" or app._world == null:
		f.append("spawn: the app never reached a live WORLD level (state=%s after %d advances)"
			% [str(app.state()), guard])
		root.remove_child(app)
		app.free()
		return
	var world = app._world
	var PanelScript = load("res://view/tester/debug_panel.gd")
	var panel = PanelScript.new()
	panel.setup(app)
	root.add_child(panel)
	# the app's own handoff (D-T2-9): the panel arms its tick hook before any tick
	panel.on_world_built(world)
	panel.open()
	_report_list_contents(f, panel)
	_report_list_geometry(f, panel, root)
	_spawn_every_registry_enemy(f, panel, world)
	_spawn_peter_through_boss_path(f, panel, world)
	panel.close()
	root.remove_child(panel)
	panel.free()
	root.remove_child(app)
	app.free()
	_rm(scratch)
	_rm(log_path)


## (a) of the ask: the dropdown holds EVERY registry id plus the pinned Peter row, each
## with a real label - no more, no fewer.
func _report_list_contents(f: Array[String], panel) -> void:
	var api: RefCounted = panel._api()
	if api == null:
		f.append("spawn: the panel found no content registry")
		return
	var ids: Array[String] = []
	for id in api.enemy_ids():
		ids.append(str(id))
	var listed: Array[String] = []
	for i in panel._content.item_count:
		listed.append(str(panel._content.get_item_metadata(i)))
		var txt := str(panel._content.get_item_text(i)).strip_edges()
		if txt == "":
			f.append("spawn: enemy list row %d has a blank label" % i)
	if listed.size() != ids.size() + 1:
		f.append("spawn: the enemy list holds %d rows; want the %d registry ids plus Peter (%d)"
			% [listed.size(), ids.size(), ids.size() + 1])
	for id in ids:
		if not listed.has(id):
			f.append("spawn: registry enemy %s is missing from the panel's list" % id)
	if not listed.has(SPAWN_PETER_ID):
		f.append("spawn: the pinned Peter row is missing from the panel's list")
	if listed.has(SPAWN_PETER_ID) and api.enemy_ids().has(SPAWN_PETER_ID):
		f.append("spawn: Peter must be a pinned row, not registry content")


## The "cut off" half of the ask, two teeth: (1) the popup caps at a share of the window
## height, so a list that outgrows the window SCROLLS and every entry stays reachable;
## (2) every horizontal row of the panel column fits the scroll column's width - the
## cycle-8 bug was a 432-px enemies row inside a 370-px column, its spawn buttons off
## the viewport.
func _report_list_geometry(f: Array[String], panel, root: Window) -> void:
	var scroll: ScrollContainer = panel._layer.get_child(0)
	var avail := float(scroll.get_rect().size.x)
	if avail <= 0.0:
		f.append("spawn: the panel's scroll column reports no width (%s)" % str(scroll.get_rect()))
		return
	var column: Container = scroll.get_child(0)
	for row in column.get_children():
		if not (row is HBoxContainer):
			continue
		var rw := 0.0
		var kids: Array = (row as HBoxContainer).get_children()
		for k in kids:
			rw += (k as Control).get_combined_minimum_size().x
		rw += float(maxi(kids.size() - 1, 0)) * \
			float((row as HBoxContainer).get_theme_constant("separation"))
		if rw > avail:
			f.append("spawn: a panel row is %d px wide inside the %d-px column - it is cut off"
				% [int(rw), int(avail)])
	# the popup cap: max_size's height half (this engine has no PopupMenu.max_height);
	# 0 means uncapped, an uncapped list can run past the window
	var vh := float(root.size.y)
	var pop: PopupMenu = panel._content.get_popup()
	var cap := int(pop.max_size.y)
	if cap <= 0:
		f.append("spawn: the enemy popup's max_size height is 0 - an uncapped list can run"
			+ " past the window and its tail is unreachable")
	elif float(cap) > vh * 0.61:
		f.append("spawn: the enemy popup's max_size height %d exceeds the 60%% cap of the %d-px window"
			% [cap, int(vh)])


## (b) of the ask, the registry LOOP: for every id the registry reports, pick it in the
## panel's own dropdown and spawn through the panel's own path, then assert a LIVE row
## reached the world (runtime rows + the body mirror the game's own readers use).
func _spawn_every_registry_enemy(f: Array[String], panel, world) -> void:
	var api: RefCounted = panel._api()
	for id in api.enemy_ids():
		var idx := _panel_row_of(panel, str(id))
		if idx < 0:
			continue   # _report_list_contents already reported the missing row
		panel._content.selected = idx
		var before: int = world.rt.enemies.size()
		var mirrors_before: int = (world.w["enemies"] as Array).size()
		panel._spawn(false)
		var rows: Array = world.rt.enemies
		if rows.size() != before + 1:
			f.append("spawn: %s never reached the runtime (rows %d -> %d)"
				% [str(id), before, rows.size()])
			continue
		var row: Dictionary = rows[rows.size() - 1]
		if str(row["id"]) != str(id):
			f.append("spawn: the panel spawned %s, want %s" % [str(row["id"]), str(id)])
		if EnemyRuntimeScript.is_out_of_play(row):
			f.append("spawn: %s arrived already out of play" % str(id))
		var pos := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
		if not pos.is_finite():
			f.append("spawn: %s arrived at a bad position %s" % [str(id), str(pos)])
		var cfg: Dictionary = row["cfg"]
		var mirrors: int = (world.w["enemies"] as Array).size()
		if not bool(cfg.get("bodyless", false)) and mirrors != mirrors_before + 1:
			f.append("spawn: %s spawned without a body mirror (mirrors %d -> %d)"
				% [str(id), mirrors_before, mirrors])
		if not str(panel._status_line.text).begins_with("spawned "):
			f.append("spawn: %s left the status line at \"%s\"" % [str(id),
				str(panel._status_line.text)])


## Peter: the pinned row must spawn through the BOSS machinery - _force_boss queues the
## arena entry, the world's tick hook runs it (D-T2-9), and the boss instance it created
## enters the arena. A panel that tried the enemy runtime instead never makes
## arena_entered true, and a row that queues nothing fails the tick's assertion.
func _spawn_peter_through_boss_path(f: Array[String], panel, world) -> void:
	var idx := _panel_row_of(panel, SPAWN_PETER_ID)
	if idx < 0:
		f.append("spawn: the Peter row is missing, nothing to pick")
		return
	panel._content.selected = idx
	panel._spawn(false)
	var boss = world.lstate.get("boss") if world.lstate != null else null
	if boss == null:
		f.append("spawn: the Peter row did not create the boss instance")
		return
	if bool(boss.get("arena_entered")):
		f.append("spawn: Peter claims the arena BEFORE the queued tick ran it")
		return
	world.step(SPAWN_DT)
	if not bool(boss.get("arena_entered")):
		f.append("spawn: the Peter row never entered the boss arena on its tick hook")
	if str(panel._status_line.text).find("boss") < 0:
		f.append("spawn: spawning Peter left the status line at \"%s\""
			% str(panel._status_line.text))


## The dropdown row carrying p_id, or -1.
func _panel_row_of(panel, p_id: String) -> int:
	for i in panel._content.item_count:
		if str(panel._content.get_item_metadata(i)) == p_id:
			return i
	return -1


## Remove one user:// file if it exists (the scratch records + this leg's run log).
func _rm(path: String) -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir != null and dir.file_exists(path.get_file()):
		dir.remove(path.get_file())


