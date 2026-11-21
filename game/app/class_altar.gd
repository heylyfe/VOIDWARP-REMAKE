extends Control
#
# The class altar (gap 2; DESIGN.md section 4: "Class is chosen at a class altar in the
# pre-run lobby"). A real PLAY press shows this panel over the loading screen, and the run
# WAITS for it: the app holds the loading screen until the player confirms a class or
# presses SKIP (app.gd _on_loading_finished). No timer ever decides the class.
#
# The three cards are drawn from data/player.json's class table (the same table
# sim/intermission.gd's CLASS bay draws from) - no class id is invented here, and every
# number in a stats line is the file's own value. Each card: the class icon
# (assets/icons/classes/<id>.png, rasterised from docs/classes/<id>.svg), the name, one
# plain sentence of what the class does, and the stats line (blurb()).
#
# Two steps, never one: SELECT a card (click it, or Left/Right/Tab/1-3 on the keyboard),
# then CONFIRM it (the CONFIRM button, Enter/Space, or a second click on the selected
# card). Nothing is selected when the altar opens, so a key that is still held from the
# menu (the press that started the run) has nothing to confirm; key echoes are ignored.
# None of the buttons take keyboard focus - the altar reads the keys itself
# (handle_input), so Godot's built-in ui_accept can never press a card behind its back.
# The backdrop is the only mouse stop; every container between it and the cards ignores
# the mouse, so a click lands on the card under the cursor.
#
# Headless-built like view/hud/run_over.gd: the layout is _init, no scene tree needed.
# public API:
#   signal class_chosen(class_id: String)   - a CONFIRMED pick (the altar closes)
#   signal skipped                           - SKIP (the altar closes; the seed decides)
#   func open(p_current := "") / close() / is_open()
#   func select(class_id) -> bool  - step 1 (refuses ids the table does not hold)
#   func confirm() -> bool         - step 2: emits class_chosen for the selection
#   func choose(class_id)          - select + confirm in one call (tests, the bot)
#   func skip()
#   func handle_input(event) -> bool   - the keyboard (and is fed by _unhandled_input)
#   func selected_id() / chosen_id() / class_ids() / card(id) / confirm_button() / skip_button()
#   static func blurb(class_id, p_classes) -> String   - the stats line
#   static func plain_text(class_id) -> String          - the one plain sentence

static var PlayerDataPath := "res://data/player.json"   # static var so tests can point it at a scratch file

const ICON_DIR := "res://assets/icons/classes/"
const C_VOID := Color(0.0078, 0.0118, 0.0588)        # #02030F the void backdrop (menu.gd)
const C_CARD := Color(0.051, 0.071, 0.161)           # #0D1229 the card fill (= the icon canvas)
const C_WHITE := Color(0.910, 1.0, 1.0)              # #E8FFFF beacon_open
const C_GOLD := Color(1.0, 0.784, 0.239)             # #FFC83D gold_gift
const C_TEAL := Color(0.486, 1.0, 0.957)             # #7CFFF4 the icons' highlight
const C_MUTED := Color(0.545, 0.620, 0.718)
const CARD_SIZE := Vector2(250, 340)
const ICON_SIZE := 128.0

signal class_chosen(class_id: String)
signal skipped

var chosen: String = ""                 # the confirmed pick made at this altar this visit
var _selected: String = ""              # step 1: the highlighted card ("" = none yet)
var _classes: Dictionary = {}           # player.json's class table (id -> block)
var _ids: Array = []                    # the table's ids, sorted (draw order)
var _cards: Dictionary = {}             # id -> Button (the whole card is the button)
var _styles: Dictionary = {}            # "idle" / "hover" / "selected" -> StyleBoxFlat
var _confirm: Button
var _skip: Button
var _hint: Label


func _init() -> void:
	name = "ClassAltar"
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(PlayerDataPath))
	if doc is Dictionary:
		var raw: Variant = (doc as Dictionary).get("classes", {})
		if raw is Dictionary:
			_classes = raw
		# else the table is corrupt: an empty altar (title + SKIP) is built below, never
		# an empty full-rect stop that swallows the mouse with nothing visible
	_ids = _classes.keys()
	_ids.sort()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	visible = false
	_styles["idle"] = _card_style(Color(C_MUTED.r, C_MUTED.g, C_MUTED.b, 0.35), 2)
	_styles["hover"] = _card_style(Color(C_TEAL.r, C_TEAL.g, C_TEAL.b, 0.7), 2)
	_styles["selected"] = _card_style(C_GOLD, 4)
	var bg := ColorRect.new()
	bg.color = Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# centred on screen at any window size: a full-rect CenterContainer
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	col.add_child(_label("CHOOSE YOUR CLASS", 42, C_WHITE))
	col.add_child(_label("pick a card, then confirm - the run waits for you", 16, C_MUTED))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	for i in _ids.size():
		var fid := str(_ids[i])
		var b := _build_card(fid, i + 1)
		row.add_child(b)
		_cards[fid] = b
	_hint = _label("", 16, C_MUTED)
	col.add_child(_hint)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(buttons)
	_confirm = Button.new()
	_confirm.name = "Confirm"
	_confirm.text = "CONFIRM"
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.custom_minimum_size = Vector2(220, 48)
	_confirm.add_theme_font_size_override("font_size", 24)
	_confirm.add_theme_color_override("font_color", C_GOLD)
	_confirm.pressed.connect(func() -> void: confirm())
	buttons.add_child(_confirm)
	_skip = Button.new()
	_skip.name = "Skip"
	_skip.text = "SKIP - let the seed decide"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.custom_minimum_size = Vector2(0, 48)
	_skip.add_theme_font_size_override("font_size", 17)
	_skip.add_theme_color_override("font_color", C_MUTED)
	_skip.pressed.connect(func() -> void: skip())
	buttons.add_child(_skip)
	_refresh()

func _label(p_text: String, p_size: int, p_color: Color) -> Label:
	var l := Label.new()
	l.text = p_text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", p_size)
	l.add_theme_color_override("font_color", p_color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _card_style(p_border: Color, p_width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.border_color = p_border
	sb.set_border_width_all(p_width)
	sb.set_corner_radius_all(10)
	return sb


## One card: the whole card is one Button (the click target); the icon and the text sit
## inside it and ignore the mouse, so a click anywhere on the card is a click on it.
func _build_card(p_id: String, p_number: int) -> Button:
	var b := Button.new()
	b.name = "Card" + p_id.capitalize()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = CARD_SIZE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func() -> void: _on_card_pressed(p_id))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 14
	box.offset_right = -14
	box.offset_top = 16
	box.offset_bottom = -14
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := ICON_DIR + p_id + ".png"
	if ResourceLoader.exists(path):
		icon.texture = load(path)
	box.add_child(icon)
	var title := _label("%d  %s" % [p_number, p_id.to_upper()], 26, C_WHITE)
	title.name = "Name"
	box.add_child(title)
	var plain := _label(plain_text(p_id), 16, C_WHITE)
	plain.name = "Plain"
	plain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plain.custom_minimum_size = Vector2(CARD_SIZE.x - 28, 0)
	box.add_child(plain)
	var stats := _label(blurb(p_id, _classes), 13, C_MUTED)
	stats.name = "Stats"
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.custom_minimum_size = Vector2(CARD_SIZE.x - 28, 0)
	box.add_child(stats)
	return b


## One plain sentence of what the class does - what a new player needs, no numbers.
static func plain_text(class_id: String) -> String:
	match class_id:
		"dasher":
			return "Press the ability key to dash a short burst in any direction - even in mid-air."
		"glider":
			return "Hold jump while falling to glide slowly across long gaps."
		"athletic":
			return "Simply runs faster than everyone else. Nothing to press."
	return str(class_id).capitalize()


## The stats line per class, composed from player.json's own numbers.
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


# ---- the two steps ------------------------------------------------------------------------

## A click on a card selects exactly that card; a click on the card that is ALREADY
## selected confirms it (the second click is the confirm step for the mouse).
func _on_card_pressed(p_id: String) -> void:
	if not visible:
		return
	if _selected == p_id:
		confirm()
	else:
		select(p_id)


## Step 1. Refuses ids the class table does not hold (the cards are the only altars).
func select(class_id: String) -> bool:
	if not _classes.has(class_id):
		return false
	_selected = class_id
	_refresh()
	return true


## Step 2: confirm the selection. Nothing selected -> nothing happens (false).
func confirm() -> bool:
	if _selected == "" or not _classes.has(_selected):
		return false
	chosen = _selected
	close()
	class_chosen.emit(chosen)
	return true


## One pick in one call (select + confirm). Unknown ids are refused.
func choose(class_id: String) -> void:
	if select(class_id):
		confirm()


func skip() -> void:
	chosen = ""
	close()   # the seeded replay decides the class
	skipped.emit()


## Show the altar; p_current marks the class the runs currently use ("" = none). The
## mark is a label only - nothing is pre-selected, so a stray Enter confirms nothing.
func open(p_current: String = "") -> void:
	chosen = ""
	_selected = ""
	for id in _cards.keys():
		var title: Label = (_cards[id] as Button).find_child("Name", true, false)
		var n := _ids.find(id) + 1
		title.text = "%d  %s%s" % [n, str(id).to_upper(), "  (last)" if str(id) == p_current else ""]
	_refresh()
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func chosen_id() -> String:
	return chosen


func selected_id() -> String:
	return _selected


## The class ids this altar offers, in draw order (sorted) - sim/intermission.gd's rule.
func class_ids() -> Array:
	return _ids.duplicate()


func card(class_id: String) -> Button:
	return _cards.get(class_id, null)


func confirm_button() -> Button:
	return _confirm


func skip_button() -> Button:
	return _skip

# ---- keyboard -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event) and is_inside_tree():
		get_viewport().set_input_as_handled()


## The altar's keys. Left/Right (or A/D), Tab / Shift+Tab move the selection, 1..n select
## that card, Enter/Space confirm the selection (SKIP is mouse-only: S is a movement key,
## and a run must never be skipped by a stray WASD press). Echoes (a held key) are
## ignored, so the press that started the run can never also confirm a card. ESC is left
## to the app (back to the menu). Returns true when the event was the altar's.
func handle_input(event: InputEvent) -> bool:
	if not visible or not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return false
	var code: int = int(k.keycode) if k.keycode != KEY_NONE else int(k.physical_keycode)
	match code:
		KEY_LEFT, KEY_A, KEY_UP:
			_step(-1)
			return true
		KEY_RIGHT, KEY_D, KEY_DOWN:
			_step(1)
			return true
		KEY_TAB:
			_step(-1 if k.shift_pressed else 1)
			return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			confirm()
			return true
	if code >= KEY_1 and code <= KEY_9:
		var i := code - KEY_1
		if i < _ids.size():
			select(str(_ids[i]))
			return true
	return false


## Move the selection one card; from "nothing selected" the first step lands on the
## first card (Right/Tab) or the last one (Left).
func _step(p_dir: int) -> void:
	if _ids.is_empty():
		return
	var i := _ids.find(_selected)
	if i < 0:
		i = 0 if p_dir > 0 else _ids.size() - 1
	else:
		i = posmod(i + p_dir, _ids.size())
	select(str(_ids[i]))


## The look follows the state: the selected card wears the gold frame, CONFIRM is live
## only with a selection, and the hint says what the next action does.
func _refresh() -> void:
	for id in _cards.keys():
		var b: Button = _cards[id]
		var sel := str(id) == _selected
		var normal: StyleBoxFlat = _styles["selected"] if sel else _styles["idle"]
		var hover: StyleBoxFlat = _styles["selected"] if sel else _styles["hover"]
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", _styles["selected"])
		b.add_theme_stylebox_override("hover_pressed", _styles["selected"])
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if _confirm != null:
		_confirm.disabled = _selected == ""
		_confirm.text = "CONFIRM" if _selected == "" else "CONFIRM " + _selected.to_upper()
	if _hint != null:
		if _selected == "":
			_hint.text = "click a card or press 1-%d / arrows to select it" % maxi(_ids.size(), 1)
		else:
			_hint.text = "%s selected - press Enter, click CONFIRM or click the card again" % _selected.to_upper()