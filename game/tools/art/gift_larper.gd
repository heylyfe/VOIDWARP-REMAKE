extends SceneTree
# game/tools/art/gift_larper.gd - the gift Larper's real sprite art (T-016/T-083).
# Headless generator; deterministic (no randomness anywhere):
#   "<godot>" --headless --path game --script res://tools/art/gift_larper.gd
#
# Source: assets_src/enemies/tripine.png (800x800 RGBA, the owner's photo of the Roblox
# tripmine - the "gift Larper" of ENEMIES.md section 1.7, image 9).
#
# MEASURED on the real image (2026-11-17):
#   - the four canvas corners are alpha 0 (measured (0,0,0,0) at all four);
#   - the four image edges carry 0 pixels with alpha != 0 (fully transparent border);
#   - 457841 / 640000 px (71.5%) are alpha 0; 8946 px are partial alpha (0<a<255);
#   - tight bbox of alpha > 16: (58, 72) size 739x688;
#   - mean opaque (a>=128, 175736 px): rgb (33.2, 2.7, 52.5) - a near-black violet,
#     WCAG-vs-fog luminance ~0.019 (palette fog #021416, visible(40u)=0.619): WAY under the
#     ENEMIES.md hard rule (mean opaque colour vs fog >= 3.0 at 40 u), so the art is graded
#     up (see GRADE below). The 12 u pink particles / 12 u tell are shader-side, untouched.
#
# Background removal: the source is an RGBA image whose corners are ALREADY alpha 0, so the
# removal is a border flood fill over pixels with alpha == 0 (the measured background, a
# zero-alpha matte) from every border cell; the filled region becomes transparent black, and
# only the LARGEST connected opaque component survives (keeps the spiky body, drops stray
# specks). The 8946 partial-alpha edge pixels were measured (mean rgb (54,0,49)) - the same
# hue family as the body (33,3,53), no foreign-colour halo (the image was matted on black,
# and the fog is near-black #021416, so a dark fringe is invisible by construction): the
# defringe pass is therefore a NO-OP beyond the alpha key, kept for the record.
#
# GRADE (the fog-readability fix, ART-side, never the threshold): a screen blend against
# GRADE_A = (175, 76, 192) per 255 - the source is nearly black, so no muliplier alone can
# lift it (gain 10 still misses mean luminance in pale_abyss-like biomes); the screen blend
# compresses into the highlights least and keeps the star neon. Resulting mean opaque
# (185, 78, 205): validate_sprites.gd formula (palette fog #021416, density 0.012, d=40u)
# gives 3.18 (>= 3.0). fog_check per-biome (direct WCAG ratio vs each biome fog) sits at
# 4.9+ for all five biomes. The frame PULSE (below) only ever brightens from there.
#
# Frames written (the T-083 anim block, section 1.7 - counts/ticks/fps/loop/effects untouched):
#   spawn            reuses sprites/cycle_00.png (spec larper_00; present from level start, no fade)
#   idle             5 DISTINCT frames sprites/cycle_00..04.png (spec larper_00..04, the
#                    "turning/rotating with its light pulsing" cycle):
#                      cycle_00  identity, light normal
#                      cycle_01  rotate +5.0 deg about the feet pivot, sy 0.94 / sx 1/sqrt(0.94), pulse 1.07
#                      cycle_02  horizontal mirror (the turn), pulse 1.14 (the light flares face-on), bob -4 px
#                      cycle_03  rotate -5.0 deg about the feet pivot, sy 1.06 / sx 1/sqrt(1.06), pulse 1.07
#                      cycle_04  horizontal mirror, pulse 1.00 (back to base; the mirror is the tell)
#   (the rotated frames lift by the downward swing of the rotated bottom corners - about
#    20 px - so the feet-pivot rotation never pokes the body past the canvas margin)
#   telegraph        NO frames (the section 1.7 table lists none; the tell is the 12 u look)
#   attack_detonation NO frames (the table lists none; the 18-tick white flash + pink->black
#                    burst to 3 u is shader-side, billboard-level; it changes no body_rect)
#   defused          sprites/defused_00.png - the defused pose (spec larper_00, ONE frame):
#                    the body desaturated 70% toward its own luminance gray and deflated
#                    (sy 0.78, sx 1/sqrt(0.78), feet pivot) - grey_out+drop_u are view-side.
#
# Canvas: 512x512 (POT), bottom-anchored (enemies stand on the ground), 8 px fully
# transparent margin on every edge (>= the 2 px validate_sprites.gd demands), body base
# height 400 px (sy 1.06 frame lands at 424 px, top still inside the canvas).
# body_rect printed per frame = tight bbox of alpha > 16 (the HITBOXES rule) - paste into
# sprites.json. See DECISIONS.md D-ART-gift_larper-1 / D-ART-gift_larper-2.

const SRC_REL := "assets_src/enemies/tripine.png"   # repo-root relative
const OUT_REL := "content/enemies/gift_larper/sprites"
const CANVAS := 512
const MARGIN := 8
const BASE_H := 400.0
const GRADE_A := Vector3(175.0, 76.0, 192.0)   # screen-blend lift (255-based), see header
const BODY_A_THR := 16.0 / 255.0               # alpha > 16/255 defines the body (HITBOXES)
const GREY := 0.70        # defused: desaturation toward the pixel's own luminance gray
const DEFUSED_SY := 0.78  # defused: deflated squash (sx = 1/sqrt(sy), feet pivot)
const IDLE_FRAMES := [
	{"file": "cycle_00.png", "sy": 1.00, "rot_deg": 0.0, "mirror": false, "yoff": 0.0, "pulse": 1.00},
	{"file": "cycle_01.png", "sy": 0.94, "rot_deg": 5.0, "mirror": false, "yoff": -21.0, "pulse": 1.07},
	{"file": "cycle_02.png", "sy": 1.00, "rot_deg": 0.0, "mirror": true, "yoff": -4.0, "pulse": 1.14},
	{"file": "cycle_03.png", "sy": 1.06, "rot_deg": -5.0, "mirror": false, "yoff": -19.0, "pulse": 1.07},
	{"file": "cycle_04.png", "sy": 1.00, "rot_deg": 0.0, "mirror": true, "yoff": 0.0, "pulse": 1.00},
]

func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var root := game_dir.get_base_dir()
	var src_path := root + "/" + SRC_REL
	var out_dir := game_dir + "/" + OUT_REL
	var src := Image.load_from_file(src_path)
	if src == null:
		print("GIFT LARPER ART FAILED: cannot load %s" % src_path)
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	print("source loaded: %dx%d" % [src.get_width(), src.get_height()])
	var body := _cut_background(src)
	var crop := _crop_tight(body)
	if crop == null:
		print("GIFT LARPER ART FAILED: no body after background removal")
		quit(1)
		return
	print("body crop: %dx%d" % [crop.get_width(), crop.get_height()])
	_grade(crop)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for fr in IDLE_FRAMES:
		var frame := _render_frame(crop, fr["sy"], fr["rot_deg"], fr["mirror"], fr["yoff"], fr["pulse"], 0.0)
		_emit(out_dir, str(fr["file"]), frame)
	var defused := _render_frame(crop, DEFUSED_SY, 0.0, false, 0.0, 1.0, GREY)
	_emit(out_dir, "defused_00.png", defused)
	print("GIFT LARPER ART OK 6 frames -> %s" % out_dir)
	quit(0)

func _emit(out_dir: String, file: String, frame: Image) -> void:
	var out_path := "%s/%s" % [out_dir, file]
	if frame.save_png(out_path) != OK:
		print("GIFT LARPER ART FAILED: cannot write %s" % out_path)
		quit(1)
		return
	var rect := _body_bbox(frame)
	if rect[0] <= 0 or rect[1] <= 0 or rect[0] + rect[2] >= CANVAS or rect[1] + rect[3] >= CANVAS:
		print("GIFT LARPER ART FAILED: %s touches the canvas edge (body_rect=%s) - margin violated" % [file, str(rect)])
		quit(1)
		return
	print("GIFT LARPER ART %s %dx%d body_rect=[%d, %d, %d, %d]" % [file, CANVAS, CANVAS, rect[0], rect[1], rect[2], rect[3]])


# Border flood fill over pixels with alpha == 0 (the measured zero-alpha matte; corners are
# alpha 0, edges carry no non-zero alpha pixel); the filled region becomes transparent black.
# Then keep only the largest connected opaque component (drops stray specks the key strands).
func _cut_background(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var data := src.get_data()      # RGBA8 bytes
	var n := w * h
	var bg := PackedByteArray()     # 1 = background (erase), 0 = keep candidate
	bg.resize(n)
	var stack: Array[int] = []
	for x in range(w):
		for y: int in [0, h - 1]:
			stack.append(y * w + x)
	for y in range(h):
		for x: int in [0, w - 1]:
			stack.append(y * w + x)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if bg[i] == 1:
			continue
		if data[i * 4 + 3] != 0:
			continue                # body blocks the fill (alpha is the whole test - measured)
		bg[i] = 1
		var x := i % w
		var y := i / w
		if x > 0:
			stack.append(i - 1)
		if x < w - 1:
			stack.append(i + 1)
		if y > 0:
			stack.append(i - w)
		if y < h - 1:
			stack.append(i + w)
	for i in range(n):
		if bg[i] == 1:
			data[i * 4 + 3] = 0
	# keep only the largest connected opaque component (the spiky body)
	var labels := PackedInt32Array()
	labels.resize(n)
	labels.fill(0)
	var sizes: Array[int] = [0]
	for start in range(n):
		if labels[start] != 0:
			continue
		if data[start * 4 + 3] <= int(BODY_A_THR * 255.0):
			labels[start] = -1
			continue
		var label := sizes.size()
		var q: Array[int] = [start]
		labels[start] = label
		var count := 0
		while not q.is_empty():
			var i: int = q.pop_back()
			count += 1
			var x := i % w
			var y := i / w
			var nb: Array[int] = []
			if x > 0:
				nb.append(i - 1)
			if x < w - 1:
				nb.append(i + 1)
			if y > 0:
				nb.append(i - w)
			if y < h - 1:
				nb.append(i + w)
			for j in nb:
				if labels[j] == 0 and data[j * 4 + 3] > int(BODY_A_THR * 255.0):
					labels[j] = label
					q.append(j)
		sizes.append(count)
	var best := 1
	for k in range(2, sizes.size()):
		if sizes[k] > sizes[best]:
			best = k
	for i in range(n):
		if labels[i] != best:
			data[i * 4 + 3] = 0
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


# Tight bbox of alpha > 16/255, then crop to it.
func _crop_tight(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var thr := int(BODY_A_THR * 255.0)
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in range(h):
		var o := y * w * 4
		for x in range(w):
			if data[o + x * 4 + 3] > thr:
				if x < x0:
					x0 = x
				if x > x1:
					x1 = x
				if y < y0:
					y0 = y
				if y > y1:
					y1 = y
	if x1 < 0:
		return null
	return img.get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))


# The fog-readability grade (see header GRADE): screen blend against GRADE_A, in-place.
# Pixels keep their hue family; only the luminance is lifted for the fog rule.
func _grade(img: Image) -> void:
	var data := img.get_data()
	var n := data.size() / 4
	for i in range(n):
		var o := i * 4
		if data[o + 3] == 0:
			continue
		for c in range(3):
			var src := float(data[o + c])
			var a := GRADE_A[c]
			var v := 255.0 - (255.0 - src) * (255.0 - a) / 255.0
			data[o + c] = int(round(clampf(v, 0.0, 255.0)))
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)


# One frame: the graded base body scaled by (sx = 1/sqrt(sy), sy), optionally mirrored and
# rotated about the FEET pivot (bottom-centre of the body at the canvas's feet line),
# bottom-anchored, then the light pulse / defused grey passes.
func _render_frame(crop: Image, sy: float, rot_deg: float, mirror: bool, yoff: float, pulse: float, grey: float) -> Image:
	var base_scale := BASE_H / float(crop.get_height())
	var w0 := int(round(crop.get_width() * base_scale / sqrt(sy)))
	var h0 := int(round(BASE_H * sy))
	var body := crop.duplicate()
	body.resize(w0, h0, Image.INTERPOLATE_LANCZOS)
	var img := Image.create_empty(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rot := deg_to_rad(rot_deg)
	var cos_r := cos(rot)
	var sin_r := sin(rot)
	var pivot := Vector2(CANVAS * 0.5, float(CANVAS - MARGIN) + yoff)
	for y in range(CANVAS):
		for x in range(CANVAS):
			var q := Vector2(float(x) + 0.5, float(y) + 0.5) - pivot
			# inverse rotate into the unrotated body frame
			var tx := q.x * cos_r + q.y * sin_r
			var ty := -q.x * sin_r + q.y * cos_r
			var u := tx + float(w0) * 0.5
			var v := ty + float(h0)
			if mirror:
				u = float(w0) - u
			if u < -1.0 or v < -1.0 or u > float(w0) + 1.0 or v > float(h0) + 1.0:
				continue
			var c := _bilinear(body, u, v)
			if c.a <= 0.0:
				continue
			var cc := c
			if grey > 0.0:
				var lin := 0.2126 * _s2l(cc.r) + 0.7152 * _s2l(cc.g) + 0.0722 * _s2l(cc.b)
				var gb := _l2s(lin)
				cc = Color(lerpf(cc.r, gb, grey), lerpf(cc.g, gb, grey), lerpf(cc.b, gb, grey), cc.a)
			if pulse != 1.0:
				cc = Color(clampf(cc.r * pulse, 0.0, 1.0), clampf(cc.g * pulse, 0.0, 1.0), clampf(cc.b * pulse, 0.0, 1.0), cc.a)
			img.set_pixel(x, y, cc)
	return img


static func _s2l(u: float) -> float:
	return u / 12.92 if u <= 0.04045 else pow((u + 0.055) / 1.055, 2.4)

static func _l2s(v: float) -> float:
	return 12.92 * v if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055


# Premultiplied-alpha bilinear sample of the resized body at (u, v) in body-pixel space.
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
	var ia := 1.0 / acc.a
	return Color(clampf(acc.r * ia, 0.0, 1.0), clampf(acc.g * ia, 0.0, 1.0), clampf(acc.b * ia, 0.0, 1.0), clampf(acc.a, 0.0, 1.0))


# Tight bbox of alpha > 16/255 as [x, y, w, h] (the same rule validate_sprites.gd uses).
func _body_bbox(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var thr := int(BODY_A_THR * 255.0)
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in range(h):
		var o := y * w * 4
		for x in range(w):
			if data[o + x * 4 + 3] > thr:
				if x < x0:
					x0 = x
				if x > x1:
					x1 = x
				if y < y0:
					y0 = y
				if y > y1:
					y1 = y
	if x1 < 0:
		return [0, 0, 0, 0]
	return [x0, y0, x1 - x0 + 1, y1 - y0 + 1]
