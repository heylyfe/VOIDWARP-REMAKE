extends Node3D
#
# coil view (ticket W11-D; DESIGN.md section 5.2; the T-083 anim block in
# sprites.json). View layer only: reads sim EVENTS (the enemy_spawn / coil_ring
# telegraph ticks) and the sim ROW, never writes sim state; every effect is
# driven by the sim tick counter the caller passes to step(), never by a wall
# clock.
#
# The T-083 anim block (sprites.json -> anim) is the frame source of truth:
#   spawn         cycle_02 held, 30 ticks, common_fade: alpha 0 -> 1, scale 0.8 -> 1.0
#   idle          cycle_01 <-> cycle_02 every 30 ticks (180-tick cycle, loops)
#   telegraph     the pre-jump crouch: cycle_02 (ticks 0-11) -> cycle_01 (12-23) ->
#                 cycle_00 (24-35); 36 ticks (0.6 s); the squat deepens as the cue runs
#   attack_flight extend: cycle_03 (ticks 0-20) -> cycle_04 (21-144, the apex) ->
#                 cycle_03 (145-164); 165 ticks (2.75 s)
#   attack_landing cycle_00, shown through the landing tick (reached via recover)
#   recover       cycle_00 (ticks 0-11) -> cycle_01 (12-23); 24 ticks
#
# The compress/extend spring: the cycle animation's own per-frame world_height
# ([1.0, 1.214, 1.429, 1.714, 2.0]) is applied to the billboard as the frame
# advances, so the body squats 1.43 -> 1.21 -> 1.0 over the cue and extends to
# 2.0 at the apex. Nothing here re-derives a timing or a height the data carries.
#
# The landing ring and the shockwave belong to view/vfx/coil_telegraph.gd and are
# NOT drawn here. This file carries the body only: the sprite, the spawn fade and
# the spring.
#
# The red_ring effect in the telegraph row lives in coil_telegraph.gd; the view
# honors the frame half of the cue (cycle_02/01/00) and leaves the ring to the
# VFX file that owns it.

const BillboardScript := preload("res://view/billboard.gd")

const TICKS_PER_SECOND := 60.0

const STATE_SPAWN := "spawn"
const STATE_IDLE := "idle"
const STATE_TELEGRAPH := "telegraph"
const STATE_FLIGHT := "attack_flight"
const STATE_RECOVER := "recover"

## live map from the sim row's own state word (content/enemy_coil behavior row)
## onto the anim block's state ids. Unknown words read as idle.
const ROW_MAP := {"spawn": STATE_SPAWN, "idle": STATE_IDLE, "cue": STATE_TELEGRAPH,
		"flight": STATE_FLIGHT, "recover": STATE_RECOVER}

var billboard: Sprite3D = null
var anim: Dictionary = {}
var world_height := 2.0                    # the sheet's top row (extended)
var frame_heights: Dictionary = {}         # cycle frame index -> body u

var _state_defs: Dictionary = {}           # state id -> parsed block row
var _spawn_left := 0
var _spawn_total := 30
var _telegraph_total := 36
var _flight_total := 165
var _recover_total := 24

var _state := STATE_IDLE
var _state_t := 0                          # ticks spent in the current state
var _idle_t := 0                           # idle accumulator (row feed leaves it be)
var _shown_state := ""
var _shown_frame := -1
var _base_scale := Vector3.ONE


## Parses sprites.json, builds the billboarded PNG sprite (body = the per-frame world
## height, feet on the origin, BILLBOARDING + TRANSPARENCY rules live in billboard.gd)
## and caches the anim-block timings + the cycle animation's per-frame world heights.
## folder_dir is the enemy folder's res:// path.
func setup(folder_dir: String = "res://content/enemies/coil") -> void:
	var text := FileAccess.get_file_as_string(folder_dir.path_join("sprites.json"))
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		push_warning("coil_view: sprites.json unreadable at %s" % folder_dir)
		doc = {}
	anim = (doc as Dictionary).get("anim", {})
	var wh: Variant = (doc as Dictionary).get("world_height", 2.0)
	world_height = float(wh) if (wh is float or wh is int) else 2.0
	_read_cycle_heights(doc as Dictionary)
	_read_states()
	_spawn_total = _total_for(STATE_SPAWN, 30)
	_telegraph_total = _total_for(STATE_TELEGRAPH, 36)
	_flight_total = _total_for(STATE_FLIGHT, 165)
	_recover_total = _total_for(STATE_RECOVER, 24)
	billboard = BillboardScript.new()
	add_child(billboard)
	billboard.setup_from_sheet(doc as Dictionary, folder_dir)
	billboard.world_height = world_height
	_enter_state(STATE_IDLE, 0)


## The cycle animation's per-frame world_height rows, keyed by cycle frame index
## (frame i renders at its own u; the body_rect rules in billboard.gd do the rest).
func _read_cycle_heights(doc: Dictionary) -> void:
	frame_heights.clear()
	for a in doc.get("animations", []):
		if str(a.get("name", "")) != "cycle":
			continue
		var fs: Array = a.get("frames", [])
		var hs: Array = a.get("world_height", [])
		for i in fs.size():
			var cyc := _cycle_index_of(str(fs[i]))
			if cyc >= 0:
				frame_heights[cyc] = float(hs[i]) if i < hs.size() else world_height


## Parses the anim block's states into _state_defs. tick_ranges wins where the block
## carries them (telegraph / attack_flight); ticks_per_frame synthesizes them otherwise
## (idle / recover); spawn is a single held frame.
func _read_states() -> void:
	_state_defs.clear()
	var states: Dictionary = anim.get("states", {})
	for id in states.keys():
		var st: Dictionary = states[id]
		var def := {}
		var total: Variant = st.get("total_ticks")
		def["total"] = int(total) if (total is float or total is int) else -1
		def["loop"] = bool(st.get("loop", false))
		var tpf: Variant = st.get("ticks_per_frame")
		def["tpf"] = float(tpf) if (tpf is float or tpf is int) else 0.0
		var cyc_of: Array = []
		for f in st.get("frames", []):
			cyc_of.append(_cycle_index_of(str(f)))
		def["cycle_of_frame"] = cyc_of
		var ranges: Array = []
		var tr: Variant = st.get("tick_ranges")
		if tr is Array:
			for r in tr:
				if r is Array and (r as Array).size() >= 3:
					ranges.append([_cycle_index_of(str(r[0])), int(r[1]), int(r[2])])
		def["ranges"] = ranges
		_state_defs[str(id)] = def


## "sprites/cycle_02.png" (or the tick_ranges' "coil_02") -> 2; -1 when no match.
func _cycle_index_of(name: String) -> int:
	var at := name.find("cycle_")
	if at >= 0:
		var s := name.substr(at + 6, 2)
		return int(s) if s.is_valid_int() else -1
	at = name.find("coil_")
	if at >= 0:
		var s2 := name.substr(at + 5, 2)
		return int(s2) if s2.is_valid_int() else -1
	return -1


func _total_for(state: String, fallback: int) -> int:
	var def: Dictionary = _state_defs.get(state, {})
	var t := int(def.get("total", -1))
	return t if t > 0 else fallback


## Frame index inside the state's frames array for tick t. tick_ranges is authoritative
## where the block carries them; looping states wrap on the total; one-frame states hold.
func _frame_index_for(state: String, t: int) -> int:
	var def: Dictionary = _state_defs.get(state, {})
	if def.is_empty():
		return 0
	var cyc_of: Array = def.get("cycle_of_frame", [])
	if cyc_of.is_empty():
		return 0
	var tt := t
	var total := int(def.get("total", -1))
	var looping := bool(def.get("loop", false))
	var ranges: Array = def.get("ranges", [])
	if not ranges.is_empty():
		if looping and total > 0:
			tt = tt % total
		var pick := -1
		var want_cyc := -1
		var want_ord := 0
		var seen := {}
		for r in ranges:
			var rc := int(r[0])
			if tt >= int(r[1]) and tt <= int(r[2]):
				want_cyc = rc
				want_ord = int(seen.get(rc, 0))
				pick = 1
				break
			seen[rc] = int(seen.get(rc, 0)) + 1
		if pick < 0:   # t past the last range: hold the block's last row
			var last = ranges[ranges.size() - 1]
			want_cyc = int(last[0])
			seen = {}
			for r in ranges:
				var rc2 := int(r[0])
				if rc2 == want_cyc:
					if r == last:
						want_ord = int(seen.get(rc2, 0))
						break
					seen[rc2] = int(seen.get(rc2, 0)) + 1
		var occ := 0
		for i in cyc_of.size():
			if int(cyc_of[i]) == want_cyc:
				if occ == want_ord:
					return i
				occ += 1
		return 0
	var tpf := float(def.get("tpf", 0.0))
	if tpf <= 0.0:
		return 0
	var idx := int(float(tt) / tpf)
	if looping:
		idx = idx % cyc_of.size()
	else:
		idx = mini(idx, cyc_of.size() - 1)
	return idx


## Shows one frame of one state, with the billboard re-scaled so the body is that frame's
## own cycle world_height tall (the compress/extend spring). _apply_frame re-derives scale
## + feet from the frame's body_rect; the spawn fade is applied on top by the anim step.
func _show(state: String, idx: int) -> void:
	if billboard == null:
		return
	var def: Dictionary = _state_defs.get(state, {})
	var cyc_of: Array = def.get("cycle_of_frame", [])
	var cyc := int(cyc_of[idx]) if idx >= 0 and idx < cyc_of.size() else -1
	billboard.world_height = float(frame_heights.get(cyc, world_height))
	if billboard.anim_name != state:
		billboard.set_animation(state)
	billboard.frame_i = idx
	billboard._apply_frame(idx)
	_base_scale = billboard.scale
	_shown_state = state
	_shown_frame = idx


## Enters a state at elapsed tick t (clamped to the state's length) and shows its frame.
func _enter_state(state: String, t: int) -> void:
	_state = state
	_state_t = maxi(t, 0)
	if state == STATE_IDLE:
		_idle_t = _state_t
	var idx := _frame_index_for(state, _state_t)
	_show(state, idx)


## The spawn fade (common_fade effect params): alpha 0 -> 1, scale 0.8 -> 1.0 over the
## spawn total. Applied without decrementing; step() owns the countdown.
func _apply_fade(scale_mul: float, fade: float) -> void:
	if billboard == null:
		return
	billboard.modulate = Color(1.0, 1.0, 1.0, fade)
	billboard.scale = _base_scale * scale_mul


func _fade_now() -> void:
	var fade := 1.0
	var scale_mul := 1.0
	if _spawn_left > 0:
		var done := 1.0 - float(_spawn_left) / float(maxi(_spawn_total, 1))
		fade = done
		scale_mul = 0.8 + 0.2 * done
	_apply_fade(scale_mul, fade)


## The spawn fade restarts (the sim's enemy_spawn event for this enemy).
func on_spawn() -> void:
	_spawn_left = _spawn_total
	_enter_state(STATE_SPAWN, 0)
	_apply_fade(0.8, 0.0)


## A sim telegraph event for this enemy. "coil_ring": enter the 36-tick pre-jump crouch
## (the frames; the red landing ring is coil_telegraph.gd's, not drawn here). ticks > 0
## overrides the anim block's cue length. Any other kind is ignored.
func on_telegraph(kind: String, ticks: int = -1) -> void:
	if kind != "coil_ring":
		return
	if ticks > 0:
		_telegraph_total = ticks
	_enter_state(STATE_TELEGRAPH, 0)


## One sim tick of view state: the state machine, the tick_ranges' frame choice, the spawn
## fade. dt_ticks is the sim tick count (1 at 60 Hz) - the caller drives this from the sim,
## never from _process. With step() not called, nothing advances.
func step(dt_ticks: int = 1) -> void:
	if billboard == null:
		return
	var step_ticks := maxi(dt_ticks, 0)
	if step_ticks == 0:
		_fade_now()
		return
	_state_t += step_ticks
	match _state:
		STATE_SPAWN:
			if _state_t >= _spawn_total:
				_enter_state(STATE_IDLE, 0)
		STATE_TELEGRAPH:
			if _state_t >= _telegraph_total:
				_enter_state(STATE_FLIGHT, 0)
		STATE_FLIGHT:
			if _state_t >= _flight_total:
				_enter_state(STATE_RECOVER, 0)
		STATE_RECOVER:
			if _state_t >= _recover_total:
				_enter_state(STATE_IDLE, _idle_t)
		STATE_IDLE:
			_idle_t = _state_t
	var idx := _frame_index_for(_state, _state_t)
	if idx != _shown_frame or _shown_state != _state:
		_show(_state, idx)
	if _spawn_left > 0:
		_spawn_left = maxi(_spawn_left - step_ticks, 0)
	_fade_now()


## The per-row feed the sim's live coil row drives (the compress/extend spring included):
## state ("spawn"/"idle"/"cue"/"flight"/"recover"), seg_left (ticks left in the current
## segment) and flight_i (ticks into the arc). The row maps onto the anim block's tick
## ranges, so a row fed once per sim tick lands each frame on the exact tick the block
## names. Read-only; the row is never written.
func update_from_row(row: Dictionary) -> void:
	if billboard == null:
		return
	var s := str(row.get("state", "idle"))
	var mapped: String = str(ROW_MAP.get(s, STATE_IDLE))
	if mapped == STATE_IDLE:
		if _state != STATE_IDLE:
			_enter_state(STATE_IDLE, _idle_t)
		_fade_now()
		return
	var t := 0
	if mapped == STATE_FLIGHT:
		var fi: Variant = row.get("flight_i", _state_t if _state == STATE_FLIGHT else 0)
		t = int(fi) if (fi is float or fi is int) else 0
	else:
		var total := _total_for(mapped, _spawn_total if mapped == STATE_SPAWN else (_telegraph_total if mapped == STATE_TELEGRAPH else _recover_total))
		var seg: Variant = row.get("seg_left", total)
		t = maxi(total - int(seg if (seg is float or seg is int) else total), 0)
	if mapped == _state and _state_t == t:
		_fade_now()
		return
	_enter_state(mapped, t)
	if mapped == STATE_SPAWN:
		_spawn_left = maxi(_spawn_total - _state_t, 0)
	_fade_now()


## The anim block the view was set up with (tests assert the block, not a re-derived
## copy, drives the frames).
func anim_block() -> Dictionary:
	return anim
