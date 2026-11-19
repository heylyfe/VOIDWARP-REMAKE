extends RefCounted
#
# W11-D - the coil body view (game/view/coil_view.gd): the last enemy off the generic
# billboard. Drives the view the way the world will: setup from the REAL sprites.json,
# on_spawn, a real coil_ring telegraph, N steps, and the per-row feed - and asserts the
# observable state changed: frame index advanced per the anim block's tick_ranges, the
# compress/extend spring (the cycle animation's per-frame world_height) moved the
# billboard, and the anim state followed the row.
#
# NEGATIVE CONTROL: with step() never called, no frame may advance. Failures in that
# leg are prefixed "negative control:" so the count is read straight off the output.
#
# The landing ring / shockwave are coil_telegraph.gd's job; this view must create no
# mesh surface at all - asserted, so a future edit cannot quietly duplicate the ring.

const CoilViewScript := preload("res://view/coil_view.gd")

const FOLDER := "res://content/enemies/coil"

func run() -> Array[String]:
	var f: Array[String] = []
	_leg_block_source(f)
	_leg_spawn_fade(f)
	_leg_telegraph_then_flight(f)
	_leg_row_feed(f)
	_leg_no_meshes(f)
	_leg_negative_control(f)
	return f


func _new_view() -> Node3D:
	var v: Node3D = CoilViewScript.new()
	v.setup(FOLDER)
	return v


func _check(f: Array[String], cond: bool, msg: String) -> void:
	if not cond:
		f.append(msg)


func _expect_height(f: Array[String], view, cycle_index: int, want: float) -> void:
	var got := float(view.frame_heights.get(cycle_index, -1.0))
	_check(f, absf(got - want) < 0.001,
			"frame_heights[%d] = %.3f, want %.3f" % [cycle_index, got, want])


func _leg_block_source(f: Array[String]) -> void:
	var view: Node3D = _new_view()
	var block: Dictionary = view.anim_block()
	_check(f, not block.is_empty(), "anim block unread - nothing drives the frames")
	var states: Dictionary = block.get("states", {})
	for key in ["spawn", "idle", "telegraph", "attack_flight", "attack_landing", "recover"]:
		if not states.has(key):
			f.append("anim block is missing state %s" % key)
	var tele: Dictionary = states.get("telegraph", {})
	_check(f, int(tele.get("total_ticks", -1)) == 36,
			"telegraph total_ticks %d, want 36" % int(tele.get("total_ticks", -1)))
	var ranges: Variant = tele.get("tick_ranges", [])
	_check(f, ranges is Array and (ranges as Array).size() == 3,
			"telegraph tick_ranges not the block's 3 rows")
	var flight: Dictionary = states.get("attack_flight", {})
	_check(f, int(flight.get("total_ticks", -1)) == 165,
			"attack_flight total_ticks %d, want 165" % int(flight.get("total_ticks", -1)))
	# the per-frame heights the spring runs on (the cycle animation's own data)
	_expect_height(f, view, 0, 1.0)
	_expect_height(f, view, 2, 1.429)
	_expect_height(f, view, 4, 2.0)
	# the sheet loads real frames for every block state
	_check(f, view.billboard != null, "setup built no billboard")
	view.free()


func _leg_spawn_fade(f: Array[String]) -> void:
	var view: Node3D = _new_view()
	view.on_spawn()
	_check(f, str(view.billboard.anim_name) == "spawn",
			"on_spawn left the sprite on %s, want spawn" % str(view.billboard.anim_name))
	_check(f, is_equal_approx(view.billboard.modulate.a, 0.0),
			"on_spawn alpha %.3f, want 0.0" % view.billboard.modulate.a)
	view.step(1)
	var want_a := 1.0 / 30.0
	_check(f, absf(view.billboard.modulate.a - want_a) < 0.02,
			"after 1 tick alpha %.3f, want ~%.3f" % [view.billboard.modulate.a, want_a])
	view.step(29)
	_check(f, is_equal_approx(view.billboard.modulate.a, 1.0),
			"after 30 ticks alpha %.3f, want 1.0" % view.billboard.modulate.a)
	_check(f, str(view.billboard.anim_name) == "idle",
			"after the fade the sprite shows %s, want idle" % str(view.billboard.anim_name))
	view.free()


## The real telegraph, stepped tick by tick: the crouch deepens (coil_02 -> coil_01 ->
## coil_00 per the block's tick_ranges), the spring (per-frame world_height) follows,
## then the flight extends to coil_04 at the apex tick and back, and recover closes it.
func _leg_telegraph_then_flight(f: Array[String]) -> void:
	var view: Node3D = _new_view()
	view.on_telegraph("coil_ring", 36)
	_check(f, str(view.billboard.anim_name) == "telegraph",
			"on_telegraph left the sprite on %s, want telegraph" % str(view.billboard.anim_name))
	_check(f, view.billboard.frame_i == 0, "telegraph opened on frame %d, want 0"
			% view.billboard.frame_i)
	_check(f, absf(view.billboard.world_height - 1.429) < 0.001,
			"cue frame 0 height %.3f, want 1.429 (the 1.43u coil_02)" % view.billboard.world_height)
	var h_start: float = view.billboard.world_height
	view.step(12)
	_check(f, view.billboard.frame_i == 1,
			"tick 12 frame %d, want 1 (coil_01 at 12-23)" % view.billboard.frame_i)
	_check(f, absf(view.billboard.world_height - 1.214) < 0.001,
			"tick 12 height %.3f, want 1.214" % view.billboard.world_height)
	view.step(12)
	_check(f, view.billboard.frame_i == 2,
			"tick 24 frame %d, want 2 (coil_00 at 24-35)" % view.billboard.frame_i)
	_check(f, absf(view.billboard.world_height - 1.0) < 0.001,
			"tick 24 height %.3f, want 1.0 (full squash)" % view.billboard.world_height)
	_check(f, view.billboard.world_height < h_start,
			"spring never squatted (start %.3f, end %.3f)" % [h_start, view.billboard.world_height])
	view.step(12)   # t = 36: the cue ends; the flight begins
	_check(f, str(view.billboard.anim_name) == "attack_flight",
			"at cue end the sprite shows %s, want attack_flight" % str(view.billboard.anim_name))
	_check(f, view.billboard.frame_i == 0,
			"flight opened on frame %d, want 0 (coil_03)" % view.billboard.frame_i)
	view.step(21)   # flight t = 21: coil_04 spans 21-144
	_check(f, view.billboard.frame_i == 1,
			"flight tick 21 frame %d, want 1 (coil_04)" % view.billboard.frame_i)
	_check(f, absf(view.billboard.world_height - 2.0) < 0.001,
			"apex height %.3f, want 2.0 (full extension)" % view.billboard.world_height)
	view.step(124)  # flight t = 145: coil_03 returns for 145-164
	_check(f, view.billboard.frame_i == 2,
			"flight tick 145 frame %d, want 2 (coil_03)" % view.billboard.frame_i)
	view.step(20)   # flight t = 165: the landing; recover takes over
	_check(f, str(view.billboard.anim_name) == "recover",
			"at flight end the sprite shows %s, want recover" % str(view.billboard.anim_name))
	view.step(12)   # recover t = 12: coil_01
	_check(f, view.billboard.frame_i == 1,
			"recover tick 12 frame %d, want 1 (coil_01)" % view.billboard.frame_i)
	view.step(12)   # recover t = 24: back to idle
	_check(f, str(view.billboard.anim_name) == "idle",
			"after recover the sprite shows %s, want idle" % str(view.billboard.anim_name))
	view.free()


## The per-row feed: the sim row's own words (state + seg_left + flight_i) map onto the
## anim block's tick ranges, and unknown words read as idle.
func _leg_row_feed(f: Array[String]) -> void:
	var view: Node3D = _new_view()
	view.update_from_row({"state": "cue", "seg_left": 36})
	_check(f, str(view.billboard.anim_name) == "telegraph" and view.billboard.frame_i == 0,
			"row cue/36 frame %d (%s), want 0 (telegraph)" % [view.billboard.frame_i,
			str(view.billboard.anim_name)])
	view.update_from_row({"state": "cue", "seg_left": 24})
	_check(f, view.billboard.frame_i == 1,
			"row cue/24 frame %d, want 1" % view.billboard.frame_i)
	view.update_from_row({"state": "cue", "seg_left": 12})
	_check(f, view.billboard.frame_i == 2 and absf(view.billboard.world_height - 1.0) < 0.001,
			"row cue/12 frame %d (height %.3f), want 2 (height 1.0)"
			% [view.billboard.frame_i, view.billboard.world_height])
	view.update_from_row({"state": "flight", "flight_i": 30})
	_check(f, view.billboard.frame_i == 1 and absf(view.billboard.world_height - 2.0) < 0.001,
			"row flight_i=30 frame %d (height %.3f), want 1 (height 2.0, the apex)"
			% [view.billboard.frame_i, view.billboard.world_height])
	view.update_from_row({"state": "flight", "flight_i": 160})
	_check(f, view.billboard.frame_i == 2,
			"row flight_i=160 frame %d, want 2 (coil_03 at 145-164)" % view.billboard.frame_i)
	view.update_from_row({"state": "recover", "seg_left": 24})
	_check(f, str(view.billboard.anim_name) == "recover" and view.billboard.frame_i == 0,
			"row recover/24 frame %d (%s), want 0 (recover)" % [view.billboard.frame_i,
			str(view.billboard.anim_name)])
	view.update_from_row({"state": "recover", "seg_left": 12})
	_check(f, view.billboard.frame_i == 1,
			"row recover/12 frame %d, want 1 (coil_01)" % view.billboard.frame_i)
	view.update_from_row({"state": "spawn", "seg_left": 30})
	_check(f, str(view.billboard.anim_name) == "spawn"
			and is_equal_approx(view.billboard.modulate.a, 0.0),
			"row spawn/30 never restarted the fade (%s, a=%.3f)"
			% [str(view.billboard.anim_name), view.billboard.modulate.a])
	view.update_from_row({"state": "spawn", "seg_left": 15})
	_check(f, absf(view.billboard.modulate.a - 0.5) < 0.02,
			"row spawn/15 alpha %.3f, want ~0.5" % view.billboard.modulate.a)
	view.update_from_row({"state": "bogus-word"})
	_check(f, str(view.billboard.anim_name) == "idle",
			"row with an unknown state showed %s, want idle" % str(view.billboard.anim_name))
	view.free()


func _leg_no_meshes(f: Array[String]) -> void:
	var view: Node3D = _new_view()
	view.on_spawn()
	view.on_telegraph("coil_ring", 36)
	var meshes := _count_meshes(view)
	_check(f, meshes == 0,
			"the view built %d mesh surface(s) - the landing ring belongs to coil_telegraph.gd" % meshes)
	view.free()


func _count_meshes(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c is MeshInstance3D:
			n += 1
		n += _count_meshes(c)
	return n


## NEGATIVE CONTROL: setup + on_spawn + on_telegraph and NO step() calls. The frame, the
## anim state, the internal tick counter and the body height must not move. step(0) is
## also not allowed to advance them.
func _leg_negative_control(f: Array[String]) -> void:
	var view: Node3D = _new_view()
	view.on_spawn()
	view.on_telegraph("coil_ring", 36)
	var frame0: int = view.billboard.frame_i
	var anim0: String = str(view.billboard.anim_name)
	var ticks0: int = int(view.get("_state_t"))
	var height0: float = view.billboard.world_height
	# nothing advances without step()
	_check(f, view.billboard.frame_i == frame0,
			"negative control: frame moved without step() (%d -> %d)" % [frame0, view.billboard.frame_i])
	_check(f, str(view.billboard.anim_name) == anim0,
			"negative control: anim state changed without step() (%s -> %s)" % [anim0,
			str(view.billboard.anim_name)])
	_check(f, int(view.get("_state_t")) == ticks0,
			"negative control: internal tick counter moved without step() (%d -> %d)"
			% [ticks0, int(view.get("_state_t"))])
	_check(f, is_equal_approx(view.billboard.world_height, height0),
			"negative control: body height moved without step() (%.3f -> %.3f)"
			% [height0, view.billboard.world_height])
	# step(0) is not a clock either
	view.step(0)
	_check(f, view.billboard.frame_i == frame0 and str(view.billboard.anim_name) == anim0 \
			and int(view.get("_state_t")) == ticks0 \
			and is_equal_approx(view.billboard.world_height, height0),
			"negative control: step(0) advanced the view (frame %d, t %d, height %.3f)"
			% [view.billboard.frame_i, int(view.get("_state_t")), view.billboard.world_height])
	# a foreign telegraph kind never starts the cue
	view.on_telegraph("meow", 12)
	_check(f, str(view.billboard.anim_name) == anim0 and int(view.get("_state_t")) == ticks0,
			"negative control: an unknown telegraph kind started the cue (%s)"
			% str(view.billboard.anim_name))
	view.free()
