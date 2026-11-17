extends Control
#
# Void charge pips + the Last Light icon (ticket T-025; DESIGN.md section 14 and
# section 3.1; research/fable-tickets.md section 2.4; D-050, D-052, D-053, D-063).
#
# One pip per holdable charge: 2, or 1 under Hungry Void (D-052) - the pip count IS
# the cap, never a number typed here. Filled = held, hollow = spent. The row sits
# bottom-left, 24 px from each edge (section 2.4); each pip is a 28 px diamond:
#   held   = filled #7CFFF4 with emission
#   spent  = 2 px outline #3A4A55
# The Last Light icon sits right of the pips (section 2.4): lit (white, soft glow)
# while unspent AND charges >= 1, dim (40% alpha) at 0 charges, grey with a slash
# once spent. hud_last_light() on the controller feeds set_last_light().
#
# The HUD never writes sim state; charges/cap come from the controller.

const HELD_COLOR := Color(0.486, 1.0, 0.957)    # #7CFFF4
const SPENT_COLOR := Color(0.227, 0.290, 0.333) # #3A4A55
const PIP_STEP := 40.0    # 28 px diamond + 12 px gap
const EDGE := 24.0
const PIP := 28.0
const LL_SIZE := 28.0
const LL_GAP := 16.0      # gap between the last pip and the Last Light icon
const ROW_HEIGHT := 28.0

var held := 2
var charge_cap := 2
var last_light := "lit"   # "lit" | "dim" | "grey"


func _init() -> void:
	custom_minimum_size = Vector2(EDGE * 2 + PIP_STEP * 2 + LL_GAP + LL_SIZE, ROW_HEIGHT)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = EDGE
	offset_right = EDGE + PIP_STEP * 2.0 + LL_GAP + LL_SIZE
	offset_top = -EDGE - ROW_HEIGHT
	offset_bottom = -EDGE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## held: charges currently held; p_cap: the holdable cap (Hungry Void => 1).
func set_charges(p_held: int, p_cap: int) -> void:
	charge_cap = maxi(1, p_cap)
	held = clampi(p_held, 0, charge_cap)
	offset_right = EDGE + PIP_STEP * float(charge_cap) + LL_GAP + LL_SIZE
	custom_minimum_size = Vector2(EDGE + offset_right, ROW_HEIGHT)
	queue_redraw()


func set_last_light(state: String) -> void:
	if state != "lit" and state != "dim" and state != "grey":
		state = "grey"
	last_light = state
	queue_redraw()


func pip_count() -> int:
	return charge_cap


func filled_count() -> int:
	return held


func hollow_count() -> int:
	return charge_cap - held


func last_light_state() -> String:
	return last_light


func _draw() -> void:
	for i in charge_cap:
		var cx := float(i) * PIP_STEP + PIP * 0.5
		var cy := ROW_HEIGHT * 0.5
		var pts := PackedVector2Array([
			Vector2(cx, cy - PIP * 0.5), Vector2(cx + PIP * 0.5, cy),
			Vector2(cx, cy + PIP * 0.5), Vector2(cx - PIP * 0.5, cy)])
		if i < held:
			# soft glow behind the filled pip, then the filled diamond
			draw_colored_polygon(_scale_pts(pts, cx, cy, 1.45), Color(HELD_COLOR.r, HELD_COLOR.g, HELD_COLOR.b, 0.25))
			draw_colored_polygon(pts, HELD_COLOR)
		else:
			_draw_outline(pts, SPENT_COLOR, 2.0)
	_draw_last_light(float(charge_cap) * PIP_STEP + LL_GAP + LL_SIZE * 0.5, ROW_HEIGHT * 0.5)


static func _scale_pts(pts: PackedVector2Array, cx: float, cy: float, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(cx + (p.x - cx) * s, cy + (p.y - cy) * s))
	return out


func _draw_outline(pts: PackedVector2Array, color: Color, width: float) -> void:
	var loop := PackedVector2Array(pts)
	loop.append(pts[0])
	draw_polyline(loop, color, width, true)


func _draw_last_light(cx: float, cy: float) -> void:
	var r := LL_SIZE * 0.5
	if last_light == "lit":
		draw_circle(Vector2(cx, cy), r * 1.45, Color(1.0, 1.0, 1.0, 0.18))
		draw_circle(Vector2(cx, cy), r, Color(1.0, 1.0, 1.0, 1.0))
	elif last_light == "dim":
		draw_circle(Vector2(cx, cy), r, Color(1.0, 1.0, 1.0, 0.4))
	else: # grey with a slash
		draw_circle(Vector2(cx, cy), r, Color(0.45, 0.45, 0.45, 1.0))
		var d := r * 0.75
		draw_line(Vector2(cx - d, cy + d), Vector2(cx + d, cy - d), Color(0.2, 0.2, 0.2, 1.0), 3.0, true)
