extends RefCounted
#
# APP-VIEWS test (headless): the playable level's core-loop views, through
# game/app/world.gd's own build(), step() and teardown(). The bug hunt found the app built
# terrain, fog, the camera, the enemy billboards and the HUD and instantiated no gift,
# tripmine or beacon view at all - view/gifts_view.gd, view/tripmine_view.gd and
# view/beacon_view.gd were referenced only by their own tests - so a real level was played
# blind: invisible gifts, an invisible beacon, invisible mines.
#
#   leg A (level 1, seed 1): build() adds the gift view with one black + one gold model
#   per REAL gift slot (occ == 1 slots get none), the black one shown and both on the
#   sim's own slot_pos(); and the beacon view on the dais tile with its column down.
#   Collecting every real black gift through world.step() flips the phase: the gold
#   models take over at the same slots and the light column is up on the open tick.
#   teardown() leaves no child, no view reference and no live node behind.
#   leg A also asserts the gifts render through a real, non-default base material
#   (the glb carries no material by design, so without the override the surface drew
#   Godot's default white and the vertex colours were never seen - J3/J8), and the
#   beacon's CLOSED body does the same (the glb's COLOR_0 is a single flat
#   beacon_closed #3A4A55 - J13), while the OPEN body stays the emissive #E8FFFF
#   override (T-085 / TERRAIN_SPEC 6.1).
#   leg B (level 5, seed 0 - mine occupancy): one tripmine view root per mine, on the
#   sim's own point(), all shown; a consumed mine leaves the view on the next step().
#
# The test fails if build() stops instantiating the three views, if step() stops driving
# them from the sim state, or if teardown() stops freeing them.

const WorldScript := preload("res://app/world.gd")
const GiftsScript := preload("res://sim/gifts.gd")

const SEED_A := 1
const LEVEL_A := 1
const SEED_B := 0
const LEVEL_B := 5   # mine occupancy (TERRAIN_SPEC 6.8); seed 0 level 5 measured 3 mines
const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_a(f)
	_leg_b(f)
	_leg_c(f)
	return f


func _leg_a(f: Array[String]) -> void:
	var world = WorldScript.new()
	if not world.build(SEED_A, LEVEL_A):
		f.append("leg A: world failed to build level %d seed %d" % [LEVEL_A, SEED_A])
		world.free()
		return
	if world.gifts_view == null or world.tripmine_view == null or world.beacon_view == null:
		f.append("leg A: build() added no core-loop view (gifts %s, tripmine %s, beacon %s)"
				% [str(world.gifts_view), str(world.tripmine_view), str(world.beacon_view)])
		_drop(world)
		return
	var g: RefCounted = world.lstate.gifts
	var real_total: int = int(g.total_real)
	if real_total <= 0:
		f.append("leg A: no real gifts in level %d seed %d" % [LEVEL_A, SEED_A])
		_drop(world)
		return
	var gv = world.gifts_view
	var slots: int = g.slots.size()

	# one black AND one gold model per REAL slot: the gold set is the same slot ids
	# (DESIGN.md section 3, "same slot id, same position"), hidden until the flip
	if int(gv.get_child_count()) != 2 * real_total:
		f.append("leg A: gift view holds %d nodes for %d real slots, want %d (black + gold)"
				% [int(gv.get_child_count()), real_total, 2 * real_total])
	if int(gv._black.size()) != slots or int(gv._gold.size()) != slots:
		f.append("leg A: gift slot tables are %d/%d entries, want %d (one per slot id)"
				% [int(gv._black.size()), int(gv._gold.size()), slots])
	var shown := 0
	for i in slots:
		var black = gv._black[i]
		var gold = gv._gold[i]
		if not bool(g.is_real(i)):
			if black != null or gold != null:
				f.append("leg A: tripmine slot %d got a gift node (occ == 1 never has one)" % i)
			continue
		if black == null:
			f.append("leg A: no black model for real slot %d" % i)
			continue
		if gold == null:
			f.append("leg A: no gold model for real slot %d" % i)
			continue
		var want: Vector3 = g.slot_pos(i)
		if not (black as Node3D).position.is_equal_approx(want):
			f.append("leg A: black gift %d sits at %s, want the sim's slot_pos %s"
					% [i, str((black as Node3D).position), str(want)])
		if not (gold as Node3D).position.is_equal_approx(want):
			f.append("leg A: gold gift %d sits at %s, want the same slot %s"
					% [i, str((gold as Node3D).position), str(want)])
		if not (black as Node3D).visible:
			f.append("leg A: black gift %d is hidden in the black phase" % i)
		if (gold as Node3D).visible:
			f.append("leg A: gold gift %d shows before the gold phase" % i)
		if (black as Node3D).visible:
			shown += 1
	if shown != real_total:
		f.append("leg A: %d black gifts on screen, want %d" % [shown, real_total])

	# the beacon view stands on the dais tile the Level dict names (the sim's own mapping)
	var bp: Array = world.lv["beacon"]
	var want_bp := Vector3(float(int(bp[0])) + 0.5, float(int(bp[2])) * 0.5,
			float(int(bp[1])) + 0.5)
	if not world.beacon_view.position.is_equal_approx(want_bp):
		f.append("leg A: the beacon view sits at %s, want the dais tile %s"
				% [str(world.beacon_view.position), str(want_bp)])
	if world.beacon_view.column_visible():
		f.append("leg A: the beacon column shows while the beacon is CLOSED")
	_check_beacon_body(f, world.beacon_view, false)

	# collect every real black gift, one world.step() each (test_app_loop.gd's idiom):
	# the black models go out, the gold ones arrive at the same slots, and the light
	# column is up on the tick the beacon opens
	for i in slots:
		if not bool(g.is_real(i)):
			continue
		var pos: Vector3 = g.slot_pos(i)
		world.ctl.x = pos.x
		world.ctl.y = pos.y - 1.0   # feet on the slot's tile top; pickup centre 0.9 u up
		world.ctl.z = pos.z
		world.ctl.vy = 0.0
		world.step(DT)
	if g.phase != GiftsScript.PHASE_GOLD:
		f.append("leg A: the gold phase never started (phase = %s)" % str(g.phase))
	if not bool(world.lstate.beacon.is_open()):
		f.append("leg A: the beacon did not open on the last real black gift")
	var gold_shown := 0
	for i in slots:
		if not bool(g.is_real(i)):
			continue
		var black2 = gv._black[i]
		var gold2 = gv._gold[i]
		if black2 == null or gold2 == null:
			continue   # the missing model was reported above
		if (black2 as Node3D).visible:
			f.append("leg A: black gift %d still shows in the gold phase" % i)
		if not (gold2 as Node3D).visible:
			f.append("leg A: no gold gift at slot %d after the flip" % i)
			continue
		gold_shown += 1
	if gold_shown != real_total:
		f.append("leg A: %d gold gifts on screen, want %d (the same slots)"
				% [gold_shown, real_total])
	if not world.beacon_view.column_visible():
		f.append("leg A: no light column on the tick the beacon opened")
	elif world.beacon_view.column_height() <= 0.0:
		f.append("leg A: the light column has zero height on the open tick")
	_check_beacon_body(f, world.beacon_view, true)
	_check_gift_materials(f, gv)

	# teardown leaves nothing behind: no child, no reference, no live node
	var freed_view = world.gifts_view
	world.teardown()
	if int(world.get_child_count()) != 0:
		f.append("teardown: %d children left behind" % int(world.get_child_count()))
	if is_instance_valid(freed_view):
		f.append("teardown: the gift view outlived the level (its nodes were not freed)")
	if world.gifts_view != null or world.tripmine_view != null or world.beacon_view != null:
		f.append("teardown: a view reference was not cleared (step() would touch freed nodes)")
	world.free()


## The gifts must render through a real, non-default base material (J3/J8): the glb
## carries no material by design, so before the fix the surface drew with Godot's
## default white material and the vertex colours were never seen. Asserts on the
## actual material properties and on the mesh's vertex colours - never on a screenshot.
## The black gift must carry the #7CFFF4 ribbon in its vertex colours (the rim) and must
## NOT carry the additive rim overlay (J8: it lifts the body to a slate box).
func _check_gift_materials(f: Array[String], gv) -> void:
	for i in gv._black.size():
		var b = gv._black[i]
		if b != null:
			_check_gift_body(f, b, "black", Color(1.0, 1.0, 1.0), BaseMaterial3D.SHADING_MODE_UNSHADED)
			if _first_overlay(b) != null:
				f.append("gift materials: black gift %d still carries the additive rim overlay (J8: it lifts the body to a slate box)" % i)
			if not _mesh_has_rim(b):
				f.append("gift materials: black gift %d has no #7CFFF4 ribbon in its vertex colours (the rim, D-T020-6)" % i)
		var g = gv._gold[i]
		if g != null:
			_check_gift_body(f, g, "gold", Color(1.0, 1.0, 1.0), BaseMaterial3D.SHADING_MODE_UNSHADED)


## One gift instance's surfaces: each must carry a StandardMaterial3D that uses the
## mesh's vertex colours as albedo, with the expected albedo tint and shading mode
## (both gifts are unshaded: J3 for gold, J8 for black), and the mesh must actually
## carry vertex colours ("not the default white").
func _check_gift_body(f: Array[String], root: Node3D, which: String, want_albedo: Color,
		want_shading: BaseMaterial3D.ShadingMode) -> void:
	var found := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				found += 1
				var m: Material = mi.get_surface_override_material(s)
				if m == null:
					f.append("gift materials: %s gift surface %d has no base material (renders default white)"
							% [which, s])
					continue
				if not (m is StandardMaterial3D):
					f.append("gift materials: %s gift surface %d base material is %s, want StandardMaterial3D"
							% [which, s, m.get_class()])
					continue
				var sm := m as StandardMaterial3D
				if sm.shading_mode != want_shading:
					f.append("gift materials: %s gift surface %d shading_mode %d, want %d"
							% [which, s, sm.shading_mode, want_shading])
				if not sm.vertex_color_use_as_albedo:
					f.append("gift materials: %s gift surface %d does not use vertex colours as albedo"
							% [which, s])
				if not sm.albedo_color.is_equal_approx(want_albedo):
					f.append("gift materials: %s gift surface %d albedo %s, want %s"
							% [which, s, str(sm.albedo_color), str(want_albedo)])
				var arrays: Array = mi.mesh.surface_get_arrays(s)
				var col_v: Variant = arrays[Mesh.ARRAY_COLOR] if arrays.size() > Mesh.ARRAY_COLOR else null
				if not (col_v is PackedColorArray) or (col_v as PackedColorArray).is_empty():
					f.append("gift materials: %s gift surface %d carries no vertex colours" % [which, s])
	if found == 0:
		f.append("gift materials: %s gift has no mesh surfaces" % which)


## The black gift's glb must carry the #7CFFF4 ribbon in its vertex colours (the rim,
## D-T020-6): the mesh is the only place the rim lives once the additive overlay is gone.
func _mesh_has_rim(root: Node3D) -> bool:
	const RIM_MAX_DIST_SQUARED := 0.01  # #7CFFF4 within ~0.1 per channel
	var rim := Color(0.2016, 1.0, 0.9047)   # #7CFFF4 as stored LINEAR by the glTF COLOR_0 export (J14)
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var arrays: Array = mi.mesh.surface_get_arrays(s)
				if arrays.size() <= Mesh.ARRAY_COLOR:
					continue
				var cols: Variant = arrays[Mesh.ARRAY_COLOR]
				if not (cols is PackedColorArray):
					continue
				for col in cols:
					var d: Vector3 = Vector3(col.r, col.g, col.b) - Vector3(rim.r, rim.g, rim.b)
					if d.length_squared() <= RIM_MAX_DIST_SQUARED:
						return true
	return false


## The first MeshInstance3D's material_overlay under a node (the gift view's rim).
static func _first_overlay(root: Node) -> StandardMaterial3D:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).material_overlay != null:
			return (n as MeshInstance3D).material_overlay as StandardMaterial3D
		for c in n.get_children():
			stack.push_back(c)
	return null


## The beacon's body must never draw Godot's default white (J13). While CLOSED the
## base pass renders: unshaded, vertex_color_use_as_albedo, white albedo, no
## material_override; the mesh must carry non-empty COLOR_0, and the recorded
## beacon_closed palette (#3A4A55, stored as LINEAR floats - glTF COLOR_0) is
## pinned with a u16-quantization tolerance.
## While OPEN the body must carry the emissive #E8FFFF material_override (T-085 /
## TERRAIN_SPEC 6.1, white when open, EMISSION_MAX x4.0 ramped). Asserts on the
## material properties only - never on a screenshot.
func _check_beacon_body(f: Array[String], bv, want_open: bool) -> void:
	const CLOSED_TAG := "beacon materials: CLOSED body surface %d "
	const OPEN_TAG := "beacon materials: OPEN body surface %d "
	const OPEN_COL := Color(0.910, 1.0, 1.0)   # #E8FFFF beacon_open
	const DIM_COL := Color(0.0423, 0.0685, 0.0908)   # #3A4A55 beacon_closed, LINEAR (glTF COLOR_0)
	var found := 0
	for mi in bv._body:
		if not (mi is MeshInstance3D) or mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			found += 1
			var tag := OPEN_TAG if want_open else CLOSED_TAG
			if want_open:
				var om: Material = mi.material_override
				if om == null:
					f.append(tag % s + "has no material_override (the OPEN state is the emissive override)")
					continue
				if not (om is StandardMaterial3D):
					f.append(tag % s + "material_override is %s, want StandardMaterial3D" % om.get_class())
					continue
				var osm := om as StandardMaterial3D
				if not osm.emission_enabled:
					f.append(tag % s + "emission is off, want on (beacon_open is emissive, EMISSION_MAX x4.0)")
				if not osm.emission.is_equal_approx(OPEN_COL):
					f.append(tag % s + "emission %s, want #E8FFFF" % str(osm.emission))
				if not osm.albedo_color.is_equal_approx(OPEN_COL):
					f.append(tag % s + "albedo %s, want #E8FFFF (TERRAIN_SPEC 6.1, white when open)" % str(osm.albedo_color))
				if osm.emission_energy_multiplier <= 0.0:
					f.append(tag % s + "emission x %.2f, want > 0 (EMISSION_MAX x4.0 through the open ramp)"
							% osm.emission_energy_multiplier)
				continue
			if mi.material_override != null:
				f.append(tag % s + "carries a material_override (the closed body renders the vertex-colour base pass)")
			var m: Material = mi.get_surface_override_material(s)
			if m == null:
				f.append(tag % s + "has no base material (renders default white)")
				continue
			if not (m is StandardMaterial3D):
				f.append(tag % s + "base material is %s, want StandardMaterial3D" % m.get_class())
				continue
			var sm := m as StandardMaterial3D
			if sm.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
				f.append(tag % s + "shading_mode %d, want UNSHADED (%d)"
						% [sm.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED])
			if not sm.vertex_color_use_as_albedo:
				f.append(tag % s + "does not use vertex colours as albedo (the glb's palette is beacon_closed #3A4A55)")
			if not sm.albedo_color.is_equal_approx(Color(1.0, 1.0, 1.0)):
				f.append(tag % s + "albedo %s, want (1.0, 1.0, 1.0) (pass the mesh's colours through)"
						% str(sm.albedo_color))
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var col_v: Variant = arrays[Mesh.ARRAY_COLOR] if arrays.size() > Mesh.ARRAY_COLOR else null
			if not (col_v is PackedColorArray) or (col_v as PackedColorArray).is_empty():
				f.append(tag % s + "carries no vertex colours")
			else:
				for col in col_v:
					var d: float = maxf(absf(col.r - DIM_COL.r),
							maxf(absf(col.g - DIM_COL.g), absf(col.b - DIM_COL.b)))
					if d > 0.01:   # u16-normalized quantization tolerance
						f.append(tag % s + "COLOR_0 %s, want beacon_closed #3A4A55 (within 0.01)" % str(col))
						break
	if found == 0:
		f.append("beacon materials: the beacon body has no mesh surfaces")


func _leg_b(f: Array[String]) -> void:
	var world = WorldScript.new()
	if not world.build(SEED_B, LEVEL_B):
		f.append("leg B: world failed to build level %d seed %d" % [LEVEL_B, SEED_B])
		world.free()
		return
	if world.tripmine_view == null:
		f.append("leg B: build() added no tripmine view")
		_drop(world)
		return
	var mines: RefCounted = world.lstate.mines
	if mines.count() == 0:
		f.append("leg B: level %d seed %d has no tripmines (the tell is untested)"
				% [LEVEL_B, SEED_B])
		_drop(world)
		return
	var tv = world.tripmine_view
	if int(tv.get_child_count()) != mines.count():
		f.append("leg B: tripmine view holds %d nodes for %d mines, want one per mine"
				% [int(tv.get_child_count()), mines.count()])
	# every live mine has a node on the sim's own point(), and it shows
	for slot in mines.ids:
		var want: Vector3 = mines.point(int(slot))
		var shown := false
		for c in tv.get_children():
			if (c as Node3D).position.is_equal_approx(want):
				shown = (c as Node3D).visible
		if not shown:
			f.append("leg B: no visible tripmine node on the sim point for slot %d" % int(slot))
	# a consumed mine (defused / shielded / detonated) leaves the view on the next step
	var slot0: int = int(mines.ids[0])
	mines.consume(slot0)
	world.step(DT)
	var point0: Vector3 = mines.point(slot0)
	for c in tv.get_children():
		if (c as Node3D).position.is_equal_approx(point0) and (c as Node3D).visible:
			f.append("leg B: the consumed mine at slot %d still shows" % slot0)
	_drop(world)


## Camera lock (D-T082-4, owner request "add a camera lock for the character, you cant turn"):
## the character does not turn and the camera does not turn. The figure is locked to the
## camera's forward, so it strafes instead of rotating to face its velocity - the pre-lock
## behaviour turned the figure to face movement while the camera stayed put.
func _leg_c(f: Array[String]) -> void:
	var world = WorldScript.new()
	if not world.build(SEED_A, LEVEL_A):
		f.append("leg C: world failed to build level %d seed %d" % [LEVEL_A, SEED_A])
		world.free()
		return
	if world.player_model == null or world.rig == null:
		f.append("leg C: build() added no player figure or camera rig")
		_drop(world)
		return
	# At spawn the figure faces the camera's forward (the camera sits behind it).
	if absf(float(world.player_model.rotation.y) - deg_to_rad(float(world.rig.yaw_deg))) > 1e-6:
		f.append("leg C: the figure does not face the camera's forward at spawn")
	# Drive the controller in several directions and re-run the figure pass: the character must
	# NOT turn to face its velocity.
	for v in [Vector2(6.0, 0.0), Vector2(0.0, -6.0), Vector2(-4.0, 4.0), Vector2(0.0, 6.0)]:
		world.ctl.vx = (v as Vector2).x
		world.ctl.vz = (v as Vector2).y
		world._player_pass()
		if absf(float(world.player_model.rotation.y)) > 1e-6:
			f.append("leg C: the character turned to face velocity %s (yaw %.4f)"
					% [str(v), float(world.player_model.rotation.y)])
	# Stepping the world must not rotate the rig either.
	var yaw0 := float(world.rig.yaw_deg)
	for i in 30:
		world.step(DT)
	if absf(float(world.rig.yaw_deg) - yaw0) > 1e-9:
		f.append("leg C: the camera yaw moved %.6f while stepping"
				% (float(world.rig.yaw_deg) - yaw0))
	_drop(world)


func _drop(world) -> void:
	world.teardown()
	world.free()
