extends RefCounted
#
# WAVE-2 regression pins for PARKED rows 20-22 (brief: billboard stands ON its node; the
# loading screen is driven once per frame, never twice).
#
#   1. BILLBOARD LIFT: the sprite's world position (the quad's centre, from the engine's own
#      generate_triangle_mesh geometry) equals the node's position plus the declared lift
#      (body_feet_shift) - i.e. the body's feet land on the node origin, not below it.
#      body_feet_shift, offset and the mesh are three independent reads; all three must agree.
#   2. LOADING - ONE DRIVE PER FRAME: a single _process frame advances the loading model
#      exactly once (elapsed == delta, the simulated fraction == one step, never two), through
#      the real frame path including _ready's creation-frame skip.
#
# Negative controls (both applied by hand, never shipped): sign-flipping billboard.gd's offset
# fails (1); doubling the advance() call in loading_screen.gd's _process fails (2).
# Style: tabs, GDScript 4, no class_name, preload() res:// paths.

const Billboard := preload("res://view/billboard.gd")
const LoadingScreenScript := preload("res://app/loading_screen.gd")

const PX := 0.01                 # billboard.gd's pixel_size assumption (u/px)
const TOL := 1e-4                # u; the feet assertion itself uses test_billboard's 1e-3
const FEET_TOL := 1e-3
const CENTER_TOL := 1e-6


func run() -> Array[String]:
	var f: Array[String] = []
	_test_billboard_world_pos_is_node_plus_lift(f)
	_test_loading_one_frame_advances_once(f)
	return f


# (1) the sprite's world position == node position + the declared lift (body_feet_shift).
# Uses the real kiwi_cat sheet + texture so the numbers are the shipped ones, and reads the
# engine's generated quad geometry rather than re-deriving billboard.gd's expression.
func _test_billboard_world_pos_is_node_plus_lift(f: Array[String]) -> void:
	var folder := "res://content/enemies/kiwi_cat"
	var jf := FileAccess.open(folder + "/sprites.json", FileAccess.READ)
	if jf == null:
		f.append("billboard lift: cannot open %s/sprites.json" % folder)
		return
	var doc: Variant = JSON.parse_string(jf.get_as_text())
	if not (doc is Dictionary):
		f.append("billboard lift: %s/sprites.json did not parse" % folder)
		return
	var b := Billboard.new()
	var node_pos := Vector3(2.5, 3.0, -1.0)
	b.position = node_pos
	b.setup_from_sheet(doc, folder)   # applies frame 0 of the first animation
	var frame_h: float = 256.0
	if b.texture != null:
		frame_h = float(b.texture.get_height())
	# the body_rect the current frame actually used (first animation, frame 0)
	var a := b._current_anim()
	var brs: Array = a.get("body_rect", [])
	if brs.is_empty():
		f.append("billboard lift: current animation has no body_rect")
		b.free()
		return
	var br: Array = brs[mini(b.frame_i, brs.size() - 1)]
	var body_bottom_row: float = float(br[1]) + float(br[3])
	var s: float = b.scale.y
	var lift: float = b.body_feet_shift
	# (a) the declared lift is exactly the unscaled px distance from frame center to body bottom
	var want_lift: float = (body_bottom_row - frame_h * 0.5) * PX * s
	if absf(lift - want_lift) > CENTER_TOL:
		f.append("billboard lift: body_feet_shift %.6f, want %.6f (declared lift drifted)" % [lift, want_lift])
	# (b) offset (px) encodes the same lift: offset.y * PX * scale == body_feet_shift
	if absf(b.offset.y * PX * s - lift) > CENTER_TOL:
		f.append("billboard lift: offset.y %.4f px decodes to %.6f u, declared lift is %.6f u" % [b.offset.y, b.offset.y * PX * s, lift])
	# (c) the engine mesh (offset baked in, pre-scale local units) puts the quad centre exactly
	#     at the declared lift above the node origin
	var mesh: TriangleMesh = b.generate_triangle_mesh()
	if mesh == null:
		f.append("billboard lift: generate_triangle_mesh() returned null")
		b.free()
		return
	var verts: PackedVector3Array = mesh.get_faces()
	if verts.is_empty():
		f.append("billboard lift: generated quad has no vertices")
		b.free()
		return
	var mn: float = verts[0].y
	var mx: float = verts[0].y
	for p in verts:
		mn = minf(mn, p.y)
		mx = maxf(mx, p.y)
	var center_local: float = (mn + mx) * 0.5
	var world_center_y: float = node_pos.y + center_local * s
	if absf(world_center_y - (node_pos.y + lift)) > CENTER_TOL:
		f.append("billboard lift: sprite world centre y %.6f, want node y %.6f + declared lift %.6f = %.6f" % [world_center_y, node_pos.y, lift, node_pos.y + lift])
	# (d) and the body's feet still land ON the node origin (the row-21 invariant)
	var feet_y: float = node_pos.y + (mn + (frame_h - body_bottom_row) * PX) * s
	if absf(feet_y - node_pos.y) > FEET_TOL:
		f.append("billboard lift: body bottom at world y %.6f, want the node origin y %.6f +/- %.4f" % [feet_y, node_pos.y, FEET_TOL])
	b.free()


# (2) one frame through the real path advances the loading model exactly once.
# start() first (so _ready() does not re-seed), then _ready() to arm the creation-frame skip,
# then _process frames. Simulated load of 10 s so the screen stays incomplete and the fraction
# is a clean elapsed/10 - a double drive shows up as double the fraction.
func _test_loading_one_frame_advances_once(f: Array[String]) -> void:
	var ls := LoadingScreenScript.new()
	ls.start(1234, 10.0, true)
	ls._ready()                      # builds the view and arms _skip_creation_frame
	ls._process(0.5)                 # the creation frame: dropped, accrues nothing
	if absf(ls.shown_time()) > CENTER_TOL:
		f.append("loading once: creation frame accrued %.6f s, want 0 (skip did not drop the first call)" % ls.shown_time())
	if absf(ls.load_fraction()) > CENTER_TOL:
		f.append("loading once: creation frame moved the bar to %.6f, want 0.0" % ls.load_fraction())
	ls._process(0.5)                 # first real frame: exactly one advance
	if absf(ls.shown_time() - 0.5) > CENTER_TOL:
		f.append("loading once: one frame accrued %.6f s, want exactly 0.5 (double-driven if 1.0)" % ls.shown_time())
	if absf(ls.load_fraction() - 0.05) > 1e-6:
		f.append("loading once: bar at %.6f after one 0.5 s frame, want 0.05 (one advance of a 10 s simulated load)" % ls.load_fraction())
	ls._process(0.25)                # a second, different-sized frame: exactly one more advance
	if absf(ls.shown_time() - 0.75) > CENTER_TOL:
		f.append("loading once: two frames accrued %.6f s, want exactly 0.75" % ls.shown_time())
	if absf(ls.load_fraction() - 0.075) > 1e-6:
		f.append("loading once: bar at %.6f after 0.75 s, want 0.075" % ls.load_fraction())
	ls.free()
