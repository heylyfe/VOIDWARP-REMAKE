extends SceneTree
#
# game/tools/art/address_me.gd - address me sprites (art ticket ART-ADDRESS_ME, headless).
#
#   "<godot>" --headless --path game --script res://tools/art/address_me.gd
#
# Turns the two owner sources into the six real frame PNGs under
# game/content/enemies/address_me/sprites/. Deterministic: no randomness anywhere.
#
# Sources:
#   assets_src/enemies/address me elephant.png (1080x726, RGBA, opaque photo of the
#       "address me" elephant meme; grey room, dark furniture in front of the legs,
#       white "Address me" lettering struck across the lower third)
#   assets_src/enemies/explosionsffect.jpg (736x740, RGB, the explosion frame: a big
#       fireball with the tabby cat in front; grey sky, blue-grey beach)
#
# Background removal, per image (the shared pipeline's corner flood fill cannot do these):
#   elephant : flood fill from the image border with neighbour-step colour distance
#              30, blocked by a hand-traced sure-foreground polygon around the
#              silhouette (the room is the same mid-grey as the hide, so colour
#              alone cannot separate them). Enclosed background islands are refilled,
#              the largest connected component is kept, and the white meme lettering
#              that falls OUTSIDE the silhouette (it struck the whole room) is removed;
#              lettering on the hide stays - it is part of the meme.
#   explosion: border flood (same rule) is useless here - the fireball fades into
#              sky/beach over smooth gradients, so the global rule "warm (r > b+10)
#              or bright (max >= 175)" picks the body; the cat's neutral-dark pixels
#              that fail it are protected by a sure-foreground polygon of the cat;
#              largest component wins, enclosed islands refilled.
#
# Frames (binding counts from the T-083 anim block, unchanged): each state's frame is
# derived from the cutouts - spawn: brightness flash (the trumpet tell); telegraph:
# desaturated, dimmed (the held breath before the ring); leaves: 1.18x / 0.78y squash
# (the anticipation of shrink_to_0); attack: the spec's explode frame, Image 14
# composited over the elephant at 30% alpha; cycle_00/cycle_01: the plain/ghosted-base
# normal and explode frames the view pins by index.
const FIT := 448              # body fit inside the 512 canvas (portrait crops stay >= 64 px of margin total)
const MARGIN := 4             # transparent margin on every side (validator: no opaque pixel within 2 px of an edge)
const CANVAS := 512
const LETTER_BAND_Y := 455    # the white "Address me" strike runs y ~ 460..610
const LETTER_MIN := 150       # letters are neutral-white; hide pixels in the band are far darker
const FLOOD_T := 30.0         # neighbour-step colour distance for the border flood
const ALPHA_HIT := 16.0 / 255.0


func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var repo_dir := game_dir.get_base_dir()
	var src_ele := repo_dir + "/assets_src/enemies/address me elephant.png"
	var src_exp := repo_dir + "/assets_src/enemies/explosionsffect.jpg"
	var out_dir := game_dir + "/content/enemies/address_me/sprites/"
	print("ART-ADDRESS_ME src ", src_ele)
	print("ART-ADDRESS_ME src ", src_exp)
	var ele := Image.load_from_file(src_ele)
	var exp := Image.load_from_file(src_exp)
	if ele == null or exp == null:
		push_error("ART-ADDRESS_ME: cannot load a source image")
		quit(1)
		return
	if ele.get_format() != Image.FORMAT_RGBA8:
		ele.convert(Image.FORMAT_RGBA8)
	if exp.get_format() != Image.FORMAT_RGBA8:
		exp.convert(Image.FORMAT_RGBA8)
	var ele_mask: Array = _elephant_mask(ele)
	var exp_mask: Array = _explosion_mask(exp)
	var ele_body := _fog_lift(_cutout(ele, ele_mask[0], ele_mask[1]))
	var exp_body := _cutout(exp, exp_mask[0], exp_mask[1])
	var cycle_00 := _fit_canvas(ele_body, 1.0, 1.0)
	var cycle_01 := _composite_attack(ele_body, exp_body)
	var spawn_00 := _fit_canvas(_brightness(ele_body, 1.16), 1.0, 1.0)
	var telegraph_00 := _fit_canvas(_desat_dim(ele_body, 0.45, 1.0), 1.0, 1.0)
	var leaves_00 := _squash_canvas(ele_body, 1.18, 0.78)
	var attack_00: Image = cycle_01.duplicate()
	_write(out_dir, "cycle_00.png", cycle_00)
	_write(out_dir, "cycle_01.png", cycle_01)
	_write(out_dir, "spawn_00.png", spawn_00)
	_write(out_dir, "telegraph_00.png", telegraph_00)
	_write(out_dir, "leaves_00.png", leaves_00)
	_write(out_dir, "attack_00.png", attack_00)
	for pair in [["cycle_00", cycle_00], ["cycle_01", cycle_01], ["spawn_00", spawn_00], ["telegraph_00", telegraph_00], ["leaves_00", leaves_00], ["attack_00", attack_00]]:
		var rect := _tight_bbox(pair[1])
		print("ART-ADDRESS_ME RECT ", pair[0], " [", rect.position.x, ", ", rect.position.y, ", ", rect.size.x, ", ", rect.size.y, "]")
	print("ART-ADDRESS_ME DONE")
	quit(0)


# ---- masks -------------------------------------------------------------------

# Scanline polygon fill: 1 where the point is inside the polygon, else 0.
func _poly_mask(w: int, h: int, pts: Array) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(w * h)
	mask.fill(0)
	var n := pts.size()
	for y in h:
		var xs: Array = []
		for i in n:
			var a: Vector2i = pts[i]
			var b: Vector2i = pts[(i + 1) % n]
			if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
				var t := float(y - a.y) / float(b.y - a.y)
				xs.append(a.x + t * (b.x - a.x))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			var x0 := int(ceil(xs[k]))
			var x1 := int(floor(xs[k + 1]))
			for x in range(maxi(x0, 0), mini(x1, w - 1) + 1):
				mask[y * w + x] = 1
			k += 2
	return mask


# BFS flood from the border. can_enter(j, i) gates entry onto pixel j from neighbour i.
func _border_flood(w: int, h: int, can_enter: Callable) -> PackedByteArray:
	var bg := PackedByteArray()
	bg.resize(w * h)
	bg.fill(0)
	var queue: Array = []
	for x in w:
		for y: int in [0, h - 1]:
			var i := y * w + x
			if bg[i] == 0:
				bg[i] = 1
				queue.append(i)
	for y in h:
		for x: int in [0, w - 1]:
			var i := y * w + x
			if bg[i] == 0:
				bg[i] = 1
				queue.append(i)
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var y := i / w
		var x := i % w
		for off in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
			var ny: int = y + int(off[0])
			var nx: int = x + int(off[1])
			if ny < 0 or ny >= h or nx < 0 or nx >= w:
				continue
			var j := ny * w + nx
			if bg[j] == 1:
				continue
			if can_enter.call(j, i):
				bg[j] = 1
				queue.append(j)
	return bg


func _largest_component(fg: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var label := PackedInt32Array()
	label.resize(w * h)
	label.fill(-1)
	var sizes: Dictionary = {}
	var cur := 0
	for sy in h:
		for sx in w:
			var s := sy * w + sx
			if fg[s] != 1 or label[s] != -1:
				continue
			var queue: Array = [s]
			label[s] = cur
			var count := 0
			var head := 0
			while head < queue.size():
				var i: int = queue[head]
				head += 1
				count += 1
				var y := i / w
				var x := i % w
				for off in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
					var ny: int = y + int(off[0])
					var nx: int = x + int(off[1])
					if ny < 0 or ny >= h or nx < 0 or nx >= w:
						continue
					var j := ny * w + nx
					if fg[j] == 1 and label[j] == -1:
						label[j] = cur
						queue.append(j)
			sizes[cur] = count
			cur += 1
	var keep := -1
	var best := -1
	for k in sizes.keys():
		if int(sizes[k]) > best:
			best = int(sizes[k])
			keep = int(k)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in w * h:
		out[i] = 1 if label[i] == keep else 0
	return out


# Enclosed !fg islands become fg (the flood leaves interior specks of shirt/reflection out).
func _fill_holes(fg: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var inv := PackedByteArray()
	inv.resize(w * h)
	for i in w * h:
		inv[i] = 0 if fg[i] == 1 else 1
	var reach := _border_flood(w, h, func(j: int, i: int) -> bool: return inv[j] == 1)
	var out := PackedByteArray()
	out.resize(w * h)
	for i in w * h:
		out[i] = 1 if fg[i] == 1 or reach[i] == 0 else 0
	return out


# Dilate a 0/1 mask by r iterations of 4-neighbour growth (letter rim eat).
func _dilate(mask: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	var m := mask
	for _i in r:
		var d := m.duplicate()
		for y in h:
			for x in w:
				var i := y * w + x
				if m[i] == 1:
					continue
				var hit := false
				if x > 0 and m[i - 1] == 1:
					hit = true
				elif x < w - 1 and m[i + 1] == 1:
					hit = true
				elif y > 0 and m[i - w] == 1:
					hit = true
				elif y < h - 1 and m[i + w] == 1:
					hit = true
				if hit:
					d[i] = 1
		m = d
	return m


# The elephant: sure-foreground polygon (hand-traced interior silhouette) + neighbour-step
# border flood, hole refill, largest component; the white meme strike OUTSIDE the polygon
# is removed afterwards (inside it, it is the meme and stays).
func _elephant_mask(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var sure_fg := _poly_mask(w, h, [
		Vector2i(185, 250), Vector2i(210, 215), Vector2i(320, 185), Vector2i(420, 165),
		Vector2i(520, 158), Vector2i(640, 158), Vector2i(700, 165), Vector2i(735, 195),
		Vector2i(758, 235), Vector2i(768, 275), Vector2i(742, 300), Vector2i(738, 330),
		Vector2i(745, 400), Vector2i(752, 470), Vector2i(762, 545), Vector2i(748, 615),
		Vector2i(700, 615), Vector2i(688, 540), Vector2i(668, 460), Vector2i(650, 440),
		Vector2i(655, 535), Vector2i(575, 535), Vector2i(572, 425), Vector2i(555, 430),
		Vector2i(540, 500), Vector2i(528, 585), Vector2i(460, 585), Vector2i(452, 470),
		Vector2i(400, 450), Vector2i(330, 445), Vector2i(300, 432), Vector2i(268, 430),
		Vector2i(268, 490), Vector2i(150, 490), Vector2i(150, 380), Vector2i(218, 410),
		Vector2i(196, 340), Vector2i(185, 260),
	])
	var flood := _border_flood(w, h, func(j: int, i: int) -> bool:
		if sure_fg[j] == 1:
			return false
		var dr := float(d[j * 4]) - float(d[i * 4])
		var dg := float(d[j * 4 + 1]) - float(d[i * 4 + 1])
		var db := float(d[j * 4 + 2]) - float(d[i * 4 + 2])
		return sqrt(dr * dr + dg * dg + db * db) <= FLOOD_T)
	var fg := PackedByteArray()
	fg.resize(w * h)
	for i in w * h:
		fg[i] = 0 if flood[i] == 1 else 1
	fg = _fill_holes(fg, w, h)
	fg = _largest_component(fg, w, h)
	# white meme strike: neutral-white pixels in the letter band are letter paint.
	# Letters ON the body (fg==1, e.g. the strike across the legs) are inpainted with
	# the surrounding hide colour (diffusion from the border of each letter shape);
	# letters off the body are nowhere near fg and drop out with the component cut.
	var letters := PackedByteArray()
	letters.resize(w * h)
	letters.fill(0)
	for y in range(LETTER_BAND_Y, h):
		for x in w:
			var i := y * w + x
			var r := d[i * 4]
			var g := d[i * 4 + 1]
			var b := d[i * 4 + 2]
			var mx := maxi(maxi(r, g), b)
			var mn := mini(mini(r, g), b)
			if mn > LETTER_MIN and mx - mn < 60:
				letters[i] = 1
	letters = _dilate(letters, w, h, 2)
	return [fg, letters]


# The explosion: global rule "warm (r > b + 10) or bright (max >= 175)"; the cat's
# neutral-dark pixels fail it, so a cat-silhouette polygon protects them; largest
# component wins, enclosed islands refilled.
func _explosion_mask(img: Image) -> Array:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var cat := _poly_mask(w, h, [
		Vector2i(340, 340), Vector2i(365, 380), Vector2i(320, 400), Vector2i(290, 455),
		Vector2i(300, 600), Vector2i(315, 715), Vector2i(540, 715), Vector2i(555, 560),
		Vector2i(545, 445), Vector2i(520, 395), Vector2i(470, 375), Vector2i(490, 330),
		Vector2i(420, 360), Vector2i(375, 360),
	])
	var fg := PackedByteArray()
	fg.resize(w * h)
	for i in w * h:
		var r := d[i * 4]
		var b := d[i * 4 + 2]
		var mx := maxi(maxi(d[i * 4], d[i * 4 + 1]), d[i * 4 + 2])
		var warm := r > b + 10
		var bright := mx >= 175
		fg[i] = 1 if (warm or bright or cat[i] == 1) else 0
	fg = _largest_component(fg, w, h)
	fg = _fill_holes(fg, w, h)
	var empty := PackedByteArray()
	empty.resize(w * h)
	return [fg, empty]


# Tight crop of the source to the mask (alpha > 16), alpha from the mask. Letters that
# survive inside fg (paint ON the hide) are diffused inward from their borders with the
# surrounding hide colour.
func _cutout(img: Image, mask: PackedByteArray, paint := PackedByteArray()) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				if x < x0:
					x0 = x
				if x > x1:
					x1 = x
				if y < y0:
					y0 = y
				if y > y1:
					y1 = y
	var cw := x1 - x0 + 1
	var ch := y1 - y0 + 1
	var d := img.get_data()
	var out := PackedByteArray()
	out.resize(cw * ch * 4)
	for yy in ch:
		for xx in cw:
			var si := ((y0 + yy) * w + (x0 + xx)) * 4
			var di := (yy * cw + xx) * 4
			out[di] = d[si]
			out[di + 1] = d[si + 1]
			out[di + 2] = d[si + 2]
			out[di + 3] = 255 if mask[(y0 + yy) * w + (x0 + xx)] == 1 else 0
	# inpaint: pixels in `paint` that are on the body take the nearest non-paint colour,
	# filled inward sweep by sweep (letters on the hide are paint, the hide is not)
	if paint.size() == mask.size():
		var done := PackedByteArray()
		done.resize(cw * ch)
		done.fill(0)
		var remaining := 0
		for yy in ch:
			for xx in cw:
				var mi := (y0 + yy) * w + (x0 + xx)
				var di := yy * cw + xx
				if paint[mi] == 1 and mask[mi] == 1:
					remaining += 1
				else:
					done[di] = 1
		var sweep := 0
		while remaining > 0 and sweep < 128:
			sweep += 1
			var changed := false
			for i in cw * ch:
				if done[i] == 1:
					continue
				var y := i / cw
				var x := i % cw
				var nb := -1
				for off in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
					var ny := y + int(off[0])
					var nx := x + int(off[1])
					if ny < 0 or ny >= ch or nx < 0 or nx >= cw:
						continue
					var j := ny * cw + nx
					if done[j] == 1:
						nb = j
						break
				if nb >= 0:
					out[i * 4] = out[nb * 4]
					out[i * 4 + 1] = out[nb * 4 + 1]
					out[i * 4 + 2] = out[nb * 4 + 2]
					done[i] = 1
					remaining -= 1
					changed = true
			if not changed:
				break
	return Image.create_from_data(cw, ch, false, Image.FORMAT_RGBA8, out)


# Lift the cutout toward white so the mean opaque colour clears the fog-contrast bar
# (ENEMIES.md hard rule, WCAG >= 3.0 vs #021416 at 40 u) - the art moves, never the
# threshold. Adds +10/255 on sRGB channels and scales x1.16.
func _fog_lift(img: Image) -> Image:
	var out: Image = img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var p := out.get_pixel(x, y)
			out.set_pixel(x, y, Color(minf(p.r * 1.22 + 14.0 / 255.0, 1.0), minf(p.g * 1.22 + 14.0 / 255.0, 1.0), minf(p.b * 1.22 + 14.0 / 255.0, 1.0), p.a))
	return out


# ---- frame transforms ----------------------------------------------------------

func _brightness(img: Image, factor: float) -> Image:
	var out: Image = img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var p := out.get_pixel(x, y)
			out.set_pixel(x, y, Color(p.r * factor, p.g * factor, p.b * factor, p.a))
	return out


func _desat_dim(img: Image, desat: float, dim: float) -> Image:
	var out: Image = img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var p := out.get_pixel(x, y)
			var lum := (p.r + p.g + p.b) / 3.0
			var nr := (lum + (p.r - lum) * (1.0 - desat)) * dim
			var ng := (lum + (p.g - lum) * (1.0 - desat)) * dim
			var nb := (lum + (p.b - lum) * (1.0 - desat)) * dim
			out.set_pixel(x, y, Color(nr, ng, nb, p.a))
	return out


# Transparent 512x512 canvas, body scaled to FIT preserving aspect, centred horizontally,
# bottom-anchored (the enemy stands on the ground).
func _fit_canvas(body: Image, grow_x: float, grow_y: float) -> Image:
	var canvas := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	var fit := FIT
	var bw := body.get_width()
	var bh := body.get_height()
	if grow_x != 1.0 or grow_y != 1.0:
		bw = maxi(1, int(bw * grow_x))
		bh = maxi(1, int(bh * grow_y))
	var s := float(fit) / float(maxi(bw, bh))
	var nw := maxi(1, int(bw * s))
	var nh := maxi(1, int(bh * s))
	var scaled: Image = body.duplicate()
	scaled.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	canvas.blit_rect(scaled, Rect2i(0, 0, nw, nh), Vector2i((CANVAS - nw) / 2, CANVAS - MARGIN - nh))
	return canvas


# Squash preview: 1.18x wider, 0.78x shorter - the anticipation of shrink_to_0.
func _squash_canvas(body: Image, gx: float, gy: float) -> Image:
	var squashed: Image = body.duplicate()
	squashed.resize(maxi(1, int(body.get_width() * gx)), maxi(1, int(body.get_height() * gy)), Image.INTERPOLATE_LANCZOS)
	return _fit_canvas(squashed, 1.0, 1.0)


# The spec's explode frame: Image 14 composited over the elephant at 30% alpha.
func _composite_attack(ele_body: Image, exp_body: Image) -> Image:
	var canvas := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	# elephant ghost at 30% alpha
	var s := float(FIT) / float(maxi(ele_body.get_width(), ele_body.get_height()))
	var nw := maxi(1, int(ele_body.get_width() * s))
	var nh := maxi(1, int(ele_body.get_height() * s))
	var ghost: Image = ele_body.duplicate()
	ghost.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	for y in nh:
		for x in nw:
			var p := ghost.get_pixel(x, y)
			ghost.set_pixel(x, y, Color(p.r, p.g, p.b, p.a * 0.30))
	canvas.blit_rect(ghost, Rect2i(0, 0, nw, nh), Vector2i((CANVAS - nw) / 2, CANVAS - MARGIN - nh))
	# the explosion over it
	var s2 := float(FIT) / float(maxi(exp_body.get_width(), exp_body.get_height()))
	var nw2 := maxi(1, int(exp_body.get_width() * s2))
	var nh2 := maxi(1, int(exp_body.get_height() * s2))
	var fire: Image = exp_body.duplicate()
	fire.resize(nw2, nh2, Image.INTERPOLATE_LANCZOS)
	canvas.blend_rect(fire, Rect2i(0, 0, nw2, nh2), Vector2i((CANVAS - nw2) / 2, CANVAS - MARGIN - nh2))
	return canvas


func _tight_bbox(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > ALPHA_HIT:
				if x < x0:
					x0 = x
				if x > x1:
					x1 = x
				if y < y0:
					y0 = y
				if y > y1:
					y1 = y
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _write(out_dir: String, file: String, img: Image) -> void:
	var path := out_dir + file
	var err := img.save_png(path)
	if err != OK:
		push_error("ART-ADDRESS_ME: cannot write " + path)
		quit(1)

