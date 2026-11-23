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
#   (h) the cycle-8 ask (D-T2-10/D-T2-11): the enemy picker is an IN-PANEL scroll list
#       (no popup Window anywhere near choosing an enemy) that carries EVERY registry
#       enemy plus the pinned Peter row, every entry spawns LIVE through the panel's own
#       path - the world's single tester_spawn_enemy entry for registry ids (ahead AND at
#       the cursor), the boss arena entry for Peter - and the ids come from the registry
#       itself, so a new enemy added under content/enemies/ is swept automatically, no
#       name hardcoded. Claude and gin are ALSO asserted by name (the owner names them).
#       The rest of the panel is regression-pinned in the same boot: gold, gifts, upgrade
#       stacks, charges, god mode, force collapse, force bankai's fallback, skip level,
#       the hash probe, panels at 1280x720 and 1920x1080, and the tester build's boot.
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
const CollapseState := preload("res://sim/collapse.gd")
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
		f.append("tester: the panel built without its list/picker/layer (headless _init)")
	if panel._enemy_host == null or panel._enemy_scroll == null:
		f.append("tester: the panel built without its enemy list viewport (D-T2-11)")
	if not (panel._content is ItemList):
		f.append("tester: the enemy picker is not an in-panel ItemList (D-T2-11)")
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


# ---- (h): cycle 8, D-T2-11 - the list is in-panel, registry-driven, complete, scrollable, spawnable ----


## The owner's cycle-8 ask. Boot the real app to a live WORLD level (that IS the tester
## build's start leg: menu -> altar -> loading -> live level, no scene file), host the real
## panel on the tree, then LOOP over the registry: every id enemy_ids() reports must (a)
## be in the panel's enemy list - through the registry loop, and Claude / gin BY NAME as
## well (the owner names them) - and (b) spawn a LIVE body through the panel's own path
## for BOTH spawn buttons. The pinned Peter row must route to the boss machinery (the
## arena entry on the tick hook), never to the enemy runtime. The same boot then
## regression-pins the REST of the panel: the hash probe, gold, gifts, an upgrade stack,
## charges, god mode, force collapse, force bankai's fallback, and skip level (last - it
## tears the world down). A new enemy added under content/enemies/ is swept by the loop
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
		f.append("spawn: the tester build never reached a live WORLD level (state=%s after"
				+ " %d advances) - the boot itself is broken" % [str(app.state()), guard])
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
	_owner_named_enemies(f, panel)
	_report_list_geometry(f, panel, root)
	_panel_actions_regression(f, panel, world, app)
	_spawn_every_registry_enemy(f, panel, world, false)
	_spawn_every_registry_enemy(f, panel, world, true)
	_bankai_fallback_action(f, panel, world)
	_spawn_peter_through_boss_path(f, panel, world)
	_skip_level_action(f, panel, app)
	panel.close()
	root.remove_child(panel)
	panel.free()
	root.remove_child(app)
	app.free()
	_rm(scratch)
	_rm(log_path)


## (a) of the ask: the list holds EVERY registry id plus the pinned Peter row, each with
## a real label - no more, no fewer, each id EXACTLY ONCE (a duplicated row would read as
## "all enemies listed" while hiding one behind another).
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
		var n := listed.count(id)
		if n != 1:
			f.append("spawn: registry enemy %s is listed %d times (want exactly one row)"
					% [id, n])
	if listed.count(SPAWN_PETER_ID) != 1:
		f.append("spawn: the pinned Peter row must list EXACTLY once (got %d rows)"
				% listed.count(SPAWN_PETER_ID))
	if listed.has(SPAWN_PETER_ID) and api.enemy_ids().has(SPAWN_PETER_ID):
		f.append("spawn: Peter must be a pinned row, not registry content")


## The owner names Claude and Gin ("showing ALL enemies incl. Claude, Gin, Peter"), so the
## two are asserted BY NAME on top of the registry loop: the registry must still carry the
## id, its display name must still say the name, and the list row carrying the id must
## show that display name. If the roster ever loses the owner's named enemies, this
## fails even though the registry loop would pass against whatever else is registered.
func _owner_named_enemies(f: Array[String], panel) -> void:
	var api: RefCounted = panel._api()
	if api == null:
		return
	for wanted in [["claude", "Claude"], ["gin", "Gin"]]:
		var id := str(wanted[0])
		var nm := str(wanted[1])
		var ids: Array = api.enemy_ids()
		if not ids.has(id):
			f.append("spawn: the owner's named enemy %s is not in the registry any more" % id)
			continue
		var display := str(api.enemy(id).get("name", ""))
		if display.to_lower().find(nm.to_lower()) < 0:
			f.append("spawn: registry enemy %s no longer says %s (name=%s)"
					% [id, nm, display])
		var idx := _panel_row_of(panel, id)
		if idx < 0:
			f.append("spawn: the owner's named enemy %s has no row in the panel list" % id)
			continue
		var label := str(panel._content.get_item_text(idx))
		if label.to_lower().find(nm.to_lower()) < 0:
			f.append("spawn: the %s row's label does not say the name (row %d: %s)"
					% [id, idx, label])
## The "cut off" half of the ask, now that the list is in-panel (D-T2-11): (1) NO popup
## Window anywhere in the enemy-picking subtree - the failure mode this track removes was
## an OptionButton popup whose entries could not all be reached; (2) every horizontal row
## of the panel column fits the scroll column's width - at BOTH 1280x720 and 1920x1080
## (the cycle-8 bug was a 432-px enemies row inside a 370-px column); (3) the enemy list
## viewport is height-BOUNDED, the list inside it carries its FULL content height and
## vertical scrolling stays on, so the roster overflows the viewport and the list scrolls
## IN PLACE - the LAST row is one wheel-turn away at any window size. Horizontal
## scrolling is disabled inside the list, so a long label can never run past the column.
func _report_list_geometry(f: Array[String], panel, root: Window) -> void:
	# (a) the failure mode itself: no Window-mode node in the enemy-picking subtree
	var pick_win := _first_window_under(panel._enemy_host)
	if pick_win != null:
		f.append("spawn: the enemy picker involves a popup Window (%s) - D-T2-11: choosing"
				+ " an enemy must happen in the panel, no Window can take part"
				% str(pick_win.name))
	var scroll: ScrollContainer = panel._layer.get_child(0)
	var avail := float(scroll.get_rect().size.x)
	if avail <= 0.0:
		avail = float(scroll.custom_minimum_size.x)   # the panel's own fixed column width
	# the list subtree (a ScrollContainer cannot scroll horizontally here, a PopupMenu
	# cannot appear): the bound wins exactly when the viewport's minimum height stops at
	# the cap while the list's content height keeps growing
	var host_min: Vector2 = panel._enemy_host.get_combined_minimum_size()
	var list_min: Vector2 = panel._content.get_combined_minimum_size()
	if host_min.y > panel.LIST_CAP_H + 0.5:
		f.append("spawn: the enemy list viewport grew to %d px - it must stay bounded at %d"
				+ " px so the spawn buttons under it are on screen at any window size"
				% [int(host_min.y), int(panel.LIST_CAP_H)])
	var rows: int = panel._content.item_count
	if absf(list_min.y - float(rows) * panel.LIST_ROW_H) > 0.5:
		f.append("spawn: the enemy list's content height is %d px, want all %d rows at full"
				+ " height (%d) - a list that does not carry its whole content cannot"
				+ " scroll to its last row" % [int(list_min.y), rows,
				int(float(rows) * panel.LIST_ROW_H)])
	if list_min.y > host_min.y + 0.5 \
			and panel._enemy_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
		f.append("spawn: the enemy roster overflows its viewport (%d px in %d px) but the"
				+ " scroll is off - entries below the fold are unreachable"
				% [int(list_min.y), int(host_min.y)])
	if panel._enemy_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		f.append("spawn: the enemy list may scroll horizontally - a row could run past the"
				+ " 370-px column (D-T2-10's row-fit rule)")
	# the LAST row must be reachable: it is exactly when the content the viewport scrolls
	# is the FULL list (content height pinned above) and the viewport is bounded (pinned
	# above) with scrolling on (pinned above): every row, the last one included, sits
	# inside the scroll's wheel range.
	if rows > 0 and list_min.y <= host_min.y + 0.5 \
			and float(rows) * panel.LIST_ROW_H > panel.LIST_CAP_H:
		f.append("spawn: a %d-row list claims to fit its %d-px viewport - the bound or the"
				+ " content height is lying, one of the two must give" % [rows,
				int(host_min.y)])
	# (b) the row-fit rule at both resolutions the owner runs
	var had_size: Vector2i = root.size
	for res in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = res
		var avail_n := float(panel._layer.get_child(0).get_rect().size.x)
		if avail_n <= 0.0:
			avail_n = avail
		_rows_fit_column(f, panel, avail_n, res)
	root.size = had_size


## One resolution's row-fit check: every HBox row of the panel column fits the scroll
## column's width (combined minimum sizes - the arithmetic the layout itself runs).
func _rows_fit_column(f: Array[String], panel, avail: float, res: Vector2i) -> void:
	var column: Container = panel._layer.get_child(0).get_child(0)
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
			var parts: Array[String] = []
			for k in kids:
				var kc := k as Control
				parts.append("%s[%s] min=%d" % [str(kc.name), str(kc.get("text")),
					int(kc.get_combined_minimum_size().x)])
			f.append("spawn: at %dx%d a panel row is %d px wide inside the %d-px column"
					+ " - it is cut off (row %s: %s)" % [res.x, res.y, int(rw), int(avail),
					str(row.name), " | ".join(parts)])


## The first Window-mode node anywhere under p_node (null when there is none) - the
## no-popup probe. A PopupMenu IS a Window in this engine, so any picker that opens one
## is caught however it was built. NOTE: it does not descend into the panel's spawn
## buttons' own subtrees; the OptionButton upgrade picker's popup is legitimately a Window
## (the owner's complaint is the ENEMY list), and it lives outside the host probed here.
static func _first_window_under(p_node: Node) -> Window:
	var stack: Array = [p_node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Window:
			return n
		for c in n.get_children():
			stack.append(c)
	return null
## No-regression pins for the REST of the panel, in the SAME boot, live app/world state
## each time: the meta line + hash probe, GIVE GOLD, GIVE N GIFTS through the queued tick
## job (one real world.step collects them and the purse takes the payout), GIVE +1 STACK
## into the run ledger, SET CHARGES, GOD MODE mirror + invuln window, FORCE COLLAPSE
## leaving the schedule's idle phase. Each of these is the panel's own action function -
## the same callable the button wiring presses.
func _panel_actions_regression(f: Array[String], panel, world, app) -> void:
	panel._process(0.0)
	if not str(panel._meta_line.text).contains("SEED %d" % SPAWN_SEED):
		f.append("panel: the meta line no longer reports the run (%s)"
				% str(panel._meta_line.text))
	var hash := str(panel._hash_line.text)
	if hash.length() != 64 or not hash.is_valid_hex_number():
		f.append("panel: the hash probe no longer shows a sha256 (got \"%s\")" % hash)
	var gold_before := int(world._economy.purse_centi)
	panel._give_gold()
	if int(world._economy.purse_centi) - gold_before != int(panel._gold_spin.value) * 100:
		f.append("panel: GIVE GOLD left a wrong purse delta (%d for %d gold)"
				% [int(world._economy.purse_centi) - gold_before,
				int(panel._gold_spin.value)])
	var purse_before := int(world._economy.purse_centi)
	panel._give_gifts()
	world.step(SPAWN_DT)
	if not str(panel._status_line.text).begins_with("collected"):
		f.append("panel: GIVE N GIFTS left the status line at \"%s\" - the queued tick"
				+ " job never ran in the world's step" % str(panel._status_line.text))
	elif int(world._economy.purse_centi) <= purse_before:
		f.append("panel: the gift collect paid no gold (purse %d -> %d)"
				% [purse_before, int(world._economy.purse_centi)])
	var up_ids: Array = panel._api().upgrade_ids()
	if up_ids.is_empty():
		f.append("panel: the registry reports no upgrades - the give-stack leg cannot run")
	else:
		var up := str(up_ids[0])
		panel._refresh_options()
		var up_row := -1
		for i in panel._upgrade_pick.item_count:
			if str(panel._upgrade_pick.get_item_metadata(i)) == up:
				up_row = i
		if up_row >= 0:
			panel._upgrade_pick.selected = up_row
		var stacks: Dictionary = world.run_ledger().get("stacks", {})
		var had := int(stacks.get(up, 0))
		panel._give_upgrade()
		if int(world.run_ledger().get("stacks", {}).get(up, 0)) != had + 1:
			f.append("panel: GIVE +1 STACK left the ledger unchanged for %s" % up)
	panel._charge_spin.value = 3
	panel._set_charges()
	if int(world.ctl.charges) != 3:
		f.append("panel: SET CHARGES left the controller at %d" % int(world.ctl.charges))
	panel._toggle_god()
	if not bool(world.tester_god) or float(world.ctl.invuln) < 1.0:
		f.append("panel: GOD MODE ON did not mirror the world flag or open the invuln"
				+ " window (tester_god=%s invuln=%f)"
				% [str(bool(world.tester_god)), float(world.ctl.invuln)])
	panel._toggle_god()
	if bool(world.tester_god):
		f.append("panel: GOD MODE OFF left the world flag set")
	panel._force_collapse()
	if CollapseState.phase(world._collapse) == CollapseState.PHASE_IDLE:
		f.append("panel: FORCE COLLAPSE left the schedule IDLE - the cracks never arm")


## FORCE BANKAI's fallback: no boss is live yet (the Peter leg comes later), so the
## button's honest no-boss path must run - the standalone preview - without touching the
## world or crashing the live level. The with-boss path is exercised by its own track's
## suite (T8); what must not regress is the button's no-live-boss behaviour.
func _bankai_fallback_action(f: Array[String], panel, world) -> void:
	var boss = world.lstate.get("boss") if world.lstate != null else null
	if boss != null and bool(boss.get("arena_entered")):
		f.append("panel: a boss arena claim exists BEFORE the Peter leg - ordering broke")
		return
	var status := str(panel._status_line.text)
	panel._force_bankai()
	var s := str(panel._status_line.text)
	if s == status and s.find("bankai") < 0:
		f.append("panel: FORCE BANKAI did nothing and reported nothing about bankai"
				+ " (status \"%s\")" % s)


## SKIP LEVEL, last - it tears the live world down. The app's own completion path runs
## (the Antechamber opens), proving the panel's skip wiring still reaches it.
func _skip_level_action(f: Array[String], panel, app) -> void:
	var lv := int(app._world.call("level_number"))
	panel._skip_level()
	if str(app.state()) != "LOBBY" or app._lobby == null:
		f.append("panel: SKIP LEVEL left the app in state %s with lobby %s - the"
				+ " Antechamber never opened for level %d"
				% [str(app.state()), str(app._lobby), lv])
## (b) of the ask, the registry LOOP: for every id the registry reports, pick it in the
## panel's own list and drive the panel's own spawn path - once through SPAWN AHEAD
## (p_at_cursor false) and once through SPAWN AT CURSOR (true) - then assert a LIVE row
## reached the world by reading the runtime rows BACK BY ID: the id must have one row
## more than it had before, in play, at a finite position, with the body mirror grown.
## The single world spawn entry (U2b) does the row build + the clawds attach for claude.
func _spawn_every_registry_enemy(f: Array[String], panel, world, p_at_cursor: bool) -> void:
	var api: RefCounted = panel._api()
	var kind := "at the cursor" if p_at_cursor else "ahead"
	for id in api.enemy_ids():
		var id_s := str(id)
		var idx := _panel_row_of(panel, id_s)
		if idx < 0:
			continue   # _report_list_contents already reported the missing row
		panel._content.deselect_all()
		panel._content.select(idx)
		var before := _rows_of(world, id_s)
		var mirrors_before: int = (world.w["enemies"] as Array).size()
		panel._spawn(p_at_cursor)
		var rows: Array = world.rt.enemies
		var after := _rows_of(world, id_s)
		if after != before + 1:
			f.append("spawn: %s (%s) never reached the runtime by id (%d rows before, %d"
					+ " after)" % [id_s, kind, before, after])
			continue
		var row: Dictionary = rows[rows.size() - 1]
		if str(row["id"]) != id_s:
			f.append("spawn: the panel spawned %s at button %s while reading back %s"
					% [id_s, kind, str(row["id"])])
		if EnemyRuntimeScript.is_out_of_play(row):
			f.append("spawn: %s (%s) arrived already out of play" % [id_s, kind])
		var pos := Vector3(float(row["x"]), float(row["y"]), float(row["z"]))
		if not pos.is_finite():
			f.append("spawn: %s (%s) arrived at a bad position %s" % [id_s, kind, str(pos)])
		var cfg: Dictionary = row["cfg"]
		var mirrors: int = (world.w["enemies"] as Array).size()
		if not bool(cfg.get("bodyless", false)) and mirrors != mirrors_before + 1:
			f.append("spawn: %s (%s) spawned without a body mirror (mirrors %d -> %d)"
					% [id_s, kind, mirrors_before, mirrors])
		if not str(panel._status_line.text).begins_with("spawned "):
			f.append("spawn: %s (%s) left the status line at \"%s\""
					% [id_s, kind, str(panel._status_line.text)])


## The runtime rows carrying p_id (the read-back-by-id the game's own readers use).
static func _rows_of(world, p_id: String) -> int:
	var n := 0
	for row in world.rt.enemies:
		if str(row["id"]) == p_id:
			n += 1
	return n


## Peter: the pinned row must spawn through the BOSS machinery - _force_boss queues the
## arena entry, the world's tick hook runs it (D-T2-9), and the boss instance it created
## enters the arena - and NEVER through the enemy runtime: no "peter" row may exist in
## the enemy runtime. A panel that tried the runtime instead never makes
## arena_entered true, and a row that queues nothing fails the tick's assertion.
func _spawn_peter_through_boss_path(f: Array[String], panel, world) -> void:
	var idx := _panel_row_of(panel, SPAWN_PETER_ID)
	if idx < 0:
		f.append("spawn: the Peter row is missing, nothing to pick")
		return
	var rt_rows_before: int = world.rt.enemies.size()
	panel._content.deselect_all()
	panel._content.select(idx)
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
	if world.rt.enemies.size() != rt_rows_before:
		f.append("spawn: the Peter row reached the ENEMY RUNTIME (rows %d -> %d) - he"
				+ " rides the boss machinery, not the runtime"
				% [rt_rows_before, world.rt.enemies.size()])
	if _rows_of(world, SPAWN_PETER_ID) != 0:
		f.append("spawn: a \"%s\" enemy row exists in the runtime - Peter is boss content"
				% SPAWN_PETER_ID)
	if str(panel._status_line.text).find("boss") < 0:
		f.append("spawn: spawning Peter left the status line at \"%s\""
				% str(panel._status_line.text))


## The list row carrying p_id, or -1.
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
