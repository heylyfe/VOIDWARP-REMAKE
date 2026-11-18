extends Control
#
# Loading screen (ticket T-024, rewritten by TICKET LOADING; DESIGN.md section 14 [CANON], the owner
# spec, and the owner's FINAL ruling for this ticket):
#
#   THE TWO-DURATION LAW (D-LOAD-5, owner ruling, FINAL): the session's FIRST launch shows the screen
#   for FIRST_LAUNCH_SECONDS = 5.0 s (it doubles as onboarding); EVERY RESTART shows it for exactly
#   RESTART_SECONDS = 2.0 s - never less, never longer. The hold is a pure function of one explicit flag:
#   hold_seconds_for(first_launch). It never reads wall time or a global, so the headless test proves
#   both branches. A load that finishes faster than the hold completes AT the hold (and shown_time()
#   is exactly the hold - the last step is clamped, so a coarse frame cannot overshoot it); a slower
#   load completes at its own duration, on the real fraction, because the level must exist before the
#   screen can go. The hold never blocks a load past what the law allows.
#
# Timing model (D-T024-1, D-T024-2, unchanged): everything is driven by the injected `advance(delta)`
# step, never by _process wall time, so the headless tests step it deterministically.
# `set_load_progress(p)` wires the real loader; the first call switches the fraction source off the
# simulated estimate for good - the bar is the REAL load, never a fake one.
#
# Tips (D-T024-3): data-driven from data/tips.json (30 tips, 15 hazard_tell). The draw pool expands each
# hazard_tell tip x3; the rotation is a seeded shuffle of that pool, cycled and reshuffled per cycle;
# the visible tip changes exactly at multiples of 5.0 s of elapsed display time.
#
# The scene (D-LOAD-1..4): a flat 2D stage (app/loading_stage.gd) where one enemy sprite acts out a
# short gag (app/loading_gags.gd) while the level builds; the gag is picked per load from the seed and
# is never the previous load's. The maths lives in pure functions; _ready() only builds view nodes.

const LoadingGagsScript := preload("res://app/loading_gags.gd")
const LoadingStageScript := preload("res://app/loading_stage.gd")

## The first launch of a session: the loading screen is also the onboarding (D-LOAD-5).
const FIRST_LAUNCH_SECONDS := 5.0
## Every restart: exactly this long, never less, never longer (D-LOAD-5).
const RESTART_SECONDS := 2.0
## T-024's name for the 5.0 s hold; the first-launch hold. Kept so existing readers keep working.
const MIN_DISPLAY_SECONDS := FIRST_LAUNCH_SECONDS
const TIP_ROTATION_SECONDS := 5.0
const HAZARD_TELL_WEIGHT := 3
const TIPS_PATH := "res://data/tips.json"
const PROGRESS_EPSILON := 0.000001
## Float slack on "the hold is reached" so 40 accumulated 0.05 steps count as 2.0 s.
const HOLD_EPSILON := 0.000000001

## The gag shown by the previous load in this process (so consecutive loads differ). Display only;
## nothing in the timing law reads it.
static var _last_gag_id: String = ""

var elapsed: float = 0.0

var _first_launch: bool = true
var _hold: float = FIRST_LAUNCH_SECONDS
var _gag_id: String = ""
var _tips: Array[Dictionary] = []
var _pool: Array[int] = []              # weighted tip indices (hazard_tell x3)
var _order: Array[int] = []             # current shuffled cycle of the pool
var _order_pos: int = 0
var _rng := RandomNumberGenerator.new()
var _simulated_duration: float = -1.0
var _real_progress: float = -1.0        # < 0 = no report from the loader yet
var _finished_emitted: bool = false
var _skip_creation_frame: bool = false  # drop the delta of the frame the screen entered the tree

var _stage: Control
var _bar: ProgressBar
var _tip_label: Label
var _status_label: Label

signal loading_finished


## THE LAW (D-LOAD-5): how long the screen is held, as a pure function of the explicit flag.
static func hold_seconds_for(first_launch: bool) -> float:
	return FIRST_LAUNCH_SECONDS if first_launch else RESTART_SECONDS


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


## Start a load. `seed_value` seeds the tip rotation and the gag pick; `simulated_load_seconds >= 0`
## enables the simulated fraction source (tests, and a floor while the real loader is silent; 0.0 is an
## instant load). `p_first_launch` is the explicit flag of the two-duration law: true = the session's
## first launch (5.0 s), false = a restart (exactly 2.0 s). It defaults to true, T-024's behaviour.
func start(seed_value: int, simulated_load_seconds: float = -1.0, p_first_launch: bool = true) -> void:
	elapsed = 0.0
	_simulated_duration = simulated_load_seconds
	_real_progress = -1.0
	_finished_emitted = false
	_order_pos = 0
	_first_launch = p_first_launch
	_hold = hold_seconds_for(p_first_launch)
	_tips = load_tips()
	_pool = build_weighted_pool(_tips)
	_rng.seed = seed_value
	_order = []
	_reshuffle_order()
	_gag_id = LoadingGagsScript.pick_gag(seed_value, _last_gag_id)
	_last_gag_id = _gag_id
	_update_view()


## Switch the law's flag on a running screen (re-derives the hold; elapsed is kept).
func set_first_launch(p_first_launch: bool) -> void:
	_first_launch = p_first_launch
	_hold = hold_seconds_for(p_first_launch)


func is_first_launch() -> bool:
	return _first_launch


## The hold this screen is bound to: 5.0 (first launch) or 2.0 (restart).
func hold_seconds() -> float:
	return _hold


## The gag the stage is playing ("" before start()).
func gag_id() -> String:
	return _gag_id


## Report the real fraction from the loader (0..1). The first call switches the fraction source
## off the simulated estimate; later calls just update the reported fraction.
func set_load_progress(p: float) -> void:
	_real_progress = clampf(p, 0.0, 1.0)


## Advance the model. Returns true once the screen has held long enough AND load is complete.
## When the hold is the only thing left to wait for, the step that reaches it is clamped to land on the
## hold exactly (never overshoots it), so a fast load is shown for exactly the hold.
func advance(delta: float) -> bool:
	var before := elapsed
	elapsed += maxf(delta, 0.0)
	if before < _hold - HOLD_EPSILON and elapsed >= _hold - HOLD_EPSILON and _load_done_at(_hold):
		elapsed = _hold
	_update_view()
	return is_complete()


## Is the load complete by display time t? (the real report, else the simulated estimate)
func _load_done_at(t: float) -> bool:
	if _real_progress >= 0.0:
		return _real_progress >= 1.0 - PROGRESS_EPSILON
	if _simulated_duration >= 0.0:
		return _simulated_duration <= t + HOLD_EPSILON
	return false


## The fraction the bar shows: the loader's real report if any, else the simulated estimate.
func load_fraction() -> float:
	if _real_progress >= 0.0:
		return _real_progress
	if _simulated_duration > 0.0:
		return clampf(elapsed / _simulated_duration, 0.0, 1.0)
	if _simulated_duration == 0.0:
		return 1.0
	return 0.0


## Done predicate (D-T024-1, D-LOAD-5): held >= the hold and the load is complete.
func is_complete() -> bool:
	return elapsed >= _hold - HOLD_EPSILON and load_fraction() >= 1.0 - PROGRESS_EPSILON


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


## Build the view: the gag stage, the wordmark, the real progress bar and the rotating tip.
func _ready() -> void:
	if _tips.is_empty():
		start(0)
	# The app adds the screen mid-frame, so the _process call that arrives in this frame counts
	# time that passed before the screen existed (a real first launch measured 4.859 s for a
	# 5.0 s hold, AUDIT.md). Skip exactly that one call; from the next frame the screen self-drives.
	_skip_creation_frame = true
	_build_view()
	_update_view()


func _process(delta: float) -> void:
	if _skip_creation_frame:
		_skip_creation_frame = false
		return
	advance(delta)


func _build_view() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage = LoadingStageScript.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 22.0
	add_child(top)
	var title := Label.new()
	title.text = "VOIDWRAP RUN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.97, 0.97, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.08))
	title.add_theme_constant_override("outline_size", 12)
	top.add_child(title)
	var sub := Label.new()
	sub.text = "the world is serious. the enemies are not."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.486, 1.0, 0.957))
	top.add_child(sub)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -190.0
	bottom.offset_bottom = -24.0
	bottom.alignment = BoxContainer.ALIGNMENT_END
	add_child(bottom)
	var tip_header := Label.new()
	tip_header.text = "FIELD NOTE"
	tip_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_header.add_theme_font_size_override("font_size", 13)
	tip_header.add_theme_color_override("font_color", Color(1.0, 0.31, 0.847))
	bottom.add_child(tip_header)
	_tip_label = Label.new()
	_tip_label.custom_minimum_size = Vector2(820, 0)
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tip_label.add_theme_font_size_override("font_size", 20)
	_tip_label.add_theme_color_override("font_color", Color(0.93, 0.93, 1.0))
	bottom.add_child(_tip_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	bottom.add_child(gap)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(560, 22)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.03, 0.03, 0.09)
	bar_bg.set_border_width_all(3)
	bar_bg.border_color = Color(0.486, 1.0, 0.957)
	bar_bg.set_corner_radius_all(11)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(1.0, 0.31, 0.847)
	bar_fill.set_corner_radius_all(11)
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar.add_theme_stylebox_override("fill", bar_fill)
	bottom.add_child(_bar)
	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.9))
	bottom.add_child(_status_label)


## The status line: honest percentage, in the screen's register. First launch is setting up; a
## restart is "again".
func status_text() -> String:
	var pct := int(round(load_fraction() * 100.0))
	if _first_launch:
		return "setting up the void... %d%%" % pct
	return "rebuilding the void, again... %d%%" % pct


## Push model state into the view nodes (safe before _ready / headless).
func _update_view() -> void:
	if _stage != null:
		_stage.set_gag(_gag_id)
		_stage.set_time(elapsed)
	if _bar != null:
		_bar.value = load_fraction() * 100.0
	if _status_label != null:
		_status_label.text = status_text()
	if _tip_label != null:
		var tip := current_tip()
		_tip_label.text = str(tip.get("text", ""))
	if is_complete() and not _finished_emitted:
		_finished_emitted = true
		loading_finished.emit()
