extends Control
#
# Curse and upgrade icon rows, top of the screen, collapsible with Tab (ticket
# T-025; DESIGN.md section 14).
#
# Two rows: owned curses on top, owned upgrades beneath. Each entry is a
# synthesized placeholder icon (icon_placeholder.gd - no curse/upgrade art exists
# yet, D-T025-4) with a stack badge when more than one stack is held. Pressing
# Tab (KEY_TAB, hud.gd routes it here) toggles both rows collapsed/expanded;
# collapsed hides the rows, never the rest of the HUD. The rows carry no
# tooltips - the shop and lobby own item text.

const CELL := 40.0
const GAP := 6.0

var collapsed := false
var _curses_row: HBoxContainer
var _upgrades_row: HBoxContainer
var _curse_items: Array = []
var _upgrade_items: Array = []
var _placeholder_script: GDScript


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder_script = load("res://view/hud/icon_placeholder.gd")
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -400.0
	offset_right = 400.0
	offset_top = 8.0
	offset_bottom = 8.0 + CELL * 2.0 + GAP
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	_curses_row = HBoxContainer.new()
	_curses_row.add_theme_constant_override("separation", int(GAP))
	col.add_child(_curses_row)
	_upgrades_row = HBoxContainer.new()
	_upgrades_row.add_theme_constant_override("separation", int(GAP))
	col.add_child(_upgrades_row)


## items: Array of {"id": String, "stacks": int}. stacks defaults to 1.
## An unchanged list is a no-op (hud.sync runs every tick; rebuilding the cells each tick
## would churn nodes for nothing).
func set_curses(items: Array) -> void:
	if items == _curse_items and _curses_row.get_child_count() == items.size():
		return
	_curse_items = items.duplicate()
	_rebuild(_curses_row, _curse_items)


func set_upgrades(items: Array) -> void:
	if items == _upgrade_items and _upgrades_row.get_child_count() == items.size():
		return
	_upgrade_items = items.duplicate()
	_rebuild(_upgrades_row, _upgrade_items)


func toggle_collapsed() -> void:
	collapsed = not collapsed
	_curses_row.visible = not collapsed
	_upgrades_row.visible = not collapsed


func is_collapsed() -> bool:
	return collapsed


func curse_count() -> int:
	return _curse_items.size()


func upgrade_count() -> int:
	return _upgrade_items.size()


func _rebuild(row: HBoxContainer, items: Array) -> void:
	for c in row.get_children():
		row.remove_child(c)   # queue_free alone leaves the old cell drawn this frame
		c.queue_free()
	for item in items:
		var id := str(item.get("id", ""))
		var stacks := int(item.get("stacks", 1))
		var cell: Control = _placeholder_script.new()
		cell.setup(id, CELL)
		var badge := Label.new()
		badge.text = "x%d" % stacks
		badge.add_theme_font_size_override("font_size", 14)
		badge.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		badge.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		badge.add_theme_constant_override("outline_size", 3)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if stacks > 1:
			cell.add_child(badge)
		row.add_child(cell)
