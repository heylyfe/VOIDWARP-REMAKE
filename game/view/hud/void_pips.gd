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
#
# T-086 (research/fable-tickets.md section 2.4, verify + close): the pip ANIMATIONS are
# stepped here, driven by the injected advance(ticks) (60 ticks/s; _process feeds
# delta * TICKS_PER_SECOND) - the spec's durations are tick counts (D-T086-1). Callers:
#   pip_spend()       on the fall tick, AFTER set_charges with the post-spend count
#   pip_restore()     on the beacon_enter event, BEFORE the next sync; self-corrects to
#                     the pulse case (D-T086-5) when no hollow pip exists at call time
#   pip_free_fall()   on a Field Dressing free fall (app/world.gd _fx_events forwards the
#                     void_fall event's `free` flag; PARKED.md row 3 is closed)
#   last_light_trigger()  on the Last Light save; the bloom lives in screen_fx.gd
# All four are wired by app/world.gd and pinned by tests/test_world_stat_wiring.gd.

const HudStyle := preload("res://view/hud/hud_style.gd")

const HELD_COLOR := Color(0.486, 1.0, 0.957)    # #7CFFF4
const SPENT_COLOR := Color(0.227, 0.290, 0.333) # #3A4A55
const PIP_STEP := 40.0    # 28 px diamond + 12 px gap
const EDGE := HudStyle.MARGIN   # D-GUI-1: the shared screen margin (was 24)
const PIP := 28.0
const LL_SIZE := 28.0
const LL_GAP := 16.0      # gap between the last pip and the Last Light icon
const ROW_HEIGHT := 28.0
# D-GUI-1: the row sits inside a dark rounded panel, BOTTOM_ROW_H tall like the class
# ability panel beside it. The diamonds are drawn PAD_X / PAD_TOP in from the panel corner;
# the panel's lower padding leaves room for the "FREE" tick under a pip.
const PAD_X := HudStyle.PAD_X
const PANEL_H := HudStyle.BOTTOM_ROW_H
const PAD_TOP := (PANEL_H - ROW_HEIGHT) * 0.5
const TICKS_PER_SECOND := 60.0
const SPEND_TICKS := 18.0       # binding (section 2.4): pip drains downward over 18 ticks
const RESTORE_TICKS := 24.0     # binding (section 2.4): first hollow pip fills upward
const FREE_TICKS := 60.0        # binding (section 2.4): "FREE" tick for 60 ticks
const FREE_FLASH_TICKS := 12.0  # [CONTESTABLE] D-T086-4: pip white flash, first 12 of 60
const PULSE_TICKS := 12.0       # [CONTESTABLE] D-T086-3: already-full pulse, once
const GLINT_TAIL_TICKS := 6.0   # [CONTESTABLE] D-T086-5: white glow after the fill lands
const SHATTER_TICKS := 12.0     # [CONTESTABLE] D-T086-6: icon shatter, matches the bloom

var held := 2
var charge_cap := 2
var last_light := "lit"   # "lit" | "dim" | "grey"

# T-086 animation state (all stepped by advance(); idle values below)
var _anim := "none"       # "none" | "spend" | "restore"
var _anim_t := 0.0        # elapsed ticks of the current _anim
var _anim_index := -1     # pip index the current _anim draws
var _pulse_t := -1.0      # < 0 idle; else ticks of the already-full pulse remaining
var _free_t := -1.0       # < 0 idle; else ticks of the FREE tick remaining
var _free_index := 0      # pip flashing white during the FREE tick
var _glint_tail_t := -1.0 # < 0 idle; else ticks of the post-fill glint glow remaining
var _glint_index := -1    # pip carrying the glint tail
var _shatter_t := -1.0    # < 0 idle; else elapsed ticks of the Last Light shatter


func _init() -> void:
	custom_minimum_size = Vector2(panel_width(2), PANEL_H)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = EDGE
	offset_right = EDGE + panel_width(2)
	offset_top = -EDGE - PANEL_H
	offset_bottom = -EDGE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The panel width for a cap of p_cap pips: the pips, the Last Light icon, the padding.
static func panel_width(p_cap: int) -> float:
	return PAD_X * 2.0 + PIP_STEP * float(p_cap) + LL_GAP + LL_SIZE


## held: charges currently held; p_cap: the holdable cap (Hungry Void => 1).
func set_charges(p_held: int, p_cap: int) -> void:
	charge_cap = maxi(1, p_cap)
	held = clampi(p_held, 0, charge_cap)
	if _free_t >= 0.0:
		# a charge spent inside the FREE window: the flash follows the held count
		_free_index = maxi(held - 1, 0)
	custom_minimum_size = Vector2(panel_width(charge_cap), PANEL_H)
	offset_right = EDGE + panel_width(charge_cap)
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


# ---- T-086: the section 2.4 animations (stepped by advance(); D-T086-1..6) ----------

## The pip that just went hollow cracks and drains downward over 18 ticks (binding).
## Call AFTER set_charges with the post-spend count: the draining pip is the first
## hollow one (index held). No-op when no hollow pip exists.
func pip_spend() -> void:
	if held >= charge_cap:
		return
	_anim = "spend"
	_anim_t = 0.0
	_anim_index = held
	queue_redraw()


## The first hollow pip fills upward over 24 ticks with a white glint (binding).
## Call on the beacon_enter event, BEFORE the next sync carries the incremented
## count: the animating pip is the one at index held at call time (post-sync it reads
## as the last filled pip - same index). If the pips are already full, pulse once
## instead (section 2.4) - one call site handles both spec branches.
func pip_restore() -> void:
	if held >= charge_cap:
		pip_already_full()
		return
	_anim = "restore"
	_anim_t = 0.0
	_anim_index = held
	queue_redraw()


## The already-full case: the pips pulse once (section 2.4). No fill change.
func pip_already_full() -> void:
	if _pulse_t >= 0.0:
		return   # one pulse at a time - "once" is the spec
	_pulse_t = PULSE_TICKS
	queue_redraw()


## Field Dressing (upgrade): the last held pip flashes white and stays filled; a small
## "FREE" tick appears for 60 ticks (binding). Sim hook absent - see PARKED.md row 3.
func pip_free_fall() -> void:
	if held <= 0:
		return   # no held pip to flash (a fall with no charge is a death, not a FREE tick)
	_free_index = maxi(held - 1, 0)
	_free_t = FREE_TICKS
	queue_redraw()


## The Last Light trigger: the icon shatters over 12 ticks (D-T086-6). The white bloom
## is screen_fx.white_bloom(); "the player appears on the dais" is sim-side (D-053).
func last_light_trigger() -> void:
	if _shatter_t >= 0.0:
		return
	_shatter_t = 0.0
	queue_redraw()


## Advance every animation clock by `ticks` (tests call this directly - no real time).
func advance(ticks: float) -> void:
	var dt := maxf(ticks, 0.0)
	if _pulse_t >= 0.0:
		_pulse_t -= dt
		if _pulse_t <= 0.0:
			_pulse_t = -1.0
	if _free_t >= 0.0:
		_free_t -= dt
		if _free_t <= 0.0:
			_free_t = -1.0
	if _glint_tail_t >= 0.0:
		_glint_tail_t -= dt
		if _glint_tail_t <= 0.0:
			_glint_tail_t = -1.0
			_glint_index = -1
	if _shatter_t >= 0.0:
		_shatter_t += dt
		if _shatter_t >= SHATTER_TICKS:
			_shatter_t = -1.0
	if _anim == "spend":
		_anim_t += dt
		if _anim_t >= SPEND_TICKS:
			_anim = "none"
			_anim_t = 0.0
			_anim_index = -1
	elif _anim == "restore":
		_anim_t += dt
		if _anim_t >= RESTORE_TICKS:
			_anim = "none"
			_anim_t = 0.0
			_glint_index = _anim_index
			_glint_tail_t = GLINT_TAIL_TICKS
			_anim_index = -1
	queue_redraw()


func _process(delta: float) -> void:
	advance(delta * TICKS_PER_SECOND)


func spend_active() -> bool:
	return _anim == "spend"


func restore_active() -> bool:
	return _anim == "restore"


## 0..1 progress of the running pip animation; -1 when idle.
func anim_progress() -> float:
	if _anim == "spend":
		return clampf(_anim_t / SPEND_TICKS, 0.0, 1.0)
	if _anim == "restore":
		return clampf(_anim_t / RESTORE_TICKS, 0.0, 1.0)
	return -1.0


func pulse_active() -> bool:
	return _pulse_t >= 0.0


func free_tick_active() -> bool:
	return _free_t >= 0.0


## True while the pip flashes white at the start of the FREE window (D-T086-4).
func free_flash_active() -> bool:
	return _free_t >= 0.0 and _free_t > FREE_TICKS - FREE_FLASH_TICKS


func shatter_active() -> bool:
	return _shatter_t >= 0.0


func shatter_progress() -> float:
	if _shatter_t < 0.0:
		return -1.0
	return clampf(_shatter_t / SHATTER_TICKS, 0.0, 1.0)


func glint_active() -> bool:
	return _glint_tail_t >= 0.0


## Fill fraction (0..1) of the pip currently animating; spend drains 1->0, restore 0->1.
func filling_fraction() -> float:
	if _anim == "restore":
		return clampf(_anim_t / RESTORE_TICKS, 0.0, 1.0)
	if _anim == "spend":
		return 1.0 - clampf(_anim_t / SPEND_TICKS, 0.0, 1.0)
	return -1.0


## Sutherland-Hodgman clip of a convex polygon to the half-plane y >= y_min.
static func _clip_above(pts: PackedVector2Array, y_min: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var cur := pts[i]
		var prev := pts[(i - 1 + n) % n]
		var cur_in := cur.y >= y_min
		var prev_in := prev.y >= y_min
		if cur_in != prev_in:
			var t := (y_min - prev.y) / (cur.y - prev.y)
			out.append(Vector2(prev.x + (cur.x - prev.x) * t, y_min))
		if cur_in:
			out.append(cur)
	return out


func _surface_y(f: float) -> float:
	return ROW_HEIGHT * 0.5 + PIP * 0.5 - f * PIP


## Half-width of the diamond at row-local y (0 outside).
func _diamond_half_width(y: float) -> float:
	var cy := ROW_HEIGHT * 0.5
	var hw := PIP * 0.5 * (1.0 - absf(y - cy) / (PIP * 0.5))
	return maxf(hw, 0.0)


func _draw() -> void:
	# D-GUI-1: the panel first, then everything else in panel-content coordinates
	draw_style_box(_panel_box(), Rect2(Vector2.ZERO, size))
	draw_set_transform(Vector2(PAD_X, PAD_TOP))
	var pulse := 0.0
	if _pulse_t >= 0.0:
		pulse = sin(PI * (1.0 - _pulse_t / PULSE_TICKS))
	for i in charge_cap:
		var cx := float(i) * PIP_STEP + PIP * 0.5
		var cy := ROW_HEIGHT * 0.5
		var pts := PackedVector2Array([
			Vector2(cx, cy - PIP * 0.5), Vector2(cx + PIP * 0.5, cy),
			Vector2(cx, cy + PIP * 0.5), Vector2(cx - PIP * 0.5, cy)])
		if held > 0 and i == _free_index and free_flash_active():
			# Field Dressing: the pip flashes white and stays filled (section 2.4)
			draw_colored_polygon(_scale_pts(pts, cx, cy, 1.45), Color(1.0, 1.0, 1.0, 0.5))
			draw_colored_polygon(pts, Color(1.0, 1.0, 1.0, 1.0))
		elif i == _anim_index and _anim == "spend":
			# cracked and draining downward over 18 ticks; spent outline beneath
			var f := filling_fraction()
			_draw_outline(pts, SPENT_COLOR, 2.0)
			_draw_cracks(cx, cy, 1.0 - f)
			if f > 0.001:
				var clipped := _clip_above(pts, _surface_y(f))
				if clipped.size() >= 3:
					draw_colored_polygon(clipped, HELD_COLOR)
		elif i == _anim_index and _anim == "restore":
			# filling upward over 24 ticks, white glint riding the surface
			var f := filling_fraction()
			_draw_outline(pts, SPENT_COLOR, 2.0)
			if f > 0.001:
				var clipped := _clip_above(pts, _surface_y(f))
				if clipped.size() >= 3:
					draw_colored_polygon(clipped, HELD_COLOR)
			var surface_y := _surface_y(f)
			var hw := _diamond_half_width(surface_y)
			if hw > 1.0:
				draw_line(Vector2(cx - hw, surface_y), Vector2(cx + hw, surface_y),
						Color(1.0, 1.0, 1.0, 0.95), 3.0, true)
				draw_circle(Vector2(cx, surface_y), 3.0, Color(1.0, 1.0, 1.0, 0.8))
		elif i < held:
			# soft glow behind the filled pip, then the filled diamond; the already-full
			# pulse (section 2.4) swells the glow once
			draw_colored_polygon(_scale_pts(pts, cx, cy, 1.45 + 0.25 * pulse),
					Color(HELD_COLOR.r, HELD_COLOR.g, HELD_COLOR.b, 0.25 + 0.45 * pulse))
			draw_colored_polygon(pts, HELD_COLOR)
			if i == _glint_index and _glint_tail_t >= 0.0:
				var ga := _glint_tail_t / GLINT_TAIL_TICKS
				draw_colored_polygon(_scale_pts(pts, cx, cy, 1.3 + 0.2 * (1.0 - ga)),
						Color(1.0, 1.0, 1.0, 0.5 * ga))
		else:
			_draw_outline(pts, SPENT_COLOR, 2.0)
	if _free_t >= 0.0:
		# the small "FREE" tick for 60 ticks, under the flashing pip (section 2.4)
		var fx := float(_free_index) * PIP_STEP + PIP * 0.5
		var font := ThemeDB.fallback_font
		var fs := 11
		var tw := font.get_string_size("FREE", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(fx - tw * 0.5, ROW_HEIGHT + 13), "FREE",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 1.0, 1.0, 0.95))
	var ll_cx := float(charge_cap) * PIP_STEP + LL_GAP + LL_SIZE * 0.5
	if _shatter_t >= 0.0:
		_draw_shatter(ll_cx, ROW_HEIGHT * 0.5)
	else:
		_draw_last_light(ll_cx, ROW_HEIGHT * 0.5)


var _box: StyleBoxFlat = null


func _panel_box() -> StyleBoxFlat:
	if _box == null:
		_box = HudStyle.panel()
	return _box


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


## Crack lines across a draining pip (alpha ramps in over the first third of the drain).
func _draw_cracks(cx: float, cy: float, phase: float) -> void:
	var a := clampf(phase * 3.0, 0.0, 1.0) * 0.9
	if a <= 0.01:
		return
	var col := Color(0.10, 0.13, 0.16, a)
	var cracks := [
		PackedVector2Array([Vector2(cx - 6.0, cy - 14.0), Vector2(cx, cy - 4.0), Vector2(cx - 4.0, cy + 6.0)]),
		PackedVector2Array([Vector2(cx + 8.0, cy - 10.0), Vector2(cx + 2.0, cy + 2.0), Vector2(cx + 9.0, cy + 12.0)]),
		PackedVector2Array([Vector2(cx - 10.0, cy + 2.0), Vector2(cx, cy + 8.0), Vector2(cx - 2.0, cy + 14.0)]),
	]
	for crack in cracks:
		draw_polyline(crack, col, 2.0, true)


## The Last Light icon shattering: six wedge shards fly radially outward, spin, fade (D-T086-6).
func _draw_shatter(cx: float, cy: float) -> void:
	var p := shatter_progress()
	var ease_out := sin(p * PI * 0.5)
	var r := LL_SIZE * 0.5
	var col := Color(1.0, 1.0, 1.0, 1.0 - p)
	for k in 6:
		var base := float(k) * TAU / 6.0 + 0.26
		var dir := Vector2(cos(base), sin(base))
		var c := Vector2(cx, cy) + dir * (4.0 + ease_out * 38.0)
		var ang := base + p * 1.6
		var p1 := c + Vector2(cos(ang), sin(ang)) * r
		var p2 := c + Vector2(cos(ang + 2.1), sin(ang + 2.1)) * r * 0.8
		var p3 := c + Vector2(cos(ang + 4.2), sin(ang + 4.2)) * r * 0.9
		draw_colored_polygon(PackedVector2Array([p1, p2, p3]), col)
