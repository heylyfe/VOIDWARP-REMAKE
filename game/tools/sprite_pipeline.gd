extends SceneTree
#
# game/tools/sprite_pipeline.gd - the enemy sprite pipeline (FLEET_PACK.md T-016, headless).
#
#   tools\godot\godot.exe --headless --path game --script res://tools/sprite_pipeline.gd
#
# Reads nothing from the Godot resource system: every image is loaded from disk with
# Image.load_from_file and written back with Image.save_png at native filesystem paths.
# For each of the 12 enemies of DESIGN.md section 5: load the owner source image(s) named
# in ENEMIES.md "Attachment mapping" (by number AND exact filename), remove the background
# (flood fill from the four corners, colour tolerance 24/255), crop the body tight
# (alpha > 16), fit it on a power-of-two canvas <= 512 with a transparent margin, derive
# every animation frame from one base + overlays exactly as the owner spec lists (every
# overlay seeded by mix(enemy_index, frame) - TERRAIN_SPEC.md section 3 - so a rebuild is
# byte-stable), and write per-frame PNGs + sprites.json (frames, fps, per-frame body_rect
# = the tight bbox of alpha > 16, world height = DESIGN.md section 5's body-size table)
# + SOURCES.md.
#
# TBD FALLBACK (ENEMIES.md): a source that is missing, unreadable, or fails validation
# after background removal never stops the run - that enemy's frames are built from the
# magenta TBD placeholder (make_tbd_png.gd), "tbd": true goes into its sprites.json and a
# row lands in TBD.md. Dropping a real PNG in later with the exact filename and rebuilding
# swaps every placeholder for the real art with no code change.
#
# Output (per enemy): game/content/enemies/<id>/sprites/<name>_<NN>.png,
# game/content/enemies/<id>/sprites.json, game/content/enemies/<id>/SOURCES.md.

const MakeTbd := preload("res://tools/make_tbd_png.gd")

const MAX_CANVAS := 512                       # power-of-two canvas cap
const MIN_MARGIN := 2                         # transparent margin between body and edge
const POT_LADDER := [16, 32, 64, 128, 256, 512]
const BG_TOL := 24                            # per-channel bg tolerance, "24/255"
const BODY_ALPHA := 16.0                      # "alpha > 16" defines the body (HITBOXES)
const COIL_PCTS := [50, 65, 80, 100, 120]     # squash -> extend, ENEMIES.md
const NUKE_PCTS := [20, 26, 22, 30]           # flame lengths % of missile, T-016 spec
const NUKE_HOT := Color(1.0, 200.0 / 255.0, 61.0 / 255.0)   # #FFC83D
const NUKE_COLD := Color(1.0, 42.0 / 255.0, 42.0 / 255.0)   # #FF2A2A
const GIFT_SQUASH := [100, 70, 30, 70, 100]   # gift Larper fake rotation, T-016 spec
const GIFT_LIGHT := [0.60, 0.80, 1.0, 0.80, 0.60]
const SEAL_DEGS := [-12.0, 12.0]              # dash flipper rotation, T-016 spec
const CLAUDE_DYS := [0, -2, 2]                # plushie idle bob px, spec is silent
const CLAUDE_LIGHT := [1.0, 0.9, 1.0]

# The roster with DESIGN.md section 5's world heights (SR-2 table). "cycle_heights" marks
# the one animation (coil) whose world height changes per frame. null = section 5 gives
# the enemy no row of its own: the nuke IS a missile with no body and gift Larper occupies
# gift slots as the tripmine ("the roster's other rows carry no world size"); the view
# scales both from body_rect. Isagi's "shot" is the section 5.4 projectile: radius 0.5 u.
const ROSTER := [
	{"id": "kiwi_cat", "name": "kiwi cat", "index": 1, "world_height": 1.0},
	{"id": "coil", "name": "coil", "index": 2, "world_height": 2.0},
	{"id": "thicc_ben", "name": "thicc ben", "index": 3, "world_height": 4.0},
	{"id": "isagi", "name": "Isagi", "index": 4, "world_height": 1.8, "shot_height": 0.5},
	{"id": "nuke", "name": "nuke", "index": 5, "world_height": null},
	{"id": "you", "name": "YOU?!", "index": 6, "world_height": 1.8},
	{"id": "gift_larper", "name": "gift Larper", "index": 7, "world_height": null},
	{"id": "toucher", "name": "toucher", "index": 8, "world_height": 1.4},
	{"id": "seal", "name": "seal", "index": 9, "world_height": 0.6},
	{"id": "address_me", "name": "address me", "index": 10, "world_height": 2.5},
	{"id": "claude", "name": "Claude", "index": 11, "world_height": 2.0},
	{"id": "gin", "name": "gin ichimaru", "index": 12, "world_height": 1.8},
]

# ENEMIES.md "Attachment mapping" - image number AND exact filename, one role per enemy.
const SOURCES := {
	"kiwi_cat": [{"n": 1, "file": "kiwicat.png", "role": "base"}],
	"coil": [{"n": 2, "file": "springer.png", "role": "base"}],
	"thicc_ben": [{"n": 3, "file": "thiccben.png", "role": "base"}],
	"isagi": [
		{"n": 4, "file": "isagi_idle.jpeg", "role": "idle"},
		{"n": 5, "file": "ISAGI_SHOOT.webp", "role": "shoot"},
		{"n": 6, "file": "blueballprojectile.webp", "role": "shot"},
	],
	"nuke": [{"n": 7, "file": "NUKE.jpeg", "role": "base"}],
	"you": [{"n": 8, "file": "character to be corrupted.png", "role": "base"}],
	"gift_larper": [{"n": 9, "file": "tripine.png", "role": "base"}],
	"toucher": [
		{"n": 10, "file": "toucher.jpeg", "role": "finger"},
		{"n": 11, "file": "glitchedground.jpeg", "role": "floor"},
	],
	"seal": [{"n": 12, "file": "babehseal.webp", "role": "base"}],
	"address_me": [
		{"n": 13, "file": "address me elephant.png", "role": "normal"},
		{"n": 14, "file": "explosionsffect.jpg", "role": "explode"},
	],
	"claude": [{"n": 15, "file": "claudelogo.png", "role": "base"}],
	"gin": [
		{"n": 16, "file": "gin idle.png", "role": "idle"},
		{"n": 17, "file": "ginsword.png", "role": "launch"},
	],
}

# ---- deterministic seeds -----------------------------------------------------------------------

static func _mul32(a: int, b: int) -> int:
	# 32-bit wrap multiply built from 16-bit halves: two halves of two 32-bit values can
	# never overflow the 64-bit int they are computed in.
	var al: int = a & 0xFFFF
	var ah: int = (a >> 16) & 0xFFFF
	return (((al * (b & 0xFFFFFFFF)) & 0xFFFFFFFF)
			+ (((ah * (b & 0xFFFFFFFF)) << 16) & 0xFFFFFFFF)) & 0xFFFFFFFF


static func _fmix32(x: int) -> int:
	# fmix of TERRAIN_SPEC.md section 3 (MurmurHash3 finalizer).
	x = x & 0xFFFFFFFF
	x = x ^ (x >> 16)
	x = _mul32(x, 0x85EBCA6B)
	x = x ^ (x >> 13)
	x = _mul32(x, 0xC2B2AE35)
	x = x ^ (x >> 16)
	return x


static func _mix(a: int, b: int) -> int:
	# mix(a, b) of TERRAIN_SPEC.md section 3. Every derived frame's overlays are seeded
	# with _mix(enemy_index, frame) so a rebuild is byte-stable.
	return _fmix32((a & 0xFFFFFFFF) ^ ((b + 0x9E3779B9) & 0xFFFFFFFF))


# ---- image plumbing -----------------------------------------------------------------------------

static func _load(path: String) -> Image:
	# null = missing or unreadable - the caller turns that into the TBD placeholder path
	# (never a stall: ENEMIES.md TBD FALLBACK).
	if not FileAccess.file_exists(path):
		return null
	var img: Image = Image.load_from_file(path)
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _strip_bg(img: Image) -> void:
	# Flood fill from the four corners with per-channel colour tolerance 24/255: every
	# pixel that reaches a corner through similarly coloured pixels goes to alpha 0.
	# Skipped entirely when all four corners are already alpha 0 (the TBD placeholders).
	@warning_ignore("integer_division")
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var refs: Array = []
	for c in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		var base: int = (c.y * w + c.x) * 4
		refs.append([data[base], data[base + 1], data[base + 2]])
	var open := false
	for c in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		if data[((c.y * w) + c.x) * 4 + 3] != 0:
			open = true
			break
	if open:
		var visited := PackedByteArray()
		visited.resize(w * h)
		var stack: Array[int] = [0, w - 1, (h - 1) * w, h * w - 1]
		for pi in stack:
			visited[pi] = 1
		while not stack.is_empty():
			var pi: int = stack.pop_back()
			var base := pi * 4
			var hit := false
			for ref in refs:
				if absi(data[base] - ref[0]) <= tol_int() and absi(data[base + 1] - ref[1]) <= tol_int() \
						and absi(data[base + 2] - ref[2]) <= tol_int():
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


static func tol_int() -> int:
	return int(round(BG_TOL * 255.0))


static func _crop_body(img: Image) -> Image:
	# Tight crop to the body: the bbox of pixels with alpha > 16 (HITBOXES: the body_rect
	# of the sprite, nothing more). null when there is no body at all.
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


static func _fit_pot(img: Image, bottom := false) -> Image:
	# Centre (or bottom-line anchor) the body on the smallest power-of-two canvas <= 512
	# (never the body's edge on the canvas border: hard-rule TRANSPARENCY).
	@warning_ignore("integer_division")
	var w := img.get_width()
	var h := img.get_height()
	var canvas := MAX_CANVAS
	for v in POT_LADDER:
		if v >= w + 2 * MIN_MARGIN and v >= h + 2 * MIN_MARGIN:
			canvas = v
			break
	var out := Image.create_empty(canvas, canvas, false, Image.FORMAT_RGBA8)
	var dx: int = (canvas - w) / 2
	var dy: int = (canvas - h) / 2
	if bottom:
		dy = canvas - h - MIN_MARGIN
	out.blend_rect(img, Rect2i(0, 0, w, h), Vector2i(dx, dy))
	return out


static func _body_rect(img: Image) -> Rect2i:
	# Tight bbox of alpha > 16 inside the saved frame PNG - the billboarding hitbox data.
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


static func _final_lower(img: Image, deg: float, rot_deg: float) -> Image:
	# Rotates "the lower 25% of the sprite" by deg about its own centre (nearest-neighbour
	# inverse mapping: deterministic). Used for the seal's dash flippers.
	@warning_ignore("integer_division")
	var w := img.get_width()
	var h := img.get_height()
	var y0: int = h - maxi(1, int(round(h * 0.25)))
	var rh: int = h - y0
	var rw := w
	if rh <= 0 or deg == 0.0:
		return img
	var region := img.get_region(Rect2i(0, y0, rw, rh))
	var rad: float = deg_to_rad(deg)
	var cosv := cos(rad)
	var sinv := sin(rad)
	var icx := (rw - 1) / 2.0
	var icy := (rh - 1) / 2.0
	var out := Image.create_empty(rw, rh, false, Image.FORMAT_RGBA8)
	for y in rh:
		for x in rw:
			var dx: float = x - icx
			var dy: float = y - icy
			var sx: int = floori(cosv * dx + sinv * dy + icx)
			var sy: int = floori(-sinv * dx + cosv * dy + icy)
			@warning_ignore("integer_division")
			if sx >= 0 and sx < w and sy >= 0 and sy < h:
				var px := img.get_pixel(sx, sy)
				if px.a > 0.0:
					out.set_pixel(x, y, px)
	# paste the rotated lower part back over the untouched upper part
	var out_full: Image = img.duplicate()
	out_full.blend_rect(out, Rect2i(0, 0, rw, rh), Vector2i(0, y0))
	return out_full


# ---- derived-frame overlays (all deterministic: no RNG, no wall clock) --------------------------

static func _resize_step(img: Image, w: int, h: int, lanczos: bool) -> Image:
	var out: Image = img.duplicate()
	out.resize(w, h, Image.INTERPOLATE_LANCZOS if lanczos else Image.INTERPOLATE_NEAREST)
	return out


static func _squash(img: Image, pct: int) -> Image:
	# vertical squash towards the resting base line (bottom stays put), ENEMIES.md coil
	var w := img.get_width()
	var h := img.get_height()
	var nh := maxi(1, int(round(h * pct / 100.0)))
	var out: Image = img.duplicate()
	out.resize(w, nh, Image.INTERPOLATE_LANCZOS)
	return out


@warning_ignore("integer_division")
static func _corrupt(img: Image, enemy_index: int, frame: int) -> Image:
	# corruption flicker (YOU?! 5 frames, toucher finger 3 / floor 5, ENEMIES.md "Model"):
	# three horizontal bands of 6-18 px height shifted by plus/minus 6 px, the red
	# channel 2 px right and the blue 2 px left, and 2% of the opaque pixels dropped to
	# alpha 0 inside the body (the outline is protected). Every quantity is seeded by
	# mix(enemy_index, frame) - a rebuild is byte-stable.
	var w := img.get_width()
	var h := img.get_height()
	var out: Image = img.duplicate()
	for k in 3:
		var bh: int = 6 + (_mix(enemy_index, frame * 10 + k) % 13)        # 6..18 px
		var s: int = (_mix(enemy_index, frame * 10 + k + 3) % 13) - 6     # -6..+6 px
		var y0: int = k * (h - bh) / 2
		var band := img.get_region(Rect2i(0, clampi(y0 + s, 0, h - bh), w, bh))
		out.blend_rect(band, Rect2i(0, 0, w, bh), Vector2i(0, clampi(y0, 0, h - bh)))
	# red channel 2 px right, blue channel 2 px left
	for y in h:
		for x in w:
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				var r: float = out.get_pixel(mini(x + 2, w - 1), y).r
				var b: float = out.get_pixel(maxi(x - 2, 0), y).b
				out.set_pixel(x, y, Color(r, c.g, b, c.a))
	# 2% of the opaque body pixels drop to alpha 0 (seeded)
	for y in h:
		for x in w:
			if _mix(_mix(enemy_index, frame), y * w + x) % 50 == 0:
				var c2 := out.get_pixel(x, y)
				if c2.a > 0.0:
					out.set_pixel(x, y, Color(c2.r, c2.g, c2.b, 0.0))
	return out


static func _flame_frame(missile: Image, enemy_index: int, frame: int, bottom := true) -> Image:
	# nuke booster flame (T-016 spec): one flame overlay per frame, length 20/26/22/30% of
	# the missile, colours lerped #FFC83D (nozzle) -> #FF2A2A (tail), horizontal jitter
	# seeded by mix(enemy_index, frame). The missile is drawn over the flame.
	var w := missile.get_width()
	var h := missile.get_height()
	var fh := maxi(1, int(round(h * NUKE_PCTS[frame] / 100.0)))
	var jx: int = int(_mix(enemy_index, 1000 + frame) % (w + 12)) - 6
	var fw := maxi(3, int(round(w * 0.16)))
	var out := Image.create_empty(w, h + fh, false, Image.FORMAT_RGBA8)
	for i in fh:
		var t := float(i) / maxf(1.0, float(fh - 1))
		var col := NUKE_HOT.lerp(NUKE_COLD, t)
		var cx0: int = clampi((w - fw) / 2 + jx, 0, w - fw)
		var y := h + i
		for x in range(cx0, cx0 + fw):
			out.set_pixel(x, y, col)
	out.blend_rect(missile, Rect2i(0, 0, w, h), Vector2i(0, 0))
	return out


static func _squash_light(img: Image, squash_pct: int, light_factor: float) -> Image:
	# gift Larper (T-016 spec): the base "rotated" in five steps of horizontal squash
	# (100/70/30/70/100% about the centre) with its light at 60/80/100/80/60% brightness.
	@warning_ignore("integer_division")
	var w := img.get_width()
	var nw := maxi(1, int(round(w * squash_pct / 100.0)))
	var h := img.get_height()
	var scaled: Image = img.duplicate()
	scaled.resize(nw, h, Image.INTERPOLATE_NEAREST)
	# the light = the mine's lamp: a central disc of radius 18% of the body width; its
	# pixels pulse to light_factor brightness while the rest of the body stays put
	var cx: int = (nw - 1) / 2
	var cy: int = (h - 1) / 2
	var rad: int = maxi(2, int(round(nw * 0.18)))
	for y in h:
		for x in nw:
			var c := scaled.get_pixel(x, y)
			if c.a > 0.0 and (x - cx) * (x - cx) + (y - cy) * (y - cy) <= rad * rad:
				scaled.set_pixel(x, y, Color(c.r * light_factor, c.g * light_factor, c.b * light_factor, c.a))
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.blend_rect(scaled, Rect2i(0, 0, nw, h), Vector2i((w - nw) / 2, 0))
	return out


static func _seal_dash(img: Image, deg: float) -> Image:
	# seal dash frames (T-016 spec): mouth-open = a dark ellipse 18% of body width at the
	# muzzle (right side), flippers = the lower 25% of the sprite rotated -12/+12 degrees.
	var w := img.get_width()
	var h := img.get_height()
	var out: Image = img.duplicate()
	var rw: int = maxi(2, int(round(w * 0.18)))
	var rh: int = maxi(1, int(round(rw * 0.55)))
	var cx: int = w - 2 - rw / 2
	var cy: int = int(round(h * 0.3))
	var dark := Color(0.05, 0.03, 0.05, 1.0)
	for y in range(maxi(0, cy - rh), mini(h, cy + rh + 1)):
		for x in range(maxi(0, cx - rw), mini(w, cx + rw + 1)):
			var dx := float(x - cx) / float(rw)
			var dy := float(y - cy) / float(rh)
			if dx * dx + dy * dy <= 1.0:
				out.set_pixel(x, y, dark)
	return _final_lower(out, deg, deg)


static func _compose_explode(elephant: Image, boom: Image) -> Image:
	# address me explode frame (T-016 spec): Image 14 composited over the elephant at
	# 100% size, the elephant fading to 30% alpha. The _fit pass rescales to the canvas.
	var w := maxi(elephant.get_width(), boom.get_width())
	var h := maxi(elephant.get_height(), boom.get_height())
	var ghost: Image = elephant.duplicate()
	for y in ghost.get_height():
		for x in ghost.get_width():
			var c := ghost.get_pixel(x, y)
			ghost.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * 0.3))
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	out.blend_rect(ghost, Rect2i(0, 0, ghost.get_width(), ghost.get_height()), Vector2i(0, 0))
	out.blend_rect(boom, Rect2i(0, 0, boom.get_width(), boom.get_height()), Vector2i(0, 0))
	return out


static func _flash(img: Image, factor := 1.5) -> Image:
	# Isagi wind-up telegraph (ENEMIES.md: "use the idle pose with a wind-up telegraph/flash")
	var out: Image = img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(minf(1.0, c.r * factor), minf(1.0, c.g * factor), minf(1.0, c.b * factor), c.a))
	return out


static func _bob(img: Image, dy: int, factor: float) -> Image:
	# Claude plushie idle bob (spec is silent on the 3 idle frames; D-T016).
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create_empty(w, h + 4, false, Image.FORMAT_RGBA8)
	out.blend_rect(img, Rect2i(0, 0, w, h), Vector2i(0, 2 + dy))
	for y in out.get_height():
		for x in w:
			var c := out.get_pixel(x, y)
			if c.a > 0.0 and factor != 1.0:
				out.set_pixel(x, y, Color(minf(1.0, c.r * factor), minf(1.0, c.g * factor), minf(1.0, c.b * factor), c.a))
	return out


# ---- the per-enemy frame recipes (ENEMIES.md "Animation" + the T-016 derived-frame spec) --------

static func _frames(srcs: Dictionary, enemy: Dictionary) -> Array:
	# srcs maps role -> processed (bg-stripped, tight-cropped) Image. Each anim dict:
	# name, fps, loop, imgs (pre-fit), optional per-frame world heights, optional anchor.
	var id: String = enemy["id"]
	var idx: int = enemy["index"]
	var anims: Array = []
	match id:
		"kiwi_cat":
			anims.append({"name": "cycle", "fps": 1, "loop": true, "imgs": [srcs["base"]]})
		"coil":
			var imgs: Array = []
			for f in 5:
				imgs.append(_squash(srcs["base"], COIL_PCTS[f]))
			var hs: Array = []
			for p in COIL_PCTS:
				hs.append(roundf((1.0 + (p - 50) / 70.0) * 1000.0) / 1000.0)  # 1.0 -> 2.0 u
			anims.append({"name": "cycle", "fps": 8, "loop": true, "imgs": imgs, "heights": hs, "anchor": "bottom"})
		"thicc_ben":
			anims.append({"name": "cycle", "fps": 1, "loop": true, "imgs": [srcs["base"]]})
		"isagi":
			anims.append({"name": "fire", "fps": 8, "loop": false, "imgs": [
				srcs["idle"], _flash(srcs["idle"], 1.5), srcs["shoot"]]})
			anims.append({"name": "shot", "fps": 20, "loop": true, "imgs": [srcs["shot"]], "world_height": enemy["shot_height"]})
		"nuke":
			var imgs: Array = []
			for f in 4:
				imgs.append(_fit_pot(_flame_frame(srcs["base"], idx, f), true))
			anims.append({"name": "cycle", "fps": 10, "loop": true, "imgs": imgs})
		"you":
			var imgs: Array = []
			for f in 5:
				imgs.append(_corrupt(srcs["base"], idx, f))
			anims.append({"name": "cycle", "fps": 10, "loop": true, "imgs": imgs})
		"gift_larper":
			var imgs: Array = []
			for f in 5:
				var sl := _squash_light(srcs["base"], GIFT_SQUASH[f], GIFT_LIGHT[f])
				imgs.append(_fit_pot(sl, false))
			anims.append({"name": "cycle", "fps": 10, "loop": true, "imgs": imgs})
		"toucher":
			var finger: Array = []
			for f in 3:
				finger.append(_corrupt(srcs["finger"], idx, f))
			anims.append({"name": "cycle", "fps": 6, "loop": true, "imgs": finger})
			var floor_imgs: Array = []
			for f in 5:
				floor_imgs.append(_corrupt(srcs["floor"], idx, f))
			anims.append({"name": "floor", "fps": 8, "loop": true, "imgs": floor_imgs})
		"seal":
			anims.append({"name": "idle", "fps": 1, "loop": true, "imgs": [srcs["base"]]})
			var dash: Array = []
			for deg in SEAL_DEGS:
				dash.append(_seal_dash(srcs["base"], deg))
			anims.append({"name": "dash", "fps": 10, "loop": false, "imgs": dash})
		"address_me":
			anims.append({"name": "cycle", "fps": 2, "loop": true, "imgs": [
				srcs["normal"], _compose_explode(srcs["normal"], srcs["explode"])]})
		"claude":
			var imgs: Array = []
			for f in 3:
				imgs.append(_bob(srcs["base"], CLAUDE_DYS[f], CLAUDE_LIGHT[f]))
			anims.append({"name": "idle", "fps": 6, "loop": true, "imgs": imgs})
		"gin":
			anims.append({"name": "idle", "fps": 2, "loop": true, "imgs": [srcs["idle"]]})
			anims.append({"name": "launch", "fps": 4, "loop": false, "imgs": [srcs["launch"]]})
	return anims


# ---- per-enemy orchestration: sources -> frames -> sprites/<name>_NN.png + json + SOURCES.md ----

static func _round3(v: float) -> float:
	return roundf(v * 1000.0) / 1000.0


static func _write_png(img: Image, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return img.save_png(path) == OK


static func _write_text(text: String, path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


static func _rect_json(r: Rect2i) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


# The previous sprites.json, or {} when there is none yet (first build) or it does not
# parse. Used only to carry over keys this pipeline does not own (T-083's `anim` block).
static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func _process_enemy(enemy: Dictionary, src_dir: String, out_dir: String) -> Dictionary:
	var id: String = enemy["id"]
	var idx: int = enemy["index"]
	var enemy_dir: String = out_dir + "/" + id
	DirAccess.make_dir_recursive_absolute(enemy_dir)
	var tbd := false
	var srcs := {}
	var src_rows: Array = []
	for s in SOURCES[id]:
		var img := _load(src_dir + "/" + s["file"])
		var row := {"image": s["n"], "file": s["file"], "role": s["role"],
			"path": "assets_src/enemies/" + s["file"]}
		if img == null:
			tbd = true
			row["state"] = "MISSING -> TBD"
			srcs[s["role"]] = null
		else:
			_strip_bg(img)
			var body := _crop_body(img)
			if body == null:
				tbd = true
				row["state"] = "NO BODY AFTER BACKGROUND REMOVAL -> TBD"
				srcs[s["role"]] = null
			else:
				row["state"] = "OK"
				row["pixels"] = body.get_width() * body.get_height()
				srcs[s["role"]] = body
		src_rows.append(row)
	if tbd:
		# ENEMIES.md TBD FALLBACK: the placeholder IS that source for every role, so the
		# recipes run unmodified and emit one TBD frame per listed frame.
		var ph: Image = _crop_body(MakeTbd.build(256))
		for k in srcs:
			srcs[k] = ph
	var anims: Array = _frames(srcs, enemy)
	var anim_rows: Array = []
	var n_png := 0
	for anim in anims:
		var imgs: Array = anim["imgs"]
		var bottom: bool = anim.get("anchor", "center") == "bottom"
		var fitted: Array = []
		var need := 0
		for im: Image in imgs:
			need = maxi(need, maxi(im.get_width(), im.get_height()) + 2 * MIN_MARGIN)
		var canvas := MAX_CANVAS
		for v in POT_LADDER:
			if v >= need:
				canvas = v
				break
		for im: Image in imgs:
			var w: int = im.get_width()
			var h: int = im.get_height()
			var dst := Image.create_empty(canvas, canvas, false, Image.FORMAT_RGBA8)
			var dx: int = (canvas - w) / 2
			var dy: int = (canvas - h) / 2
			if bottom:
				dy = canvas - h - MIN_MARGIN
			dst.blend_rect(im, Rect2i(0, 0, w, h), Vector2i(dx, dy))
			fitted.append(dst)
		var files: Array = []
		var rects: Array = []
		for j in fitted.size():
			var fname: String = "%s_%02d.png" % [anim["name"], j]
			_write_png(fitted[j], enemy_dir + "/sprites/" + fname)
			files.append("sprites/" + fname)
			rects.append(_rect_json(_body_rect(fitted[j])))
			n_png += 1
		var row := {"name": anim["name"], "fps": anim["fps"], "loop": anim["loop"],
			"frames": files, "body_rect": rects}
		if anim.has("heights"):
			row["world_height"] = anim["heights"]          # per-frame u (coil: 1.0 -> 2.0)
		elif anim.has("world_height"):
			row["world_height"] = anim["world_height"]     # per-animation override (isagi shot)
		anim_rows.append(row)
	var json := {
		"_doc": "Generated by game/tools/sprite_pipeline.gd (FLEET_PACK.md T-016). Schema: id, name, tbd, world_height (DESIGN.md section 5 body-size table, SR-2; null where the section gives the enemy no row), animations[] {name, fps, loop, frames[] (paths relative to this folder), body_rect[] (tight bbox of alpha > 16 per frame, the HITBOXES shape), world_height per animation/frame where it differs}, sources[] = the ENEMIES.md 'Attachment mapping' state. Resourced at res://content/enemies/<id>/sprites.json.",
		"id": id,
		"name": enemy["name"],
		"tbd": tbd,
		"world_height": enemy.get("world_height"),
		"animations": anim_rows,
		"sources": src_rows,
	}
	# T-083's `anim` block is authored by hand and is NOT this pipeline's output: a rebuild
	# must never delete it. Carry over every top-level key this pipeline does not own, so a
	# re-run after the art lands keeps the state table, its timings and its frame_map.
	var prev := _read_json(enemy_dir + "/sprites.json")
	for k in prev.keys():
		if not json.has(k):
			json[k] = prev[k]
	# DESIGN.md section 5 gives gift Larper and the nuke no row of their own, so the roster
	# carries null - but gift Larper's merged, test-pinned value is 1.0 (D-T073-2: it is the
	# tripmine model box its behaviour mirrors). A rebuild must not null a pinned value.
	if json["world_height"] == null and prev.get("world_height") != null:
		json["world_height"] = prev["world_height"]
	_write_text(JSON.stringify(json, "\t") + "\n", enemy_dir + "/sprites.json")
	_write_text(_sources_md(enemy, src_rows), enemy_dir + "/SOURCES.md")
	return {"pngs": n_png, "tbd": tbd}


static func _sources_md(enemy: Dictionary, src_rows: Array) -> String:
	var lines: Array[String] = []
	lines.append("# %s - SOURCES" % enemy["name"])
	lines.append("")
	lines.append("Generated by `game/tools/sprite_pipeline.gd` (FLEET_PACK.md T-016). Spec: ENEMIES.md")
	lines.append("(roster + \"Attachment mapping\", by image number AND exact filename) and DESIGN.md")
	lines.append("section 5 (world sizes). PNG frames under `sprites/` are committed build artifacts with")
	lines.append("their sources documented here.")
	lines.append("")
	lines.append("| image | exact filename | path (repo-relative) | pipeline state |")
	lines.append("|---|---|---|---|")
	for row in src_rows:
		lines.append("| %d | `%s` | `%s` | %s |" % [row["image"], row["file"], row["path"], row["state"]])
	lines.append("")
	lines.append("Pipeline (every source): RGBA convert, background removed by a flood fill from the four")
	lines.append("image corners (colour tolerance 24/255, skipped when the corners are already alpha 0),")
	lines.append("tight crop to the body (alpha > 16 = the only hitbox-eligible pixels), then fitted onto a")
	lines.append("power-of-two canvas (max 512, transparent margin). Every derived frame is a deterministic")
	lines.append("overlay of the base: bands / channel offsets / pixel drops seeded by `mix(enemy_index,")
	lines.append("frame)` (TERRAIN_SPEC.md section 3) - a rebuild is byte-stable.")
	lines.append("")
	lines.append("HITBOXES hard rule: a frame's `body_rect` in sprites.json (tight bbox of alpha > 16) is the")
	lines.append("only solid part of the sprite; the transparent padding and margins never hit.")
	lines.append("")
	lines.append("DISCLAIMER (ENEMIES.md hard rule): this is a personal, non-commercial project with no money")
	lines.append("involved; it is not affiliated with, endorsed by, or connected to any person, brand,")
	lines.append("character, or IP referenced or depicted here.")
	return "\n".join(lines) + "\n"


func _init() -> void:
	var t0: int = Time.get_ticks_msec()
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var root: String = game_dir.get_base_dir()
	var src_dir: String = root + "/assets_src/enemies"
	var out_dir: String = game_dir + "/content/enemies"
	var n_png := 0
	var n_tbd := 0
	for enemy in ROSTER:
		# An enemy with its own art module (game/tools/art/<id>.gd) owns its frames: that
		# module does the background removal its source image actually needs and writes the
		# per-state frames. Re-running this pipeline must not regress it back to the naive
		# corner flood fill, so the enemy is skipped and the module is the generator.
		if FileAccess.file_exists(game_dir + "/tools/art/" + enemy["id"] + ".gd"):
			print("ENEMY %s SKIPPED (owned by tools/art/%s.gd)" % [enemy["id"], enemy["id"]])
			continue
		var res: Dictionary = _process_enemy(enemy, src_dir, out_dir)
		n_png += res["pngs"]
		if res["tbd"]:
			n_tbd += 1
		print("ENEMY %s pngs=%d tbd=%s" % [enemy["id"], res["pngs"], str(res["tbd"])])
	print("PIPELINE 12 enemies, %d frame PNGs, %d TBD enemies, %d ms" % [n_png, n_tbd, Time.get_ticks_msec() - t0])
	quit(0)


