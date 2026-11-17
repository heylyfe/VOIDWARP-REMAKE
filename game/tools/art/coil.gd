extends SceneTree
#
# game/tools/art/coil.gd - the coil's own art module (T-016/T-083; the shared pipeline
# game/tools/sprite_pipeline.gd SKIPS any enemy with an art module, so this module owns
# coil's frames end to end and a later pipeline rebuild cannot regress them).
#
#   "<godot>" --headless --path game --script res://tools/art/coil.gd
#
# Source: assets_src/enemies/springer.png (840x859, the owner photo of the metal spring;
# the corners are OPAQUE white / near-white, so the pipeline's 24/255 corner flood fill
# eats the whole image and the pipeline reports "NO BODY AFTER BACKGROUND REMOVAL -> TBD").
#
# Deterministic (no randomness anywhere):
# 1. Loads the source with Image.load_from_file from a filesystem path (never res://).
# 2. Removes the background: the photo's backdrop is a flat near-white checkerboard of
#    ~238/255 grays. Flood fill from every border pixel eats any pixel whose darkest
#    channel is >= BG_MIN (233); the metal wires dunk to ~100 so they block the fill;
#    the bright inner wire highlights (>= 233) survive because they are enclosed by
#    darker wire and never reached from the border. The stray sub-233 anti-alias specks
#    the fill strands inside the backdrop are erased by keeping only the largest
#    connected opaque component.
# 3. Crops tight to the body (alpha > 16/255, the HITBOXES rule).
# 4. Fits the body on a 512x512 power-of-two canvas, bottom-anchored (the spring stands
#    on the ground), MARGIN (8 px) transparent on every edge (>= the required 2 px).
# 5. Emits the 5 cycle frames of the T-083 anim block (coil_00..coil_04, the ENEMIES.md
#    squash -> extend cycle) from the one base body: vertical scale 50/65/80/100/120%
#    of the base with inverse-sqrt width compensation sx = 1/sqrt(sy) (the squashed
#    spring widens, the extended one thins). The frame COUNT, the file names, the tick
#    ranges, the loop flags and the effect parameters of the anim block are untouched;
#    the block's effects (spawn fade, red ring, shockwave) are shader-side and never
#    change body_rect.
# 6. Writes game/content/enemies/coil/sprites/cycle_00..04.png and prints each frame's
#    body_rect (tight bbox of alpha > 16) for pasting into sprites.json. sprites.json is
#    NOT rewritten here: a JSON re-serialization would churn the T-083 anim block's
#    formatting and its (pre-existing) mojibake, so the rects are edited in by hand.
#
# See DECISIONS.md D-ART-COIL-1 for the numbers no document states (SPEC GAPs).

const SRC_REL := "assets_src/enemies/springer.png"   # repo-root relative
const OUT_REL := "content/enemies/coil/sprites"
const CANVAS := 512
const MARGIN := 8
const BASE_H := 400.0
const BG_MIN := 233
const BODY_A_THR := 16.0 / 255.0     # alpha > 16/255 defines the body (HITBOXES)
const SQUASH_PCTS := [50, 65, 80, 100, 120]

func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var root := game_dir.get_base_dir()
	var src_path := root + "/" + SRC_REL
	var out_dir := game_dir + "/" + OUT_REL
	var src := Image.load_from_file(src_path)
	if src == null:
		print("COIL ART FAILED: cannot load %s" % src_path)
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	var body := _cut_backdrop(src)
	if body == null:
		print("COIL ART FAILED: no body after background removal")
		quit(1)
		return
	var crop := _crop_tight(body)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for f in range(SQUASH_PCTS.size()):
		var frame := _squash_frame(crop, SQUASH_PCTS[f])
		var out_path := "%s/cycle_%02d.png" % [out_dir, f]
		if frame.save_png(out_path) != OK:
			print("COIL ART FAILED: cannot write %s" % out_path)
			quit(1)
			return
		var rect := _body_bbox(frame)
		print("COIL ART cycle_%02d.png %dx%d body_rect=[%d, %d, %d, %d]" % [f, CANVAS, CANVAS, rect[0], rect[1], rect[2], rect[3]])
	print("COIL ART OK %d frames -> %s" % [SQUASH_PCTS.size(), out_dir])
	quit(0)


# Flood-fill the near-white backdrop away from the border; keep only the largest
# connected opaque component (erases the stray specks the fill strands).
func _cut_backdrop(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var data := src.get_data()      # RGBA8 bytes
	var n := w * h
	var state := PackedByteArray()  # 0 unvisited, 1 = backdrop (erase), 2 = body (keep)
	state.resize(n)
	state.fill(0)
	var stack: Array[int] = []
	for x in range(w):
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in range(h):
		stack.append(y * w)
		stack.append(y * w + w - 1)
	var bg_min := float(BG_MIN) / 255.0
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if state[i] != 0:
			continue
		var o := i * 4
		var mn := minf(float(data[o]), minf(float(data[o + 1]), float(data[o + 2]))) / 255.0
		if mn < bg_min:
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
			data[i * 4 + 3] = 0
	# label connected opaque components; erase every component but the largest
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
	var body := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	return body


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
	return img.get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))


# One cycle frame: the base body squashed/extended vertically (sx = 1/sqrt(sy)),
# bottom-anchored on the transparent 512x512 canvas.
func _squash_frame(crop: Image, pct: int) -> Image:
	var sy := float(pct) / 100.0
	var sx := 1.0 / sqrt(sy)
	var base_scale := BASE_H / float(crop.get_height())
	var w0 := int(round(crop.get_width() * base_scale))
	var h0 := int(round(BASE_H))
	var w := int(round(w0 * sx))
	var h := int(round(h0 * sy))
	var resized := crop.duplicate()
	resized.resize(w, h, Image.INTERPOLATE_LANCZOS)
	var canvas := Image.create_empty(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	canvas.blit_rect(resized, Rect2i(0, 0, w, h), Vector2i((CANVAS - w) / 2, CANVAS - MARGIN - h))
	return canvas


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
