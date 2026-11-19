extends Control
#
# The class altar (gap 2; DESIGN.md section 4: "Class is chosen at a class altar in the
# pre-run lobby"). The app skipped that lobby and rolled 1-in-3 at run start; now a real
# PLAY press shows this panel over the loading screen, before the run starts, and the
# pick is what the run uses (app.gd rebuilds the level-1 world around the loading screen
# with a carried ledger whose class IS the pick).
#
# The three altars are drawn from data/player.json's class table (the same table
# sim/intermission.gd's CLASS bay draws from) - no class id is invented here, and every
# number in a blurb is the file's own value. A SKIP entry keeps the previous behaviour:
# the seeded pre-run replay decides the class.
#
# Headless-built like view/hud/run_over.gd: the layout is _init, no scene tree needed.
# public API:
#   signal class_chosen(class_id: String)
#   signal skipped
#   func open(p_current := "")  - show, marking the current pick on the altars
#   func close() / func is_open() / func chosen_id() / func class_ids()
#   func choose(class_id)       - one pick: validates against the table, emits the signal
#   func skip()                 - emits skipped
#   static func blurb(class_id, p_classes) -> String   - the one-line kit text

const PlayerDataPath := "res://data/player.json"

const C_VOID := Color(0.0078, 0.0118, 0.0588)        # #02030F the void backdrop (menu.gd)
const C_WHITE := Color(0.910, 1.0, 1.0)              # #E8FFFF beacon_open
const C_GOLD := Color(1.0, 0.784, 0.239)             # #FFC83D gold_gift
const C_MUTED := Color(0.545, 0.620, 0.718)

signal class_chosen(class_id: String)
signal skipped

var chosen: String = ""                 # the pick made at this altar this visit
var _classes: Dictionary = {}           # player.json's class table (id -> block)
var _buttons: Dictionary = {}           # id -> Button
var _skip: Button


func _init() -> void:
	name = "ClassAltar"
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(PlayerDataPath))
	if doc is Dictionary:
		_classes = (doc as Dictionary).get("classes", {})
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var title := Label.new()
	title.text = "THE CLASS ALTAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", C_WHITE)
	col.add_child(title)
	var sub := Label.new()
	sub.text = "choose a kit - the run uses the pick"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", C_MUTED)
	col.add_child(sub)
	var rule := ColorRect.new()
	rule.color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.85)
	rule.custom_minimum_size = Vector2(64, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(rule)
	# one altar row per class in the table, in the schedule's own sorted order
	var ids: Array = _classes.keys()
	ids.sort()
	for id in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		col.add_child(row)
		var b := Button.new()
		b.text = str(id).capitalize()
		b.name = "Altar" + str(id).capitalize()
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", C_GOLD)
		b.custom_minimum_size = Vector2(220, 46)
		var fid := str(id)
		b.pressed.connect(func() -> void: choose(fid))
		row.add_child(b)
		_buttons[fid] = b
		var blurb_label := Label.new()
		blurb_label.text = blurb(fid, _classes)
		blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb_label.custom_minimum_size = Vector2(430, 0)
		blurb_label.add_theme_font_size_override("font_size", 15)
		blurb_label.add_theme_color_override("font_color", C_MUTED)
		row.add_child(blurb_label)
	_skip = Button.new()
	_skip.text = "SKIP - let the seed decide"
	_skip.focus_mode = Control.FOCUS_ALL
	_skip.add_theme_font_size_override("font_size", 17)
	_skip.add_theme_color_override("font_color", C_MUTED)
	_skip.pressed.connect(func() -> void: skip())
	col.add_child(_skip)


## The one-line kit text per class, composed from player.json's own numbers.
## The active-ability classes name their lock lines the way section 4 does.
static func blurb(class_id: String, p_classes: Dictionary) -> String:
	var c: Dictionary = p_classes.get(class_id, {})
	match class_id:
		"dasher":
			return "Dash %.1f u in %.2f s in the input direction, usable in air. One charge, regenerates in %.1f s." % [
				float(c.get("dash_distance", 6.0)), float(c.get("dash_time", 0.2)),
				float(c.get("dash_regen", 3.0))]
		"glider":
			return "Hold jump while falling: fall capped at %.1f u/s, moving %.1f u/s. Glide energy %.1f s, refills on landing." % [
				float(c.get("glide_fall_speed_cap", 2.0)),
				float(c.get("glide_horizontal_speed", 10.0)),
				float(c.get("glide_energy", 3.0))]
		"athletic":
			return "+%.0f%% run speed from the start (%.2f u/s). Speed upgrades x1.5 as strong. No active ability." % [
				(float(c.get("speed_bonus_mul", 1.15)) - 1.0) * 100.0,
				float(c.get("run_speed", 10.35))]
	return str(class_id).capitalize()


## One pick. Refuses ids the class table does not hold (the rows above are the only
## altars); emits class_chosen so the app decides what the pick does to the run.
func choose(class_id: String) -> void:
	if not _classes.has(class_id):
		return
	chosen = class_id
	class_chosen.emit(class_id)


func skip() -> void:
	chosen = ""
	skipped.emit()


## Show the altar; p_current marks the class the runs currently use ("" = none).
func open(p_current: String = "") -> void:
	chosen = ""
	for id in _buttons.keys():
		var b: Button = _buttons[id]
		b.text = str(id).capitalize() + (" (current)" if str(id) == p_current else "")
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func chosen_id() -> String:
	return chosen


## The class ids this altar offers, in draw order (sorted) - sim/intermission.gd's rule.
func class_ids() -> Array:
	return _classes.keys()
