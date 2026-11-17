extends SceneTree
#
# game/tools/art/kiwi_cat.gd - kiwi cat sprite art (ticket T-ART-KIWI_CAT, headless).
#
#   tools\godot\godot.exe --headless --path game --script res://tools/art/kiwi_cat.gd
#
# Owns kiwi_cat's frames (sprite_pipeline.gd SKIPS any enemy with a module here, so a
# pipeline rebuild cannot regress this enemy back to the naive corner flood fill).
# Deterministic: every frame is a pure function of the source image - no RNG, no wall
# clock, byte-stable across rebuilds.
#
# The source (assets_src/enemies/kiwicat.png, 636x769) ships with an alpha channel and
# alpha-0 corners (the curled kitten is cut out already), so the background mask is the
# alpha channel itself; the border flood fill below is the fallback for a source whose
# corners are opaque, and is skipped when the corners are already alpha 0.
#
# Frames (the T-083 anim block lists one spec frame, kiwicat_00, per visual state):
#   cycle_00.png      the base body, unaltered (the legacy single-frame "cycle" loop)
#   spawn_00.png      base at 1.25x brightness (the materialize shimmer; the fade itself
#                     is the common_fade shader effect - alpha 0 -> 1, scale 0.8 -> 1.0)
#   idle_chase_00.png base squashed to 96% height about the bottom line (a breathing
#                     compression; the y bob +-0.08 u at 1.0 Hz stays the bob effect)
#   telegraph_00.png  base blended 30% toward danger red #FF2A2A at 1.15x brightness
#                     (the meow tell; scale pulse 1.0 -> 1.12 -> 1.0 stays the effect)
# All frames are bottom-anchored on a 512x512 canvas (the cat stands on the ground),
# power-of-two, with a transparent margin of at least 2 px on every side.

const MAX_CANVAS := 512
const MIN_MARGIN := 2
const BODY_ALPHA := 16.0            # alpha > 16 defines the body (HITBOXES)
const BG_TOL := 24                  # per-channel background tolerance (fallback fill)
const SRC_REL := "assets_src/enemies/kiwicat.png"
const OUT_REL := "content/enemies/kiwi_cat/sprites"
# A8 fog-contrast art lift (see DECISIONS D-ART-KIWI_CAT-2/3): the source's mean opaque
# colour washes out against the #021416 fog at 40 u, so the body is lifted uniformly.
const BODY_LIFT := 1.22
const SPAWN_LIFT := 1.25
const IDLE_SQUASH := 0.96
const TELEGRAPH_TINT := 0.3         # blend toward danger red #FF2A2A
const TELEGRAPH_LIFT := 1.15
const DANGER_RED := Color(1.0, 42.0 / 255.0, 42.0 / 255.0, 1.0)
const POT_LADDER := [16, 32, 64, 128, 256, 512]

# ---- image plumbing -----------------------------------------------------------------------------

static func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img: Image = Image.load_from_file(path)
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


# Background removal that works for THIS image: the source is cut out on an alpha
# channel (all four corners are alpha 0), so the alpha channel is the mask and no
# colour-keying is applied. Fallback (kept for a re-export with opaque corners): sample
# the border colours, flood fill inward from every border pixel at per-channel distance
# <= BG_TOL, and zero the alpha of everything the fill reaches.
static func _strip_background(img: Image) -> void:
	@warning_ignore("integer_division")
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var corners := [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]
	var corners_clear := true
	for c in corners:
		if data[((c.y * w) + c.x) * 4 + 3] != 0:
			corners_clear = false
			break
	if corners_clear:
		print("kiwi_cat: corners already alpha 0 - using the source's alpha channel as the background mask")
		return
	var refs: Array = []
	for x in range(0, w, 8):
		refs.append([data[x * 4], data[x * 4 + 1], data[x * 4 + 2]])
		refs.append([data[((h - 1) * w + x) * 4], data[((h - 1) * w + x) * 4 + 1], data[((h - 1) * w + x) * 4 + 2]])
	for y in range(0, h, 8):
		refs.append([data[(y * w) * 4], data[(y * w) * 4 + 1], data[(y * w) * 4 + 2]])
		refs.append([data[(y * w + w - 1) * 4], data[(y * w + w - 1) * 4 + 1], data[(y * w + w - 1) * 4 + 2]])
	var visited := PackedByteArray()
	visited.resize(w * h)
	var stack: Array[int] = []
	for x in w:
		stack.append(x)
		stack.append((h - 1) * w + x)
	for y in h:
		stack.append(y * w)
		stack.append(y * w + w - 1)
	for pi in stack:
		visited[pi] = 1
	while not stack.is_empty():
		var pi: int = stack.pop_back()
		var base := pi * 4
		var hit := data[base + 3] == 0
		if not hit:
			for ref in refs:
				if absi(data[base] - ref[0]) <= BG_TOL and absi(data[base + 1] - ref[1]) <= BG_TOL \
						and absi(data[base + 2] - ref[2]) <= BG_TOL:
					hit = true
					break
		if not hit:
			continue
		data[base + 3] = 0
		var x: int = pi % w
		var y: int = pi / w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or nx >= w or ny < 0 or ny >= h:
				continue
			var np: int = ny * w + nx
			if visited[np] == 0:
				visited[np] = 1
				stack.push_back(np)
	img.set_data(w, h, false, Image.FORMAT_RGBA8, data)
	print("kiwi_cat: opaque corners - removed the background with a border flood fill (tol %d)" % BG_TOL)


# Tight crop to the body: the bbox of pixels with alpha > 16 (HITBOXES). null when the
# source has no body at all.
static func _crop_body(img: Image) -> Image:
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
		return null
	return img.get_region(Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1))


static func _body_rect(img: Image) -> Rect2i:
	@warning_ignore("integer_division")
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


# Uniform brightness lift (clamped to 1.0 per channel), alpha untouched: the A8 fog-contrast
# art adjustment. Deterministic.
static func _brightness(img: Image, factor: float) -> Image:
	var out: Image = img.duplicate()
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(minf(1.0, c.r * factor), minf(1.0, c.g * factor),
						minf(1.0, c.b * factor), c.a))
	return out


# Vertical squash towards the resting base line (the bottom edge stays put): the breathing
# compression for the idle / chase pose.
static func _squash(img: Image, pct: float) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var nh := maxi(1, int(round(h * pct)))
	var out: Image = img.duplicate()
	out.resize(w, nh, Image.INTERPOLATE_LANCZOS)
	return out


# Telegraph flash: blend every body pixel toward danger red #FF2A2A (the only colour the
# spec uses for telegraph flashes), then lift. The scale pulse stays the telegraph's effect.
static func _telegraph_flash(img: Image, tint: float, lift: float) -> Image:
	var out: Image = img.duplicate()
	for y in range(out.get_height()):
		for x in range(out.get_width()):
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				var t := c.lerp(DANGER_RED, tint)
				out.set_pixel(x, y, Color(minf(1.0, t.r * lift), minf(1.0, t.g * lift),
						minf(1.0, t.b * lift), t.a))
	return out


# Fit the body onto a power-of-two canvas (max 512), bottom-anchored with a >= 2 px
# transparent margin on every side (the cat stands on the ground; the billboard puts the
# body's bottom on the node origin).
static func _fit_pot(body: Image) -> Image:
	var w := body.get_width()
	var h := body.get_height()
	var canvas := MAX_CANVAS
	for v in POT_LADDER:
		if v >= w + 2 * MIN_MARGIN and v >= h + 2 * MIN_MARGIN:
			canvas = v
			break
	var out := Image.create_empty(canvas, canvas, false, Image.FORMAT_RGBA8)
	@warning_ignore("integer_division")
	var dx: int = (canvas - w) / 2
	var dy: int = canvas - h - MIN_MARGIN
	out.blend_rect(body, Rect2i(0, 0, w, h), Vector2i(dx, dy))
	return out


static func _write_png(img: Image, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return img.save_png(path) == OK


static func _rect_json(r: Rect2i) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var root: String = game_dir.get_base_dir()
	var out_dir: String = game_dir + "/" + OUT_REL
	var img := _load(root + "/" + SRC_REL)
	if img == null:
		push_error("kiwi_cat: cannot load %s" % SRC_REL)
		quit(1)
		return
	_strip_background(img)
	var body := _crop_body(img)
	if body == null:
		push_error("kiwi_cat: no body after background removal")
		quit(1)
		return
	print("kiwi_cat: body %dx%d (tight alpha > 16 crop)" % [body.get_width(), body.get_height()])
	var lifted := _brightness(body, BODY_LIFT)
	var frames := {
		"cycle_00.png": lifted,
		"spawn_00.png": _brightness(lifted, SPAWN_LIFT),
		"idle_chase_00.png": _squash(lifted, IDLE_SQUASH),
		"telegraph_00.png": _telegraph_flash(lifted, TELEGRAPH_TINT, TELEGRAPH_LIFT),
	}
	for fname in ["cycle_00.png", "spawn_00.png", "idle_chase_00.png", "telegraph_00.png"]:
		var fitted := _fit_pot(frames[fname])
		var rect := _body_rect(fitted)
		var ok := _write_png(fitted, out_dir + "/" + fname)
		print("kiwi_cat: wrote %s canvas=%dx%d body_rect=[%d, %d, %d, %d] ok=%s" % [
			fname, fitted.get_width(), fitted.get_height(),
			rect.position.x, rect.position.y, rect.size.x, rect.size.y, str(ok)])
	quit(0)

