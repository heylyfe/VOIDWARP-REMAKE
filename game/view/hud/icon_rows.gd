extends Control
#
# Curse and upgrade icon rows, top of the screen, collapsible with Tab (ticket
# T-025; DESIGN.md section 14).
#
# Two rows: owned curses on top, owned upgrades beneath. Each entry is the item's own
# icon (assets/icons/<kind>/<id>.png through view/icon_art.gd) with a stack badge when
# more than one stack is held; an id with no art yet falls back to the synthesized
# placeholder (icon_placeholder.gd), so a missing icon never blanks the row. Pressing
# Tab (KEY_TAB, hud.gd routes it here) toggles both rows collapsed/expanded;
# collapsed hides the rows, never the rest of the HUD. The rows carry no
# tooltips - the shop and lobby own item text.
# The rows are CENTRED in their ±400 px anchor box, so cells pack around the
# middle and never walk into the roster (top-left) or the purse (top-right).

const IconArtScript := preload("res://view/icon_art.gd")

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
	col.name = "Rows"
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	_curses_row = HBoxContainer.new()
	_curses_row.name = "CursesRow"
	_curses_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_curses_row.add_theme_constant_override("separation", int(GAP))
	col.add_child(_curses_row)
	_upgrades_row = HBoxContainer.new()
	_upgrades_row.name = "UpgradesRow"
	_upgrades_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_upgrades_row.add_theme_constant_override("separation", int(GAP))
	col.add_child(_upgrades_row)


## items: Array of {"id": String, "stacks": int}. stacks defaults to 1.
## An unchanged list is a no-op (hud.sync runs every tick; rebuilding the cells each tick
## would churn nodes for nothing).
func set_curses(items: Array) -> void:
	if items == _curse_items and _curses_row.get_child_count() == items.size():
		return
	_curse_items = items.duplicate()
	_rebuild(_curses_row, _curse_items, "curses")


func set_upgrades(items: Array) -> void:
	if items == _upgrade_items and _upgrades_row.get_child_count() == items.size():
		return
	_upgrade_items = items.duplicate()
	_rebuild(_upgrades_row, _upgrade_items, "upgrades")


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


func _rebuild(row: HBoxContainer, items: Array, kind: String) -> void:
	for c in row.get_children():
		row.remove_child(c)   # queue_free alone leaves the old cell drawn this frame
		c.queue_free()
	for item in items:
		var id := str(item.get("id", ""))
		var stacks := int(item.get("stacks", 1))
		var cell: Control = _make_cell(id, kind)
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


## One CELL-square cell: the item's own icon on a dark backing, or the placeholder when
## this id has no art yet. set_meta("icon_kind") lets a test tell the two apart.
func _make_cell(id: String, kind: String) -> Control:
	var tex := IconArtScript.texture_for(kind, id)
	if tex == null:
		var ph: Control = _placeholder_script.new()
		ph.setup(id, CELL)
		ph.set_meta("icon_kind", "placeholder")
		return ph
	var back := Panel.new()
	back.custom_minimum_size = Vector2(CELL, CELL)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	sb.set_corner_radius_all(4)
	back.add_theme_stylebox_override("panel", sb)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.offset_left = 2.0
	tr.offset_top = 2.0
	tr.offset_right = -2.0
	tr.offset_bottom = -2.0
	back.add_child(tr)
	back.set_meta("icon_kind", "art")
	return back
