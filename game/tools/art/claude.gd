extends SceneTree
# game/tools/art/claude.gd - the Claude (Cadence) enemy's real sprite art (T-016/T-083 follow-up).
#
#   "<godot>" --headless --path game --script res://tools/art/claude.gd
#
# Source: assets_src/enemies/claudelogo.png (the Claude logo, ENEMIES.md image 15) - the ONLY
# source that exists. The clawd Crab plushie source was never fetched (ENEMIES.md points at
# github.com/xyc/plushie), so the plushie_* frames CANNOT be made real and stay TBD placeholders.
#
# What the source actually is (measured, not assumed):
#   2000x2000, FORMAT_RGBA8. All four corners are already alpha 0 (measured:
#   (0,0,0,0) at (0,0), (1999,0), (0,1999), (1999,1999)); the image carries NO opaque
#   background. Alpha histogram: 2,390,179 px at alpha 0; ~10,032 px of faint resize noise at
#   alpha 1..15; 26,451 px at 16..249 (the body's anti-aliased edge ring - the modal body
#   colour is (217,119,87,255) = #D97757, 1,567,684 px, ~98% of the body); 1,573,338 px at
#   alpha >= 250. Every alpha > 16 pixel forms ONE connected component (the logo itself,
#   touching the source's borders at rows/cols ~0 and ~1999 - the source canvas CLIPS the
#   starburst). The shared pipeline's 24/255 corner flood fill is therefore not what this
#   image needs; the body is separated by the alpha > 16 rule the validator already uses.
#
# Deterministic (no randomness anywhere). Background removal:
#   1. border flood fill from every border pixel eating pixels with alpha <= 16 (the measured
#      background: transparent black (0,0,0,0) plus its faint sub-16 resize-noise web);
#   2. zero every pixel with alpha <= 16 (drops inner noise pockets the border fill cannot reach);
#   3. keep only the largest connected opaque component (erases isolated specks, e.g. the
#      sub-16 noise that survives at the very edge of the source);
#   4. defringe: RGB of every alpha == 0 pixel is set to (0,0,0) (kills colour halos), the
#      anti-aliased edge ring keeps its alpha and hue.
# Then: crop tight to alpha > 16; derive one DISTINCT frame per ANIM-BLOCK STATE from the base
# body; fit onto a 512x512 power-of-two canvas, bottom-anchored (feet on the ground), MARGIN (8)
# transparent on every edge (>= the 2 px the validator demands). Frames may not poke the canvas
# edge: the fit is clamped so the ROTATED, DEFORMED body fits inside the margin automatically.
# Frame derivations (all inverse bilinear about the feet pivot, alpha-weighted):
#   idle_00            the base body (the T-083 idle spec, claude_00)
#   idle_01            +15 deg metronome step pose (the idle effect rotates 15 deg per beat IN STEPS)
#   idle_02            1.06x pulse pose (the idle effect scale pulse 1.0 -> 1.06, small lift)
#   spawn_00           0.8x pose (the spawn fade pose; scale_from 0.8, feet planted)
#   telegraph_drums_00 squash sy 0.85 with sx = 1/sqrt(sy), lean-back -6 deg (the coiled anticipation)
#   attack_drums_00    stretch sy 1.15, feet planted, +3 deg, bright 1.28 (the strike; the logo
#                      flashes white on the hit beat - the shine is baked in, it never hits the edge)
#   telegraph_strings_00 lean +12 deg, squash 0.92 (aiming the sweep at its starting angle)
#   attack_strings_00  wide horizontal stretch sx 1.22 / sy 0.88, bright 1.15 (the beam sweep)
#   attack_wind_00     coiled-low squash sy 0.72, sx = 1/sqrt(sy), no rotation (gathering the wind)
#   deadline_00        red tint 0.5 toward (255, 72, 64) baked in, +2 deg (agitation 100, Deadline)
# The clawd Crab plushie frames are NOT derived here: the source was never fetched, so
# plushie_00/01/02.png stay TBD magenta placeholders (make_tbd_png.gd), "tbd": true stays, and
# TBD.md records it. The anim block's spec_frames, frame COUNTS, fps, loop flags, tick ranges,
# tick_ranges, effect names/params and the animations[] order are untouched.
#
# See DECISIONS.md D-ART-claude-1 / D-ART-claude-2 for the numbers no document states (SPEC GAPs).

const SRC_REL := "assets_src/enemies/claudelogo.png"   # repo-root relative
const OUT_REL := "content/enemies/claude/sprites"
const CANVAS := 512
const MARGIN := 8
const BASE_H := 430.0         # base body height in px before per-frame deform/clamp (SPEC GAP)
const ALPHA_KEEP := 16        # alpha > 16 defines the body (the HITBOXES alpha rule)
const DEADLINE_TINT := Color(1.0, 72.0 / 255.0, 64.0 / 255.0)   # Deadline red (art judgment)
const DEADLINE_TINT_AMT := 0.5

# file, rotation (deg, about the feet pivot), vertical/horizontal deform (about the feet),
# dy (px the body is LIFTED off its feet line), brightness multiplier, tint color, tint amount.
# Every number here is art judgment (D-ART-claude-2 [CONTESTABLE]); the anim block is untouched.
const FRAMES := [
	{"file": "idle_00.png",            "rot": 0.0,  "sy": 1.00, "sx": 1.0000, "dy": 0.0, "bright": 1.00, "tint": Color(1, 1, 1, 1), "tint_amt": 0.0},
	{"file": "idle_01.png",            "rot": 15.0, "sy": 1.00, "sx": 1.0000, "dy": 0.0, "bright": 1.00, "tint": Color(1, 1, 1, 1), "tint_amt": 0.0},
	{"file": "idle_02.png",            "rot": 0.0,  "sy": 1.06, "sx": 1.0600, "dy": 4.0, "bright": 1.03, "tint": Color(1, 1, 1, 1), "tint_amt": 0.0},
	{"file": "spawn_00.png",           "rot": 0.0,  "sy": 0.80, "sx": 0.8000, "dy": 0.0, "bright": 1.00, "tint": Color(1, 1, 1, 1), "tint_amt": 0.0},
	{"file": "telegraph_drums_00.png", "rot": -6.0, "sy": 0.85, "sx": 1.0847, "dy": 0.0, "bright": 1.00, "tint": Color(1, 1, 1, 1), "tint_amt": 0.0},
	{"file": "attack_drums_00.png",    "rot": 3.0,  "sy": 1.15, "sx": 0.9327, "dy": 8.0, "bright": 1.28, "tint": Color(1, 1, 1, 1), "tint_amt": 0.0},
	{"file": "telegraph_strings_00.png", "rot": 12.0, "sy": 0.92, "sx": 1.0426, "dy": 0.0, "bright": 1.00, "tint": Color(1, 1, 1, 1), "tint_amt": 0.0},
	{"file": "attack_strings_00.png",  "rot": 2.0,  "sy": 0.88, "sx": 1.2200, "dy": 2.0, "bright": 1.15, "tint": Color(1, 1, 1, 1), "tint_amt": 0.0},
	{"file": "attack_wind_00.png",     "rot": 0.0,  "sy": 0.72, "sx": 1.1795, "dy": 0.0, "bright": 1.00, "tint": Color(1, 1, 1, 1), "tint_amt": 0.0},
	{"file": "deadline_00.png",        "rot": 2.0,  "sy": 1.00, "sx": 1.0000, "dy": 0.0, "bright": 1.00, "tint": DEADLINE_TINT, "tint_amt": DEADLINE_TINT_AMT},
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
		print("CLAUDE ART FAILED: cannot load %s" % src_path)
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width()
	var h := src.get_height()
	print("source loaded: %dx%d" % [w, h])
	_print_measurements(src)
	var body := _cut_body(src)
	if body == null:
		print("CLAUDE ART FAILED: no body after background removal")
		quit(1)
		return
	var crop := _crop_tight(body)
	print("body crop: %dx%d" % [crop.get_width(), crop.get_height()])
	DirAccess.make_dir_recursive_absolute(out_dir)
	for f in FRAMES:
		var canvas := _render_frame(crop, f)
		var out_path := "%s/%s" % [out_dir, str(f["file"])]
		if canvas.save_png(out_path) != OK:
			print("CLAUDE ART FAILED: cannot write %s" % out_path)
			quit(1)
			return
	_report_rects(out_dir)
	print("CLAUDE ART OK %d frames -> %s" % [FRAMES.size(), out_dir])
	quit(0)


func _report_rects(out_dir: String) -> Array:
	var rects: Array = []
	for f in FRAMES:
		var path := "%s/%s" % [out_dir, str(f["file"])]
		var img := Image.load_from_file(path)
		var rect := _body_bbox(img)
		print("RECT %s %dx%d body_rect=[%d, %d, %d, %d]" % [str(f["file"]), CANVAS, CANVAS, rect[0], rect[1], rect[2], rect[3]])
		rects.append(rect)
	return rects


# Measure and print the real corner/background colours (see the header: the "opaque photo" the
# shared pipeline's flood fill cannot eat does not exist in this file - the corners are alpha 0
# and the only contamination is faint sub-16-alpha resize noise).
func _print_measurements(src: Image) -> void:
	var w := src.get_width()
	var h := src.get_height()
	var data := src.get_data()
	var corners: Array = []
	for c in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		var o: int = (c.y * w + c.x) * 4
		corners.append("(%d, %d): (%d, %d, %d, %d)" % [c.x, c.y, data[o], data[o + 1], data[o + 2], data[o + 3]])
	print("corners %s / %s / %s / %s" % corners)
	var n0 := 0
	var n_noise := 0
	var n_edge := 0
	var n_body := 0
	for i in range(w * h):
		var a := int(data[i * 4 + 3])
		if a == 0:
			n0 += 1
		elif a <= ALPHA_KEEP - 1:
			n_noise += 1
		elif a <= 249:
			n_edge += 1
		else:
			n_body += 1
	print("alpha==0: %d  alpha 1-15: %d  alpha 16-249: %d  alpha>=250: %d" % [n0, n_noise, n_edge, n_body])


# 1. border flood fill from every border pixel eating pixels with alpha <= ALPHA_KEEP
#    (the measured background: transparent black + its faint sub-16 resize-noise web);
# 2. zero every pixel with alpha <= ALPHA_KEEP (inner noise pockets the fill cannot reach);
# 3. keep only the largest connected opaque component (isolated specks erased);
# 4. defringe: RGB of alpha == 0 pixels set to (0,0,0).
func _cut_body(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var data := src.get_data()
	var n := w * h
	# 1. border flood fill
	var state := PackedByteArray()   # 0 unvisited, 1 = background (erase), 2 = keep
	state.resize(n)
	state.fill(0)
	var stack: Array[int] = []
	for x in range(w):
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in range(h):
		stack.append(y * w)
		stack.append(y * w + w - 1)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if state[i] != 0:
			continue
		var o := i * 4
		if int(data[o + 3]) > ALPHA_KEEP:
			state[i] = 2
			continue
		state[i] = 1
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
		if state[i] == 1:
			data[i * 4] = 0
			data[i * 4 + 1] = 0
			data[i * 4 + 2] = 0
			data[i * 4 + 3] = 0
	# 2. zero every remaining pixel with alpha <= ALPHA_KEEP
	for i in range(n):
		if int(data[i * 4 + 3]) <= ALPHA_KEEP:
			data[i * 4] = 0
			data[i * 4 + 1] = 0
			data[i * 4 + 2] = 0
			data[i * 4 + 3] = 0
	# 3. label connected opaque components; keep the largest
	var labels := PackedInt32Array()
	labels.resize(n)
	labels.fill(0)
	var sizes: Array[int] = [0]
	for start in range(n):
		if labels[start] != 0:
			continue
		if int(data[start * 4 + 3]) <= ALPHA_KEEP:
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
				if labels[j] == 0 and int(data[j * 4 + 3]) > ALPHA_KEEP:
					labels[j] = label
					q.append(j)
		sizes.append(count)
	var best := 1
	for k in range(2, sizes.size()):
		if sizes[k] > sizes[best]:
			best = k
	for i in range(n):
		if labels[i] != best:
			data[i * 4] = 0
			data[i * 4 + 1] = 0
			data[i * 4 + 2] = 0
			data[i * 4 + 3] = 0
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


# Tight bbox of alpha > ALPHA_KEEP, then crop to it.
func _crop_tight(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in range(h):
		var o := y * w * 4
		for x in range(w):
			if int(data[o + x * 4 + 3]) > ALPHA_KEEP:
				if x < x0:
					x0 = x
				if x > x1:
					x1 = x
				if y < y0:
					y0 = y
				if y > y1:
					y1 = y
	return img.get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))


# One frame: the base body deformed about the FEET pivot (squash/stretch keeps the feet planted),
# rotated (about the same pivot), lifted by dy px, brightened and/or tinted. The fit is clamped
# so the deformed, rotated body stays inside the margin (no opaque pixel ever touches the edge).
func _render_frame(crop: Image, f: Dictionary) -> Image:
	var bw := float(crop.get_width())
	var bh := float(crop.get_height())
	var avail := float(CANVAS - 2 * MARGIN)
	var fit := BASE_H / bh
	if bw * fit > avail:
		fit = avail / bw
	var rot := deg_to_rad(float(f["rot"]))
	var cw := cos(absf(rot))
	var sw := sin(absf(rot))
	var bw2 := bw * fit * float(f["sx"])
	var bh2 := bh * fit * float(f["sy"])
	var rot_w := bw2 * cw + bh2 * sw
	var rot_h := bw2 * sw + bh2 * cw
	fit *= minf(1.0, minf(avail / rot_w, avail / rot_h))
	var sx := fit * float(f["sx"])
	var sy := fit * float(f["sy"])
	var cos_r := cos(rot)
	var sin_r := sin(rot)
	var feet_y := float(CANVAS - MARGIN) - float(f["dy"])
	var tint: Color = f["tint"]
	var tint_amt := float(f["tint_amt"])
	var bright := float(f["bright"])
	var canvas := Image.create_empty(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	for y in range(CANVAS):
		for x in range(CANVAS):
			var dx := float(x) + 0.5 - float(CANVAS) * 0.5
			var dy := float(y) + 0.5 - feet_y
			# inverse rotate
			var ux := dx * cos_r + dy * sin_r
			var uy := -dx * sin_r + dy * cos_r
			# inverse deform; feet line = source row bh (pivot), so no content below the feet
			var su := ux / sx + bw * 0.5
			var src_y := bh - (-uy / sy)
			if su < -1.0 or src_y < -1.0 or su > bw or src_y > bh:
				canvas.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var c := _bilinear(crop, su, src_y)
			if c.a <= 0.0:
				canvas.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var cr := clampf(c.r * bright, 0.0, 1.0)
			var cg := clampf(c.g * bright, 0.0, 1.0)
			var cb := clampf(c.b * bright, 0.0, 1.0)
			if tint_amt > 0.0:
				cr = lerpf(cr, tint.r, tint_amt)
				cg = lerpf(cg, tint.g, tint_amt)
				cb = lerpf(cb, tint.b, tint_amt)
			canvas.set_pixel(x, y, Color(cr, cg, cb, c.a))
	return canvas


func _bilinear(img: Image, u: float, v: float) -> Color:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int(floor(u))
	var y0 := int(floor(v))
	var fx := u - float(x0)
	var fy := v - float(y0)
	var acc := Color(0, 0, 0, 0)
	var wsum := 0.0
	for j in [0, 1]:
		for i in [0, 1]:
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
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in range(h):
		var o := y * w * 4
		for x in range(w):
			if int(data[o + x * 4 + 3]) > ALPHA_KEEP:
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
