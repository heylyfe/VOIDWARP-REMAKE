extends Control
#
# view/lobby/lobby_hud.gd - the Antechamber's HUD (owner defect: the lobby showed no purse
# at all, so a player could not see the gold the altars were asking for).
#
# One compact pill, top-right (D-GUI-1, view/ui_style.gd: the front end's pill language):
# the tracked PURSE label, the gold-balance icon, then the purse in whole gold in the mono
# face, so the number never jitters as it changes. The pill grows leftwards from the
# corner, so a 6-digit purse keeps its padding. The purse is the lobby state's own field
# (sim/intermission.gd `purse`) - the integer a curse bounty adds to and a purchase, a tithe
# or a reroll deducts from - so the number on screen is the number the shop spends.
#
# view/lobby/lobby_scene.gd owns one of these on a CanvasLayer and syncs it every tick;
# sync() is a no-op when the value has not moved, so a purchase shows up on the next frame.
#
# Pure view: nothing here writes sim state.

const UiStyle := preload("res://view/ui_style.gd")
const EDGE := 24.0
const ICON_SIZE := 18.0
const GOLD_BALANCE_ICON := preload("res://assets/icons/gold_balance.png")

var _purse_gold := 0
var _label: Label            # the value ("999999 g")
var _icon: TextureRect


func _init() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_left = -EDGE
	offset_right = -EDGE
	offset_top = EDGE
	offset_bottom = EDGE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := UiStyle.pill("PURSE", "")
	pill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pill)
	var row: HBoxContainer = pill.get_node("Row")
	_label = pill.get_node("Row/Value")
	_icon = TextureRect.new()
	_icon.texture = GOLD_BALANCE_ICON
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	row.move_child(_icon, _label.get_index())
	_refresh()


func _get_minimum_size() -> Vector2:
	return get_child(0).get_combined_minimum_size() if get_child_count() > 0 else Vector2.ZERO


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


## The exact HUD string (the pill shows the PURSE label and this value).
func purse_text() -> String:
	return "PURSE  %d g" % _purse_gold


func _refresh() -> void:
	if _label != null:
		_label.text = "%d g" % _purse_gold
		# Pin the right edge to the corner and grow leftwards to the new width now, not next
		# frame (set_size grows to the right, past the screen edge, on a 6-digit purse).
		update_minimum_size()
		var m := get_combined_minimum_size()
		offset_right = -EDGE
		offset_left = -EDGE - m.x
		offset_top = EDGE
		offset_bottom = EDGE + m.y
