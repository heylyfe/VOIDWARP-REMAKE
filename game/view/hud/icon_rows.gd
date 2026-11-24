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
# The rows are CENTRED in a fixed slot (hud_style.gd: MARGIN .. ICON_ROWS_BOTTOM, wide
# enough for MAX_PER_ROW cells), so cells pack around the middle and never walk into the
# roster (top-left) or the purse (top-right). D-GUI-1: both rows sit in one dark rounded
# panel that shrinks to the cells it holds (hidden when empty or collapsed). A row with
# more than MAX_PER_ROW items shows the first MAX_PER_ROW - 1 and a "+N" cell, so the
# 100+ curse catalogue can never push a row off its slot.

const IconArtScript := preload("res://view/icon_art.gd")
const HudStyle := preload("res://view/hud/hud_style.gd")

const CELL := HudStyle.ICON_CELL
const GAP := HudStyle.ICON_GAP
const MAX_PER_ROW := 12
const SLOT_W := CELL * MAX_PER_ROW + GAP * (MAX_PER_ROW - 1) + HudStyle.PAD_X * 2.0   # 574

var collapsed := false
var _panel: Panel
var _rows: VBoxContainer
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
	offset_left = -SLOT_W * 0.5
	offset_right = SLOT_W * 0.5
	offset_top = HudStyle.ICON_ROWS_TOP
	offset_bottom = HudStyle.ICON_ROWS_BOTTOM
	# the panel is a plain backing sized by _update_panel(); the rows keep their
	# "Rows/CursesRow" / "Rows/UpgradesRow" paths (test_polish_cycle2.gd reads them)
	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", HudStyle.panel())
	add_child(_panel)
	var col := VBoxContainer.new()
	col.name = "Rows"
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", int(GAP))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	_rows = col
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
	_update_panel()


## items: Array of {"id": String, "stacks": int}. stacks defaults to 1.
## An unchanged list is a no-op (hud.sync runs every tick; rebuilding the cells each tick
## would churn nodes for nothing).
func set_curses(items: Array) -> void:
	if items == _curse_items and _curses_row.get_child_count() == cells_for(items.size()):
		return
	_curse_items = items.duplicate()
	_rebuild(_curses_row, _curse_items, "curses")
	_update_panel()


func set_upgrades(items: Array) -> void:
	if items == _upgrade_items and _upgrades_row.get_child_count() == cells_for(items.size()):
		return
	_upgrade_items = items.duplicate()
	_rebuild(_upgrades_row, _upgrade_items, "upgrades")
	_update_panel()


func toggle_collapsed() -> void:
	collapsed = not collapsed
	_curses_row.visible = not collapsed
	_upgrades_row.visible = not collapsed
	_update_panel()


## How many cells a row of n items draws (n, or MAX_PER_ROW once "+N" folds the rest).
static func cells_for(n: int) -> int:
	return mini(n, MAX_PER_ROW)


## The panel shows only when it holds something: hidden while collapsed or empty; an
## empty row folds away so one row of cells gets a one-row panel.
func _update_panel() -> void:
	if collapsed:
		_panel.visible = false
		return
	_curses_row.visible = not _curse_items.is_empty()
	_upgrades_row.visible = not _upgrade_items.is_empty()
	_panel.visible = _curses_row.visible or _upgrades_row.visible
	var w := 0.0
	var h := 0.0
	for pair in [[_curses_row.visible, _curse_items.size()], [_upgrades_row.visible, _upgrade_items.size()]]:
		if not pair[0]:
			continue
		var n := cells_for(int(pair[1]))
		w = maxf(w, CELL * n + GAP * (n - 1))
		h += CELL if h == 0.0 else GAP + CELL
	var pw := w + HudStyle.PAD_X * 2.0
	var ph := h + HudStyle.PAD_Y * 2.0
	_panel.position = Vector2((SLOT_W - pw) * 0.5, 0.0)
	_panel.size = Vector2(pw, ph)
	_rows.position = Vector2(HudStyle.PAD_X, HudStyle.PAD_Y)
	_rows.size = Vector2(SLOT_W - HudStyle.PAD_X * 2.0, h)


## The on-screen panel rect (global), or an empty Rect2 when the panel is hidden.
func panel_rect() -> Rect2:
	if not _panel.is_visible_in_tree():
		return Rect2()
	return _panel.get_global_rect()


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
	var shown := items.size()
	if shown > MAX_PER_ROW:
		shown = MAX_PER_ROW - 1
	for k in shown:
		var item: Dictionary = items[k]
		var id := str(item.get("id", ""))
		var stacks := int(item.get("stacks", 1))
		var cell: Control = _make_cell(id, kind)
		# D-U5-1: the badge exists only for a cell that SHOWS a stack count. It used to be
		# built for every cell and parented only when stacks > 1, so a single-stack cell
		# dropped a styled Label on the floor - created, never parented, never freed, once
		# per cell per rebuild. Nothing allocates a badge the row is not going to hold.
		if stacks > 1:
			cell.add_child(_stack_badge(stacks))
		row.add_child(cell)
	if shown < items.size():
		row.add_child(_overflow_cell(items.size() - shown))


## The "xN" stack badge, bottom-right of a cell. Built only when N > 1, and always parented
## by its caller: it is a child of the cell, so the cell's own free takes it with it.
func _stack_badge(stacks: int) -> Label:
	var badge := Label.new()
	badge.text = "x%d" % stacks
	HudStyle.style_label(badge, HudStyle.FONT_SMALL)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	return badge


## "+N": the items a full row cannot show.
func _overflow_cell(n: int) -> Control:
	var back := Panel.new()
	back.custom_minimum_size = Vector2(CELL, CELL)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_theme_stylebox_override("panel", HudStyle.cell())
	var l := Label.new()
	l.text = "+%d" % n
	HudStyle.style_label(l, HudStyle.FONT_SMALL, HudStyle.TEXT_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.add_child(l)
	back.set_meta("icon_kind", "overflow")
	return back


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
	back.add_theme_stylebox_override("panel", HudStyle.cell())
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
