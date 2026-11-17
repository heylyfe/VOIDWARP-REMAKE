extends SceneTree
#
# game/tools/art/thicc_ben.gd - THICC BEN art module (the ENEMIES.md "thicc ben" clock tower;
# the owner image is a PHOTO: white top/side background, the building's dark base running off
# the bottom of the frame, so the shared corner flood fill in sprite_pipeline.gd eats the body
# and the pipeline skips this enemy - this module owns its frames).
#
#   tools\godot\godot.exe --headless --path game --script res://tools/art/thicc_ben.gd
#
# Deterministic (no unseeded randomness; there is no randomness at all):
#   1. loads assets_src/enemies/thiccben.png from the repo root (never res://);
#   2. background removal tuned to THIS image: a flood fill from the border against near-white
#      (dist <= WHITE_TOL), then an iterated defringe pass that clears foreground pixels
#      adjacent to background with dist < HALO_TOL (the anti-aliased white halo);
#   3. grades the body toward a warm gilt (GRADE_MUL / GRADE_OFF) so the mean opaque colour
#      clears the A8 fog-contrast check against the #021416 fog (the raw photo is ~1.56, the
#      check needs >= 3.0 - the art was adjusted, never the threshold);
#   4. crops tight to alpha > 16, fits onto a 512x512 canvas bottom-anchored (the tower stands
#      on the ground), MARGIN px transparent margin on every side;
#   5. writes one DISTINCT frame per state the T-083 anim block lists (telegraph lists none and
#      stays empty, by the block):
#        cycle_00.png         the base body (idle; anim block thiccben_00)
#        spawn_00.png         squash anticipation pose (sx 1.14 / sy 0.78, bottom-anchored) -
#                             the block's spawn effect (common_fade) stays a view-side shader
#        attack_arrival_00.png  white-flash pose: blended 78% toward white (the block's
#                             attack_arrival white_flash effect, baked as the pose)
#        attack_ring_00.png   rock pose: +8 deg about the feet pivot, mid-swing of the block's
#                             rock_and_ring (+/-8 deg twice)
#        recover_00.png       settle pose: vertical stretch 1.07 (x 0.95), 40% desaturated
#                             (luminance-preserving; a darkened pose would fail fog contrast)
#   6. prints per-frame stats (bbox, transparency, mean opaque colour, fog ratio) and exits 0.
#
# sprites.json is updated by hand to point the anim block + animations[] at these files; every
# frame's body_rect there is the tight alpha > 16 bbox printed here.

const SRC_REL := "assets_src/enemies/thiccben.png"
const OUT_DIR_REL := "game/content/enemies/thicc_ben/sprites"
const CANVAS := 512
const MARGIN := 6                  # >= 2 px transparent margin on every side
const WHITE_TOL := 45.0            # flood-fill tolerance against pure white background
const HALO_TOL := 128.0            # defringe: clear fg adjacent to bg closer than this to white
const GRADE_MUL := 1.7             # warm gilt lift (fog contrast: art adjusted, never the threshold)
const GRADE_OFF := Vector3(22.0, 18.0, 14.0)
const FLASH_BLEND := 0.78          # attack_arrival pose: blend toward white
const SPAWN_SX := 1.14
const SPAWN_SY := 0.78
const SPAWN_EXTENT := 420          # pre-shrink so the squashed pose keeps the 6 px margin
const RING_EXTENT := 440           # pre-shrink so the +8 deg rock keeps the 6 px margin
const ROCK_DEG := 8.0              # == the anim block attack_ring effect rock_deg (8.0)
const RECOVER_SX := 0.95
const RECOVER_SY := 1.07
const RECOVER_DESAT := 0.4

var _w := 0
var _h := 0
var _px: PackedByteArray = PackedByteArray()
var _bg: PackedByteArray = PackedByteArray()

static func _dist_white(r: float, g: float, b: float) -> float:
	return sqrt(pow(255.0 - r, 2.0) + pow(255.0 - g, 2.0) + pow(255.0 - b, 2.0))


func _seed(x: int, y: int, queue: PackedInt32Array) -> void:
	var i := y * _w + x
	if _bg[i] == 0 and _dist_white(_px[i * 4], _px[i * 4 + 1], _px[i * 4 + 2]) <= WHITE_TOL:
		_bg[i] = 1
		queue.append(i)


func _flood_from_border() -> void:
	var total := _w * _h
	var queue := PackedInt32Array()
	for x in _w:
		_seed(x, 0, queue)
		_seed(x, _h - 1, queue)
	for y in _h:
		_seed(0, y, queue)
		_seed(_w - 1, y, queue)
	var qi := 0
	while qi < queue.size():
		var i := queue[qi]
		qi += 1
		var x := i % _w
		var y := i / _w
		for off in [1, -1, _w, -_w]:
			if off == 1 and x == _w - 1:
				continue  # would wrap to the next row
			if off == -1 and x == 0:
				continue
			var n: int = i + off
			if n < 0 or n >= total:
				continue
			if _bg[n] == 0 and _dist_white(_px[n * 4], _px[n * 4 + 1], _px[n * 4 + 2]) <= WHITE_TOL:
				_bg[n] = 1
				queue.append(n)


func _defringe() -> int:
	# iterate: a foreground pixel adjacent to background and closer than HALO_TOL to white is
	# anti-aliased halo, not body. Clears the white fringe the flood fill leaves behind.
	var cleared := 0
	for _iter in 32:
		var doomed := PackedInt32Array()
		for y in _h:
			for x in _w:
				var i := y * _w + x
				if _bg[i] == 1:
					continue
				var touches_bg := false
				if x > 0 and _bg[i - 1] == 1:
					touches_bg = true
				elif x < _w - 1 and _bg[i + 1] == 1:
					touches_bg = true
				elif y > 0 and _bg[i - _w] == 1:
					touches_bg = true
				elif y < _h - 1 and _bg[i + _w] == 1:
					touches_bg = true
				if touches_bg and _dist_white(_px[i * 4], _px[i * 4 + 1], _px[i * 4 + 2]) < HALO_TOL:
					doomed.append(i)
		if doomed.is_empty():
			return cleared
		for i in doomed:
			_bg[i] = 1
		cleared += doomed.size()
	return cleared


static func _body_bbox(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 16.0 / 255.0:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


static func _blend_white(img: Image, t: float) -> Image:
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			out.set_pixel(x, y, Color(lerpf(c.r, 1.0, t), lerpf(c.g, 1.0, t), lerpf(c.b, 1.0, t), c.a))
	return out


static func _desaturate(img: Image, t: float) -> Image:
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var luma := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			out.set_pixel(x, y, Color(lerpf(c.r, luma, t), lerpf(c.g, luma, t), lerpf(c.b, luma, t), c.a))
	return out


# Inverse-mapped bilinear sample of src through an affine map about a pivot.
# dest = pivot + R(rot) * S(sx, sy) * (src - pivot); sampled premultiplied so transparent
# neighbours do not bleed colour. The map renders onto a padded canvas so poses may overshoot
# the 512 frame mid-transform; _refit crops the alpha bbox and re-anchors afterwards.
# Out-of-range samples stretch edge colours (alpha-renormalised) rather than fading to black.
const PAD := 256

static func _transform(src: Image, sx: float, sy: float, rot_deg: float, pivot: Vector2) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var W := w + 2 * PAD
	var H := h + 2 * PAD
	var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var rad := deg_to_rad(rot_deg)
	var cs := cos(rad)
	var sn := sin(rad)
	# inverse map: src = pivot + S^-1 * R^-1 * (dest - pivot2), pivot2 = pivot + PAD offset
	var pivot2 := pivot + Vector2(PAD, PAD)
	for dy in H:
		for dx in W:
			var ox := float(dx) + 0.5 - pivot2.x
			var oy := float(dy) + 0.5 - pivot2.y
			# R^-1 (rotate by -rad)
			var rx := cs * ox + sn * oy
			var ry := -sn * ox + cs * oy
			var sxr := rx / sx
			var syr := ry / sy
			var px := sxr + pivot.x - 0.5
			var py := syr + pivot.y - 0.5
			var x0 := int(floor(px))
			var y0 := int(floor(py))
			var fx := px - float(x0)
			var fy := py - float(y0)
			var acc_r := 0.0
			var acc_g := 0.0
			var acc_b := 0.0
			var acc_a := 0.0
			var total := 0.0
			for oy2 in [0, 1]:
				for ox2 in [0, 1]:
					var ix: int = x0 + ox2
					var iy: int = y0 + oy2
					var wgt := (fx if ox2 == 1 else 1.0 - fx) * (fy if oy2 == 1 else 1.0 - fy)
					if ix >= 0 and iy >= 0 and ix < src.get_width() and iy < src.get_height():
						var c := src.get_pixel(ix, iy)
						acc_r += c.r * c.a * wgt
						acc_g += c.g * c.a * wgt
						acc_b += c.b * c.a * wgt
						acc_a += c.a * wgt
					total += wgt
			if total > 0.0 and acc_a > 0.0:
				acc_r /= acc_a
				acc_g /= acc_a
				acc_b /= acc_a
				acc_a /= total
				out.set_pixel(dx, dy, Color(acc_r, acc_g, acc_b, acc_a))
	return out


static func _grade(img: Image) -> Image:
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			out.set_pixel(x, y, Color(clampf(c.r * GRADE_MUL + GRADE_OFF.x / 255.0, 0.0, 1.0),
				clampf(c.g * GRADE_MUL + GRADE_OFF.y / 255.0, 0.0, 1.0),
				clampf(c.b * GRADE_MUL + GRADE_OFF.z / 255.0, 0.0, 1.0), c.a))
	return out


static func _premultiply(img: Image) -> Image:
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			out.set_pixel(x, y, Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a))
	return out


static func _unpremultiply(img: Image) -> Image:
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(c.r / c.a, c.g / c.a, c.b / c.a, c.a))
	return out


# Crop a transformed frame to its alpha bbox and re-fit bottom-anchored onto a fresh canvas,
# so any pose (rotation, squash) is guaranteed the transparent margin on every side.
static func _refit(img: Image) -> Image:
	var bbox := _body_bbox(img)
	if bbox.size.x <= 0 or bbox.size.y <= 0:
		return img
	return _fit_canvas(img.get_region(bbox), CANVAS - 2 * MARGIN)


static func _fit_canvas(body: Image, extent: int = CANVAS - 2 * MARGIN) -> Image:
	var bw := body.get_width()
	var bh := body.get_height()
	var fit := minf(float(extent) / float(bw), float(extent) / float(bh))
	var nw := maxi(1, int(floor(float(bw) * fit)))
	var nh := maxi(1, int(floor(float(bh) * fit)))
	var resized := _premultiply(body)
	resized.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
	var canvas := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var ox := int((CANVAS - nw) / 2)
	var oy := CANVAS - MARGIN - nh   # bottom-anchored: the tower stands on the ground
	canvas.blit_rect(resized, Rect2i(0, 0, nw, nh), Vector2i(ox, oy))
	return _unpremultiply(canvas)


static func _stats(label: String, img: Image) -> Rect2i:
	var bbox := _body_bbox(img)
	var w := img.get_width()
	var h := img.get_height()
	var transparent := 0
	var opaque := 0
	var rr := 0.0
	var gg := 0.0
	var bb := 0.0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a == 0.0:
				transparent += 1
			if c.a >= 128.0 / 255.0:
				opaque += 1
				rr += c.r
				gg += c.g
				bb += c.b
	var tpct := 100.0 * float(transparent) / float(w * h)
	var mean := Color(rr / opaque, gg / opaque, bb / opaque) if opaque > 0 else Color(0, 0, 0)
	print("STAT %s bbox=[%d, %d, %d, %d] transparent=%.1f%% mean=(%.3f, %.3f, %.3f)" % [
		label, bbox.position.x, bbox.position.y, bbox.size.x, bbox.size.y, tpct, mean.r, mean.g, mean.b])
	return bbox


func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var root := game_dir.path_join("..").simplify_path()
	var src := root.path_join(SRC_REL)
	var out_dir := root.path_join(OUT_DIR_REL)
	var img := Image.load_from_file(src)
	if img == null:
		printerr("thicc_ben: cannot load %s" % src)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	_w = img.get_width()
	_h = img.get_height()
	_px = img.get_data()
	_bg = PackedByteArray()
	_bg.resize(_w * _h)
	_bg.fill(0)
	print("thicc_ben: loaded %s (%dx%d)" % [src, _w, _h])
	_flood_from_border()
	var defringed := _defringe()
	var bg_count := 0
	for v in _bg:
		bg_count += v
	print("thicc_ben: background cleared %d px (%.1f%%, defringe %d)" % [
		bg_count, 100.0 * float(bg_count) / float(_w * _h), defringed])
	# cut the background (and its colour bleed) out of the body
	for i in _bg.size():
		if _bg[i] == 1:
			_px[i * 4] = 0
			_px[i * 4 + 1] = 0
			_px[i * 4 + 2] = 0
			_px[i * 4 + 3] = 0
	var keyed := Image.create_from_data(_w, _h, false, Image.FORMAT_RGBA8, _px)
	var crop_rect := _body_bbox(keyed)
	if crop_rect.size.x <= 0 or crop_rect.size.y <= 0:
		printerr("thicc_ben: NO BODY AFTER BACKGROUND REMOVAL")
		quit(1)
		return
	print("thicc_ben: body bbox %s" % crop_rect)
	var body := keyed.get_region(crop_rect)
	body = _grade(body)
	var base := _fit_canvas(body)
	var spawn_body := _fit_canvas(body, SPAWN_EXTENT)
	var ring_body := _fit_canvas(body, RING_EXTENT)
	var pivot := Vector2(float(CANVAS) / 2.0, float(CANVAS - MARGIN))
	var frames := {
		"cycle_00.png": base,
		"spawn_00.png": _refit(_transform(spawn_body, SPAWN_SX, SPAWN_SY, 0.0, pivot)),
		"attack_arrival_00.png": _blend_white(base, FLASH_BLEND),
		"attack_ring_00.png": _refit(_transform(ring_body, 1.0, 1.0, ROCK_DEG, pivot)),
		"recover_00.png": _desaturate(_refit(_transform(base, RECOVER_SX, RECOVER_SY, 0.0, pivot)), RECOVER_DESAT),
	}
	for fname in frames:
		var fimg: Image = frames[fname]
		_stats(fname, fimg)
		var err := fimg.save_png(out_dir.path_join(fname))
		if err != OK:
			printerr("thicc_ben: save_png %s failed (%d)" % [fname, err])
			quit(1)
			return
	print("thicc_ben: wrote %d frames to %s" % [frames.size(), out_dir])
	quit(0)


