extends Control
#
# Loading screen (ticket T-024; DESIGN.md section 2 [CANON] row "loading screen on initial load and
# on run start | >= 5.0 s shown", section 14 [CANON], and the owner spec: "Loading screen: shown on
# initial load and run start; ~5s minimum display (holds at 5s if load is faster, shows real
# progress if slower); doubles as onboarding via a rotating, data-driven tip pool (15+ tips,
# prioritizing gift-vs-hazard tells)."
#
# Timing model (D-T024-1, D-T024-2): everything is driven by the injected `advance(delta)` step,
# never by _process wall time, so the headless tests step it deterministically. A load that
# finishes faster than MIN_DISPLAY_SECONDS completes on the first step at/after 5.0 s (a 1.0 s
# load completes at exactly 5.0 s); a slower load completes at its own duration with the real
# fraction on the bar. `set_load_progress(p)` wires the real loader; the first call switches the
# fraction source off the simulated estimate for good.
#
# Tips (D-T024-3): data-driven from data/tips.json (18 tips, 11 hazard_tell, T-014c — unchanged).
# The draw pool expands each hazard_tell tip x3; the rotation is a seeded shuffle of that pool,
# cycled and reshuffled per cycle; the visible tip changes exactly at multiples of 5.0 s of
# elapsed display time (tip_step = floor(elapsed / 5.0)).
#
# The math lives in pure functions (headless tests exercise them directly); _ready() only builds
# the view nodes the scene shows.

const MIN_DISPLAY_SECONDS := 5.0
const TIP_ROTATION_SECONDS := 5.0
const HAZARD_TELL_WEIGHT := 3
const TIPS_PATH := "res://data/tips.json"
const PROGRESS_EPSILON := 0.000001

var elapsed: float = 0.0

var _tips: Array[Dictionary] = []
var _pool: Array[int] = []              # weighted tip indices (hazard_tell x3)
var _order: Array[int] = []             # current shuffled cycle of the pool
var _order_pos: int = 0
var _rng := RandomNumberGenerator.new()
var _simulated_duration: float = -1.0
var _real_progress: float = -1.0        # < 0 = no report from the loader yet
var _finished_emitted: bool = false

var _bar: ProgressBar
var _tip_label: Label
var _status_label: Label

signal loading_finished


## Parse data/tips.json. Returns [] on any parse/shape failure (caller decides).
func load_tips(path: String = TIPS_PATH) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var raw: Variant = (parsed as Dictionary).get("tips", [])
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		if not d.has("id") or not d.has("text") or not d.has("tags"):
			continue
		out.append(d)
	return out


## Weighted draw pool: each hazard_tell tip appears HAZARD_TELL_WEIGHT times, others once.
static func build_weighted_pool(tips: Array[Dictionary]) -> Array[int]:
	var pool: Array[int] = []
	for i in tips.size():
		var tags: Variant = tips[i].get("tags", [])
		var weight := 1
		if tags is Array and (tags as Array).has("hazard_tell"):
			weight = HAZARD_TELL_WEIGHT
		for _w in weight:
			pool.append(i)
	return pool


## Rotation step for a given elapsed display time (D-T024-5): floor(t / 5.0).
static func tip_step_for(t: float) -> int:
	if t < 0.0:
		return 0
	return int(floor(t / TIP_ROTATION_SECONDS))




## (Re)shuffle the cycle order from the weighted pool. Deterministic per rng stream.
func _reshuffle_order() -> void:
	_order = _pool.duplicate()
	for i in range(_order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _order[i]
		_order[i] = _order[j]
		_order[j] = tmp


## Tip index into _tips for rotation step k; extends the cycle as needed.
func _tip_index_for_step(k: int) -> int:
	if _pool.is_empty():
		return -1
	while _order_pos <= k:
		if _order_pos == 0 and _order.is_empty():
			_reshuffle_order()
		elif _order_pos > 0 and _order_pos % _order.size() == 0:
			_reshuffle_order()
		_order_pos += 1
	return _order[k % _order.size()]


## Start a load. `seed_value` seeds the tip rotation; `simulated_load_seconds >= 0` enables the
## simulated fraction source (used by tests and as a floor while the real loader is silent).
func start(seed_value: int, simulated_load_seconds: float = -1.0) -> void:
	elapsed = 0.0
	_simulated_duration = simulated_load_seconds
	_real_progress = -1.0
	_finished_emitted = false
	_order_pos = 0
	_tips = load_tips()
	_pool = build_weighted_pool(_tips)
	_rng.seed = seed_value
	_order = []
	_reshuffle_order()
	_update_view()


## Report the real fraction from the loader (0..1). The first call switches the fraction source
## off the simulated estimate; later calls just update the reported fraction.
func set_load_progress(p: float) -> void:
	_real_progress = clampf(p, 0.0, 1.0)


## Advance the model. Returns true once the screen has held long enough AND load is complete.
func advance(delta: float) -> bool:
	elapsed += max(delta, 0.0)
	_update_view()
	return is_complete()


## The fraction the bar shows: the loader's real report if any, else the simulated estimate.
func load_fraction() -> float:
	if _real_progress >= 0.0:
		return _real_progress
	if _simulated_duration > 0.0:
		return clampf(elapsed / _simulated_duration, 0.0, 1.0)
	return 0.0


## Done predicate (D-T024-1): held >= MIN_DISPLAY_SECONDS and the load is complete.
func is_complete() -> bool:
	return elapsed >= MIN_DISPLAY_SECONDS and load_fraction() >= 1.0 - PROGRESS_EPSILON


## Display time held so far.
func shown_time() -> float:
	return elapsed


## Current rotation step (floor(elapsed / 5.0)).
func tip_step() -> int:
	return tip_step_for(elapsed)


## The tip shown right now, or {} when the pool is empty/unreadable.
func current_tip() -> Dictionary:
	if _tips.is_empty():
		return {}
	var idx := _tip_index_for_step(tip_step())
	if idx < 0 or idx >= _tips.size():
		return {}
	return _tips[idx]



## Build the view: black void, VOIDWRAP RUN wordmark, progress bar, rotating tip.
func _ready() -> void:
	if _tips.is_empty():
		start(0)
	_build_view()
	_update_view()


func _process(delta: float) -> void:
	advance(delta)


func _build_view() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)
	var title := Label.new()
	title.text = "VOIDWRAP RUN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	vbox.add_child(title)
	var sub := Label.new()
	sub.text = "the world is serious. the enemies are not."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 48)
	vbox.add_child(spacer)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(520, 24)
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	vbox.add_child(_bar)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(_status_label)
	var tip_spacer := Control.new()
	tip_spacer.custom_minimum_size = Vector2(0, 64)
	vbox.add_child(tip_spacer)
	var tip_header := Label.new()
	tip_header.text = "FIELD NOTE"
	tip_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_header.add_theme_font_size_override("font_size", 13)
	tip_header.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
	vbox.add_child(tip_header)
	_tip_label = Label.new()
	_tip_label.custom_minimum_size = Vector2(760, 0)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.add_theme_font_size_override("font_size", 20)
	_tip_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(_tip_label)


## Push model state into the view nodes (safe before _ready / headless).
func _update_view() -> void:
	if _bar != null:
		_bar.value = load_fraction() * 100.0
	if _status_label != null:
		_status_label.text = "loading... %d%%" % int(round(load_fraction() * 100.0))
	if _tip_label != null:
		var tip := current_tip()
		_tip_label.text = str(tip.get("text", ""))
	if is_complete() and not _finished_emitted:
		_finished_emitted = true
		loading_finished.emit()

