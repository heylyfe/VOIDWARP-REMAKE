extends RefCounted
#
# A7 hitbox clause (ticket T-027; ENEMIES.md HITBOXES hard rule, DESIGN.md section 5):
# the hit shape covers ONLY the body in the PNG (the tight bbox of alpha > 16), never the
# transparent padding. Hit shape = upright cylinder, diameter = 0.8 x body width, height =
# body height. A probe inside the PNG rect but outside body_rect NEVER hits.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const Util := preload("res://tests/sim_testutil.gd")


func run() -> Array[String]:
	var f: Array[String] = []
	_derived_sizes(f)
	_point_probes(f)
	_live_contact(f)
	return f


# ENEMIES.md's own example: PNG 512x512, the cat occupies 300x400 - the hitbox is the cat.
func _derived_sizes(f: Array[String]) -> void:
	var body: Dictionary = EnemyRuntime.cylinder_from_sheet(1.8, 512, 512, [106, 56, 300, 400])
	var scale: float = 1.8 / 400.0   # world u per px so the BODY is 1.8 u tall
	if absf(float(body["width_u"]) - 300.0 * scale) > 1e-9:
		f.append("hitbox: body width %s, want 300 px x scale %.6f" % [str(body["width_u"]), scale])
	if absf(float(body["diameter_u"]) - 0.8 * 300.0 * scale) > 1e-9:
		f.append("hitbox: diameter %s, want 0.8 x body width" % str(body["diameter_u"]))
	if absf(float(body["height_u"]) - 1.8) > 1e-9:
		f.append("hitbox: cylinder height %s, want the body height 1.8" % str(body["height_u"]))
	# the frame size never enters the shape: a 1024-px frame holding the same body scales equal
	var big: Dictionary = EnemyRuntime.cylinder_from_sheet(1.8, 1024, 1024, [213, 112, 600, 800])
	if absf(float(big["diameter_u"]) - float(body["diameter_u"])) > 1e-9:
		f.append("hitbox: diameter changed with the frame padding (%s vs %s)" % [
				str(big["diameter_u"]), str(body["diameter_u"])])


# Point probes against a 256x256 frame, body_rect [16,16,224,224], body height 1.0 u:
# scale = 1/224 u per px; PNG half-width = 128 px x scale = 0.5714 u; body cylinder r = 0.4.
func _point_probes(f: Array[String]) -> void:
	var cfg := {"world_height": 1.0, "frame_w": 256, "frame_h": 256,
			"body_rect": [16, 16, 224, 224], "contact_kill": true, "cycle_s": 0.0}
	var body: Dictionary = EnemyRuntime.cylinder_from_sheet(1.0, 256, 256, cfg["body_rect"])
	var row := {"x": 0.0, "y": 0.0, "z": 0.0, "diameter_u": body["diameter_u"],
			"height_u": body["height_u"]}
	var png_half: float = 128.0 / 224.0   # u from the enemy centre to the PNG edge
	if absf(png_half - 0.5714285714) > 1e-6:
		f.append("hitbox: unexpected PNG half-width %.7f (test premise moved)" % png_half)
	# inside the PNG rect but outside the cylinder, in the side padding:
	if EnemyRuntime.cylinder_hit_point(row, 0.55, 0.5, 0.0):
		f.append("hitbox: probe at x 0.55 u (in the PNG padding, outside the body) HIT")
	# ... and in the corner padding (both axes outside the body, inside the PNG rect):
	if EnemyRuntime.cylinder_hit_point(row, 0.5, 0.5, 0.5):
		f.append("hitbox: corner probe (0.5, 0.5, 0.5) hit the padding")
	# ... and in the top padding, above the body but inside the PNG rect:
	if EnemyRuntime.cylinder_hit_point(row, 0.0, 1.05, 0.0):
		f.append("hitbox: probe at y 1.05 u (above the body top, inside the PNG) HIT")
	# ... and below the feet:
	if EnemyRuntime.cylinder_hit_point(row, 0.0, -0.05, 0.0):
		f.append("hitbox: probe at y -0.05 u (below the feet) HIT")
	# inside the cylinder, mid-body: hits
	if not EnemyRuntime.cylinder_hit_point(row, 0.2, 0.5, 0.0):
		f.append("hitbox: probe at x 0.2 u (inside the body) did not hit")
	if not EnemyRuntime.cylinder_hit_point(row, 0.0, 0.99, 0.0):
		f.append("hitbox: probe at y 0.99 u (inside the body) did not hit")


# Live path: the same sheet through a full runtime - contact kills only where the cylinder is.
func _live_contact(f: Array[String]) -> void:
	var tiles: Array = []
	for x in range(-4, 5):
		for z in range(-4, 5):
			tiles.append([x, z, 0])
	var w := Util.world_from_tiles(tiles)
	w["dais"] = [0, 0, 0]
	var cfg := {"world_height": 1.0, "frame_w": 256, "frame_h": 256,
			"body_rect": [16, 16, 224, 224], "contact_kill": true, "cycle_s": 0.0,
			"preferred_kind": "", "cycle_ticks": 0}
	# player 2.0 u away: the whole PNG (half-width 0.5714 + 0.4 reach) cannot touch them
	var rt = EnemyRuntime.new()
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.x = 2.5
	ctl.z = 0.5
	ctl.y = 0.0
	ctl.last_light_spent = true   # kill tests run with Last Light already spent (D-057)
	ctl.charges = 1
	rt.setup({}, w, [ctl], 12345)
	rt.spawn_at("tbd", "TBD", EnemyRuntime.FixtureBehavior.new(), cfg, Vector3(0.5, 0.0, 0.5))
	rt.step(Util.DT)
	if ctl.dead:
		f.append("hitbox: player 2.0 u from the body died (the padding or the frame hit)")
	# player standing in the body: dies (Last Light spent, so the save cannot mask it)
	var rt2 = EnemyRuntime.new()
	var ctl2 = Util.ControllerScript.new()
	ctl2.setup("dasher", Util.consts())
	ctl2.place(w)
	ctl2.last_light_spent = true
	ctl2.charges = 1
	rt2.setup({}, w, [ctl2], 12345)
	rt2.spawn_at("tbd", "TBD", EnemyRuntime.FixtureBehavior.new(), cfg, Vector3(0.5, 0.0, 0.5))
	rt2.step(Util.DT)
	if not ctl2.dead:
		f.append("hitbox: player standing inside the body survived the contact")
