extends Control
#
# Class ability cooldown, bottom-left right of the void pips / Last Light icon
# (ticket T-025; DESIGN.md section 14). Position is not stated by any document -
# placed there to keep the bottom-left cluster together (D-T025-3).
#
# Data comes from the controller (sim/controller.gd): the Dasher's dash_cd /
# dash_regen (3.0 s, DESIGN.md section 4), the Glider's glide_energy /
# C["glide_energy"] (3.0 s of airtime, refilled on landing). The Athletic has no
# active ability (DESIGN.md section 4), so the element hides itself for that
# class. A radial sweep shows the fraction remaining; the seconds text shows the
# exact number.

const HudStyle := preload("res://view/hud/hud_style.gd")
const VoidPipsScript := preload("res://view/hud/void_pips.gd")

const ICON := 48.0
const BAR_W := 110.0
const BAR_H := 10.0
const GAP := 12.0
const READY_COLOR := Color(0.486, 1.0, 0.957)   # #7CFFF4
const CD_COLOR := Color(1.0, 0.85, 0.4, 1.0)
# D-GUI-1: a dark rounded panel the same height as the pips panel, one GAP to its right
# (the pips panel is measured at the normal 2-pip cap; under Hungry Void the gap widens).
const PAD_X := HudStyle.PAD_X
const PANEL_H := HudStyle.BOTTOM_ROW_H
const PAD_TOP := (PANEL_H - ICON) * 0.5

var kit := "dasher"
var remaining := 0.0
var total := 3.0
var _icon: Control
var _bar: Control
var _seconds: Label


func _init() -> void:
	custom_minimum_size = Vector2(PAD_X * 2.0 + ICON + GAP + BAR_W, PANEL_H)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	# right of the pips + Last Light panel, one GAP over
	offset_left = HudStyle.MARGIN + VoidPipsScript.panel_width(2) + HudStyle.GAP
	offset_right = offset_left + custom_minimum_size.x
	offset_top = -HudStyle.MARGIN - PANEL_H
	offset_bottom = -HudStyle.MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudStyle.add_background(self)
	_icon = _AbilityIcon.new()
	_icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_icon.position = Vector2(PAD_X, PAD_TOP)
	_icon.size = Vector2(ICON, ICON)
	add_child(_icon)
	_bar = _CooldownBar.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_bar.position = Vector2(PAD_X + ICON + GAP, PAD_TOP + ICON * 0.5 - BAR_H - 1.0)
	_bar.size = Vector2(BAR_W, BAR_H)
	add_child(_bar)
	_seconds = Label.new()
	_seconds.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_seconds.position = Vector2(PAD_X + ICON + GAP, PAD_TOP + ICON * 0.5 + 1.0)
	HudStyle.style_label(_seconds, HudStyle.FONT_SMALL)
	add_child(_seconds)


## kit: "dasher" | "glider" | "athletic"; remaining/total in seconds.
func sync(p_kit: String, p_remaining: float, p_total: float) -> void:
	kit = p_kit
	total = maxf(0.0001, p_total)
	remaining = clampf(p_remaining, 0.0, total)
	var has_active := kit != "athletic"
	visible = has_active
	if not has_active:
		return
	(_icon as _AbilityIcon).kit = kit
	(_icon as _AbilityIcon).fraction = fraction()
	(_icon as _AbilityIcon).queue_redraw()
	(_bar as _CooldownBar).fraction = fraction()
	(_bar as _CooldownBar).charged = is_ready()
	(_bar as _CooldownBar).queue_redraw()
	_seconds.text = seconds_text()


func fraction() -> float:
	if kit == "glider":
		return clampf(remaining / total, 0.0, 1.0)   # energy left
	return clampf(1.0 - remaining / total, 0.0, 1.0) # cooldown charged


func is_ready() -> bool:
	if kit == "glider":
		return remaining >= total - 1e-6
	return remaining <= 1e-6


func seconds_text() -> String:
	if is_ready():
		return "READY"
	return "%.1fs" % remaining


class _AbilityIcon extends Control:
	var kit := "dasher"
	var fraction := 1.0

	func _draw() -> void:
		var s := size
		draw_style_box(HudStyle.cell(), Rect2(Vector2.ZERO, s))
		# sweep: the dim sector is the cooling part (full circle when ready)
		var c := Vector2(s.x * 0.5, s.y * 0.5)
		var r := s.x * 0.28
		draw_circle(c, r * 1.6, Color(0.0, 0.0, 0.0, 0.35))
		if kit == "dasher":
			_draw_chevron(c, r, READY_COLOR if fraction >= 1.0 else CD_COLOR)
		else:
			_draw_wing(c, r, READY_COLOR if fraction >= 1.0 else CD_COLOR)

	func _draw_chevron(c: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array([
			Vector2(c.x - r, c.y - r * 0.6), Vector2(c.x, c.y), Vector2(c.x - r, c.y + r * 0.6)])
		draw_polyline(pts, col, 5.0, true)
		var pts2 := PackedVector2Array([
			Vector2(c.x, c.y - r * 0.6), Vector2(c.x + r, c.y), Vector2(c.x, c.y + r * 0.6)])
		draw_polyline(pts2, col, 5.0, true)

	func _draw_wing(c: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array([
			Vector2(c.x - r, c.y + r * 0.5), Vector2(c.x - r * 0.2, c.y - r * 0.6),
			Vector2(c.x + r, c.y - r * 0.2), Vector2(c.x + r * 0.2, c.y + r * 0.5)])
		draw_colored_polygon(pts, col)


class _CooldownBar extends Control:
	var fraction := 1.0
	var charged := true

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(1.0, 1.0, 1.0, 0.10), true)
		var w := s.x * clampf(fraction, 0.0, 1.0)
		if w > 0.5:
			draw_rect(Rect2(Vector2.ZERO, Vector2(w, s.y)), READY_COLOR if charged else CD_COLOR, true)
