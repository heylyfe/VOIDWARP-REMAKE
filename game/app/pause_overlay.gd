extends Control
#
# The pause overlay (gap 1). ESC mid-run used to destroy the run with no confirmation
# and no resume; now mid-run (WORLD / LOBBY) it opens this panel and freezes the run -
# the app stops stepping the world / the hall while it is open (app.gd's own _process
# early-out, the sim never sees a pause). RESUME closes it and the run continues exactly
# where it froze. ABANDON is the old ESC path: the run ends, the records ratchet, the
# menu comes back - but only when the player chooses it.
#
# Headless-built like view/hud/run_over.gd: the whole layout is _init, no scene tree is
# needed to construct or assert on it. ESC itself is NOT handled here - app.gd owns the
# pause binding (_load_pause_codes) and toggles open/resume, so the binding stays one
# table (data/bindings.json) and the overlay stays pure UI with two exit signals.
#
# public API:
#   signal resumed                  - the run should keep going
#   signal abandon_requested        - the old ESC behaviour (end the run, back to menu)
#   func open(p_snapshot := "")     - show; p_snapshot is the frozen-state line
#   func close() / func is_open()

#
# Look (D-GUI-1, view/ui_style.gd): the frozen run stays visible under a black scrim; the
# run's state sits in compact pills in the top-left corner (LEVEL, PURSE); the one focal
# element is the centred column - PAUSED, a 1 px accent rule, then RESUME (the primary
# action, focused when the overlay opens), SETTINGS and ABANDON RUN (secondary). The key
# hints sit at the bottom centre. Keys (view/ui_focus.gd): Tab / Shift+Tab / Up / Down
# move the ring, Enter / Space press the focused button; ESC stays app.gd's (resume).

const UiStyle := preload("res://view/ui_style.gd")
const UiFocus := preload("res://view/ui_focus.gd")
const SettingsMenuScript := preload("res://view/settings_menu.gd")

signal resumed
signal abandon_requested

var _title: Label
var _snapshot: Label            # the frozen-state line, verbatim (hidden; the pills show it)
var _pills: HBoxContainer
var _resume: Button
var _abandon: Button
var _settings_button: Button
var _settings: Control = null   # view/settings_menu.gd, built on first open
var _focus: UiFocus = UiFocus.new()


func _init() -> void:
	name = "PauseOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_child(UiStyle.backdrop(UiStyle.SCRIM))
	_pills = HBoxContainer.new()
	_pills.name = "Pills"
	_pills.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pills.add_theme_constant_override("separation", UiStyle.SP_2)
	_pills.position = Vector2(UiStyle.EDGE, UiStyle.EDGE)
	add_child(_pills)
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.name = "Column"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiStyle.SP_3)
	center.add_child(col)
	_title = UiStyle.label("PAUSED", "display")
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	col.add_child(UiStyle.rule(32.0, Control.SIZE_SHRINK_CENTER))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UiStyle.SP_4)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	_resume = _button(col, "ResumeButton", "RESUME", UiStyle.PRIMARY, func() -> void: resumed.emit())
	_settings_button = _button(col, "SettingsButton", "SETTINGS", UiStyle.SECONDARY, open_settings)
	_abandon = _button(col, "AbandonButton", "ABANDON RUN", UiStyle.SECONDARY,
			func() -> void: abandon_requested.emit())
	_snapshot = UiStyle.label("", "small")
	_snapshot.name = "Snapshot"
	_snapshot.visible = false
	add_child(_snapshot)
	var hints := UiStyle.key_hints([["TAB", "move"], ["ENTER", "select"], ["ESC", "resume"]])
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hints.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hints.offset_bottom = -UiStyle.EDGE
	add_child(hints)


func _button(p_parent: Control, p_name: String, p_text: String, p_kind: String,
		p_press: Callable) -> Button:
	var b := Button.new()
	b.name = p_name
	b.text = p_text
	b.custom_minimum_size = Vector2(UiStyle.BUTTON_W, UiStyle.BUTTON_H)
	UiStyle.style_button(b, p_kind)
	b.pressed.connect(p_press)
	p_parent.add_child(b)
	_focus.add(b, p_kind, p_press)
	return b


## p_snapshot: one line describing what is frozen (e.g. "LEVEL 3 - PURSE 12 g"). Each
## " - " part becomes one corner pill: the first word is its label, the rest its value.
func open(p_snapshot: String = "") -> void:
	_snapshot.text = p_snapshot
	for c in _pills.get_children():
		_pills.remove_child(c)
		c.queue_free()
	for part in p_snapshot.split(" - ", false):
		var words := str(part).strip_edges()
		var cut := words.find(" ")
		if cut < 0:
			_pills.add_child(UiStyle.pill("", words))
		else:
			_pills.add_child(UiStyle.pill(words.left(cut), words.substr(cut + 1)))
	_focus.focus(0)          # RESUME: the primary action is one Enter away
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func resume_button() -> Button:
	return _resume


func abandon_button() -> Button:
	return _abandon


func settings_button() -> Button:
	return _settings_button


## The keyboard focus (tests/test_ui_style.gd drives it).
func focus_cycle() -> UiFocus:
	return _focus


## Opens the settings screen over the frozen run (the volume control's way in: the screen
## existed but nothing in the game referenced it). Built on first use and kept, so the
## sliders hold their state across pauses; show_settings() reloads the saved values and
## re-applies every consumer, so the volume the player set last session is live again.
## Closing it (BACK or ESC) hands the ring back to SETTINGS.
func open_settings() -> void:
	if _settings == null:
		_settings = SettingsMenuScript.new()
		add_child(_settings)
		_settings.closed.connect(func() -> void: _focus.focus_control(_settings_button))
	_settings.show_settings()


## The settings screen, or null before it was first opened (tests read it).
func settings_screen() -> Control:
	return _settings


## The overlay's keys: the open settings screen first (its ESC closes it, not the pause),
## else the shared focus keys. ESC on the overlay itself is left to app.gd.
func handle_input(event: InputEvent) -> bool:
	if not visible:
		return false
	if _settings != null and _settings.is_open():
		return _settings.handle_input(event)
	return _focus.handle_key(event)


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event) and is_inside_tree():
		get_viewport().set_input_as_handled()
