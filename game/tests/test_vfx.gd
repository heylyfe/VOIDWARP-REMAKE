extends RefCounted
#
# T-085 - the VFX pack (research/fable-tickets.md section 2.1, 2.2, 2.3, 2.5;
# TERRAIN_SPEC.md section 12.2). One assertion group per table row:
#
#   2.1 tripmine   the emitter is ACTIVE at every distance and its particle alpha
#                  is 0 at 14 u and 1 at 10 u (5 u / 7 u under Method Acting); the
#                  rim glow is the rim frame (unshaded #7CFFF4, view geometry,
#                  J10; the additive overlay lifted every pixel by a flat
#                  ~(+45,+46,+54), J8); the particle spec
#                  numbers (12/s, 1.5 s, 0.06 u, #FF4FD8, 0.4 u/s, 0.2 u drift,
#                  emission 2.0); the star ramp; the 0.9 u trigger ring at alpha
#                  0.25; the Radar Module outline within 14 u whatever the ramp;
#                  one revolution per 4.0 s.
#   2.2 glitched floor  the 5-frame decal cycle at 8 fps with the (x + z) mod 5
#                  per-tile offset, the 12-tick appear, the 6-tick danger-red
#                  tear flash, the 10 Hz expiry flicker, the 12-tick fade, and
#                  thicc ben's cleanse wave (18 ticks, outward).
#   2.3 beacon     the column appears ON the tick of the last real black gift,
#                  reaches Y +60 u after 36 ticks, the shock ring crosses the
#                  hub, and the blocked state turns the column danger red.
#   2.5 respawn    the 3 u streak collapsing over 9 ticks, the ring expanding to
#                  1.5 u, the 8 Hz blink, and the rim gone ON the tick
#                  invulnerability ends.
#
# The fog_check 12 u particle row is proven by the gate's step 9 (tools/fog_check.gd
# prints it for all 5 biomes); this file asserts the row's distance constant.

const TripmineViewScript := preload("res://view/tripmine_view.gd")
const BeaconViewScript := preload("res://view/beacon_view.gd")
const RespawnViewScript := preload("res://view/respawn_view.gd")
const ToucherViewScript := preload("res://view/toucher_view.gd")
const MinesScript := preload("res://sim/mines.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const LevelStateScript := preload("res://sim/level_state.gd")
const ControllerScript := preload("res://sim/controller.gd")

const DT := 1.0 / 60.0
const PINK := Color(1.0, 0.309804, 0.847059)   # #FF4FD8


func run() -> Array[String]:
	var f: Array[String] = []
	_test_mine_emitter(f)
	_test_mine_rim(f)
	_test_mine_table(f)
	_test_glitched_floor(f)
	_test_beacon_column(f)
	_test_respawn(f)
	return f


# ---- fixtures -------------------------------------------------------------------

## A Level dict with a mixed slot table: occs[i] == 1 -> mine slot; else a real
## gift slot. Slot id i sits at world x = i * 10 + 0.5, z = 0.5, y = 0.
static func _level(occs: Array) -> Dictionary:
	var slots: Array = []
	var tiles: Array = []
	for i in occs.size():
		slots.append({"id": i, "x": i * 10, "z": 0, "y": 0, "piece": 0, "tier": 0, "occ": occs[i]})
		tiles.append([i * 10, 0, 0, 0, 0])
	return {
		"gen_version": 0, "seed": 0, "level": 1, "players": 1, "extra_mines": 0, "attempt": 0,
		"beacon": [0, 0, 1], "spawns": [[0, 0, 1]], "arms": [], "pieces": [],
		"tiles": tiles, "props": [], "edges": [], "gifts": slots, "anchors": [], "pads": [],
	}


## The eye position that puts the camera exactly `dist` u from a mine's box point.
static func _eye_at(point: Vector3, dist: float) -> Vector3:
	return point + Vector3(dist, 0.0, 0.0)


# ---- 2.1: the emitter is constant, the alpha follows the 14 u -> 10 u ramp --------

func _test_mine_emitter(f: Array[String]) -> void:
	var level := _level([1])
	var m := MinesScript.create(level, 1, 1)
	var v = TripmineViewScript.new()
	v.setup(level, m)
	var point: Vector3 = m.point(0)
	var e: CPUParticles3D = v.emitter_for_slot(0)
	if e == null:
		f.append("mine emitter: no emitter for the mine slot")
		v.free()
		return
	# ACTIVE at every distance - the emitter never stops (section 2.1 row 4)
	for dist in [0.0, 5.0, 7.0, 10.0, 12.0, 14.0, 20.0, 60.0]:
		v.sync(_eye_at(point, dist))
		if not e.emitting:
			f.append("mine emitter: the emitter stopped at %.1f u (it is constant)" % dist)
	# the ramp: 0 at 14 u, 1 at 10 u, linear between
	var want := {10.0: 1.0, 12.0: 0.5, 14.0: 0.0}
	for dist in want.keys():
		v.sync(_eye_at(point, dist))
		if absf(e.color.a - float(want[dist])) > 1e-6:
			f.append("mine emitter: particle alpha %.4f at %.0f u, want %.1f"
					% [e.color.a, dist, float(want[dist])])
		if absf(TripmineViewScript.particle_alpha(dist) - float(want[dist])) > 1e-6:
			f.append("mine emitter: particle_alpha(%.0f) disagrees with the applied alpha" % dist)
	# beyond 14 u the particles are invisible but still emitted
	v.sync(_eye_at(point, 20.0))
	if e.color.a != 0.0:
		f.append("mine emitter: alpha %.4f at 20 u, want 0" % e.color.a)
	if not e.emitting:
		f.append("mine emitter: the emitter stopped beyond 14 u")
	# Method Acting: the ramp becomes 0 beyond 7 u -> 1 at 5 u
	v.set_method_acting(true)
	var ma := {5.0: 1.0, 6.0: 0.5, 7.0: 0.0}
	for dist in ma.keys():
		v.sync(_eye_at(point, dist))
		if absf(e.color.a - float(ma[dist])) > 1e-6:
			f.append("mine emitter: Method Acting alpha %.4f at %.0f u, want %.1f"
					% [e.color.a, dist, float(ma[dist])])
	# and the emitter is still constant under the curse
	v.sync(_eye_at(point, 30.0))
	if not e.emitting:
		f.append("mine emitter: the emitter stopped under Method Acting")
	v.set_method_acting(false)
	v.free()
	print("VFX mine emitter: constant at every distance, alpha 0@14u 1@10u (5u/7u under Method Acting)")


# ---- 2.1: the rim glow: the rim frame, at every distance -----------------------

func _test_mine_rim(f: Array[String]) -> void:
	var level := _level([0, 1])
	# The rim (TERRAIN_SPEC 12.2 "black_gift_rim", D-T020-6) is carried by the rim
	# FRAME - twelve thin unshaded #7CFFF4 boxes on the box's edges (J10; the
	# glb carries no ribbon, and an additive overlay lifts EVERY pixel of the mesh
	# by a flat ~(+45,+46,+54) regardless of base albedo, so it could never stay -
	# J8's measurement, re-measured for the mine by J10). Asserted against LITERALS;
	# the body's base material is pinned alongside (it is what makes the mine read
	# as its palette colour, and what the overlay used to wash out).
	var m := MinesScript.create(level, 1, 1)
	var v = TripmineViewScript.new()
	v.setup(level, m)
	# the body: unshaded, vertex colours as albedo, white tint - the palette frame,
	# not a white or washed box, and no additive overlay on top of it
	var mine_body: StandardMaterial3D = v.body_material_for_slot(1)
	if mine_body == null:
		f.append("mine body: the mine has no base material (renders default white)")
		v.free()
		return
	if mine_body.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		f.append("mine body: shading_mode %d, want UNSHADED (%d)"
				% [mine_body.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED])
	if not mine_body.vertex_color_use_as_albedo:
		f.append("mine body: vertex_color_use_as_albedo is off, want on (the body is the mesh's colours)")
	if not mine_body.albedo_color.is_equal_approx(Color(1.0, 1.0, 1.0)):
		f.append("mine body: albedo %s, want (1.0, 1.0, 1.0) (pass the mesh's colours through)"
				% str(mine_body.albedo_color))
	var body_mi: MeshInstance3D = v.body_for_slot(1)
	if body_mi != null and body_mi.material_overlay != null:
		f.append("mine body: an additive material_overlay is back on the body (it lifts every pixel ~(+45,+46,+54))")
	# the rim frame: unshaded #7CFFF4, shadows off, opaque - the black gift's ribbon
	var mine_rim: StandardMaterial3D = v.rim_material_for_slot(1)
	if mine_rim == null:
		f.append("mine rim: the mine has no rim frame")
		v.free()
		return
	# every parameter the rim carries must match
	if mine_rim.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
		f.append("mine rim: shading_mode %d, want UNSHADED (%d)"
				% [mine_rim.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED])
	if not mine_rim.albedo_color.is_equal_approx(Color(0.486275, 1.0, 0.956863)):
		f.append("mine rim: albedo %s, want #7CFFF4 (0.486, 1.0, 0.957) (black_gift_rim)"
				% str(mine_rim.albedo_color))
	if not mine_rim.disable_receive_shadows:
		f.append("mine rim: disable_receive_shadows is off, want on")
	if mine_rim.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		f.append("mine rim: transparency %d, want disabled (the frame is opaque)"
				% mine_rim.transparency)
	if mine_rim.cull_mode != BaseMaterial3D.CULL_BACK:
		f.append("mine rim: cull_mode %d, want CULL_BACK (%d)"
				% [mine_rim.cull_mode, BaseMaterial3D.CULL_BACK])
	# the lie holds at EVERY distance: the rim frame is still there at 60 u
	var point: Vector3 = m.point(1)
	v.sync(_eye_at(point, 60.0))
	var far_rim: MeshInstance3D = v.rim_for_slot(1)
	if far_rim == null or not far_rim.visible:
		f.append("mine rim: the rim frame vanished at 60 u (it must hold at every distance)")
	v.free()
	print("VFX mine rim: unshaded #7CFFF4 rim frame, body pass-through (J10), at every distance")


# ---- 2.1: the rest of the table (particles, star, ring, radar, turn) -------------

func _test_mine_table(f: Array[String]) -> void:
	var level := _level([1])
	var m := MinesScript.create(level, 1, 1)
	var v = TripmineViewScript.new()
	v.setup(level, m)
	var point: Vector3 = m.point(0)
	var e: CPUParticles3D = v.emitter_for_slot(0)
	# particles: 12/s, lifetime 1.5 s, size 0.06 u, #FF4FD8, rising 0.4 u/s with a
	# 0.2 u drift volume, emission 2.0
	if absf(e.lifetime - 1.5) > 1e-6:
		f.append("mine particles: lifetime %.3f, want 1.5 s" % e.lifetime)
	var rate: float = float(e.amount) / e.lifetime
	if absf(rate - 12.0) > 1e-6:
		f.append("mine particles: %.3f particles/s, want 12" % rate)
	var spark: SphereMesh = e.mesh
	if absf(spark.radius * 2.0 - 0.06) > 1e-6:
		f.append("mine particles: size %.4f u, want 0.06" % (spark.radius * 2.0))
	var smat: StandardMaterial3D = spark.material
	if not smat.albedo_color.is_equal_approx(PINK):
		f.append("mine particles: colour %s, want #FF4FD8" % str(smat.albedo_color))
	if absf(smat.emission_energy_multiplier - 2.0) > 1e-6:
		f.append("mine particles: emission %.3f, want 2.0" % smat.emission_energy_multiplier)
	if absf(e.initial_velocity_min - 0.4) > 1e-6 or absf(e.initial_velocity_max - 0.4) > 1e-6:
		f.append("mine particles: rise %.3f..%.3f u/s, want 0.4"
				% [e.initial_velocity_min, e.initial_velocity_max])
	if e.emission_shape != CPUParticles3D.EMISSION_SHAPE_SPHERE \
			or absf(e.emission_sphere_radius - 0.2) > 1e-6:
		f.append("mine particles: drift volume is not a 0.2 u sphere")
	if e.gravity != Vector3.ZERO:
		f.append("mine particles: gravity %s, want zero (they rise, they do not fall)" % str(e.gravity))
	# the star: the same ramp as the particles, emission 1.0
	var star: StandardMaterial3D = v.star_material_for_slot(0)
	v.sync(_eye_at(point, 14.0))
	if star.albedo_color.a != 0.0:
		f.append("mine star: alpha %.4f at 14 u, want 0" % star.albedo_color.a)
	v.sync(_eye_at(point, 10.0))
	if absf(star.albedo_color.a - 1.0) > 1e-6:
		f.append("mine star: alpha %.4f at 10 u, want 1" % star.albedo_color.a)
	if absf(star.emission_energy_multiplier - 1.0) > 1e-6:
		f.append("mine star: emission %.3f, want 1.0" % star.emission_energy_multiplier)
	if not star.albedo_color.is_equal_approx(Color(PINK.r, PINK.g, PINK.b, 1.0)):
		f.append("mine star: colour %s, want #FF4FD8" % str(star.albedo_color))
	# the trigger ring: radius 0.9 u, alpha 0.25, visible inside 12 u only
	var ring: MeshInstance3D = v.ring_for_slot(0)
	var torus: TorusMesh = ring.mesh
	if absf(torus.outer_radius - 0.9) > 1e-6:
		f.append("mine ring: radius %.3f u, want 0.9" % torus.outer_radius)
	var rmat: StandardMaterial3D = ring.material_override
	if absf(rmat.albedo_color.a - 0.25) > 1e-6:
		f.append("mine ring: alpha %.3f, want 0.25" % rmat.albedo_color.a)
	if not rmat.albedo_color.is_equal_approx(Color(PINK.r, PINK.g, PINK.b, 0.25)):
		f.append("mine ring: colour %s, want #FF4FD8 at alpha 0.25" % str(rmat.albedo_color))
	v.sync(_eye_at(point, 11.9))
	if not ring.visible:
		f.append("mine ring: hidden at 11.9 u (it shows inside the 12 u tell)")
	v.sync(_eye_at(point, 12.1))
	if ring.visible:
		f.append("mine ring: visible at 12.1 u (it shows inside the 12 u tell only)")
	# the Radar Module outline: within 14 u, whatever the ramp says
	var radar: MeshInstance3D = v.radar_for_slot(0)
	v.sync(_eye_at(point, 14.0))
	if radar.visible:
		f.append("mine radar: the outline shows with the module off")
	v.set_radar(true)
	v.sync(_eye_at(point, 14.0))
	if not radar.visible:
		f.append("mine radar: no outline at 14 u with the module on (the ramp is 0 there)")
	v.sync(_eye_at(point, 14.1))
	if radar.visible:
		f.append("mine radar: the outline reaches past 14 u")
	v.set_radar(false)
	# the turn: one revolution per 4.0 s
	v.set_time(0.0)
	v.sync(_eye_at(point, 5.0))
	var y0: float = v._nodes[0]["node"].rotation.y
	v.set_time(1.0)
	v.sync(_eye_at(point, 5.0))
	var y1: float = v._nodes[0]["node"].rotation.y
	if absf((y1 - y0) - TAU / 4.0) > 1e-5:
		f.append("mine turn: %.4f rad in 1 s, want %.4f (1 rev / 4 s)" % [y1 - y0, TAU / 4.0])
	v.free()
	print("VFX mine table: 12/s 1.5 s 0.06 u #FF4FD8 0.4 u/s 0.2 u drift emission 2.0, star ramp, 0.9 u ring, radar, 1 rev / 4 s")


# ---- 2.2: the glitched floor decals ---------------------------------------------

func _test_glitched_floor(f: Array[String]) -> void:
	var v = ToucherViewScript.new()
	v.setup("res://content/enemies/toucher/sprites.json", "res://content/enemies/toucher")
	v.position = Vector3.ZERO
	if v._decal_texts.size() != 5:
		f.append("glitched floor: %d decal frames, want the 5-frame cycle" % v._decal_texts.size())
		v.free()
		return
	if absf(v._floor_fps() - 8.0) > 1e-9:
		f.append("glitched floor: cycle %.2f fps, want 8" % v._floor_fps())
	var row := {"anim_state": "idle_chase", "anim_state_t": 0, "rt_tick": 1000,
			"glitched": [
				{"key": "1,0,0", "x": 1.5, "y": 0.0, "z": 0.5, "born": 1000, "life": 720},
				{"key": "3,0,0", "x": 3.5, "y": 0.0, "z": 0.5, "born": 1000, "life": 720},
				{"key": "6,0,0", "x": 6.5, "y": 0.0, "z": 0.5, "born": 1000, "life": 720},
			]}
	v.sync(row, DT)
	if v._decals.size() != 3:
		f.append("glitched floor: %d decals for 3 tiles" % v._decals.size())
		v.free()
		return
	# the (x + z) mod 5 per-tile offset, then the 8 fps cycle on top of it
	var s1: Sprite3D = (v._decals["1,0,0"] as Dictionary)["sprite"]
	var s3: Sprite3D = (v._decals["3,0,0"] as Dictionary)["sprite"]
	if s1.texture != v._decal_texts[1]:
		f.append("glitched floor: tile (1,0) starts on frame 1, not (x + z) mod 5")
	if s3.texture != v._decal_texts[3]:
		f.append("glitched floor: tile (3,0) starts on frame 3, not (x + z) mod 5")
	row["rt_tick"] = 1008   # 8 ticks = one 8 fps frame
	v.sync(row, DT)
	if s1.texture != v._decal_texts[2]:
		f.append("glitched floor: the decal did not advance one frame after 8 ticks at 8 fps")
	row["rt_tick"] = 1015   # 15 ticks = two frames
	v.sync(row, DT)
	if s1.texture != v._decal_texts[3]:
		f.append("glitched floor: the decal did not advance two frames after 15 ticks at 8 fps")
	# the appear ramp (12 ticks) under the 6-tick danger-red tear flash
	row["rt_tick"] = 1000
	v.sync(row, DT)
	if absf(s1.modulate.a) > 0.05:
		f.append("glitched floor: alpha %.2f at birth, want 0 (12-tick appear)" % s1.modulate.a)
	if s1.modulate.r < 0.9:
		f.append("glitched floor: no danger-red tear flash on the infection tick")
	row["rt_tick"] = 1006
	v.sync(row, DT)
	if absf(s1.modulate.a - 0.5) > 0.1:
		f.append("glitched floor: alpha %.2f at age 6, want ~0.5" % s1.modulate.a)
	row["rt_tick"] = 1012
	v.sync(row, DT)
	if absf(s1.modulate.a - 1.0) > 0.01:
		f.append("glitched floor: alpha %.2f at age 12, want 1" % s1.modulate.a)
	if s1.modulate.g < 0.9:
		f.append("glitched floor: the tear flash outlived its 6 ticks")
	# the last 60 ticks flicker at 10 Hz, the final 12 fade to 0
	row["rt_tick"] = 1702
	v.sync(row, DT)
	var a1: float = s1.modulate.a
	row["rt_tick"] = 1705
	v.sync(row, DT)
	if absf(a1 - s1.modulate.a) < 0.05:
		f.append("glitched floor: no 10 Hz flicker in the last 60 ticks")
	row["rt_tick"] = 1724
	v.sync(row, DT)
	if s1.modulate.a > 0.05:
		f.append("glitched floor: alpha %.2f in the final 12-tick fade, want ~0" % s1.modulate.a)
	# thicc ben's cleanse: the decals inside 8 u leave in an outward wave over 18 ticks
	row["rt_tick"] = 1000
	row["glitched"] = [
		{"key": "1,0,0", "x": 1.5, "y": 0.0, "z": 0.5, "born": 1000, "life": 720},
		{"key": "3,0,0", "x": 3.5, "y": 0.0, "z": 0.5, "born": 1000, "life": 720},
		{"key": "6,0,0", "x": 6.5, "y": 0.0, "z": 0.5, "born": 1000, "life": 720},
	]
	v.sync(row, DT)
	v.on_cleanse({"e": "glitched_cleanse", "tick": 1000, "x": 0.5, "z": 0.5, "r": 8.0, "count": 3})
	row["glitched"] = []   # the sim erased all three on the cleanse tick
	v.sync(row, DT)
	if v._decals.size() != 3:
		f.append("glitched floor: the cleanse wave dropped %d decals on its first tick, want 0"
				% (3 - v._decals.size()))
	row["rt_tick"] = 1009   # half the wave: the front is at 4.0 u
	v.sync(row, DT)
	if v._decals.has("1,0,0") or v._decals.has("3,0,0"):
		f.append("glitched floor: the wave front (4.0 u at tick 9) has not passed the inner tiles")
	if not v._decals.has("6,0,0"):
		f.append("glitched floor: the wave took the 6.0 u tile before its front reached it")
	row["rt_tick"] = 1018   # the wave is complete
	v.sync(row, DT)
	if not v._decals.is_empty():
		f.append("glitched floor: %d decals survived the 18-tick cleanse wave" % v._decals.size())
	v.free()
	print("VFX glitched floor: 8 fps 5-frame cycle with (x+z) mod 5, 12-tick appear, 6-tick tear, 10 Hz flicker, 12-tick fade, 18-tick cleanse wave")


# ---- 2.3: the beacon column appears on the tick of the last real black gift ------

func _test_beacon_column(f: Array[String]) -> void:
	var level := _level([0, 0])
	var lv: RefCounted = LevelStateScript.build(level, 1, 1)
	var ev: Array = []
	# the last real black gift is collected on tick 140; the beacon opens on that
	# same tick (sim/gifts.gd tick() -> beacon.open(lv.tick))
	lv.gifts.collect(0, 100, 0, ev)
	lv.gifts.collect(1, 140, 0, ev)
	var open_ev: Dictionary = lv.beacon.open(140)
	var last_gift_tick := -1
	for e in ev:
		if str(e.get("type", "")) == "gift_collected":
			last_gift_tick = int(e.get("tick", -1))
	if last_gift_tick != 140:
		f.append("beacon: the last real black gift landed on tick %d, want 140" % last_gift_tick)
	if int(open_ev.get("tick", -1)) != last_gift_tick:
		f.append("beacon: the open event tick %s != the last real black gift's tick %d"
				% [str(open_ev.get("tick")), last_gift_tick])
	var bv = BeaconViewScript.new()
	bv.setup(level)
	bv.set_open(true, int(open_ev.get("tick", 0)))
	# the column is visible ON the open tick itself
	bv.sync_tick(139)
	if bv.column_visible():
		f.append("beacon: the column showed before the last real black gift")
	bv.sync_tick(140)
	if not bv.column_visible():
		f.append("beacon: no column on the tick of the last real black gift")
	if bv.column_height() <= 0.0:
		f.append("beacon: the column has zero height on the open tick")
	# the ramp completes after 36 ticks at Y +60 u
	bv.sync_tick(140 + 36)
	if absf(bv.column_height() - 60.0) > 1e-4:
		f.append("beacon: column height %.3f u after 36 ticks, want 60" % bv.column_height())
	if absf(bv.column_alpha() - 0.6) > 1e-6:
		f.append("beacon: column alpha %.3f, want 0.6" % bv.column_alpha())
	# the white shock ring crosses the hub over the same 36 ticks
	bv.sync_tick(140)
	if not bv.shock_ring_visible():
		f.append("beacon: no shock ring on the open tick")
	bv.sync_tick(140 + 36)
	if bv.shock_ring_visible():
		f.append("beacon: the shock ring outlived its 36 ticks")
	# blocked (Crowded Dais / Slow Door): the column turns danger red, the Slow
	# Door ring fills over 180 ticks
	bv.sync_tick(200)
	bv.set_blocked(true, 0)
	if not bv.column_color().is_equal_approx(Color(1.0, 0.1647, 0.1647, 0.6)):
		f.append("beacon: the blocked column is %s, want danger red #FF2A2A" % str(bv.column_color()))
	if not bv.slow_door_visible():
		f.append("beacon: no Slow Door ring while entry is refused")
	bv.set_blocked(true, 90)
	if absf(bv.slow_door_fill() - 0.5) > 0.02:
		f.append("beacon: the Slow Door ring is %.2f full at 90 of 180 ticks" % bv.slow_door_fill())
	bv.set_blocked(true, 180)
	if absf(bv.slow_door_fill() - 1.0) > 1e-4:
		f.append("beacon: the Slow Door ring is %.2f full at 180 ticks, want 1.0" % bv.slow_door_fill())
	bv.set_blocked(false)
	if bv.slow_door_visible():
		f.append("beacon: the Slow Door ring stayed after entry was allowed")
	if not bv.column_color().is_equal_approx(Color(0.910, 1.0, 1.0, 0.6)):
		f.append("beacon: the unblocked column is %s, want #E8FFFF" % str(bv.column_color()))
	bv.free()
	print("VFX beacon: the column appears on the tick of the last real black gift (140), 60 u after 36 ticks, shock ring, blocked red")


# ---- 2.5: the respawn streak, ring, blink and rim --------------------------------

func _test_respawn(f: Array[String]) -> void:
	var consts: Dictionary = ControllerScript.load_constants()
	var sim_invuln_ticks: int = int(round(float(consts["respawn_invuln"]) * 60.0))
	if RespawnViewScript.INVULN_TICKS != sim_invuln_ticks:
		f.append("respawn: the view's %d invulnerability ticks != the sim's %d"
				% [RespawnViewScript.INVULN_TICKS, sim_invuln_ticks])
	# the sim's own countdown: 1.0 s of dt steps reaches 0 on tick 60, not before
	var invuln: float = float(consts["respawn_invuln"])
	var zero_at := -1
	for i in range(1, 121):
		invuln -= DT
		if invuln < 0.0:
			invuln = 0.0
		if invuln == 0.0 and zero_at < 0:
			zero_at = i
	if zero_at != sim_invuln_ticks:
		f.append("respawn: the sim's invulnerability reaches 0 on tick %d, want %d"
				% [zero_at, sim_invuln_ticks])
	var rv = RespawnViewScript.new()
	rv.on_respawn(1000, Vector3(3.5, 0.0, 0.5))
	# the reappear: a 3 u streak collapsing onto the tile over 9 ticks
	if not rv.streak_visible():
		f.append("respawn: no streak on the respawn tick")
	if absf(rv.streak_height() - 3.0) > 1e-6:
		f.append("respawn: streak %.3f u tall at birth, want 3.0" % rv.streak_height())
	rv.sync_tick(1004, 56)
	if absf(rv.streak_height() - 3.0 * (1.0 - 4.0 / 9.0)) > 1e-4:
		f.append("respawn: streak %.3f u at tick 4, want %.3f (collapses over 9 ticks)"
				% [rv.streak_height(), 3.0 * (1.0 - 4.0 / 9.0)])
	if absf(rv.ring_radius() - 1.5 * 4.0 / 9.0) > 1e-4:
		f.append("respawn: ring %.3f u at tick 4, want %.3f (expands to 1.5 u)"
				% [rv.ring_radius(), 1.5 * 4.0 / 9.0])
	rv.sync_tick(1009, 51)
	if rv.streak_visible() or rv.ring_radius() > 0.0:
		f.append("respawn: the streak or ring outlived its 9 ticks")
	# the blink: 8 Hz = 7.5 ticks per cycle, so 8 on-periods in the 60 ticks
	var on_periods := 0
	var was_on := false
	for i in range(60):
		var on: bool = RespawnViewScript.blink_on(float(i))
		if on and not was_on:
			on_periods += 1
		was_on = on
	if on_periods != 8:
		f.append("respawn: %d blink periods in 60 ticks, want 8 (8 Hz)" % on_periods)
	# the rim: on while invulnerability holds, gone ON the tick it ends
	rv.sync_tick(1000, 60)
	if absf(rv.rim_alpha() - 1.0) > 1e-6 or not rv.rim_visible():
		f.append("respawn: no white rim on the respawn tick")
	rv.sync_tick(1059, 1)
	if absf(rv.rim_alpha() - 1.0) > 1e-6:
		f.append("respawn: rim alpha %.2f one tick before invulnerability ends, want 1"
				% rv.rim_alpha())
	rv.sync_tick(1060, 0)
	if rv.rim_alpha() != 0.0:
		f.append("respawn: rim alpha %.2f on the tick invulnerability ends, want 0"
				% rv.rim_alpha())
	if rv.rim_visible():
		f.append("respawn: the rim is still drawn on the tick invulnerability ends")
	rv.free()
	print("VFX respawn: 3 u streak over 9 ticks, ring to 1.5 u, 8 Hz blink, rim gone on tick 60")
