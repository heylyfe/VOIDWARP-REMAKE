extends SceneTree
#
# Class-altar screenshot tool (cycle 4 item 7): boots the REAL app (app/app.gd), presses
# PLAY through the menu's own play_requested signal, and captures the class altar exactly
# as the player first sees it - over the loading screen, cursor released, nothing selected.
# Then it presses "2" through the altar's own handle_input (the keyboard path a player
# uses) and captures a selected card. Windowed run - rendering needs a GPU, never --headless:
#
#   <godot> --path game --script res://tests/shot_class_altar.gd -- <out_dir>
#
# Writes <out_dir>/altar_00_first.png  (as opened: no card selected, CONFIRM dead)
#        <out_dir>/altar_01_selected.png (card 2 selected: the focus ring, CONFIRM live)
#        <out_dir>/altar_02_held.png    (5 s later: the loading clock ran out, the run waits)
#        <out_dir>/altar_03_focus_confirm.png (two Tabs walk the ring from card 2 over card 3 to
#                                        CONFIRM; card 3 stays selected - D-GUI-1 focus)
# Prints a DIAG line per shot (mouse mode, card count, per-card icon/name/desc, confirm
# state, the card row's centre vs the viewport centre) so a blank or off-centre shot is not
# mistaken for a fixed one. Named shot_*, not test_*, so tests/run_all.gd skips it. Prints
# "SHOT <path>" per PNG and "SHOTX OK" / "SHOTX FAIL <why>"; exit 1 on failure.

const AppScript := preload("res://app/app.gd")

const SHOT_SIZE := Vector2i(1280, 720)
const RECORDS := "user://shot_class_altar_records.json"

var _out_dir := ""
var _fail := ""
var _app: Node = null


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	root.size = SHOT_SIZE
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0] if args.size() >= 1 else ProjectSettings.globalize_path("res://shots_altar")
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail = "cannot create %s" % _out_dir
		_finish()
		return

	_app = AppScript.new()
	_app.records_path = RECORDS
	root.add_child(_app)   # _ready shows the menu
	for _i in 10:
		await process_frame
	if _app._menu == null:
		_fail = "the app showed no menu"
		_finish()
		return
	_app._menu.play_requested.emit()   # the PLAY press, through the menu's own signal
	for _i in 20:
		await process_frame
	var altar: Control = _app._class_altar
	if altar == null or not altar.is_open():
		_fail = "PLAY did not open the class altar (state %s)" % _app.state()
		_finish()
		return
	_diag("first", altar)
	await _shot("altar_00_first")

	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_2
	altar.handle_input(key)
	await process_frame
	if altar.selected_id() == "":
		_fail = "key 2 selected nothing"
	_diag("selected", altar)
	await _shot("altar_01_selected")

	# The loading clock runs out while the altar is open: the run must wait, not pick.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		await process_frame
	_diag("held", altar)
	print("DIAG held state=%s altar_open=%s held=%s" % [_app.state(),
			str(altar.is_open()), str(_app._held_for_altar)])
	if not altar.is_open() or _app.state() != "LOADING":
		_fail = "the altar did not hold the run (state %s)" % _app.state()
	await _shot("altar_02_held")

	var tab := InputEventKey.new()
	tab.pressed = true
	tab.keycode = KEY_TAB
	altar.handle_input(tab)                  # card 2 -> card 3
	altar.handle_input(tab)                  # card 3 -> CONFIRM (card 3 stays selected)
	await process_frame
	var on: Control = altar.focus_cycle().current() if altar.has_method("focus_cycle") else null
	print("DIAG focus ring on %s, selected '%s'" % [str(on.name) if on != null else "?", altar.selected_id()])
	if on != altar.confirm_button():
		_fail = "two Tabs from card 2 did not put the ring on CONFIRM"
	await _shot("altar_03_focus_confirm")
	_finish()


func _diag(tag: String, altar: Control) -> void:
	var ids: Array = altar.class_ids()
	var parts: PackedStringArray = []
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id in ids:
		var c: Button = altar.card(str(id))
		var r := c.get_global_rect()
		lo = Vector2(minf(lo.x, r.position.x), minf(lo.y, r.position.y))
		hi = Vector2(maxf(hi.x, r.end.x), maxf(hi.y, r.end.y))
		var tr: TextureRect = c.find_children("*", "TextureRect", true, false).front() \
				if not c.find_children("*", "TextureRect", true, false).is_empty() else null
		var nm: Label = c.find_child("Name", true, false)
		var labels := c.find_children("*", "Label", true, false)
		parts.append("%s[icon=%s name='%s' labels=%d]" % [id, str(tr != null and tr.texture != null),
				nm.text if nm != null else "?", labels.size()])
	var mid := (lo + hi) * 0.5
	var cb: Button = altar.confirm_button()
	print("DIAG %s mouse_mode=%d cards=%d %s row_centre=(%.0f,%.0f) vp_centre=(%d,%d) confirm_visible=%s confirm_disabled=%s confirm_rect=%s selected='%s'" % [
			tag, Input.mouse_mode, ids.size(), " ".join(parts), mid.x, mid.y,
			SHOT_SIZE.x / 2, SHOT_SIZE.y / 2, str(cb.is_visible_in_tree()), str(cb.disabled),
			str(cb.get_global_rect()), altar.selected_id()])
	if ids.size() < 3:
		_fail = "the altar shows %d cards" % ids.size()
	if absf(mid.x - SHOT_SIZE.x * 0.5) > 4.0:
		_fail = "the card row is off-centre by %.0f px" % (mid.x - SHOT_SIZE.x * 0.5)
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_fail = "the cursor is not free at the altar (mouse_mode %d)" % Input.mouse_mode


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	if img == null:
		_fail = "viewport texture returned null for %s" % name
		return
	var path := _out_dir.path_join(name + ".png")
	if img.save_png(path) != OK:
		_fail = "save_png(%s) failed" % path
		return
	print("SHOT %s" % path)


func _finish() -> void:
	if _app != null:
		_app.queue_free()
		_app = null
	if FileAccess.file_exists(RECORDS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RECORDS))
	if _fail != "":
		print("SHOTX FAIL %s" % _fail)
		quit(1)
		return
	print("SHOTX OK")
	quit(0)
