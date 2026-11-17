extends Control
#
# Synthesized placeholder icon (ticket T-025; TBD rule) - a hash-hue rounded
# square with the item's initials. Used by the curse/upgrade icon rows and the
# enemy roster until real icon art exists (D-T025-4; TBD.md). Deterministic per
# id: never index-dependent, so the same id always gets the same hue and letters.

var icon_id := ""
var cell := 40.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_id: String, p_cell: float = 40.0) -> void:
	icon_id = p_id
	cell = p_cell
	custom_minimum_size = Vector2(cell, cell)
	size = custom_minimum_size


static func hue_for(id: String) -> float:
	return float(abs(id.hash()) % 360) / 360.0


static func initials_for(id: String) -> String:
	var parts := id.replace("-", "_").split("_", false)
	var out := ""
	for p in parts:
		if p.length() > 0:
			out += p.substr(0, 1).to_upper()
		if out.length() >= 2:
			break
	return out if out.length() > 0 else "?"


func _draw() -> void:
	var s := size
	var hue := hue_for(icon_id)
	draw_rect(Rect2(Vector2.ZERO, s), Color.from_hsv(hue, 0.55, 0.32, 1.0), true)
	draw_rect(Rect2(Vector2.ZERO, s), Color.from_hsv(hue, 0.7, 0.75, 1.0), false, 2.0)
	var font := ThemeDB.fallback_font
	var fs := int(s.x * 0.36)
	var text := initials_for(icon_id)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var ascent := font.get_ascent(fs)
	draw_string(font, Vector2((s.x - tw) * 0.5, s.y * 0.5 + ascent * 0.5 - 2.0), text,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs, Color(1.0, 1.0, 1.0, 0.95))
