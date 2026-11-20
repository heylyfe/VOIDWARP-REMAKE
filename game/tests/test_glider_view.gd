extends RefCounted
#
# The hang glider (owner request 2026-11-20): assets_src/blender/glider.py ->
# res://assets/models/glider.glb, shown by view/glider_view.gd under the player figure
# while ctl.gliding.
#   1. the glb loads with the seven named parts, the wing spans 2.6-3.2 u, the membrane
#      carries a translucent vertex alpha and the rim is the bright cyan;
#   2. a REAL build() + step() with the jump key held (Input events, the real capture
#      path, glider kit) engages the glide and the glider is visible, parented to the
#      player figure, and fully deployed;
#   3. NEGATIVE CONTROL: the same build never gliding keeps the glider present but hidden
#      and every node on its rest transform - and that same check FAILS on the gliding
#      world of leg 2, so it can fail;
#   4. bank and pitch follow the state: two lateral speeds -> two roll angles (banked
#      into the turn), falling vs rising -> nose down vs nose up;
#   5. the deploy finishes in DEPLOY_TICKS (<= 15 ticks = 0.25 s) and overshoots; the fold
#      stays visible while folding and returns every node to rest in FOLD_TICKS;
#   6. determinism: two identical builds driven by identical input give identical glider
#      transforms on every tick.

const WorldScript := preload("res://app/world.gd")
const GliderViewScript := preload("res://view/glider_view.gd")

const DT := 1.0 / 60.0
const SEED := 1
const LEVEL := 1
const MAX_ENGAGE_TICKS := 150


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_model(f)
	_leg_real_glide_and_negative(f)
	_leg_attitude(f)
	_leg_deploy_fold(f)
	_leg_determinism(f)
	_key(KEY_SPACE, false)
	_key(KEY_D, false)
	return f


func _ledger() -> Dictionary:
	return {"class": "glider", "votes": {}, "curses": {}, "stacks": {}, "purse": 0}


## A real key event through Input (a fresh event each time - Godot refuses a reused one).
func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _build(f: Array[String], tag: String):
	var world = WorldScript.new()
	if not world.build(SEED, LEVEL, _ledger()):
		f.append("%s: world failed to build level %d seed %d" % [tag, LEVEL, SEED])
		world.free()
		return null
	if str(world.ctl.kit) != "glider":
		f.append("%s: the run's kit is %s, want glider" % [tag, str(world.ctl.kit)])
	if world.glider_view == null:
		f.append("%s: build() made no glider_view" % tag)
		world.teardown()
		world.free()
		return null
	return world


func _free(world) -> void:
	world.teardown()
	world.free()


## Leg 1: the model file itself.
func _leg_model(f: Array[String]) -> void:
	var ps: PackedScene = load(GliderViewScript.GLIDER_MODEL)
	if ps == null:
		f.append("leg 1: %s failed to load (stale import?)" % GliderViewScript.GLIDER_MODEL)
		return
	var inst: Node = ps.instantiate()
	for pn in GliderViewScript.PART_NAMES:
		var n := inst.find_child(pn, true, false)
		if n == null:
			f.append("leg 1: no node named %s in glider.glb" % pn)
		elif not (n is MeshInstance3D) or (n as MeshInstance3D).mesh == null:
			f.append("leg 1: %s is not a MeshInstance3D with a mesh" % pn)
	var wing := inst.find_child("Wing", true, false) as MeshInstance3D
	if wing != null and wing.mesh != null:
		var span := wing.get_aabb().size.x
		if span < 2.6 or span > 3.2:
			f.append("leg 1: wing span %.3f u, want 2.6-3.2" % span)
		var cols: PackedColorArray = wing.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var max_a := 0.0
		for c in cols:
			max_a = maxf(max_a, c.a)
		if cols.is_empty() or max_a >= 0.95:
			f.append("leg 1: the membrane carries no translucent vertex alpha (max %.2f)" % max_a)
	var rim := inst.find_child("WingRim", true, false) as MeshInstance3D
	if rim != null and rim.mesh != null:
		var rc: PackedColorArray = rim.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		for c in rc:
			if c.r > 0.2 or c.g < 0.7 or c.b < 0.9:
				f.append("leg 1: rim vertex colour %s is not the bright cyan" % str(c))
				break
	inst.free()


## The closed-state contract: present under the figure, hidden, open == 0, the rig and
## every part on its rest transform. Returns the problems found (empty = closed).
func _closed_problems(world) -> Array[String]:
	var p: Array[String] = []
	var gv = world.glider_view
	if gv.get_parent() != world.player_model:
		p.append("the glider is not parented to the player figure")
	if gv.visible:
		p.append("the glider is visible")
	if float(gv.open) != 0.0:
		p.append("open is %.3f" % float(gv.open))
	if not gv.transform.is_equal_approx(Transform3D(Basis(), GliderViewScript.MOUNT)):
		p.append("the rig moved off rest: %s" % str(gv.transform))
	for pn in GliderViewScript.PART_NAMES:
		if not (gv.parts[pn] as Node3D).transform.is_equal_approx(gv.rest[pn]):
			p.append("part %s moved off rest" % pn)
	return p


## Legs 2 + 3: hold jump through the real input path until the controller glides.
func _leg_real_glide_and_negative(f: Array[String]) -> void:
	# Leg 3 first: never gliding -> closed on every tick.
	var calm = _build(f, "leg 3")
	if calm == null:
		return
	var calm_bad := 0
	for t in 90:
		calm.step(DT)
		if calm.ctl.gliding:
			f.append("leg 3: the controller glided with no input")
			break
		calm_bad += _closed_problems(calm).size()
	if calm_bad != 0:
		f.append("leg 3: not gliding, the glider was not closed: %s"
				% str(_closed_problems(calm)))
	_free(calm)

	var world = _build(f, "leg 2")
	if world == null:
		return
	var gv = world.glider_view
	_key(KEY_SPACE, true)
	var engaged := -1
	for t in MAX_ENGAGE_TICKS:
		world.step(DT)
		if world.ctl.gliding:
			engaged = t
			break
	if engaged < 0:
		f.append("leg 2: holding jump never engaged the glide in %d ticks" % MAX_ENGAGE_TICKS)
		_key(KEY_SPACE, false)
		_free(world)
		return
	if not gv.visible:
		f.append("leg 2: the glide engaged but the glider is hidden")
	if gv.get_parent() != world.player_model:
		f.append("leg 2: the glider is not parented to the player figure")
	var held := 0
	for t in GliderViewScript.DEPLOY_TICKS:
		world.step(DT)
		if world.ctl.gliding:
			held += 1
	if held == GliderViewScript.DEPLOY_TICKS and float(gv.open) != 1.0:
		f.append("leg 2: open %.3f after %d gliding ticks, want 1"
				% [float(gv.open), GliderViewScript.DEPLOY_TICKS + 1])
	if world.ctl.gliding and not gv.is_visible_in_tree():
		f.append("leg 2: gliding but the glider is not visible in the tree")
	# The negative control must be able to fail: the closed check on THIS world reports.
	if world.ctl.gliding and _closed_problems(world).is_empty():
		f.append("leg 3: the closed check passed on a gliding world - it cannot fail")
	_key(KEY_SPACE, false)
	_free(world)


## Leg 4: converge on a held state, read the rig's roll/pitch.
func _settle(world, vx: float, vy: float) -> Vector2:
	world.ctl.grounded = false
	world.ctl.gliding = true
	world.ctl.dash_ticks = 0
	world.ctl.vx = vx
	world.ctl.vy = vy
	world.ctl.vz = 0.0
	for t in 60:
		world._player_pass()
	var gv = world.glider_view
	var e: Vector3 = gv.transform.basis.get_euler()
	if absf(e.x - float(gv.pitch)) > 1e-4 or absf(e.z - float(gv.roll)) > 1e-4:
		f_last.append("leg 4: the rig basis %s does not carry pitch %.3f / roll %.3f"
				% [str(e), float(gv.pitch), float(gv.roll)])
	return Vector2(float(gv.roll), float(gv.pitch))


var f_last: Array[String] = []


func _leg_attitude(f: Array[String]) -> void:
	var world = _build(f, "leg 4")
	if world == null:
		return
	world.rig.yaw_deg = 0.0
	f_last = []
	var straight := _settle(world, 0.0, -2.0)
	var right := _settle(world, 8.0, -2.0)
	var left := _settle(world, -8.0, -2.0)
	if absf(straight.x - right.x) < 0.1:
		f.append("leg 4: lateral 0 and 8 u/s give the same roll (%.3f / %.3f)"
				% [straight.x, right.x])
	if not (right.x < 0.0 and left.x > 0.0):
		f.append("leg 4: the wing must bank into the turn (right %.3f < 0 < left %.3f)"
				% [right.x, left.x])
	var falling := _settle(world, 0.0, -12.0)
	var rising := _settle(world, 0.0, 13.9)   # the updraft rise: sqrt(2 x 32 x 3)
	if not (falling.y < -0.2 and rising.y > 0.2):
		f.append("leg 4: falling must pitch nose down and rising nose up (%.3f / %.3f)"
				% [falling.y, rising.y])
	f.append_array(f_last)
	_free(world)


## Leg 5: deploy and fold timing, driven through the world's view pass.
func _leg_deploy_fold(f: Array[String]) -> void:
	var world = _build(f, "leg 5")
	if world == null:
		return
	var gv = world.glider_view
	if GliderViewScript.DEPLOY_TICKS > 15 or GliderViewScript.DEPLOY_TICKS < 9:
		f.append("leg 5: DEPLOY_TICKS %d is outside 0.15-0.25 s" % GliderViewScript.DEPLOY_TICKS)
	if GliderViewScript.FOLD_TICKS > 15 or GliderViewScript.FOLD_TICKS < 9:
		f.append("leg 5: FOLD_TICKS %d is outside 0.15-0.25 s" % GliderViewScript.FOLD_TICKS)
	world.ctl.grounded = false
	world.ctl.vx = 0.0
	world.ctl.vz = 0.0
	world.ctl.vy = -2.0
	world.ctl.gliding = true
	var wing := gv.parts["Wing"] as Node3D
	var done := -1
	var peak := 0.0
	var first_span := -1.0
	for t in 30:
		world._player_pass()
		var sx: float = wing.basis.get_scale().x
		if t == 0:
			first_span = sx
		peak = maxf(peak, sx)
		if float(gv.open) >= 1.0 and done < 0:
			done = t + 1
	if done != GliderViewScript.DEPLOY_TICKS:
		f.append("leg 5: the deploy took %d ticks, want %d" % [done, GliderViewScript.DEPLOY_TICKS])
	if first_span > 0.5:
		f.append("leg 5: the first deploy tick already shows span %.3f (no snap-open)" % first_span)
	if peak <= 1.0 + GliderViewScript.FLEX_AMP:
		f.append("leg 5: the deploy never overshot full span (peak %.3f)" % peak)
	var span_now: float = wing.basis.get_scale().x
	if absf(span_now - 1.0) > GliderViewScript.FLEX_AMP + 1e-6:
		f.append("leg 5: deployed span %.3f is outside the flex band" % span_now)
	# The ripple is alive: the wing scale changes tick to tick while gliding.
	var before: Transform3D = wing.transform
	world._player_pass()
	if wing.transform.is_equal_approx(before):
		f.append("leg 5: the wing is frozen while gliding (no flex)")
	# Fold: visible while folding, closed and at rest after FOLD_TICKS.
	world.ctl.gliding = false
	for t in GliderViewScript.FOLD_TICKS - 1:
		world._player_pass()
	if not gv.visible:
		f.append("leg 5: the glider vanished before the fold finished")
	world._player_pass()
	var p := _closed_problems(world)
	if not p.is_empty():
		f.append("leg 5: after %d fold ticks the glider is not closed at rest: %s"
				% [GliderViewScript.FOLD_TICKS, str(p)])
	_free(world)


## Leg 6: two identical builds, identical held input (jump + strafe right) -> identical
## glider transforms on every tick.
func _trace(f: Array[String], tag: String) -> Array:
	var out: Array = []
	var world = _build(f, tag)
	if world == null:
		return out
	var gv = world.glider_view
	var wing := gv.parts["Wing"] as Node3D
	_key(KEY_SPACE, true)
	_key(KEY_D, true)
	var glided := 0
	for t in 120:
		world.step(DT)
		if world.ctl.gliding:
			glided += 1
		out.append([gv.visible, gv.transform, wing.transform])
	_key(KEY_SPACE, false)
	_key(KEY_D, false)
	if glided == 0:
		f.append("%s: the scripted input never glided (the trace proves nothing)" % tag)
	_free(world)
	return out


func _leg_determinism(f: Array[String]) -> void:
	var a := _trace(f, "leg 6a")
	var b := _trace(f, "leg 6b")
	if a.size() != b.size() or a.is_empty():
		f.append("leg 6: trace sizes %d / %d" % [a.size(), b.size()])
		return
	for i in a.size():
		if a[i][0] != b[i][0] or a[i][1] != b[i][1] or a[i][2] != b[i][2]:
			f.append("leg 6: the glider diverged at tick %d: %s vs %s" % [i, str(a[i]), str(b[i])])
			return
