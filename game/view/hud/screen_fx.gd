extends Control
#
# Screen-wide stepped effects (ticket T-086; research/fable-tickets.md section 2.4):
#   void flash  - the screen edge flashes the void colour once per spend (binding)
#   white bloom - Last Light trigger, 12 ticks (binding)
#   black out   - death attribution, linear fade over 18 ticks (binding), then the
#                 caller shows the run-over screen on blackout_finished (the death
#                 wiring is the app layer's job, like T-025's run_over - D-T086-7)
#
# Everything is stepped by the injected advance(ticks); _process feeds
# delta * TICKS_PER_SECOND. advance() takes TICKS, not seconds - the spec table's
# durations are tick counts (D-T086-1). Nothing here sleeps real time, so headless
# tests step deterministically (T-024 pattern).
#
# The overlay draws the full rect but only what it must: the flash is a 48 px edge
# band (centre stays clear), the bloom and the black-out are full-screen rects.
# Void colour: D-T025-1's swatch - no document states the void-colour hex (D-T086-2/7).
# z-order: hud.gd adds this LAST so the effects draw over every other HUD element.

const TICKS_PER_SECOND := 60.0
const VOID_FLASH_TICKS := 12.0     # [CONTESTABLE] D-T086-2: 12 ticks, 48 px band, peak alpha 0.55
const FLASH_BAND := 48.0
const FLASH_PEAK := 0.55
const BLOOM_TICKS := 12.0          # binding (section 2.4)
const BLOOM_RAMP := 2.0            # [CONTESTABLE] D-T086-6: 2 ticks ramp in, 10 ticks fade out
const BLACKOUT_TICKS := 18.0       # binding (section 2.4)
const VOID_COLOR := Color(0.35, 0.2, 0.5, 1.0)   # D-T025-1's void swatch
const BLACK := Color(0.0, 0.0, 0.0, 1.0)
const WHITE := Color(1.0, 1.0, 1.0, 1.0)

signal blackout_finished
signal bloom_finished

var _flash_t := -1.0      # < 0 idle; else elapsed ticks of the single flash
var _bloom_t := -1.0      # < 0 idle; else elapsed ticks of the bloom
var _blackout_t := -1.0   # < 0 idle; else elapsed ticks (may exceed BLACKOUT_TICKS - holds black)
var _blackout_done_sent := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(true)


## Trigger the one-shot void edge flash (call on the fall tick).
func void_flash() -> void:
	_flash_t = 0.0
	_sync_visible()


## Trigger the full-screen white bloom (call on the Last Light trigger).
func white_bloom() -> void:
	_bloom_t = 0.0
	_sync_visible()


## Begin the 18-tick linear black-out (call on the death event).
func black_out() -> void:
	_blackout_t = 0.0
	_blackout_done_sent = false
	_sync_visible()


## Clear the black-out (call when the run-over screen is up - it is opaque black).
func hide_blackout() -> void:
	_blackout_t = -1.0
	_blackout_done_sent = false
	_sync_visible()


func advance(ticks: float) -> void:
	var dt := maxf(ticks, 0.0)
	if _flash_t >= 0.0:
		_flash_t += dt
		if _flash_t >= VOID_FLASH_TICKS:
			_flash_t = -1.0
	if _bloom_t >= 0.0:
		_bloom_t += dt
		if _bloom_t >= BLOOM_TICKS:
			_bloom_t = -1.0
			bloom_finished.emit()
	if _blackout_t >= 0.0:
		_blackout_t += dt
		if _blackout_t >= BLACKOUT_TICKS and not _blackout_done_sent:
			_blackout_done_sent = true
			blackout_finished.emit()
	_sync_visible()
	queue_redraw()


func _process(delta: float) -> void:
	advance(delta * TICKS_PER_SECOND)


func flash_active() -> bool:
	return _flash_t >= 0.0


func flash_alpha() -> float:
	if _flash_t < 0.0:
		return 0.0
	return FLASH_PEAK * (1.0 - clampf(_flash_t / VOID_FLASH_TICKS, 0.0, 1.0))


func bloom_active() -> bool:
	return _bloom_t >= 0.0


func bloom_alpha() -> float:
	if _bloom_t < 0.0:
		return 0.0
	if _bloom_t < BLOOM_RAMP:
		return _bloom_t / BLOOM_RAMP
	return 1.0 - (_bloom_t - BLOOM_RAMP) / (BLOOM_TICKS - BLOOM_RAMP)


func blackout_active() -> bool:
	return _blackout_t >= 0.0


func blackout_alpha() -> float:
	if _blackout_t < 0.0:
		return 0.0
	return clampf(_blackout_t / BLACKOUT_TICKS, 0.0, 1.0)


func _sync_visible() -> void:
	visible = _flash_t >= 0.0 or _bloom_t >= 0.0 or _blackout_t >= 0.0


func _draw() -> void:
	var s := size
	if _flash_t >= 0.0:
		var a := flash_alpha()
		var c := Color(VOID_COLOR.r, VOID_COLOR.g, VOID_COLOR.b, a)
		draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, FLASH_BAND)), c)                       # top
		draw_rect(Rect2(Vector2(0.0, s.y - FLASH_BAND), Vector2(s.x, FLASH_BAND)), c)     # bottom
		draw_rect(Rect2(Vector2.ZERO, Vector2(FLASH_BAND, s.y)), c)                       # left
		draw_rect(Rect2(Vector2(s.x - FLASH_BAND, 0.0), Vector2(FLASH_BAND, s.y)), c)     # right
	if _bloom_t >= 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(WHITE.r, WHITE.g, WHITE.b, bloom_alpha()))
	if _blackout_t >= 0.0:
		draw_rect(Rect2(Vector2.ZERO, s), Color(BLACK.r, BLACK.g, BLACK.b, blackout_alpha()))
