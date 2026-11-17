extends SceneTree
# game/tools/art/nuke.gd - the nuke (ICBM) enemy's real sprite art (T-016/T-083 follow-up).
# Headless generator; run as:
#   "<godot>" --headless --path game --script res://tools/art/nuke.gd
# Deterministic: no randomness. Reads the owner's source image from assets_src/enemies/,
# removes its opaque white background (border flood fill on a distance-from-white
# threshold), crops tight to the body, and fits it onto a 512x128 power-of-two canvas.
# Emits one DISTINCT frame per frame the nuke's T-083 anim block lists: the
# attack_descent state (spec frames nuke_00..nuke_03 -> sprites/cycle_00..03.png).
# The other five states list no frames in the block and get none (their effects are
# billboard transforms/shaders, not sprites). No tick, loop flag or effect parameter
# in the anim block is changed by this script.
# Frames are derived from the base body: vertical squash/stretch pulse (booster
# burn), a vertical bob, a slight rotation and a brightness flash with a booster
# flare boosted toward the rear nozzle. The anim block's 12 fps / 5 ticks per frame
# read them as the burn cycle.

const CANVAS_W := 512
const CANVAS_H := 128
const MARGIN := 8           # transparent margin; no opaque pixel touches the canvas edge
const BOD_MAX_W := 470.0    # drawn body width before per-frame scale (keeps sx>1 frames inside)
const BOD_MAX_H := 108.0    # drawn body height before per-frame scale
const FILL_TOL := 0.20      # flood fill: distance from white (normalised RGB euclidean)
const FEATHER_LO := 0.16    # edge feather: body pixels adjacent to background scale alpha over [FEATHER_LO, FEATHER_HI]
const FEATHER_HI := 0.25
const ALPHA_MIN := 16.0 / 255.0
const FLAME_START := 0.80   # u/bw beyond which the booster-flare boost ramps in
const LIFT_GAIN := 1.25     # art lift so the mean opaque colour clears fog contrast >= 3.0 at 40 u
const LIFT_ADD := 0.10      # (validate_sprites.gd / TERRAIN_SPEC.md section 12.3); art-side fix, never the threshold

func _dist_white(c: Color) -> float:
	var dr := 1.0 - c.r
	var dg := 1.0 - c.g
	var db := 1.0 - c.b
	return sqrt(dr * dr + dg * dg + db * db)

func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var repo_root := game_dir.get_base_dir()
	var src_path := repo_root + "/assets_src/enemies/NUKE.jpeg"
	var out_dir := game_dir + "/content/enemies/nuke/sprites"
	var src := Image.load_from_file(src_path)
	if src == null:
		print("NUKE ART FAILED: cannot load ", src_path)
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	print("source loaded: ", w, "x", h)
	# --- background removal -----------------------------------------------
	var bg := PackedByteArray()
	bg.resize(w * h)
	var stack: Array[int] = []
	for x in w:
		for y: int in [0, h - 1]:
			var ii: int = y * w + x
			if bg[ii] == 0 and _dist_white(src.get_pixel(x, y)) <= FILL_TOL:
				bg[ii] = 1
				stack.push_back(ii)
	for y in h:
		for x: int in [0, w - 1]:
			var ii2: int = y * w + x
			if bg[ii2] == 0 and _dist_white(src.get_pixel(x, y)) <= FILL_TOL:
				bg[ii2] = 1
				stack.push_back(ii2)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		var x := i % w
		var y := i / w
		var nb := [Vector2i(x + 1, y), Vector2i(x - 1, y), Vector2i(x, y + 1), Vector2i(x, y - 1)]
		for n in nb:
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var jj: int = n.y * w + n.x
			if bg[jj] == 0 and _dist_white(src.get_pixel(n.x, n.y)) <= FILL_TOL:
				bg[jj] = 1
				stack.push_back(jj)
	var bg_count := 0
	for v in bg:
		bg_count += v
	print("background pixels: ", bg_count)
	# build the body image: background -> transparent black, edge ring feathered
	var body := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			if bg[y * w + x] == 1:
				body.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				body.set_pixel(x, y, c)
	for y in h:
		for x in w:
			var i := y * w + x
			if bg[i] == 1:
				continue
			var near_bg := (x > 0 and bg[i - 1] == 1) or (x < w - 1 and bg[i + 1] == 1) or (y > 0 and bg[i - w] == 1) or (y < h - 1 and bg[i + w] == 1)
			if not near_bg:
				continue
			var c := body.get_pixel(x, y)
			var d := _dist_white(src.get_pixel(x, y))
			var f := clampf((d - FEATHER_LO) / (FEATHER_HI - FEATHER_LO), 0.22, 1.0)
			body.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * f))
	# --- crop tight to the body (alpha > 16/255) --------------------------
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if body.get_pixel(x, y).a > ALPHA_MIN:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		print("NUKE ART FAILED: no body after background removal")
		quit(1)
		return
	var bw := x1 - x0 + 1
	var bh := y1 - y0 + 1
	var body_crop := body.get_region(Rect2i(x0, y0, bw, bh))
	print("body crop: ", bw, "x", bh, " from ", x0, ",", y0)
	var fit := minf(BOD_MAX_W / float(bw), BOD_MAX_H / float(bh))
	print("fit scale: ", fit)
	# per-frame derived transforms (art derivations, not anim-block data)
	var frames := [
		{"file": "cycle_00.png", "sx": 1.00, "sy": 1.00, "rot_deg": 0.0, "yoff": 0.0, "bright": 1.00, "flame": 1.15},
		{"file": "cycle_01.png", "sx": 0.97, "sy": 1.07, "rot_deg": 0.0, "yoff": -2.0, "bright": 1.00, "flame": 1.45},
		{"file": "cycle_02.png", "sx": 1.04, "sy": 0.94, "rot_deg": 0.0, "yoff": 2.0, "bright": 1.12, "flame": 1.25},
		{"file": "cycle_03.png", "sx": 0.98, "sy": 1.04, "rot_deg": 1.8, "yoff": -1.0, "bright": 1.05, "flame": 1.60},
	]
	for fr in frames:
		var canvas := Image.create(CANVAS_W, CANVAS_H, false, Image.FORMAT_RGBA8)
		var rot := deg_to_rad(float(fr["rot_deg"]))
		var cos_r := cos(rot)
		var sin_r := sin(rot)
		var sx := float(fr["sx"]) * fit
		var sy := float(fr["sy"]) * fit
		for y in CANVAS_H:
			for x in CANVAS_W:
				var dx := float(x) + 0.5 - CANVAS_W * 0.5
				var dy := float(y) + 0.5 - CANVAS_H * 0.5 - float(fr["yoff"])
				# inverse rotate
				var ux := dx * cos_r + dy * sin_r
				var uy := -dx * sin_r + dy * cos_r
				# inverse scale into body-crop pixel space (source centre anchor)
				var su := ux / sx + float(bw) * 0.5
				var sv := uy / sy + float(bh) * 0.5
				if su < -1.0 or sv < -1.0 or su > float(bw) or sv > float(bh):
					canvas.set_pixel(x, y, Color(0, 0, 0, 0))
					continue
				var c := _bilinear(body_crop, su, sv)
				if c.a <= 0.0:
					canvas.set_pixel(x, y, Color(0, 0, 0, 0))
					continue
				var u_frac := su / float(bw)
				var fw := clampf((u_frac - FLAME_START) / (1.0 - FLAME_START), 0.0, 1.0)
				var flame := 1.0 + (float(fr["flame"]) - 1.0) * fw
				var b := float(fr["bright"]) * flame
				canvas.set_pixel(x, y, Color(clampf(c.r * b * LIFT_GAIN + LIFT_ADD, 0.0, 1.0), clampf(c.g * b * LIFT_GAIN + LIFT_ADD, 0.0, 1.0), clampf(c.b * b * LIFT_GAIN + LIFT_ADD, 0.0, 1.0), c.a))
		var out_path := out_dir + "/" + str(fr["file"])
		var err := canvas.save_png(out_path)
		if err != OK:
			print("NUKE ART FAILED: save_png ", out_path, " err ", err)
			quit(1)
			return
		# tight bbox of alpha > 16 for the JSON body_rect
		var bx0 := CANVAS_W
		var by0 := CANVAS_H
		var bx1 := -1
		var by1 := -1
		for y in CANVAS_H:
			for x in CANVAS_W:
				if canvas.get_pixel(x, y).a > ALPHA_MIN:
					bx0 = mini(bx0, x)
					bx1 = maxi(bx1, x)
					by0 = mini(by0, y)
					by1 = maxi(by1, y)
		print("RECT ", fr["file"], " ", bx0, " ", by0, " ", bx1 - bx0 + 1, " ", by1 - by0 + 1)
	print("NUKE ART DONE")
	quit(0)

func _bilinear(img: Image, u: float, v: float) -> Color:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int(floor(u))
	var y0 := int(floor(v))
	var fx := u - float(x0)
	var fy := v - float(y0)
	var acc := Color(0, 0, 0, 0)
	var wsum := 0.0
	for j: int in [0, 1]:
		for i: int in [0, 1]:
			var xx: int = x0 + i
			var yy: int = y0 + j
			if xx < 0 or yy < 0 or xx >= w or yy >= h:
				continue
			var q := (1.0 - fx) if i == 0 else fx
			var r := (1.0 - fy) if j == 0 else fy
			var wt := q * r
			var c := img.get_pixel(xx, yy)
			acc.r += c.r * c.a * wt
			acc.g += c.g * c.a * wt
			acc.b += c.b * c.a * wt
			acc.a += c.a * wt
			wsum += wt
	if wsum <= 0.0 or acc.a <= 0.0:
		return Color(0, 0, 0, 0)
	# unpremultiply
	var ia := 1.0 / acc.a
	return Color(clampf(acc.r * ia, 0.0, 1.0), clampf(acc.g * ia, 0.0, 1.0), clampf(acc.b * ia, 0.0, 1.0), clampf(acc.a, 0.0, 1.0))
