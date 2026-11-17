extends SceneTree
#
# game/tools/art/seal.gd - the seal's own sprite art module (FLEET_PACK; the shared
# game/tools/sprite_pipeline.gd skips this enemy because this file exists - see its
# "ENEMY <id> SKIPPED (owned by tools/art/<id>.gd)" branch). Headless:
#
#   <godot> --headless --path game --script res://tools/art/seal.gd
#
# Source: assets_src/enemies/babehseal.png (2026-11-17, owner ruling: "seal also needs to
# have its PNG replaced with this"). A transparent-background render of a harp-seal pup
# lying on its belly - white fur, big round dark eyes, black nose, whiskers, front
# flippers forward, facing the camera. 640x480, palette PNG decoded to RGBA8. Exactly one
# source per enemy: the old babehseal.webp is REMOVED, do not restore it.
#
# Background removal = the source's OWN alpha channel (the corners and all four edges
# measure alpha 0; the body sits at alpha ~254; the edge is a ~10 px feathered gradient,
# NOT a hard edge, so no feathering pass is applied - a one-pixel feather was NOT needed).
# No flood fill is run, and no defringe is applied (the owner's instruction: do not
# defringe into mush). The cutout is cropped tight to the alpha > 16 bbox.
#
# What it does:
#   1. loads the source with Image.load_from_file (repo-relative path, never res://);
#   2. converts to RGBA8 and crops tight to alpha > 16 (the HITBOXES body definition);
#   3. derives the per-state frames (see FRAMES in the header notes of each function):
#        spawn_00     base (the spawn fade is the view's alpha job)
#        idle_00      base
#        idle_01      flap-lean: -5 deg shear about the bottom edge, +7% brightness
#        telegraph_00 WIND-UP: crouched (sy 0.88, sx = 1/sqrt(0.88) width compensation),
#                     mouth gape under the nose, +5% brightness
#        dash_00      LUNGE: stretched along the dash axis, low body (sy 0.74, sx 1.16),
#                     -5 deg shear (lean into the lunge), mouth gape, +18% brightness
#        dash_01      the alternate lunge phase (sy 0.80, sx 1.08), mouth gape,
#                     +10% brightness
#        recover_00   base stretched +6% vertically, +6% brightness
#      The dash axis is NOT static in the behaviour (enemy.gd computes dash_dx/dy/dz at
#      telegraph start: body centre -> player centre, fixed for the 20 u line) and the
#      anim block does NOT expose a fixed axis, so the lunge is a fixed FORWARD lunge
#      (horizontal stretch + low body), not a data-driven direction.
#   4. frames the result on a 512x512 transparent canvas, bottom-anchored (the seal lies
#      on the ground), and writes sprites/*.png;
#   5. rewrites sprites.json (anim frames/frame_map unchanged in shape, every PNG listed
#      in animations[], per-frame body_rect = tight bbox of alpha > 16).
# Deterministic: no unseeded randomness, no wall clock, no noise synthesis - the new
# source carries real fur alpha, so the synthesized fringe of the webp cutout is gone.

const SRC_REL := "../assets_src/enemies/babehseal.png"
const OUT_DIR_REL := "content/enemies/seal/sprites"
const JSON_REL := "content/enemies/seal/sprites.json"
const MAX_CANVAS := 512              # power-of-two cap
const CANVAS := 512                  # POT canvas used for every frame
const MARGIN_BOTTOM := 12            # transparent margin between body and canvas bottom
const COL_W := 448                   # body scaled to this width before framing
const BODY_ALPHA := 16.0             # alpha > 16 defines the body (HITBOXES)
# mouth gape placement on the tight-cropped base (source abs (180,278) - crop offset
# (11,45) = (169,233)); measured on the real image 2026-11-17: the gape sits on the mouth
# line just under the nose, centred on the muzzle.
const MOUTH_X := 169                 # crop-space px (base 610 px wide)
const MOUTH_Y := 233                 # crop-space px
const MOUTH_RX_F := 0.056            # rx as a fraction of the crop width
const MOUTH_RY_F := 0.033            # ry as a fraction of the crop height

var game_dir := ""
var failures: Array[String] = []


func _init() -> void:
	game_dir = ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var src_path := game_dir.path_join(SRC_REL)
	var img := Image.load_from_file(src_path)
	if img == null:
		print("SEAL ART FAILED: cannot load %s" % src_path)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("SEAL ART source %dx%d" % [w, h])

	# ---- tight crop to alpha > 16 (the source's own alpha is the matte) ----
	var bbox := _alpha_bbox(img, BODY_ALPHA)
	if bbox.size == Vector2i.ZERO:
		print("SEAL ART FAILED: no opaque body in the source")
		quit(1)
		return
	print("SEAL ART body bbox %s" % str(bbox))
	var base: Image = img.get_region(bbox)
	print("SEAL ART crop %dx%d" % [base.get_width(), base.get_height()])

	# ---- derive the frame set ----
	var mouth := _mouth_open(base)
	var frames := {}
	frames["idle_00"] = base
	frames["idle_01"] = _brighten(_shear(base, -5.0), 1.07)
	frames["spawn_00"] = base.duplicate()
	# telegraph = wind-up: crouch (body low and compressed), mouth gape, slight lift
	frames["telegraph_00"] = _brighten(_stretch_sy_sx(mouth, 1.0 / sqrt(0.88), 0.88), 1.05)
	# dash = lunge: stretched along the (fixed forward) dash axis, body low, lean in
	frames["dash_00"] = _brighten(_shear(_stretch_sy_sx(mouth, 1.16, 0.74), -5.0), 1.18)
	frames["dash_01"] = _brighten(_stretch_sy_sx(mouth, 1.08, 0.80), 1.10)
	frames["recover_00"] = _brighten(_vstretch(base, 106), 1.06)

	# ---- fit on the POT canvas, bottom-anchored, save, collect body_rects ----
	var rects := {}
	var out_dir := game_dir.path_join(OUT_DIR_REL)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for fname in frames.keys():
		var framed := _frame_on_canvas(frames[fname])
		var p := out_dir.path_join("%s.png" % fname)
		if framed.save_png(p) != OK:
			failures.append("cannot save %s" % p)
			continue
		var rect := _tight_bbox(_reload(out_dir, "%s.png" % fname))
		rects[fname] = rect
		print("SEAL ART frame %s.png body_rect [%d, %d, %d, %d]" % [fname, rect.position.x, rect.position.y, rect.size.x, rect.size.y])

	# ---- rewrite sprites.json ----
	_write_json(rects, game_dir.path_join(JSON_REL))

	if failures.is_empty():
		print("SEAL ART OK 7 frames")
		quit(0)
		return
	for f in failures:
		print("SEAL ART FAILED: %s" % f)
	quit(1)


# ---- crop / bbox helpers ------------------------------------------------------------------

static func _alpha_bbox(img: Image, alpha_thr: float) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var thr := alpha_thr / 255.0
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > thr:
				if x < x0: x0 = x
				if x > x1: x1 = x
				if y < y0: y0 = y
				if y > y1: y1 = y
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


# ---- frame derivation ----------------------------------------------------------------------

static func _mouth_open(img: Image) -> Image:
	# spec seal_01: the mouth gapes for the telegraph/dash. The gape sits on the mouth
	# line just below the nose, centred on the muzzle (measured on the real source;
	# see MOUTH_X/MOUTH_Y in the header).
	var out: Image = img.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	var mcx := MOUTH_X
	var mcy := MOUTH_Y
	var rx: int = maxi(2, int(round(w * MOUTH_RX_F)))
	var ry: int = maxi(1, int(round(h * MOUTH_RY_F)))
	var dark := Color(12.0 / 255.0, 7.0 / 255.0, 10.0 / 255.0, 1.0)
	var gum := Color(86.0 / 255.0, 40.0 / 255.0, 46.0 / 255.0, 1.0)
	for y in range(maxi(0, mcy - ry - 1), mini(h, mcy + ry + 2)):
		for x in range(maxi(0, mcx - rx - 1), mini(w, mcx + rx + 2)):
			var dx := float(x - mcx) / float(rx)
			var dy := float(y - mcy) / float(ry)
			var q := dx * dx + dy * dy
			if q <= 1.0:
				var edge := 1.0 - (1.0 - q) * 0.3
				var tcol := gum if dy >= 0.35 else dark
				out.set_pixel(x, y, Color(tcol.r * edge, tcol.g * edge, tcol.b * edge, 1.0))
	return out


static func _shear(img: Image, deg: float) -> Image:
	# horizontal lean about the bottom edge (the lunge); bilinear, transparent
	# where the source has no pixel
	var w := img.get_width()
	var h := img.get_height()
	var yb: float = float(h - 1)
	var tan_d := tan(deg_to_rad(deg))
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var sx_off := (yb - float(y)) * tan_d
		for x in w:
			var src_x := float(x) - sx_off
			var ix := int(floorf(src_x))
			var fx := src_x - float(ix)
			if src_x < -1.0 or src_x > float(w):
				continue
			var c0: Color
			var c1: Color
			if ix < 0:
				c0 = Color(0, 0, 0, 0)
				c1 = img.get_pixel(0, y)
			elif ix >= w - 1:
				c0 = img.get_pixel(w - 1, y)
				c1 = Color(0, 0, 0, 0)
			else:
				c0 = img.get_pixel(ix, y)
				c1 = img.get_pixel(ix + 1, y)
			var c := Color(c0.r + (c1.r - c0.r) * fx, c0.g + (c1.g - c0.g) * fx,
					c0.b + (c1.b - c0.b) * fx, c0.a + (c1.a - c0.a) * fx)
			out.set_pixel(x, y, c)
	return out


static func _brighten(img: Image, factor: float) -> Image:
	var out: Image = img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(minf(1.0, c.r * factor), minf(1.0, c.g * factor), minf(1.0, c.b * factor), c.a))
	return out


static func _vstretch(img: Image, pct: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var nh := maxi(1, int(round(float(h) * float(pct) / 100.0)))
	var out: Image = img.duplicate()
	out.resize(w, nh, Image.INTERPOLATE_LANCZOS)
	return out


static func _stretch_sy_sx(img: Image, sx: float, sy: float) -> Image:
	# squash/stretch on both axes (the wind-up crouch and the lunge stretch);
	# bottom-anchored on the canvas afterwards, so the feet stay planted
	var w := img.get_width()
	var h := img.get_height()
	var nw := maxi(1, int(round(float(w) * sx)))
	var nh := maxi(1, int(round(float(h) * sy)))
	var out: Image = img.duplicate()
	out.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	return out


static func _frame_on_canvas(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var scale := float(COL_W) / float(w)
	var nw := int(round(w * scale))
	var nh := int(round(h * scale))
	var resized: Image = img.duplicate()
	resized.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create_empty(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	var px := int((CANVAS - nw) / 2)
	var py := CANVAS - MARGIN_BOTTOM - nh
	canvas.blend_rect(resized, Rect2i(0, 0, nw, nh), Vector2i(px, py))
	return canvas


static func _reload(out_dir: String, name: String) -> Image:
	return Image.load_from_file(out_dir.path_join(name))


static func _tight_bbox(img: Image) -> Rect2i:
	if img == null:
		return Rect2i()
	var w := img.get_width()
	var h := img.get_height()
	var thr := BODY_ALPHA / 255.0
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > thr:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


# ---- sprites.json ---------------------------------------------------------------------------

static func _rect_array(r: Rect2i) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


func _write_json(rects: Dictionary, json_path: String) -> void:
	var text := FileAccess.get_file_as_string(json_path)
	var doc: Variant = JSON.parse_string(text)
	if not (doc is Dictionary):
		failures.append("sprites.json does not parse - not touching it")
		return
	var out: Dictionary = doc
	out["tbd"] = false
	# sources[]: one source per enemy - the webp is gone
	var srcs: Array = out.get("sources", [])
	for s in srcs:
		if str(s.get("file", "")) == "babehseal.webp":
			s["file"] = "babehseal.png"
			s["path"] = "assets_src/enemies/babehseal.png"
		if str(s.get("file", "")) == "babehseal.png":
			s["state"] = "OK -> frames derived by game/tools/art/seal.gd (2026-11-17, D-ART-SEAL-3)"
	out["sources"] = srcs
	# anim block: point every state at the same files, add frame_map
	var anim: Dictionary = out.get("anim", {})
	anim["_doc"] = "T-083 (research/fable-tickets.md section 1.9 - the table is the spec; ENEMIES.md frozen, D-040). One entry per state of the section 1.9 table. Frames are file names relative to this folder; they are REAL art derived from babehseal.png by game/tools/art/seal.gd (2026-11-17, D-ART-SEAL-3). Driven by the SIM state and its tick counter, never a wall-clock timer."
	var states: Dictionary = anim.get("states", {})
	var spawn: Dictionary = states.get("spawn", {})
	spawn["frames"] = ["sprites/spawn_00.png"]
	spawn["timing_note"] = "common fade (section 1.0): alpha 0 -> 1 over 30 ticks, scale 0.8 -> 1.0; the body cannot touch or kill until the fade completes (frame: spawn_00.png, the base seal)"
	states["spawn"] = spawn
	var idle_flap: Dictionary = states.get("idle_flap", {})
	idle_flap["frames"] = ["sprites/idle_00.png", "sprites/idle_01.png"]
	idle_flap["timing_note"] = "table: 'seal_02 <-> seal_03 loop, 9 ticks per frame'. Real frames: idle_00 = seal_03 (base), idle_01 = seal_02 (flap-lean: -5 deg shear, +7% brightness); 9-tick-per-frame cadence kept"
	states["idle_flap"] = idle_flap
	var telegraph: Dictionary = states.get("telegraph", {})
	telegraph["frames"] = ["sprites/telegraph_00.png"]
	var eff: Dictionary = telegraph.get("effect", {})
	var params: Dictionary = eff.get("params", {})
	params["mouth_open_frame_tbd"] = false
	eff["params"] = params
	telegraph["effect"] = eff
	telegraph["timing_note"] = "45 ticks (0.75 s), binding. Table: 'seal_01 (mouth open), held' - telegraph_00.png is that frame (real art: crouched wind-up - sy 0.88 squash, sx = 1/sqrt(0.88) width compensation, mouth gape under the nose, +5% brightness). The dashed red line is drawn along the 3D dash line, brightening over the 45 ticks; the seal starts a telegraph only between 4 u and 12 u from its target"
	states["telegraph"] = telegraph
	var attack: Dictionary = states.get("attack", {})
	attack["frames"] = ["sprites/dash_00.png"]
	var aeff: Dictionary = attack.get("effect", {})
	var aparams: Dictionary = aeff.get("params", {})
	aparams["flap_overlay"] = "dash_00 (lunge: sx 1.16 horizontal stretch, sy 0.74 body low, -5 deg shear, mouth open, +18% brightness) is the attack pose held for the 60-tick dash (one entry per spec frame - seal_01); dash_00 <-> dash_01 alternate in the 'dash' animation entry at the table's 4 ticks per frame; mouth-open = spec seal_01 (telegraph_00.png) also held under it"
	aeff["params"] = aparams
	attack["effect"] = aeff
	attack["timing_note"] = "60 ticks (1.0 s), binding: 20 u along the fixed 3D line; the bark plays on tick 0 of the dash; dash_00 (lunged mouth-open: sx 1.16 / sy 0.74, -5 deg shear, fixed forward lunge - the anim block exposes no fixed dash axis) held for the dash; the flap pair dash_00/dash_01 alternates in the 'dash' animation entry at 4 ticks per frame"
	states["attack"] = attack
	var recover: Dictionary = states.get("recover", {})
	recover["frames"] = ["sprites/recover_00.png"]
	recover["timing_note"] = "45 ticks (0.75 s), binding; table: 'seal_00' - recover_00.png (the base seal stretched +6% vertically, +6% brightness)"
	states["recover"] = recover
	anim["states"] = states
	anim["frame_map"] = {
		"seal_00": "sprites/idle_00.png",
		"seal_01": "sprites/telegraph_00.png",
		"seal_02": "sprites/idle_01.png",
		"seal_03": "sprites/idle_00.png",
	}
	out["anim"] = anim
	# animations[]: fix the body_rect per frame (frames keep their slots)
	var anims: Array = out.get("animations", [])
	for a in anims:
		var nm := str(a.get("name", ""))
		if nm == "idle":
			a["body_rect"] = [_rect_array(rects["idle_00"])]
		elif nm == "dash":
			a["body_rect"] = [_rect_array(rects["dash_00"]), _rect_array(rects["dash_01"])]
		elif nm == "spawn":
			a["frames"] = ["sprites/spawn_00.png"]
			a["body_rect"] = [_rect_array(rects["spawn_00"])]
			a["fps"] = 1
			a["loop"] = false
		elif nm == "flap":
			a["frames"] = ["sprites/idle_00.png", "sprites/idle_01.png"]
			a["body_rect"] = [_rect_array(rects["idle_00"]), _rect_array(rects["idle_01"])]
			a["fps"] = 7
			a["loop"] = true
		elif nm == "telegraph":
			a["frames"] = ["sprites/telegraph_00.png"]
			a["body_rect"] = [_rect_array(rects["telegraph_00"])]
			a["fps"] = 1
			a["loop"] = false
		elif nm == "recover":
			a["frames"] = ["sprites/recover_00.png"]
			a["body_rect"] = [_rect_array(rects["recover_00"])]
			a["fps"] = 1
			a["loop"] = false
	var have := {}
	for a in anims:
		have[str(a.get("name", ""))] = true
	if not have.has("spawn"):
		anims.append({"body_rect": [_rect_array(rects["spawn_00"])], "fps": 1, "frames": ["sprites/spawn_00.png"], "loop": false, "name": "spawn"})
	if not have.has("flap"):
		anims.append({"body_rect": [_rect_array(rects["idle_00"]), _rect_array(rects["idle_01"])], "fps": 7, "frames": ["sprites/idle_00.png", "sprites/idle_01.png"], "loop": true, "name": "flap"})
	if not have.has("telegraph"):
		anims.append({"body_rect": [_rect_array(rects["telegraph_00"])], "fps": 1, "frames": ["sprites/telegraph_00.png"], "loop": false, "name": "telegraph"})
	if not have.has("recover"):
		anims.append({"body_rect": [_rect_array(rects["recover_00"])], "fps": 1, "frames": ["sprites/recover_00.png"], "loop": false, "name": "recover"})
	out["animations"] = anims
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		failures.append("cannot write %s" % json_path)
		return
	f.store_string(JSON.stringify(out, "  ") + "\n")
	f.close()
