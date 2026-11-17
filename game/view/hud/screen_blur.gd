extends Control
#
# Screen blur - thicc ben's touch (ticket T-032; DESIGN.md section 5.3; T-083 anim block
# section 1.3 "Player-side": screen blur 180 ticks (3.0 s, binding), strength 1 -> 0
# linearly over the last 60 ticks).
#
# PLACEHOLDER: Godot's blur lives behind BackBufferCopy + a shader this repo does not
# have yet (the HUD's first shader is not landed). Until it lands this draws a
# full-screen translucent teal wash whose alpha follows the strength curve - the
# timing and the strength math are the binding spec, the look is a stand-in. The
# caller triggers it on the sim's "screen_blur" event (180 ticks); T-024 wires the
# HUD screen path. No sim access; stepped by advance(ticks) so tests are deterministic
# (the T-024/T-086 pattern).

const TOTAL_TICKS_DEFAULT := 180
const TAIL_TICKS := 60            # the last 60 ticks carry the linear fade to 0
const MAX_ALPHA := 0.45           # [CONTESTABLE] D-T-032-13 view-side constant
const TINT := Color(0.012, 0.102, 0.106)   # #031A1B family, matches the smoke

signal blur_finished

var _elapsed := -1.0              # ticks since trigger; < 0 idle
var _total := TOTAL_TICKS_DEFAULT


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Strength at `elapsed_ticks` after the trigger (binding): 1.0 through the first
## 120 ticks, then linear 1 -> 0 over the last 60; 0.0 at/after TOTAL_TICKS.
static func strength_for(elapsed_ticks: float, total_ticks: float = float(TOTAL_TICKS_DEFAULT)) -> float:
	if elapsed_ticks < 0.0:
		return 0.0
	var tail_start := maxf(total_ticks - float(TAIL_TICKS), 0.0)
	if elapsed_ticks < tail_start:
		return 1.0
	if elapsed_ticks >= total_ticks:
		return 0.0
	return 1.0 - (elapsed_ticks - tail_start) / float(TAIL_TICKS)


## Begin the blur. ticks defaults to the binding 180; the engine caller passes the
## ticks carried by the sim's screen_blur event.
func trigger(ticks: int = TOTAL_TICKS_DEFAULT) -> void:
	_total = maxf(float(ticks), 1.0)
	_elapsed = 0.0
	visible = true
	queue_redraw()


func advance(ticks: float) -> void:
	if _elapsed < 0.0:
		return
	_elapsed += maxf(ticks, 0.0)
	if _elapsed >= _total:
		_elapsed = -1.0
		visible = false
		blur_finished.emit()
	queue_redraw()


func _process(delta: float) -> void:
	advance(delta * 60.0)


func active() -> bool:
	return _elapsed >= 0.0


func strength() -> float:
	return strength_for(_elapsed, _total) if _elapsed >= 0.0 else 0.0


func _draw() -> void:
	if _elapsed < 0.0:
		return
	var a := MAX_ALPHA * strength()
	draw_rect(Rect2(Vector2.ZERO, size), Color(TINT.r, TINT.g, TINT.b, a))
	# a heavier band at the edges so the wash reads as a lens, not a fade to black
	var edge := 0.10 * size.y
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, edge)), Color(TINT.r, TINT.g, TINT.b, a * 0.8))
	draw_rect(Rect2(Vector2(0.0, size.y - edge), Vector2(size.x, edge)), Color(TINT.r, TINT.g, TINT.b, a * 0.8))
