extends Control
#
# Enemy counter, top-left (ticket T-025; DESIGN.md section 14 "enemy roster icons with
# counts"; section 6: every voted enemy stays in play for the rest of the run).
#
# One cell per enemy TYPE in play this level, with its count: the run's carried vote
# ledger, which rises monotonically across the run (DESIGN.md section 6's "enemies in
# play next level" column) - so a cell never leaves once its type is voted in, and a
# repeat vote raises the badge. Enemies are never killed (ENEMIES.md), so this is the
# planned body count, not a kill tally. Entries with count < 1 are not shown; with
# nothing in play the element hides itself.
#
# Icon: the enemy's own sprite art (content/enemies/<id>/sprites/, the first frame of
# the first ICON_FRAMES name that exists), cropped to its opaque pixels so a padded
# sheet still reads at 40 px. An id with no art keeps the synthesized placeholder
# (icon_placeholder.gd, D-T025-4). Cells wrap into a COLUMNS-wide grid, so twelve types
# (the whole roster) stay a 4 x 3 block in the corner - clear of the centred Tab rows
# (icon_rows.gd, +-400 px about the centre) and of the play area (D-T025-1).
#
# The world re-sends the roster every frame; the cells are rebuilt only when the
# (id, count) list actually changed.

const CELL := 40.0
const GAP := 6.0
const EDGE := 16.0
const COLUMNS := 4
const MAX_ROWS := 3   # 12 cells: the whole enemy roster
const ICON_FRAMES := ["idle_00.png", "cycle_00.png", "idle_chase_00.png", "spawn_00.png"]

static var _icon_cache: Dictionary = {}   # id -> Texture2D or null (presentation cache only)

var _row: GridContainer   # named _row since T-025 (test_hud reads it); a wrapping grid now
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
	offset_right = EDGE + CELL * COLUMNS + GAP * (COLUMNS - 1)
	offset_top = EDGE
	offset_bottom = EDGE + CELL * MAX_ROWS + GAP * (MAX_ROWS - 1)
	_row = GridContainer.new()
	_row.columns = COLUMNS
	_row.add_theme_constant_override("h_separation", int(GAP))
	_row.add_theme_constant_override("v_separation", int(GAP))
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_row)
	visible = false


## The enemy's sprite icon (cropped to its opaque pixels), or null when the id ships no
## art - the caller then draws the placeholder. Cached per id.
static func icon_for(id: String) -> Texture2D:
	if _icon_cache.has(id):
		return _icon_cache[id]
	var tex: Texture2D = null
	for fname in ICON_FRAMES:
		var path := "res://content/enemies/%s/sprites/%s" % [id, fname]
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
			if tex != null:
				break
	if tex != null:
		var img: Image = tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			var used: Rect2i = img.get_used_rect()
			if used.size.x > 0 and used.size.y > 0 and used != Rect2i(Vector2i.ZERO, img.get_size()):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(used)
				tex = at
	_icon_cache[id] = tex
	return tex


## items: Array of {"id": String, "name": String, "count": int}.
func set_roster(items: Array) -> void:
	var fresh: Array = []
	for item in items:
		if int(item.get("count", 0)) > 0:
			fresh.append({"id": str(item.get("id", "")), "count": int(item.get("count", 0))})
	if fresh == _items and _row.get_child_count() == _items.size():
		return   # unchanged: the per-frame re-send costs nothing
	_items = fresh
	visible = not _items.is_empty()
	for c in _row.get_children():
		_row.remove_child(c)   # queue_free alone leaves the old cell drawn this frame
		c.queue_free()
	for item in _items:
		var cell := _make_icon(str(item["id"]))
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


## One CELL-square icon cell: the sprite art on a dark backing, or the placeholder.
func _make_icon(id: String) -> Control:
	var tex := icon_for(id)
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
	back.set_meta("icon_kind", "sprite")
	return back


func roster_count() -> int:
	return _items.size()


## [{id, count}] in display order (the cells' own order) - the test surface.
func rows() -> Array:
	return _items.duplicate(true)


## "sprite" or "placeholder" for the id's cell; "" when the id has no cell.
func icon_kind_for(id: String) -> String:
	for i in _items.size():
		if str(_items[i]["id"]) == id and i < _row.get_child_count():
			return str(_row.get_child(i).get_meta("icon_kind", ""))
	return ""


## The badge text of the id's cell ("x3"); "" when the id has no cell.
func badge_for(id: String) -> String:
	for i in _items.size():
		if str(_items[i]["id"]) == id and i < _row.get_child_count():
			for c in _row.get_child(i).get_children():
				if c is Label:
					return str((c as Label).text)
	return ""


func count_for(id: String) -> int:
	for item in _items:
		if str(item["id"]) == id:
			return int(item["count"])
	return 0
