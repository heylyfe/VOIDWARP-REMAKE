extends RefCounted
#
# test_review_fixes.gd - the small fixes from the fresh-eyes review (out/review_alpha.md):
#   leg 1 (finding 3): a run ends, the app returns to the menu, and the REUSED menu's
#     bests line reflects the new records file - not the launch-time values. _show_menu()
#     points the menu at the app's records_path and calls refresh_records() on reuse.
#   leg 2 (finding 4): a corrupt player.json (classes is not a Dictionary) no longer
#     aborts the altar's _init() - the altar still builds (a title + SKIP, zero class
#     rows), never an empty full-rect stop that swallows the mouse with nothing visible.
#     Same class of bug in view/audio/threat_cues.gd: one corrupt audio_cue_timing row no
#     longer aborts the whole cue scan; every Dictionary row after it still loads.
#   leg 3 (finding 5): ESC during LOADING does not write a fake level-1 run into the
#     records - the records file is never created. A run that reached WORLD still records
#     (leg 1 is that positive control).
#
# Headless, outside the scene tree, like test_app_pause_class.gd: the app node is not
# added to the tree; the test calls _ready() itself and drives the world via app._process.

const AppScript := preload("res://app/app.gd")
const RecordsScript := preload("res://core/records.gd")
const ClassAltarScript := preload("res://app/class_altar.gd")
const ThreatCuesScript := preload("res://view/audio/threat_cues.gd")

const SEED := 1
const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_menu_bests_refresh(f)
	_leg_altar_corrupt_classes(f)
	_leg_cues_corrupt_row(f)
	_leg_esc_loading_no_record(f)
	return f


func _esc(app) -> void:
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	app._unhandled_input(esc)


func _drive_to_world(f: Array[String], app) -> void:
	# the run waits at the class altar until the player confirms or skips (item 7): a run with no pick
	# yet presses SKIP, the seeded replay's class - what the old expiring window did
	_skip_open_altar(app)
	var loading = app._loading
	var guard := 0
	while app.state() == "LOADING" and loading != null and guard < 400:
		loading.advance(0.25)
		guard += 1
	if app.state() != "WORLD":
		f.append("boot: the app never reached WORLD (state=%s after %d advances)"
				% [app.state(), guard])


func _remove_scratch(scratch: String) -> void:
	var da := DirAccess.open("user://")
	if da != null:
		da.remove(scratch.get_file())


func _count_buttons(node: Node) -> int:
	var n := 1 if node is Button else 0
	for c in node.get_children():
		n += _count_buttons(c)
	return n

# ---- leg 1: the reused menu shows the records the run just ratcheted -------------------

func _leg_menu_bests_refresh(f: Array[String]) -> void:
	var scratch := "user://test_review_menu_scratch.json"
	_remove_scratch(scratch)
	var app = AppScript.new()
	app.records_path = scratch
	app.start_run(SEED)
	app._ready()
	app._menu.play_requested.emit()   # PLAY: hides the menu, builds the world, enters LOADING
	_esc_check_menu_fresh(f, app)
	_drive_to_world(f, app)
	if app.state() != "WORLD":
		app.free()
		_remove_scratch(scratch)
		return
	_esc(app)   # opens the pause overlay
	if app._pause_overlay == null:
		f.append("menu bests: ESC mid-run did not open the pause overlay")
		app.free()
		_remove_scratch(scratch)
		return
	app._pause_overlay.abandon_requested.emit()   # abandon: back to the menu
	if app.state() != "MENU":
		f.append("menu bests: abandon left app in %s, want MENU" % app.state())
		app.free()
		_remove_scratch(scratch)
		return
	# the abandoned run ratcheted the scratch records (level 1) ...
	var rec := RecordsScript.new()
	rec.load_from(scratch)
	if rec.get_best_level() != 1:
		f.append("menu bests: the abandoned run did not ratchet the scratch records (best_level=%d)"
				% rec.get_best_level())
	# ... and the REUSED menu shows them, not the launch-time 0/0
	var bests: Label = app._menu.bests_label()
	if bests == null:
		f.append("menu bests: the menu has no bests label")
	elif not bests.text.contains("BEST LEVEL 1"):
		f.append("menu bests: the reused menu shows '%s', want BEST LEVEL 1" % bests.text)
	app.free()
	_remove_scratch(scratch)


func _esc_check_menu_fresh(f: Array[String], app) -> void:
	# at boot the scratch file does not exist: the menu reads 0/0
	var bests: Label = app._menu.bests_label()
	if bests == null:
		f.append("menu bests: no bests label at boot")
	elif not bests.text.contains("BEST LEVEL 0"):
		f.append("menu bests: the fresh menu shows '%s', want BEST LEVEL 0" % bests.text)

# ---- leg 2: corrupt data files do not leave an invisible input trap / a dropped scan ----

func _leg_altar_corrupt_classes(f: Array[String]) -> void:
	var scratch := "user://test_review_altar_scratch.json"
	var cases := ["{\"classes\": 42}", "{\"classes\": [\"dasher\", \"glider\"]}", "{\"classes\": \"nope\"}"]
	for i in cases.size():
		var fh := FileAccess.open(scratch, FileAccess.WRITE)
		fh.store_string(str(cases[i]))
		fh.close()
		var old := str(ClassAltarScript.PlayerDataPath)
		ClassAltarScript.PlayerDataPath = scratch
		var altar = ClassAltarScript.new()
		ClassAltarScript.PlayerDataPath = old
		if altar.class_ids().size() != 0:
			f.append("altar: corrupt classes case %d yielded %d rows, want 0"
					% [i, altar.class_ids().size()])
		if altar.get_child_count() < 2:
			f.append("altar: corrupt classes case %d built %d children - an empty full-rect stop"
					% [i, altar.get_child_count()])
		if _count_buttons(altar) < 1:
			f.append("altar: corrupt classes case %d left no buttons - an invisible input trap" % i)
		var emitted := ["", false]
		altar.class_chosen.connect(func(id: String) -> void: emitted[0] = id)
		altar.skipped.connect(func() -> void: emitted[1] = true)
		altar.open("")
		if not altar.is_open():
			f.append("altar: corrupt classes case %d - open() did not show the altar" % i)
		altar.choose("not_a_class_id")   # refused at the table; must not emit
		if emitted[0] != "" or altar.chosen_id() != "":
			f.append("altar: corrupt classes case %d - an unknown id was accepted" % i)
		altar.skip()
		if not emitted[1]:
			f.append("altar: corrupt classes case %d - skip() emitted nothing" % i)
		altar.free()
	_remove_scratch(scratch)


func _leg_cues_corrupt_row(f: Array[String]) -> void:
	var root := "user://test_review_cues_root"
	var fixture_rel := "test_review_cues_root/cuefixture"
	var fixture_dir := "user://" + fixture_rel
	var da := DirAccess.open("user://")
	if da == null or da.make_dir_recursive(fixture_rel) != OK:
		f.append("cues: could not make the scratch content root")
		return
	var fh := FileAccess.open(fixture_dir + "/enemy.json", FileAccess.WRITE)
	# broken_row sorts BEFORE good_row: with the bug, the typed assignment aborted the
	# scan and the good row never landed in by_kind
	fh.store_string("{\"id\": \"cuefixture\", \"stats\": {\"audio_cue_timing\": {\"broken_row\": 42, \"good_row\": {\"event\": \"telegraph\", \"kind\": \"review_fix_kind\", \"offset_ticks\": 5, \"role\": \"test\"}}}}")
	fh.close()
	var old := str(ThreatCuesScript.ENEMY_ROOT)
	ThreatCuesScript.ENEMY_ROOT = root
	var tc = ThreatCuesScript.new()
	ThreatCuesScript.ENEMY_ROOT = old
	if not tc.by_kind.has("review_fix_kind"):
		f.append("cues: the valid row after a corrupt row was dropped (by_kind=%s)"
				% str(tc.by_kind.keys()))
	else:
		var entries: Array = tc.by_kind["review_fix_kind"]
		if entries.size() != 1 or int(entries[0].get("offset", -1)) != 5:
			f.append("cues: the surviving cue entry is wrong: %s" % str(entries))
	var da2 := DirAccess.open("user://")
	if da2 != null:
		da2.remove(fixture_rel + "/enemy.json")
		da2.remove(fixture_rel)
		da2.remove("test_review_cues_root")

# ---- leg 3: ESC during LOADING writes nothing to the records -----------------------------

func _leg_esc_loading_no_record(f: Array[String]) -> void:
	var scratch := "user://test_review_loading_scratch.json"
	_remove_scratch(scratch)
	var app = AppScript.new()
	app.records_path = scratch
	app.start_run(SEED)
	app._ready()
	app._menu.play_requested.emit()
	if app.state() != "LOADING":
		f.append("loading esc: PLAY left app in %s, want LOADING" % app.state())
		app.free()
		_remove_scratch(scratch)
		return
	_esc(app)   # ESC during LOADING: no run ever reached the world
	if app.state() != "MENU":
		f.append("loading esc: ESC during LOADING left app in %s, want MENU" % app.state())
	if FileAccess.file_exists(scratch):
		var rec := RecordsScript.new()
		rec.load_from(scratch)
		f.append("loading esc: ESC during LOADING wrote a records file (best_level=%d)"
				% rec.get_best_level())
	app.free()
	_remove_scratch(scratch)


## The player presses SKIP at a still-open class altar (no-op once a pick closed it).
func _skip_open_altar(app) -> void:
	if app._class_altar != null and app._class_altar.is_open():
		app._class_altar.skip()
