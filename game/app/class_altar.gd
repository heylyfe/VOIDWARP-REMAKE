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
# None of the buttons take Godot keyboard focus - the altar reads the keys itself
# (handle_input), so Godot's built-in ui_accept can never press a card behind its back.
# The focus ring is the shared one (view/ui_focus.gd, D-GUI-1): Tab walks the cards, then
# CONFIRM, then SKIP; a card that takes the ring is selected.
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
const UiStyle := preload("res://view/ui_style.gd")
const UiFocus := preload("res://view/ui_focus.gd")
const CARD_SIZE := Vector2(256, 320)     # the card's width, and its MINIMUM height
const ICON_SIZE := 96.0
const CARD_PAD_X := 16.0                 # the text column's inset from the card's sides
const CARD_PAD_TOP := 20.0
const CARD_PAD_BOTTOM := 16.0
const CARD_GAP := 8.0                    # the gap between the icon, the name and the two lines
const LAST_MARK := "  (last)"            # appended to the class the runs currently use

signal class_chosen(class_id: String)
signal skipped

var chosen: String = ""                 # the confirmed pick made at this altar this visit
var _selected: String = ""              # step 1: the highlighted card ("" = none yet)
var _classes: Dictionary = {}           # player.json's class table (id -> block)
var _ids: Array = []                    # the table's ids, sorted (draw order)
var _cards: Dictionary = {}             # id -> Button (the whole card is the button)
var _confirm: Button
var _skip: Button
var _hint: Label
var _focus: UiFocus = UiFocus.new()     # cards, then CONFIRM, then SKIP (D-GUI-1)


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
	_focus.hover_focus = false          # hover never selects a card: a click does
	_focus.changed = _on_focus_changed
	# Fully opaque: the altar is a modal decision and the loading screen behind it is
	# noise. At 0.94 the loading title, the gag line and the progress bar all showed
	# through the cards and the CONFIRM/SKIP row, which read as a broken layout.
	var bg := ColorRect.new()
	bg.color = UiStyle.GROUND
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
	col.add_theme_constant_override("separation", UiStyle.SP_3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	var title := UiStyle.label("CHOOSE YOUR CLASS", "title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	col.add_child(UiStyle.rule(32.0, Control.SIZE_SHRINK_CENTER))
	var sub := UiStyle.label("pick a card, then confirm - the run waits for your pick", "small")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UiStyle.SP_4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	for i in _ids.size():
		var fid := str(_ids[i])
		var b := _build_card(fid, i + 1)
		row.add_child(b)
		_cards[fid] = b
		_focus.add(b, UiStyle.SECONDARY, func() -> void: confirm(), Callable(), _paint_card)
	_hint = UiStyle.label("", "small", UiStyle.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_hint)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", UiStyle.SP_4)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(buttons)
	_confirm = Button.new()
	_confirm.name = "Confirm"
	_confirm.text = "CONFIRM"
	_confirm.custom_minimum_size = Vector2(UiStyle.BUTTON_W, UiStyle.BUTTON_H)
	UiStyle.style_button(_confirm, UiStyle.PRIMARY)
	_confirm.pressed.connect(func() -> void: confirm())
	buttons.add_child(_confirm)
	_focus.add(_confirm, UiStyle.PRIMARY, func() -> void: confirm())
	_skip = Button.new()
	_skip.name = "Skip"
	_skip.text = "SKIP - LET THE SEED DECIDE"
	_skip.custom_minimum_size = Vector2(0, UiStyle.BUTTON_H)
	UiStyle.style_button(_skip, UiStyle.SECONDARY)
	_skip.pressed.connect(func() -> void: skip())
	buttons.add_child(_skip)
	_focus.add(_skip, UiStyle.SECONDARY, func() -> void: skip())
	var hints := UiStyle.key_hints([["1-%d" % maxi(_ids.size(), 1), "select"], ["TAB", "move"],
			["ENTER", "confirm"], ["ESC", "menu"]])
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hints.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hints.offset_bottom = -UiStyle.EDGE
	add_child(hints)
	_refresh()


## One card: the whole card is one Button (the click target); the icon and the text sit
## inside it and ignore the mouse, so a click anywhere on the card is a click on it.
func _build_card(p_id: String, p_number: int) -> Button:
	var b := Button.new()
	b.name = "Card" + p_id.capitalize()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(CARD_SIZE.x, _card_height(p_id))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func() -> void: _on_card_pressed(p_id))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = CARD_PAD_X
	box.offset_right = -CARD_PAD_X
	box.offset_top = CARD_PAD_TOP
	box.offset_bottom = -CARD_PAD_BOTTOM
	box.add_theme_constant_override("separation", int(CARD_GAP))
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
	box.add_child(_card_label("Name", _name_text(p_number, p_id, false), "entry", UiStyle.TEXT_STRONG))
	box.add_child(_card_label("Plain", plain_text(p_id), "body", UiStyle.TEXT))
	box.add_child(_card_label("Stats", blurb(p_id, _classes), "small", UiStyle.TEXT_MUTED))
	return b


func _card_label(p_name: String, p_text: String, p_role: String, p_color: Color) -> Label:
	var l := UiStyle.label(p_text, p_role, p_color)
	l.name = p_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(CARD_SIZE.x - CARD_PAD_X * 2.0, 0)
	return l


func _name_text(p_number: int, p_id: String, p_last: bool) -> String:
	return "%d  %s%s" % [p_number, p_id.to_upper(), LAST_MARK if p_last else ""]


## The card's height. A Button does not size itself to its children, so the height is
## measured from the text the card can hold - the name WITH its "(last)" mark, the plain
## line and the stats line, each wrapped to the inner width in its own face, padding in -
## so a longer blurb makes a taller card instead of spilling past the border (the
## Glider's stats line used to). CARD_SIZE.y stays the floor.
func _card_height(p_id: String) -> float:
	var w := CARD_SIZE.x - CARD_PAD_X * 2.0
	var need := CARD_PAD_TOP + CARD_PAD_BOTTOM + ICON_SIZE + CARD_GAP * 3.0
	need += UiStyle.text_height(_name_text(_ids.size(), p_id, true), "entry", w)
	need += UiStyle.text_height(plain_text(p_id), "body", w)
	need += UiStyle.text_height(blurb(p_id, _classes), "small", w)
	return maxf(CARD_SIZE.y, ceilf(need))


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
## The selected card takes the focus ring (set directly: no changed callback, no loop).
func select(class_id: String) -> bool:
	if not _classes.has(class_id):
		return false
	_selected = class_id
	_focus.index = _ids.find(class_id)
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
	_focus.index = -1
	for id in _cards.keys():
		var title: Label = (_cards[id] as Button).find_child("Name", true, false)
		title.text = _name_text(_ids.find(id) + 1, str(id), str(id) == p_current)
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


## The keyboard focus: the cards, CONFIRM, SKIP (tests/test_ui_style.gd drives it).
func focus_cycle() -> UiFocus:
	return _focus

# ---- keyboard -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event) and is_inside_tree():
		get_viewport().set_input_as_handled()


## The altar's keys. Left/Right (or A/D, Up/Down) walk the cards, 1..n select that card,
## Tab / Shift+Tab move the focus ring through the cards, CONFIRM and SKIP (a card that
## takes the ring is selected, exactly as before). Enter/Space press what has the ring:
## SKIP skips, anything else confirms the selection (nothing selected -> nothing happens).
## SKIP has no letter key: S is a movement key, and a run must never be skipped by a stray
## WASD press. Echoes (a held key) never confirm, so the press that started the run cannot
## also pick a card. ESC is left to the app (back to the menu). Returns true when the
## event was the altar's.
func handle_input(event: InputEvent) -> bool:
	if not visible or not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	if not k.pressed:
		return false
	var code: int = int(k.keycode) if k.keycode != KEY_NONE else int(k.physical_keycode)
	if code == KEY_TAB:
		_focus.step(-1 if k.shift_pressed else 1)
		return true
	if k.echo:
		return false
	match code:
		KEY_LEFT, KEY_A, KEY_UP:
			_step(-1)
			return true
		KEY_RIGHT, KEY_D, KEY_DOWN:
			_step(1)
			return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _focus.current() == _skip:
				skip()
			else:
				confirm()
			return true
	if code >= KEY_1 and code <= KEY_9:
		var i := code - KEY_1
		if i < _ids.size():
			select(str(_ids[i]))
			return true
	return false


## Move the selection one card; from "nothing selected" the first step lands on the
## first card (Right) or the last one (Left).
func _step(p_dir: int) -> void:
	if _ids.is_empty():
		return
	var i := _ids.find(_selected)
	if i < 0:
		i = 0 if p_dir > 0 else _ids.size() - 1
	else:
		i = posmod(i + p_dir, _ids.size())
	select(str(_ids[i]))


## The ring moved (Tab): a card that takes it is selected; CONFIRM / SKIP just repaint.
func _on_focus_changed(p_i: int) -> void:
	if p_i >= 0 and p_i < _ids.size():
		select(str(_ids[p_i]))
	else:
		_refresh()


## A card's look: the focus ring when it has the ring; ACCENT edge + a faint ACCENT fill
## when it is the selection without the ring (the ring is on CONFIRM); MID edge at rest,
## ACCENT edge under the mouse.
func _paint_card(p_c: Control, p_focused: bool) -> void:
	var b := p_c as Button
	var sel := false
	for id in _cards.keys():
		if _cards[id] == b:
			sel = str(id) == _selected
	var rest: StyleBoxFlat
	if p_focused:
		rest = UiStyle.focus_box(0, 0)
	elif sel:
		rest = UiStyle.box(Color(UiStyle.ACCENT.r, UiStyle.ACCENT.g, UiStyle.ACCENT.b, 0.10),
				UiStyle.ACCENT, UiStyle.BORDER, 0, 0, 0)
	else:
		rest = UiStyle.box(UiStyle.PANEL_FILL, UiStyle.MID, UiStyle.BORDER, 0, 0, 0)
	var hover := rest.duplicate() as StyleBoxFlat
	if not p_focused:
		hover.border_color = UiStyle.ACCENT
	for st in ["normal", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, rest)
	for st in ["hover", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hover)


## The look follows the state: the ring and the selection repaint, CONFIRM is live only
## with a selection, and the hint says what the next action does.
func _refresh() -> void:
	_focus.repaint()
	if _confirm != null:
		_confirm.disabled = _selected == ""
		_confirm.text = "CONFIRM" if _selected == "" else "CONFIRM " + _selected.to_upper()
	if _hint != null:
		if _selected == "":
			_hint.text = "click a card or press 1-%d / arrows to select it" % maxi(_ids.size(), 1)
		else:
			_hint.text = "%s selected - press Enter, click CONFIRM or click the card again" % _selected.to_upper()
