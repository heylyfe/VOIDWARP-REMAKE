extends Control
#
# Run-over screen (ticket T-025; DESIGN.md section 3.1, section 14;
# research/fable-tickets.md section 2.4), hosted by The Master (item 12).
#
# On death: the killer, the death code, the level reached, the purse (section 14
# / section 3.1: "Every death records its killer and a death code, shown on the
# run-over screen"). Layout: The Master - a tabby cat in a white collar and a red
# striped tie (assets/characters/the_master.png, the owner's supplied image, see
# SOURCES.md) - stands on the left; his speech bubble tells the player what
# killed them, in his voice (master_line()). On the right: the killer's own
# sprite at 256 px (an enemy row's frame from content/enemies/<id>/sprites/, found
# by its stats.death_code when the caller supplies none), the killer name in
# danger red, the death code in small mono type, then level reached, purse,
# charges held at death and the bests. Void death: no sprite - the void colour
# and `The Void` / `D-VOID`. Curse death: the curse icon and `D-CURSE:<id>`.
#
# Two buttons: RESTART (retried - the same seed and class, straight back in) and
# BACK TO LOBBY (lobby_requested - the run is over, back to the pre-run lobby
# where PLAY opens the class altar). RESTART takes focus when the screen opens;
# Left/Right, Up/Down and Tab / Shift+Tab move between the two (focus neighbours),
# Enter / Space press the focused one (Godot's ui_accept), the mouse clicks either.
# The world releases the cursor on death (world.gd's death latch), so it is free.
#
# Killer-name resolution order:
#   1. the sim-provided killer string, normalised; a known raw id maps to its
#      content death name (core/roster.gd)
#   2. otherwise the killer string verbatim (the sim is the source of truth)
#   3. otherwise the death-code map (content death codes via core/roster.gd;
#      D-VOID -> VOID_DISPLAY, D-CURSE:<id> -> the curse)
#   4. otherwise the code itself
# A curse death shows "curse: <id>" as the name line and D-CURSE:<id> as the code.
# The Master's line is built on top of that name (the curse line uses the curse's
# own display name from content/curses/<id>.json).

const DANGER_RED := Color(1.0, 0.1647, 0.1647)   # #FF2A2A
const VOID_COLOR := Color(0.35, 0.2, 0.5, 1.0)   # void swatch (no documented hex - D-T025-1)
const C_GOLD := Color(1.0, 0.784, 0.239)         # #FFC83D gold_gift
const C_BUBBLE := Color(0.910, 1.0, 1.0)         # #E8FFFF beacon_open
const C_INK := Color(0.0078, 0.0118, 0.0588)     # #02030F
const SPRITE := 256.0
const MASTER_SIZE := Vector2(300, 566)
const MASTER_PATH := "res://assets/characters/the_master.png"
const ENEMIES_DIR := "res://content/enemies"
const CURSES_DIR := "res://content/curses"
const MINE_CODE := "D-MINE"
const RosterScript := preload("res://core/roster.gd")
const AssetLoadScript := preload("res://view/asset_load.gd")   # U4: fail-soft loads (text/scene/texture/stream)
const RecordsScript := preload("res://core/records.gd")

## the D-VOID display name (the only killer no content owns).
const VOID_DISPLAY := "The Void"
const CURSE_ICON := 96.0
const CURSE_ICON_Script := preload("res://view/hud/icon_placeholder.gd")
const IconArtScript := preload("res://view/icon_art.gd")

## The Master's lines, one set per death kind; %s is the killer's name. Picked by
## the level reached, so a run's line is stable and different runs vary.
const LINES_ENEMY := [
	"%s got you. Mrrow. I saw that coming from across the room - but then, I am a cat.",
	"Beaten by %s? I have lost naps to tougher things.",
	"%s. Really? I would have batted that off the table.",
]
const LINES_MINE := [
	"%s left a tripmine out and you stepped right on it. I watched. I did not warn you.",
	"A tripmine, courtesy of %s. Even a kitten looks before it pounces.",
]
const LINES_VOID := [
	"The void took you. I always land on my feet. You, evidently, do not.",
	"You fell into the void. Gravity is a dog's game, and you played it.",
]
const LINES_CURSE := [
	"Your own curse, %s, did you in. Never sign anything you have not read. I never do.",
	"%s. You CHOSE that curse. Delicious.",
]

signal retried
signal lobby_requested

var code := ""
var killer_text := ""
var voice_text := ""
var level_reached := 0
var purse_centi := 0
var charges_held := 0
## Tests point this at a scratch file (menu.gd's pattern); "" = the player's real
## user://records.json. Read at show time - records are ratcheted before this
## screen opens, so this run's numbers are already counted.
var records_path := ""
var _records: RefCounted = null

static var _code_to_enemy: Dictionary = {}   # death code -> enemy id (content scan, once)
static var _enemy_scan_done := false

var _master: TextureRect
var _voice_label: Label
var _sprite: TextureRect
var _tbd_box: Label
var _curse_icon: Control
var _curse_art: TextureRect
var _name_label: Label
var _code_label: Label
var _level_label: Label
var _purse_label: Label
var _charges_label: Label
var _bests_label: Label
var _retry: Button
var _lobby: Button

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var stage := HBoxContainer.new()
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override("separation", 36)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(stage)
	# --- left: The Master ---
	var host := VBoxContainer.new()
	host.alignment = BoxContainer.ALIGNMENT_CENTER
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(host)
	_master = TextureRect.new()
	_master.name = "TheMaster"
	_master.custom_minimum_size = MASTER_SIZE
	_master.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_master.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_master.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(MASTER_PATH):
		_master.texture = load(MASTER_PATH)
	host.add_child(_master)
	var plate := _label("THE MASTER", 18, C_GOLD)
	host.add_child(plate)
	# --- right: what he has to say, then the run's numbers ---
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(col)
	var bubble := PanelContainer.new()
	bubble.name = "Bubble"
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BUBBLE
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	bubble.add_theme_stylebox_override("panel", sb)
	col.add_child(bubble)
	_voice_label = _label("", 20, C_INK)
	_voice_label.name = "Voice"
	_voice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_voice_label.custom_minimum_size = Vector2(520, 0)
	bubble.add_child(_voice_label)
	_sprite = TextureRect.new()
	_sprite.custom_minimum_size = Vector2(SPRITE, SPRITE)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.size = Vector2(SPRITE, SPRITE)
	col.add_child(_sprite)
	_tbd_box = _label("?", 160, Color(0.35, 0.35, 0.38, 1.0))
	_tbd_box.custom_minimum_size = Vector2(SPRITE, SPRITE)
	_tbd_box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tbd_box.visible = false
	col.add_child(_tbd_box)
	# curse deaths show the curse icon instead of a killer sprite (section 2.4);
	# placeholder art until real curse icons exist (D-T025-4, D-T086-8)
	_curse_icon = CURSE_ICON_Script.new()
	_curse_icon.custom_minimum_size = Vector2(CURSE_ICON, CURSE_ICON)
	_curse_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_curse_icon.visible = false
	col.add_child(_curse_icon)
	# the curse's own icon (assets/icons/curses/<id>.png); the placeholder above stays the
	# fallback for an id with no art yet, and always holds the id curse_icon_id() reports
	_curse_art = TextureRect.new()
	_curse_art.custom_minimum_size = Vector2(CURSE_ICON, CURSE_ICON)
	_curse_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_curse_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_curse_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_curse_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curse_art.visible = false
	col.add_child(_curse_art)
	_name_label = _label("", 40, DANGER_RED)
	col.add_child(_name_label)
	_code_label = _label("", 18, Color(1.0, 1.0, 1.0, 0.85))
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Courier New", "Consolas", "monospace"])
	_code_label.add_theme_font_override("font", mono)
	col.add_child(_code_label)
	_level_label = _label("", 22, Color(1, 1, 1))
	col.add_child(_level_label)
	_purse_label = _label("", 22, Color(1, 1, 1))
	col.add_child(_purse_label)
	_charges_label = _label("", 16, Color(1.0, 1.0, 1.0, 0.6))
	col.add_child(_charges_label)
	# the locally recorded bests (DESIGN.md section 9): one quiet line under the run
	# numbers - same line the menu shows, read from the same records file
	_bests_label = _label("", 15, Color(1.0, 1.0, 1.0, 0.6))
	_bests_label.name = "Bests"
	col.add_child(_bests_label)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(buttons)
	_retry = _button("Restart", "RESTART")
	_retry.pressed.connect(func() -> void: retried.emit())
	buttons.add_child(_retry)
	_lobby = _button("BackToLobby", "BACK TO LOBBY")
	_lobby.pressed.connect(func() -> void: lobby_requested.emit())
	buttons.add_child(_lobby)
	# the two buttons are each other's neighbour in every direction, and the Tab ring
	for b in [_retry, _lobby]:
		var other: Button = _lobby if b == _retry else _retry
		var p := NodePath("../" + str(other.name))
		b.focus_neighbor_left = p
		b.focus_neighbor_right = p
		b.focus_neighbor_top = p
		b.focus_neighbor_bottom = p
		b.focus_next = p
		b.focus_previous = p
	visible = false


func _label(p_text: String, p_size: int, p_color: Color) -> Label:
	var l := Label.new()
	l.text = p_text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", p_size)
	l.add_theme_color_override("font_color", p_color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(p_name: String, p_text: String) -> Button:
	var b := Button.new()
	b.name = p_name
	b.text = p_text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(220, 50)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", C_GOLD)
	b.add_theme_color_override("font_focus_color", C_GOLD)
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = C_GOLD
	ring.set_border_width_all(3)
	ring.set_corner_radius_all(6)
	b.add_theme_stylebox_override("focus", ring)
	return b

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


## "void" / "curse" / "mine" / "enemy" - which set of The Master's lines applies.
static func death_kind(p_code: String) -> String:
	if is_void_death(p_code):
		return "void"
	if is_curse_death(p_code):
		return "curse"
	if p_code == MINE_CODE:
		return "mine"
	return "enemy"


## A curse's display name (content/curses/<id>.json "name"), else the id itself.
static func curse_display_name(curse_id: String) -> String:
	var doc: Variant = JSON.parse_string(
			AssetLoadScript.text("%s/%s.json" % [CURSES_DIR, curse_id]))
	if doc is Dictionary and str((doc as Dictionary).get("name", "")) != "":
		return str((doc as Dictionary)["name"])
	return curse_id


## The Master's line for a death: what killed the player, in his voice. p_killer is
## the resolved display name (killer_name()); p_pick varies the line (the level).
static func master_line(p_code: String, p_killer: String, p_pick: int = 0) -> String:
	var kind := death_kind(p_code)
	var lines: Array = LINES_ENEMY
	var who := p_killer
	match kind:
		"void":
			lines = LINES_VOID
		"curse":
			lines = LINES_CURSE
			who = curse_display_name(p_code.substr(8))
		"mine":
			lines = LINES_MINE
	var line: String = lines[posmod(p_pick, lines.size())]
	if line.contains("%s"):
		line = line % who
	# roster names are often lower case ("seal"): the sentence still starts with a capital
	return line.left(1).to_upper() + line.substr(1)


## The enemy id whose stats.death_code is p_code ("" when no enemy owns it) - one
## content scan per process (core/roster.gd's rule: content cannot change mid-game).
static func enemy_for_code(p_code: String) -> String:
	if not _enemy_scan_done:
		_enemy_scan_done = true
		var dir := DirAccess.open(ENEMIES_DIR)
		if dir != null:
			for sub in dir.get_directories():
				var doc: Variant = JSON.parse_string(AssetLoadScript.text(
						"%s/%s/enemy.json" % [ENEMIES_DIR, sub]))
				if not (doc is Dictionary):
					continue
				var stats: Variant = (doc as Dictionary).get("stats", {})
				if stats is Dictionary and str((stats as Dictionary).get("death_code", "")) != "":
					_code_to_enemy[str(stats["death_code"])] = str((doc as Dictionary).get("id", sub))
	return str(_code_to_enemy.get(p_code, ""))


## The killer's own sprite for a death code: the enemy's attack frame when it has one
## (section 2.4: "the killer's own sprite (attack frame)"), else its idle, else its
## first frame. null when no enemy owns the code or the art is missing.
static func enemy_sprite_for_code(p_code: String) -> Texture2D:
	var id := enemy_for_code(p_code)
	if id == "":
		return null
	var folder := "%s/%s/sprites" % [ENEMIES_DIR, id]
	var dir := DirAccess.open(folder)
	if dir == null:
		return null
	var pngs: Array = []
	for fn in dir.get_files():
		# exported builds list the .import sidecars, not the PNGs
		var png := fn.trim_suffix(".import")
		if png.ends_with(".png") and not pngs.has(png):
			pngs.append(png)
	pngs.sort()
	for prefix in ["attack", "idle", ""]:
		for fn in pngs:
			if str(fn).begins_with(prefix):
				var path := "%s/%s" % [folder, fn]
				if ResourceLoader.exists(path):
					return load(path) as Texture2D
	return null


## The curse id shown as the curse icon, or "" when this is not a curse death.
func curse_icon_id() -> String:
	if is_curse_death(code) and _curse_icon != null and (_curse_icon.visible or _curse_art.visible):
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
##   sprite (Texture2D, optional) - the killer at 256 px; omitted for void deaths.
##          Absent, the enemy that owns the death code supplies its own frame.
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
	voice_text = master_line(code, killer_text, level_reached)
	_voice_label.text = voice_text
	_name_label.text = killer_text
	_code_label.text = code
	_level_label.text = "LEVEL %d" % level_reached
	_purse_label.text = "PURSE %d.%02d g" % [purse_centi / 100, purse_centi % 100]
	_charges_label.text = "CHARGES HELD: %d" % charges_held
	_refresh_bests()
	var sprite: Variant = info.get("sprite")
	if not (sprite is Texture2D) and not is_void_death(code) and not is_curse_death(code):
		sprite = enemy_sprite_for_code(code)
	if is_void_death(code):
		_sprite.visible = false
		_tbd_box.visible = false
		_curse_icon.visible = false
		_curse_art.visible = false
		_name_label.add_theme_color_override("font_color", VOID_COLOR)
	elif is_curse_death(code):
		# the curse's own icon (placeholder only when it has no art yet) and D-CURSE:<id>;
		# no killer sprite
		_sprite.visible = false
		_tbd_box.visible = false
		_curse_icon.setup(code.substr(8), CURSE_ICON)
		var curse_tex := IconArtScript.texture_for("curses", code.substr(8))
		_curse_art.texture = curse_tex
		_curse_art.visible = curse_tex != null
		_curse_icon.visible = curse_tex == null
		_name_label.add_theme_color_override("font_color", DANGER_RED)
	elif sprite is Texture2D:
		_sprite.visible = true
		_tbd_box.visible = false
		_curse_icon.visible = false
		_curse_art.visible = false
		_sprite.texture = sprite
		_name_label.add_theme_color_override("font_color", DANGER_RED)
	else:
		# no art for this killer: a 256 px TBD stand-in
		_sprite.visible = false
		_tbd_box.visible = true
		_curse_icon.visible = false
		_curse_art.visible = false
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


func restart_button() -> Button:
	return _retry


func lobby_button() -> Button:
	return _lobby


func master_texture() -> Texture2D:
	return _master.texture


## The killer art on show: the enemy sprite, or null (void / curse / TBD).
func killer_texture() -> Texture2D:
	return _sprite.texture if _sprite.visible else null


func hide_run_over() -> void:
	visible = false