extends Control
#
# Run-over screen (ticket T-025; DESIGN.md section 3.1, section 14;
# research/fable-tickets.md section 2.4).
#
# On death: the killer, the death code, the level reached, the purse (section 14
# / section 3.1: "Every death records its killer and a death code, shown on the
# run-over screen"). Layout per section 2.4: centre - the killer's own sprite
# (attack frame) at 256 px; under it the killer name in danger red; under that
# the death code in small mono type; then level reached, purse, charges held at
# death. Void death: no sprite - the void colour and `The Void` / `D-VOID`.
# Curse death: the curse icon and `D-CURSE:<id>`. Retry is one button, focused
# by default.
#
# Killer-name resolution order:
#   1. the sim-provided killer string, normalised; a known raw id maps to its
#      content death name (core/roster.gd)
#   2. otherwise the killer string verbatim (the sim is the source of truth)
#   3. otherwise the death-code map (content death codes via core/roster.gd;
#      D-VOID -> VOID_DISPLAY, D-CURSE:<id> -> the curse)
#   4. otherwise the code itself
# A curse death shows "curse: <id>" as the name line and D-CURSE:<id> as the code.

const DANGER_RED := Color(1.0, 0.1647, 0.1647)   # #FF2A2A
const VOID_COLOR := Color(0.35, 0.2, 0.5, 1.0)   # void swatch (no documented hex - D-T025-1)
const SPRITE := 256.0
const RosterScript := preload("res://core/roster.gd")
const RecordsScript := preload("res://core/records.gd")

## the D-VOID display name (the only killer no content owns).
const VOID_DISPLAY := "The Void"
const CURSE_ICON := 96.0
const CURSE_ICON_Script := preload("res://view/hud/icon_placeholder.gd")

signal retried

var code := ""
var killer_text := ""
var level_reached := 0
var purse_centi := 0
var charges_held := 0
## Tests point this at a scratch file (menu.gd's pattern); "" = the player's real
## user://records.json. Read at show time - records are ratcheted before this
## screen opens, so this run's numbers are already counted.
var records_path := ""
var _records: RefCounted = null

var _sprite: TextureRect
var _tbd_box: Label
var _curse_icon: Control
var _name_label: Label
var _code_label: Label
var _level_label: Label
var _purse_label: Label
var _charges_label: Label
var _bests_label: Label
var _retry: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	_sprite = TextureRect.new()
	_sprite.custom_minimum_size = Vector2(SPRITE, SPRITE)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.size = Vector2(SPRITE, SPRITE)
	col.add_child(_sprite)
	_tbd_box = Label.new()
	_tbd_box.custom_minimum_size = Vector2(SPRITE, SPRITE)
	_tbd_box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tbd_box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tbd_box.add_theme_font_size_override("font_size", 160)
	_tbd_box.add_theme_color_override("font_color", Color(0.35, 0.35, 0.38, 1.0))
	_tbd_box.text = "?"
	_tbd_box.visible = false
	col.add_child(_tbd_box)
	# curse deaths show the curse icon instead of a killer sprite (section 2.4);
	# placeholder art until real curse icons exist (D-T025-4, D-T086-8)
	_curse_icon = CURSE_ICON_Script.new()
	_curse_icon.custom_minimum_size = Vector2(CURSE_ICON, CURSE_ICON)
	_curse_icon.visible = false
	col.add_child(_curse_icon)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 40)
	_name_label.add_theme_color_override("font_color", DANGER_RED)
	col.add_child(_name_label)
	_code_label = Label.new()
	_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_label.add_theme_font_size_override("font_size", 18)
	_code_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.85))
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Courier New", "Consolas", "monospace"])
	_code_label.add_theme_font_override("font", mono)
	col.add_child(_code_label)
	_level_label = Label.new()
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override("font_size", 22)
	col.add_child(_level_label)
	_purse_label = Label.new()
	_purse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_purse_label.add_theme_font_size_override("font_size", 22)
	col.add_child(_purse_label)
	_charges_label = Label.new()
	_charges_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_charges_label.add_theme_font_size_override("font_size", 16)
	_charges_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	col.add_child(_charges_label)
	# the locally recorded bests (DESIGN.md section 9): one quiet line under the run
	# numbers - same line the menu shows, read from the same records file
	_bests_label = Label.new()
	_bests_label.name = "Bests"
	_bests_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bests_label.add_theme_font_size_override("font_size", 15)
	_bests_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	col.add_child(_bests_label)
	_retry = Button.new()
	_retry.text = "Retry"
	_retry.focus_mode = Control.FOCUS_ALL
	_retry.pressed.connect(func() -> void: retried.emit())
	col.add_child(_retry)
	visible = false


static func normalize_killer(killer: String) -> String:
	return killer.to_lower().replace("?!", "").replace("!", "").replace(" ", "_")


## The killer display name for a (code, killer) pair; see the header for the order.
## Names come from the content tree through core/roster.gd (death_name, default
## name); D-VOID has no content row and uses VOID_DISPLAY.
static func killer_name(p_code: String, killer: String) -> String:
	if p_code.begins_with("D-CURSE:"):
		return "curse: " + p_code.substr(8)
	if killer.strip_edges() != "":
		var raw := normalize_killer(killer)
		# "the void" is sim/death.gd's already-resolved VOID_NAME, not a raw content id:
		# it normalises to "the_void" and still means the void (D-VOID).
		if raw == "void" or raw == "the_void":
			return VOID_DISPLAY
		var by_id := RosterScript.name_for_id(raw)
		if by_id != "":
			return by_id
		return killer
	if p_code == "D-VOID":
		return VOID_DISPLAY
	var by_code := RosterScript.name_for_code(p_code)
	if by_code != "":
		return by_code
	return p_code


## true for a death by a curse (D-CURSE:<id>).
static func is_curse_death(p_code: String) -> bool:
	return p_code.begins_with("D-CURSE:")


## true for a void death (D-VOID).
static func is_void_death(p_code: String) -> bool:
	return p_code == "D-VOID"


## The curse id shown as the curse icon, or "" when this is not a curse death.
func curse_icon_id() -> String:
	if is_curse_death(code) and _curse_icon != null and _curse_icon.visible:
		return str(_curse_icon.icon_id)
	return ""


## Fill the screen from a death snapshot:
##   code (String) - the death code, e.g. "D-MINE" / "D-CURSE:<curse id>"
##   killer (String) - the sim-provided killer string ("" when unknown)
##   level (int), purse_centi (int), charges (int)
##   purse (int, optional) - sim/death.gd screen_data()'s own key for the same integer
##          (centi, the number the HUD shows); read when purse_centi is absent so the
##          producer's row lands as it is. Negative means "not tracked yet" and renders
##          as 0.00 rather than as a negative purse.
##   sprite (Texture2D, optional) - the killer at 256 px; omitted for void deaths
func show_run_over(info: Dictionary) -> void:
	code = str(info.get("code", ""))
	var killer := str(info.get("killer", ""))
	level_reached = int(info.get("level", 0))
	var cents := int(info.get("purse_centi", -1))
	if cents < 0:
		cents = int(info.get("purse", 0))
	purse_centi = maxi(cents, 0)
	charges_held = int(info.get("charges", 0))
	killer_text = killer_name(code, killer)
	_name_label.text = killer_text
	_code_label.text = code
	_level_label.text = "LEVEL %d" % level_reached
	_purse_label.text = "PURSE %d.%02d g" % [purse_centi / 100, purse_centi % 100]
	_charges_label.text = "CHARGES HELD: %d" % charges_held
	_refresh_bests()
	if is_void_death(code):
		_sprite.visible = false
		_tbd_box.visible = false
		_curse_icon.visible = false
		_name_label.add_theme_color_override("font_color", VOID_COLOR)
	elif is_curse_death(code):
		# the curse icon (placeholder art) and D-CURSE:<id>; no killer sprite
		_sprite.visible = false
		_tbd_box.visible = false
		_curse_icon.setup(code.substr(8), CURSE_ICON)
		_curse_icon.visible = true
		_name_label.add_theme_color_override("font_color", DANGER_RED)
	elif info.get("sprite") is Texture2D:
		_sprite.visible = true
		_tbd_box.visible = false
		_curse_icon.visible = false
		_sprite.texture = info["sprite"]
		_name_label.add_theme_color_override("font_color", DANGER_RED)
	else:
		# no sprite supplied (sprites are TBD placeholders): a 256 px TBD stand-in
		_sprite.visible = false
		_tbd_box.visible = true
		_curse_icon.visible = false
		_name_label.add_theme_color_override("font_color", DANGER_RED)
	visible = true
	if is_inside_tree():
		_retry.grab_focus()


## Re-read the records file (records_path, or the default user://records.json) and
## refresh the bests line. Called once per show; tests call it after pointing
## records_path at a scratch file. A missing/corrupt file reads as 0/0
## (records.gd's contract) - never an error here.
func _refresh_bests() -> void:
	_records = RecordsScript.new()
	_records.load_from(records_path if records_path != "" else RecordsScript.DEFAULT_PATH)
	if _bests_label != null:
		_bests_label.text = "BEST LEVEL %d     BEST PURSE %d" % [_records.get_best_level(), _records.get_best_purse()]


func bests_label() -> Label:
	return _bests_label


func hide_run_over() -> void:
	visible = false
