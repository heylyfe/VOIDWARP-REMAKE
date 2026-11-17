extends Control
#
# Enemy roster icons with counts, top-left (ticket T-025; DESIGN.md section 14).
#
# One entry per enemy TYPE alive in the level, with the count currently alive.
# Enemies are never killed (ENEMIES.md: nothing in the roster can be killed), so
# the count is the live body count from the enemy runtime - not a kill tally.
# Entries with count < 1 are not shown; when nothing has spawned the element
# hides itself. Icons are synthesized placeholders (icon_placeholder.gd) until
# real art exists (D-T025-4). Position is not stated by any document - top-left,
# clear of the Tab rows (D-T025-1).

const CELL := 40.0
const GAP := 6.0
const EDGE := 16.0

var _row: HBoxContainer
var _items: Array = []
var _placeholder_script: GDScript


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder_script = load("res://view/hud/icon_placeholder.gd")
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = EDGE
	offset_right = EDGE + CELL * 8.0 + GAP * 7.0
	offset_top = EDGE
	offset_bottom = EDGE + CELL
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", int(GAP))
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_row)
	visible = false


## items: Array of {"id": String, "name": String, "count": int}.
func set_roster(items: Array) -> void:
	_items = []
	for item in items:
		if int(item.get("count", 0)) > 0:
			_items.append({"id": str(item.get("id", "")), "count": int(item.get("count", 0))})
	visible = not _items.is_empty()
	for c in _row.get_children():
		c.queue_free()
	for item in _items:
		var cell: Control = _placeholder_script.new()
		cell.setup(str(item["id"]), CELL)
		var badge := Label.new()
		badge.text = "x%d" % int(item["count"])
		badge.add_theme_font_size_override("font_size", 14)
		badge.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		badge.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		badge.add_theme_constant_override("outline_size", 3)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(badge)
		_row.add_child(cell)


func roster_count() -> int:
	return _items.size()


func count_for(id: String) -> int:
	for item in _items:
		if str(item["id"]) == id:
			return int(item["count"])
	return 0
