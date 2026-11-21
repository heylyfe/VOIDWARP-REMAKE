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

const C_VOID := Color(0.0078, 0.0118, 0.0588)        # #02030F the void backdrop (menu.gd)
const C_WHITE := Color(0.910, 1.0, 1.0)              # #E8FFFF beacon_open
const C_GOLD := Color(1.0, 0.784, 0.239)             # #FFC83D gold_gift
const C_MUTED := Color(0.545, 0.620, 0.718)

const SettingsMenuScript := preload("res://view/settings_menu.gd")

signal resumed
signal abandon_requested

var _title: Label
var _snapshot: Label
var _resume: Button
var _abandon: Button
var _settings_button: Button
var _settings: Control = null   # view/settings_menu.gd, built on first open


func _init() -> void:
	name = "PauseOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(C_VOID.r, C_VOID.g, C_VOID.b, 0.86)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_title = Label.new()
	_title.text = "PAUSED"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 48)
	_title.add_theme_color_override("font_color", C_WHITE)
	col.add_child(_title)
	var rule := ColorRect.new()
	rule.color = Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.85)
	rule.custom_minimum_size = Vector2(64, 3)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(rule)
	_snapshot = Label.new()
	_snapshot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_snapshot.add_theme_font_size_override("font_size", 17)
	_snapshot.add_theme_color_override("font_color", C_MUTED)
	col.add_child(_snapshot)
	_resume = Button.new()
	_resume.text = "RESUME"
	_resume.focus_mode = Control.FOCUS_ALL
	_resume.add_theme_font_size_override("font_size", 24)
	_resume.add_theme_color_override("font_color", C_GOLD)
	_resume.custom_minimum_size = Vector2(280, 48)
	_resume.pressed.connect(func() -> void: resumed.emit())
	col.add_child(_resume)
	_abandon = Button.new()
	_abandon.text = "ABANDON RUN"
	_abandon.focus_mode = Control.FOCUS_ALL
	_abandon.add_theme_font_size_override("font_size", 20)
	_abandon.add_theme_color_override("font_color", C_MUTED)
	_abandon.custom_minimum_size = Vector2(280, 40)
	_abandon.pressed.connect(func() -> void: abandon_requested.emit())
	col.add_child(_abandon)
	_settings_button = Button.new()
	_settings_button.name = "SettingsButton"
	_settings_button.text = "SETTINGS"
	_settings_button.focus_mode = Control.FOCUS_ALL
	_settings_button.add_theme_font_size_override("font_size", 20)
	_settings_button.add_theme_color_override("font_color", C_MUTED)
	_settings_button.custom_minimum_size = Vector2(280, 40)
	_settings_button.pressed.connect(open_settings)
	col.add_child(_settings_button)
	var hint := Label.new()
	hint.text = "ESC resumes - the run is frozen while this is open"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", C_MUTED)
	col.add_child(hint)


## p_snapshot: one line describing what is frozen (e.g. "LEVEL 3 - PURSE 12 g").
func open(p_snapshot: String = "") -> void:
	_snapshot.text = p_snapshot
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


## Opens the settings screen over the frozen run (the volume control's way in: the screen
## existed but nothing in the game referenced it). Built on first use and kept, so the
## sliders hold their state across pauses; show_settings() reloads the saved values and
## re-applies every consumer, so the volume the player set last session is live again.
func open_settings() -> void:
	if _settings == null:
		_settings = SettingsMenuScript.new()
		add_child(_settings)
	_settings.show_settings()


## The settings screen, or null before it was first opened (tests read it).
func settings_screen() -> Control:
	return _settings
