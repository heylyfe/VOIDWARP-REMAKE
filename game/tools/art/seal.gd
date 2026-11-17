extends SceneTree
#
# game/tools/art/seal.gd - the seal's own sprite art module (FLEET_PACK; the shared
# game/tools/sprite_pipeline.gd skips this enemy because this file exists - see its
# "ENEMY <id> SKIPPED (owned by tools/art/<id>.gd)" branch). Headless:
#
#   <godot> --headless --path game --script res://tools/art/seal.gd
#
# Source: assets_src/enemies/babehseal.webp (a PHOTO: a white harp-seal pup on a
# blue-grey gradient snowfield - the pipeline's corner flood fill cannot cut it out, so
# this module owns the cutout). Deterministic: no unseeded randomness, no wall clock.
#
# What it does:
#   1. loads the source with Image.load_from_file (repo-relative path, never res://);
#   2. estimates the background with a PER-COLUMN vertical gradient (top border row
#      lerped to the bottom border row) and flags a pixel as body when its channel-wise
#      distance to that model is >= BG_DIST and its luminance is > LUM_MIN; keeps the
#      largest connected component; closes 4 px to join soft fur edges; fills holes
#      (eyes/nose/flipper claws) enclosed by the body;
#   3. crops tight to the body, grows a synthesized fluff fringe (value-noise spikes,
#      seeded SEED_FRINGE) outward into the missing fur rim, and pastes the result onto
#      a 512x512 transparent canvas, bottom-anchored (the seal lies on the ground);
#   4. writes the per-state frames (see FRAMES below) and a rebuilt sprites.json
#      (anim frames/frame_map point at the new files, every PNG listed in animations[],
#      per-frame body_rect = tight bbox of alpha > 16).

const SRC_REL := "../assets_src/enemies/babehseal.webp"
const OUT_DIR_REL := "content/enemies/seal/sprites"
const JSON_REL := "content/enemies/seal/sprites.json"
const MAX_CANVAS := 512              # power-of-two cap
const CANVAS := 512                  # POT canvas used for every frame
const MARGIN_BOTTOM := 12            # transparent margin between body and canvas bottom
const COL_W := 448                   # body scaled to this width before framing
const FR := 16                       # fringe reach (px, pre-scale)
const BG_DIST := 33                  # channel distance to the column gradient model
const LUM_MIN := 100.0               # darkest the body may be
const CLOSE_R := 4                   # closing radius to join fur to the body
const BODY_ALPHA := 16.0             # alpha > 16 defines the body (HITBOXES)
const SEED_FRINGE := 11              # value-noise seed for the fluff fringe

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

	# ---- background model: per-column vertical lerp of the top/bottom border rows ----
	var top := PackedFloat32Array()
	var bot := PackedFloat32Array()
	for x in w:
		var c := img.get_pixel(x, 0)
		var c2 := img.get_pixel(x, h - 1)
		top.append(c.r * 255.0); top.append(c.g * 255.0); top.append(c.b * 255.0)
		bot.append(c2.r * 255.0); bot.append(c2.g * 255.0); bot.append(c2.b * 255.0)
	var n_px := w * h
	var fg := PackedByteArray()
	fg.resize(n_px)
	print("SEAL ART seg model...")
	for y in h:
		var t := float(y) / float(h - 1)
		for x in w:
			var c3 := img.get_pixel(x, y)
			var mr := top[x * 3] + (bot[x * 3] - top[x * 3]) * t
			var mg := top[x * 3 + 1] + (bot[x * 3 + 1] - top[x * 3 + 1]) * t
			var mb := top[x * 3 + 2] + (bot[x * 3 + 2] - top[x * 3 + 2]) * t
			var d: float = absf(c3.r * 255.0 - mr)
			d = maxf(d, absf(c3.g * 255.0 - mg))
			d = maxf(d, absf(c3.b * 255.0 - mb))
			var lum := (c3.r + c3.g + c3.b) * 255.0 / 3.0
			fg[y * w + x] = 1 if (d >= float(BG_DIST) and lum > LUM_MIN) else 0

	var seg_cnt := 0
	for p in fg:
		seg_cnt += p
	print("SEAL ART seg done fg=%d" % seg_cnt)
	# ---- binary open (erode then dilate): drops speckle bridging the body to the
	# snowfield, then largest connected component ----
	_erode(fg, w, h, CLOSE_R)
	_dilate(fg, w, h, CLOSE_R)
	print("SEAL ART open done")
	var body := _largest_component(fg, w, h)
	var body_cnt := 0
	for p in body:
		body_cnt += p
	print("SEAL ART largest component px=%d" % body_cnt)
	print("SEAL ART components done")
	_fill_holes(body, w, h)
	print("SEAL ART holes filled")

	# ---- tight bbox, crop with fringe margin ----
	var bbox := _bbox(body, w, h)
	if bbox.size == Vector2i.ZERO:
		print("SEAL ART FAILED: no body after segmentation")
		quit(1)
		return
	var cx0: int = maxi(0, bbox.position.x - FR)
	var cy0: int = maxi(0, bbox.position.y - FR)
	var cx1: int = mini(w - 1, bbox.position.x + bbox.size.x - 1 + FR)
	var cy1: int = mini(h - 1, bbox.position.y + bbox.size.y - 1 + FR)
	var cw := cx1 - cx0 + 1
	var ch := cy1 - cy0 + 1
	print("SEAL ART body bbox %s  crop %dx%d" % [str(bbox), cw, ch])

	# ---- compose the base body RGBA on the crop (original colours + fringe) ----
	var base := _compose_base(img, body, w, h, cx0, cy0, cw, ch)

	# ---- derive the frame set ----
	var mouth := _mouth_open(base, cx0, cy0)
	var frames := {}
	frames["idle_00"] = base
	frames["idle_01"] = _brighten(_shear(base, -5.0), 1.07)
	frames["spawn_00"] = base.duplicate()
	frames["telegraph_00"] = mouth
	frames["dash_00"] = _brighten(_shear(mouth, -5.0), 1.22)
	frames["dash_01"] = _brighten(mouth, 1.10)
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


# ---- morphology --------------------------------------------------------------------------

static func _dilate(mask: PackedByteArray, w: int, h: int, r: int) -> void:
	for _i in r:
		var src: PackedByteArray = mask.duplicate()
		for y in h:
			for x in w:
				if src[y * w + x] == 1:
					mask[y * w + x] = 1
					if x > 0: mask[y * w + x - 1] = 1
					if x < w - 1: mask[y * w + x + 1] = 1
					if y > 0: mask[(y - 1) * w + x] = 1
					if y < h - 1: mask[(y + 1) * w + x] = 1


static func _erode(mask: PackedByteArray, w: int, h: int, r: int) -> void:
	for _i in r:
		var src: PackedByteArray = mask.duplicate()
		for y in h:
			for x in w:
				if src[y * w + x] == 0:
					mask[y * w + x] = 0
					continue
				if x == 0 or x == w - 1 or y == 0 or y == h - 1:
					mask[y * w + x] = 0
					continue
				if src[y * w + x - 1] == 0 or src[y * w + x + 1] == 0 \
						or src[(y - 1) * w + x] == 0 or src[(y + 1) * w + x] == 0:
					mask[y * w + x] = 0


static func _neighbors4(mask: PackedByteArray, w: int, h: int, x: int, y: int) -> Array[int]:
	var out: Array[int] = []
	if x > 0: out.append(y * w + x - 1)
	if x < w - 1: out.append(y * w + x + 1)
	if y > 0: out.append((y - 1) * w + x)
	if y < h - 1: out.append((y + 1) * w + x)
	return out


static func _largest_component(mask: PackedByteArray, w: int, h: int) -> PackedByteArray:
	# label pass: BFS per root with an incrementing label; the largest label wins
	var label := PackedInt32Array()
	label.resize(w * h)
	print("SEAL ART label pass start")
	var cur_label := 0
	var best_label := 0
	var best_size := 0
	for start in range(w * h):
		if mask[start] != 1 or label[start] != 0:
			continue
		cur_label += 1
		var stack: Array[int] = [start]
		label[start] = cur_label
		var size := 0
		while not stack.is_empty():
			var p: int = stack.pop_back()
			size += 1
			var py: int = p / w
			var px: int = p % w
			if px > 0 and mask[p - 1] == 1 and label[p - 1] == 0:
				label[p - 1] = cur_label
				stack.append(p - 1)
			if px < w - 1 and mask[p + 1] == 1 and label[p + 1] == 0:
				label[p + 1] = cur_label
				stack.append(p + 1)
			if py > 0 and mask[p - w] == 1 and label[p - w] == 0:
				label[p - w] = cur_label
				stack.append(p - w)
			if py < h - 1 and mask[p + w] == 1 and label[p + w] == 0:
				label[p + w] = cur_label
				stack.append(p + w)
		if size > best_size:
			best_size = size
			best_label = cur_label
	print("SEAL ART components labelled=%d best=%d" % [cur_label, best_size])
	var keep := PackedByteArray()
	keep.resize(w * h)
	for i in range(w * h):
		if label[i] == best_label:
			keep[i] = 1
	return keep


static func _count(mask: PackedByteArray) -> int:
	var n := 0
	for b in mask:
		if b == 1:
			n += 1
	return n


static func _fill_holes(body: PackedByteArray, w: int, h: int) -> void:
	# flood the false pixels from the border; anything unreachable is a hole -> body
	var outside := PackedByteArray()
	outside.resize(w * h)
	var stack: Array[int] = []
	for x in w:
		for y in [0, h - 1]:
			if body[y * w + x] == 0 and outside[y * w + x] == 0:
				outside[y * w + x] = 1
				stack.append(y * w + x)
	for y in h:
		for x in [0, w - 1]:
			if body[y * w + x] == 0 and outside[y * w + x] == 0:
				outside[y * w + x] = 1
				stack.append(y * w + x)
	while not stack.is_empty():
		var p: int = stack.pop_back()
		var py: int = p / w
		var px: int = p % w
		for np in _neighbors4(body, w, h, px, py):
			if body[np] == 0 and outside[np] == 0:
				outside[np] = 1
				stack.append(np)
	for i in w * h:
		if body[i] == 0 and outside[i] == 0:
			body[i] = 1


static func _bbox(mask: PackedByteArray, w: int, h: int) -> Rect2i:
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


# ---- base composition: body photo + synthesized fluff fringe ---------------------------

static func _hash2(x: int, y: int, seed: int) -> float:
	var hsh: int = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
	hsh = ((hsh ^ (hsh >> 13)) * 1274126177) & 0xFFFFFFFF
	hsh = hsh ^ (hsh >> 16)
	return float(hsh & 0xFFFFFF) / float(0xFFFFFF)


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _value_noise(x: float, y: float, scale: float, seed: int) -> float:
	var gx := x / scale
	var gy := y / scale
	var ix := int(floorf(gx))
	var iy := int(floorf(gy))
	var fx := _smooth(gx - float(ix))
	var fy := _smooth(gy - float(iy))
	var v00 := _hash2(ix, iy, seed)
	var v10 := _hash2(ix + 1, iy, seed)
	var v01 := _hash2(ix, iy + 1, seed)
	var v11 := _hash2(ix + 1, iy + 1, seed)
	return v00 * (1.0 - fx) * (1.0 - fy) + v10 * fx * (1.0 - fy) \
			+ v01 * (1.0 - fx) * fy + v11 * fx * fy


static func _compose_base(img: Image, body: PackedByteArray, w: int, h: int,
		cx0: int, cy0: int, cw: int, ch: int) -> Image:
	# crop RGB + body alpha
	var base := Image.create_empty(cw, ch, false, Image.FORMAT_RGBA8)
	for y in ch:
		for x in cw:
			var c := img.get_pixel(cx0 + x, cy0 + y)
			if body[(cy0 + y) * w + cx0 + x] == 1:
				base.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
			else:
				base.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
	# mean of the brightest 15% of body pixels -> the fringe tint
	var samples: Array[float] = []
	var cols: Array[Color] = []
	for y in ch:
		for x in cw:
			if body[(cy0 + y) * w + cx0 + x] == 1:
				var c2 := img.get_pixel(cx0 + x, cy0 + y)
				samples.append((c2.r + c2.g + c2.b) / 3.0)
				cols.append(c2)
	samples.sort()
	var cutoff: float = samples[int(samples.size() * 0.85)] if not samples.is_empty() else 0.5
	var sr := 0.0
	var sg := 0.0
	var sb := 0.0
	var cnt := 0
	for i in samples.size():
		if samples[i] >= cutoff:
			sr += cols[i].r
			sg += cols[i].g
			sb += cols[i].b
			cnt += 1
	var fr := Color(244.0 / 255.0, 247.0 / 255.0, 252.0 / 255.0)
	var tint := Color(sr / cnt, sg / cnt, sb / cnt) if cnt > 0 else Color(0.8, 0.8, 0.8)
	var fringe := Color(tint.r * 0.35 + fr.r * 0.65, tint.g * 0.35 + fr.g * 0.65, tint.b * 0.35 + fr.b * 0.65)
	# chamfer distance transform (3-4), outside distance in px (chamfer units / 3)
	var d := PackedFloat32Array()
	d.resize(cw * ch)
	var INF := 1e9
	for y in ch:
		for x in cw:
			if base.get_pixel(x, y).a > 0.0:
				d[y * cw + x] = 0.0
				continue
			var best := INF
			if x > 0: best = minf(best, d[y * cw + x - 1] + 3.0)
			if y > 0: best = minf(best, d[(y - 1) * cw + x] + 3.0)
			if y > 0 and x > 0: best = minf(best, d[(y - 1) * cw + x - 1] + 4.0)
			if y > 0 and x < cw - 1: best = minf(best, d[(y - 1) * cw + x + 1] + 4.0)
			d[y * cw + x] = best
	for yy in range(ch - 1, -1, -1):
		for xx in range(cw - 1, -1, -1):
			if d[yy * cw + xx] == 0.0:
				continue
			var best2 := d[yy * cw + xx]
			if xx < cw - 1: best2 = minf(best2, d[yy * cw + xx + 1] + 3.0)
			if yy < ch - 1: best2 = minf(best2, d[(yy + 1) * cw + xx] + 3.0)
			if yy < ch - 1 and xx < cw - 1: best2 = minf(best2, d[(yy + 1) * cw + xx + 1] + 4.0)
			if yy < ch - 1 and xx > 0: best2 = minf(best2, d[(yy + 1) * cw + xx - 1] + 4.0)
			d[yy * cw + xx] = best2
	for y in ch:
		for x in cw:
			if base.get_pixel(x, y).a > 0.0:
				continue
			var dp := d[y * cw + x] / 3.0
			if dp > 14.0:
				continue
			var n := 0.65 * _value_noise(float(x), float(y), 7.0, SEED_FRINGE) \
					+ 0.35 * _value_noise(float(x), float(y), 3.5, 29)
			var av := (n - 0.42 - 0.30 * (dp / 14.0)) / 0.30
			av = clampf(av, 0.0, 1.0)
			if av <= 0.0:
				continue
			var shade := 0.90 + 0.10 * _value_noise(float(x), float(y), 5.0, 47)
			base.set_pixel(x, y, Color(fringe.r * shade, fringe.g * shade, fringe.b * shade, av * 235.0 / 255.0))
	return base


# ---- frame derivation ----------------------------------------------------------------------

static func _mouth_open(img: Image, cx0: int, cy0: int) -> Image:
	# spec seal_01: the mouth gapes for the telegraph/dash. Nose at abs (177,251);
	# the gape sits just under it, centred on the muzzle.
	var out: Image = img.duplicate()
	var w := img.get_width()
	var h := img.get_height()
	var nx: int = 177 - cx0
	var ny: int = 251 - cy0
	var mcx: int = nx - 1
	var mcy: int = ny + 38
	var rx: int = maxi(2, int(round(w * 0.088)))
	var ry: int = maxi(1, int(round(h * 0.034)))
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
	# horizontal lean about the bottom edge (the flap/lunge); bilinear, transparent
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
	# sources[]: the base image is now real
	var srcs: Array = out.get("sources", [])
	for s in srcs:
		if str(s.get("file", "")) == "babehseal.webp":
			s["state"] = "OK -> frames derived by game/tools/art/seal.gd (2026-11-17)"
	out["sources"] = srcs
	# anim block: point every state at the new files, add frame_map
	var anim: Dictionary = out.get("anim", {})
	anim["_doc"] = "T-083 (research/fable-tickets.md section 1.9 - the table is the spec; ENEMIES.md frozen, D-040). One entry per state of the section 1.9 table. Frames are file names relative to this folder; they are REAL art derived procedurally from babehseal.webp by game/tools/art/seal.gd (2026-11-17, D-ART-SEAL-1). Driven by the SIM state and its tick counter, never a wall-clock timer."
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
	telegraph["timing_note"] = "45 ticks (0.75 s), binding. Table: 'seal_01 (mouth open), held' - telegraph_00.png is that frame (real art). The dashed red line is drawn along the 3D dash line, brightening over the 45 ticks; the seal starts a telegraph only between 4 u and 12 u from its target"
	states["telegraph"] = telegraph
	var attack: Dictionary = states.get("attack", {})
	attack["frames"] = ["sprites/dash_00.png"]
	var aeff: Dictionary = attack.get("effect", {})
	var aparams: Dictionary = aeff.get("params", {})
	aparams["flap_overlay"] = "dash_00 (lunged, +22% brightness) is the attack pose held for the 60-tick dash (one entry per spec frame - seal_01); dash_00 <-> dash_01 alternate in the 'dash' animation entry at the table's 4 ticks per frame; mouth-open = spec seal_01 (telegraph_00.png) also held under it"
	aeff["params"] = aparams
	attack["effect"] = aeff
	attack["timing_note"] = "60 ticks (1.0 s), binding: 20 u along the fixed 3D line; the bark plays on tick 0 of the dash; dash_00 (lunged mouth-open) held for the dash; the flap pair dash_00/dash_01 alternates in the 'dash' animation entry at 4 ticks per frame"
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
	# animations[]: fix the two existing entries' body_rect (frames keep their slots),
	# append the four new clips
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
