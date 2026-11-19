extends RefCounted
#
# Polish cycle 2 (W12-D): menu / HOW TO PLAY completeness, the run-over bests line,
# the centred icon rows. One assertion per fix; the screens' own suites
# (test_menu, test_hud, test_app_death) keep their coverage unchanged.

const HowToScript := preload("res://app/menu_howto.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")
const RunOverScript := preload("res://view/hud/run_over.gd")
const IconRowsScript := preload("res://view/hud/icon_rows.gd")
const RecordsScript := preload("res://core/records.gd")

const SCRATCH := "user://test_polish_cycle2_records_scratch.json"


func run() -> Array[String]:
	var f: Array[String] = []
	_test_howto_controls_complete(f)
	_test_run_over_bests(f)
	_test_run_over_bests_missing_file(f)
	_test_icon_rows_centred(f)
	return f


## W12-D fix: HOW TO PLAY must name every control the game uses. The keyboard rows
## were there; the mouse-look lock key and the whole gamepad row were not.
func _test_howto_controls_complete(f: Array[String]) -> void:
	var b: Dictionary = InputCaptureScript.load_bindings()
	if not (b["errors"] as Array).is_empty():
		f.append("howto: bindings failed to load: %s" % str(b["errors"]))
		return
	var t: String = HowToScript.plain_text(b)
	var mouse_lock := HowToScript.key_name(InputCaptureScript.KEY_MOUSE_LOCK)
	if t.find(mouse_lock) < 0:
		f.append("howto: the CONTROLS section does not name the mouse-look lock key (%s)" % mouse_lock)
	if t.find("left stick") < 0:
		f.append("howto: the CONTROLS section does not document the gamepad move stick")
	var jb: Dictionary = b.get("joy_bindings", {})
	for action in ["jump", "ability", "interact"]:
		var want := str(int(jb.get(action, -1)))
		if t.find(want) < 0:
			f.append("howto: the CONTROLS section does not name the gamepad %s button (%s)" % [action, want])
	# the gamepad row must be read from bindings, never hardcoded: a different
	# bindings file has to move the numbers in the panel
	var shifted := b.duplicate(true)
	var pad: Dictionary = (shifted["joy_bindings"] as Dictionary).duplicate()
	pad["jump"] = 7
	pad["ability"] = 8
	pad["interact"] = 9
	shifted["joy_bindings"] = pad
	var t2: String = HowToScript.plain_text(shifted)
	if t2.find("7 / 8 / 9") < 0:
		f.append("howto: the gamepad row is hardcoded, it does not follow bindings.json")


## W12-D fix: the run-over screen shows the locally recorded bests, not just the
## run numbers. A scratch records file (never the player's real records.json)
## holds best_level 7 / best_purse 450; the screen must show both.
func _test_run_over_bests(f: Array[String]) -> void:
	var seed_rec := RecordsScript.new()
	seed_rec.best_level = 7
	seed_rec.best_purse = 450
	if not seed_rec.save_to(SCRATCH):
		f.append("bests: could not write the scratch records file %s" % SCRATCH)
		return
	var ro = RunOverScript.new()
	ro.records_path = SCRATCH
	ro.show_run_over({"code": "D-VOID", "killer": "", "level": 3, "purse_centi": 120, "charges": 0})
	var bests: Label = ro.bests_label()
	if bests == null:
		f.append("bests: the run-over screen has no bests label")
	else:
		if bests.get_parent() == null:
			f.append("bests: the bests label is not inside the screen's column")
		if bests.text.find("BEST LEVEL 7") < 0:
			f.append("bests: the bests label does not show best level 7 ('%s')" % bests.text)
		if bests.text.find("BEST PURSE 450") < 0:
			f.append("bests: the bests label does not show best purse 450 ('%s')" % bests.text)
	ro.free()
	_remove_scratch()


## A missing records file reads as 0/0 (records.gd's contract) - never an error.
func _test_run_over_bests_missing_file(f: Array[String]) -> void:
	_remove_scratch()
	var ro = RunOverScript.new()
	ro.records_path = SCRATCH
	ro.show_run_over({"code": "D-VOID", "killer": "", "level": 1, "purse_centi": 0, "charges": 0})
	var bests: Label = ro.bests_label()
	if bests != null and (bests.text.find("BEST LEVEL 0") < 0 or bests.text.find("BEST PURSE 0") < 0):
		f.append("bests: a missing records file did not read as 0/0 ('%s')" % bests.text)
	ro.free()


## W12-D fix: the curse/upgrade rows are centred in their anchor box so cells
## never walk into the roster (top-left) or the purse (top-right).
func _test_icon_rows_centred(f: Array[String]) -> void:
	var rows = IconRowsScript.new()
	var curses: HBoxContainer = rows.get_node_or_null("Rows/CursesRow")
	var upgrades: HBoxContainer = rows.get_node_or_null("Rows/UpgradesRow")
	if curses == null or upgrades == null:
		f.append("icon rows: the centred row nodes are missing")
	else:
		if curses.alignment != BoxContainer.ALIGNMENT_CENTER:
			f.append("icon rows: the curse row is not centred (cells start at the box's left edge)")
		if upgrades.alignment != BoxContainer.ALIGNMENT_CENTER:
			f.append("icon rows: the upgrade row is not centred (cells start at the box's left edge)")
	rows.free()


func _remove_scratch() -> void:
	var da := DirAccess.open("user://")
	if da != null:
		da.remove(SCRATCH.get_file())
