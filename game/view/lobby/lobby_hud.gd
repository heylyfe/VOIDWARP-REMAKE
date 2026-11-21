extends Control
#
# view/lobby/lobby_hud.gd - the Antechamber's HUD (owner defect: the lobby showed no purse
# at all, so a player could not see the gold the altars were asking for).
#
# One line, top-right, in the level HUD's own purse language (view/hud/purse_chain.gd): the
# gold-balance icon, then the purse in whole gold. The purse is the lobby state's own field
# (sim/intermission.gd `purse`) - the integer a curse bounty adds to and a purchase, a tithe
# or a reroll deducts from - so the number on screen is the number the shop spends.
#
# view/lobby/lobby_scene.gd owns one of these on a CanvasLayer and syncs it every tick;
# sync() is a no-op when the value has not moved, so a purchase shows up on the next frame.
#
# Pure view: nothing here writes sim state.

const EDGE := 24.0
const WIDTH := 300.0
const HEIGHT := 44.0
const ICON_SIZE := 30.0
const ICON_GAP := 8.0
const FONT_SIZE := 24
const TEXT_COLOR := Color(1.0, 0.956, 0.8, 1.0)
const GOLD_BALANCE_ICON := preload("res://assets/icons/gold_balance.png")

var _purse_gold := 0
var _label: Label
var _icon: TextureRect


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -EDGE - WIDTH
	offset_right = -EDGE
	offset_top = EDGE
	offset_bottom = EDGE + HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# icon glued to the left of the number: an end-aligned row that sizes to its content,
	# so the gap never opens up as the purse value's width changes
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", int(ICON_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = TextureRect.new()
	_icon.texture = GOLD_BALANCE_ICON
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	row.add_child(_label)
	_refresh()


## The purse in whole gold (sim/intermission.gd `purse`). No-op when it has not moved.
func sync(p_purse_gold: int) -> void:
	var v := maxi(0, p_purse_gold)
	if v == _purse_gold:
		return
	_purse_gold = v
	_refresh()


## The purse the HUD is showing right now (whole gold).
func purse_gold() -> int:
	return _purse_gold


## The exact HUD string.
func purse_text() -> String:
	return "PURSE  %d g" % _purse_gold


func _refresh() -> void:
	if _label != null:
		_label.text = purse_text()
