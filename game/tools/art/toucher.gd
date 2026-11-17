# toucher art module - real sprite art for the toucher (owner ticket: turn the
# owner's source images into real frames; the shared pipeline cannot do this one).
#
#   tools\godot\godot.exe --headless --path game --script res://tools/art/toucher.gd
#   (absolute engine path: C:\Users\username\Documents\REMAKE VWR\VOIDWARP-REMAKE\tools\godot\godot.exe)
#
# Sources: assets_src/enemies/toucher.jpeg        (180x180, opaque black corners - the finger)
#          assets_src/enemies/glitchedground.jpeg (300x300, opaque white corners - the cube)
#
# The finger is keyed out with a flood fill from the border (colour distance <=
# FINGER_TOL from the sampled border colour), never a global key (the finger's dark
# outline pixels are within key range of black and a global key would eat them).
# The cube's white backdrop is keyed the same way with a wider tolerance - no cube
# pixel is anywhere near white, so the key cannot touch the body.
#
# Every body frame is derived from ONE pasted base image, so the silhouette (and
# therefore the tight alpha>16 body_rect) is IDENTICAL across spawn/idle/telegraph/
# attack frames - glitch is applied as colour-only row operations (brightness
# bands, scanlines, tints). The floor decal frames use row displacement and carry
# their own per-frame body_rects.
#
# Deterministic: band positions and strengths are hardcoded constants; no RNG.
# Re-runnable: appended animations[] entries are rebuilt from scratch each run.
extends SceneTree

const CANVAS := 256              # power-of-two, <= 512
const BODY_TARGET_H := 200       # finger body height on the canvas (px)
const DECAL_TARGET_H := 208      # cube body height on the canvas (px)
const MIN_MARGIN := 2            # required transparent margin; we keep >= 12
const BODY_ALPHA := 16           # the hitbox threshold (alpha > 16)
const FINGER_TOL := 0.133        # ~34/255 border flood-fill tolerance (black backdrop)
const FLOOR_TOL := 0.24          # ~61/255 border flood-fill tolerance (white backdrop)

var _failures: Array[String] = []

func _repo_root() -> String:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	return game_dir.get_base_dir()


func _load_src(root: String, file: String) -> Image:
	var path := root + "/assets_src/enemies/" + file
	var img := Image.load_from_file(path)
	if img == null:
		_failures.append("cannot load %s" % path)
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img

## Flood fill from the border; pixels within tol of border_rgb become transparent.
## Returns a copy of img with the backdrop removed.
static func _key_out(img: Image, border_rgb: Color, tol: float) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var bg := PackedByteArray()
	bg.resize(w * h)
	var queue: Array[int] = []
	var try_add := func(x: int, y: int) -> void:
		var i := y * w + x
		if bg[i] == 1:
			return
		var p := img.get_pixel(x, y)
		var dr := p.r - border_rgb.r
		var dg := p.g - border_rgb.g
		var db := p.b - border_rgb.b
		if sqrt(dr * dr + dg * dg + db * db) <= tol:
			bg[i] = 1
			queue.append(i)
	for x in w:
		try_add.call(x, 0)
		try_add.call(x, h - 1)
	for y in h:
		try_add.call(0, y)
		try_add.call(w - 1, y)
	var head := 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		var x := i % w
		var y := i / w
		if x > 0:
			try_add.call(x - 1, y)
		if x < w - 1:
			try_add.call(x + 1, y)
		if y > 0:
			try_add.call(x, y - 1)
		if y < h - 1:
			try_add.call(x, y + 1)
	var out: Image = img.duplicate()
	for i in w * h:
		if bg[i] == 1:
			out.set_pixel(i % w, i / w, Color(0.0, 0.0, 0.0, 0.0))
	return out


## Tight crop to pixels with alpha > BODY_ALPHA. Null when nothing survives.
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


## Tight bbox of alpha > BODY_ALPHA inside a canvas-sized image (the body_rect).
static func _body_rect(img: Image) -> Rect2i:
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


## Resize to target height (aspect kept) and paste centred on a CANVAS square with
## at least MIN_MARGIN clearance on every side.
static func _fit_canvas(body: Image, target_h: int) -> Image:
	var w := body.get_width()
	var h := body.get_height()
	var s := float(target_h) / float(h)
	var nw := maxi(int(round(float(w) * s)), 1)
	var nh := target_h
	var scaled: Image = body.duplicate()
	scaled.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	var out := Image.create_empty(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	var dx := (CANVAS - nw) / 2
	var dy := (CANVAS - nh) / 2
	out.blend_rect(scaled, Rect2i(0, 0, nw, nh), Vector2i(dx, dy))
	return out

## Colour-only transform on a pasted body image: channel multiply + add, optional
## scanline darkening every `band_every` rows, and flash bands (row ranges mixed
## toward a flash colour). Alpha is never touched, so the silhouette is identical.
static func _xform(img: Image, mul: Vector3, add: Vector3, scan_every := 0, scan_mul := 1.0, flashes: Array = []) -> Image:
	var out: Image = img.duplicate()
	var w := out.get_width()
	var h := out.get_height()
	for y in h:
		var scan := scan_mul if (scan_every > 0 and y % scan_every == 0) else 1.0
		for x in w:
			var p := out.get_pixel(x, y)
			if p.a <= 0.0:
				continue
			var r := clampf((p.r * mul.x + add.x) * scan, 0.0, 1.0)
			var g := clampf((p.g * mul.y + add.y) * scan, 0.0, 1.0)
			var b := clampf((p.b * mul.z + add.z) * scan, 0.0, 1.0)
			out.set_pixel(x, y, Color(r, g, b, p.a))
	for band in flashes:
		var y0: int = int(band["y0"])
		var y1: int = int(band["y1"])
		var fc: Color = band["color"]
		var strength: float = float(band["s"])
		for y in range(maxi(y0, 0), mini(y1, h)):
			for x in w:
				var p := out.get_pixel(x, y)
				if p.a <= 0.0:
					continue
				out.set_pixel(x, y, Color(lerpf(p.r, fc.r, strength), lerpf(p.g, fc.g, strength), lerpf(p.b, fc.b, strength), p.a))
	return out


## Shift whole row bands horizontally (floor decal glitch). Pixels shifted off the
## canvas are dropped; the vacated edge is transparent. Changes the silhouette, so
## floor frames carry per-frame body_rects.
static func _shift_rows(img: Image, bands: Array) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var src: Image = img.duplicate()
	var out: Image = src.duplicate()
	for y in h:
		var dx := 0
		for band in bands:
			if y >= int(band["y0"]) and y < int(band["y1"]):
				dx = int(band["dx"])
				break
		if dx == 0:
			continue
		for x in w:
			var sx := x - dx
			if sx < 0 or sx >= w:
				out.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
			else:
				out.set_pixel(x, y, src.get_pixel(sx, y))
	return out


## The cube's palette remap. The source faces are black / dark magenta / bright
## magenta on white; on the Deepwater fog (#021416) the dark faces fail the 3.0
## contrast floor, so the faces are remapped into a glowing magenta family and the
## dark becomes a thin seam colour only (the A8 fog-contrast rule is met by the ART,
## never by moving the threshold).
static func _floor_recolor(img: Image, pulse: float, cool: float) -> Image:
	var out: Image = img.duplicate()
	var w := out.get_width()
	var h := out.get_height()
	for y in h:
		for x in w:
			var p := out.get_pixel(x, y)
			if p.a <= 0.0:
				continue
			var lum := (p.r + p.g + p.b) / 3.0
			var col: Color
			if lum < 0.10:
				col = Color(0.55, 0.13, 0.55)   # seam (was black face)
			elif lum < 0.34:
				col = Color(0.92, 0.16, 0.90)   # shadow face (was dark magenta)
			elif lum < 0.60:
				col = Color(1.00, 0.22, 0.97)   # mid face
			else:
				col = Color(1.00, 0.62, 1.00)   # top face (was bright magenta)
			col = Color(clampf(col.r * pulse, 0.0, 1.0),
					clampf(col.g * pulse * (1.0 - cool * 0.35), 0.0, 1.0),
					clampf(col.b * pulse * (1.0 - cool * 0.45), 0.0, 1.0), p.a)
			out.set_pixel(x, y, col)
	return out

func _save(img: Image, enemy_dir: String, fname: String) -> Rect2i:
	var path := enemy_dir + "/sprites/" + fname
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	if err != OK:
		_failures.append("save failed %s (%d)" % [path, err])
	return _body_rect(img)


func _rect_json(r: Rect2i) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]


func _corner_check(img: Image, label: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for c in [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		if img.get_pixel(c.x, c.y).a != 0.0:
			_failures.append("%s: corner %s not alpha 0" % [label, c])
	for x in w:
		if img.get_pixel(x, 0).a >= 16.0 / 255.0 or img.get_pixel(x, h - 1).a >= 16.0 / 255.0:
			_failures.append("%s: opaque pixel on a horizontal border" % label)
			break
	for y in h:
		if img.get_pixel(0, y).a >= 16.0 / 255.0 or img.get_pixel(w - 1, y).a >= 16.0 / 255.0:
			_failures.append("%s: opaque pixel on a vertical border" % label)
			break


func _build_finger(root: String, enemy_dir: String) -> Dictionary:
	var src := _load_src(root, "toucher.jpeg")
	if src == null:
		return {}
	var keyed := _key_out(src, Color(0.0, 0.0, 0.0), FINGER_TOL)
	var body := _crop_body(keyed)
	if body == null:
		_failures.append("toucher.jpeg: no body after background removal")
		return {}
	var base := _fit_canvas(body, BODY_TARGET_H)
	# name -> _xform args (mul, add, scan_every, scan_mul, flashes)
	var defs := {
		"spawn_00": [Vector3(0.90, 0.90, 0.94), Vector3.ZERO, 4, 0.60, []],
		"idle_00": [Vector3(1.0, 1.0, 1.0), Vector3.ZERO, 0, 1.0, []],
		"idle_01": [Vector3(1.14, 1.02, 0.90), Vector3.ZERO, 0, 1.0, [
			{"y0": 96, "y1": 103, "color": Color(1.0, 0.965, 0.816), "s": 0.5},
			{"y0": 150, "y1": 154, "color": Color(1.0, 0.965, 0.816), "s": 0.6}]],
		"idle_02": [Vector3(0.90, 0.86, 1.08), Vector3.ZERO, 0, 1.0, [
			{"y0": 70, "y1": 74, "color": Color(1.0, 1.0, 1.0), "s": 0.5},
			{"y0": 112, "y1": 120, "color": Color(0.816, 0.878, 1.0), "s": 0.4},
			{"y0": 176, "y1": 181, "color": Color(0.816, 0.878, 1.0), "s": 0.45}]],
		"telegraph_00": [Vector3(1.10, 1.02, 0.88), Vector3.ZERO, 0, 1.0, [
			{"y0": 100, "y1": 108, "color": Color(1.0, 0.914, 0.659), "s": 0.4}]],
		"telegraph_01": [Vector3(1.22, 0.98, 0.72), Vector3.ZERO, 0, 1.0, [
			{"y0": 88, "y1": 97, "color": Color(1.0, 0.353, 0.235), "s": 0.45},
			{"y0": 140, "y1": 146, "color": Color(1.0, 1.0, 1.0), "s": 0.5}]],
		"telegraph_02": [Vector3(1.34, 1.05, 0.62), Vector3.ZERO, 0, 1.0, [
			{"y0": 80, "y1": 90, "color": Color(1.0, 0.165, 0.165), "s": 0.55},
			{"y0": 120, "y1": 127, "color": Color(1.0, 1.0, 1.0), "s": 0.6},
			{"y0": 164, "y1": 172, "color": Color(1.0, 0.165, 0.165), "s": 0.5}]],
		"attack_00": [Vector3(1.5, 1.25, 1.05), Vector3(0.10, 0.06, 0.10), 0, 1.0, [
			{"y0": 64, "y1": 76, "color": Color(1.0, 1.0, 1.0), "s": 0.55},
			{"y0": 108, "y1": 118, "color": Color(1.0, 0.165, 0.165), "s": 0.5},
			{"y0": 148, "y1": 157, "color": Color(1.0, 0.165, 0.165), "s": 0.5},
			{"y0": 188, "y1": 198, "color": Color(1.0, 1.0, 1.0), "s": 0.4}]],
	}
	var frames := {}
	for fname in defs.keys():
		var d: Array = defs[fname]
		var img := _xform(base, d[0], d[1], int(d[2]), float(d[3]), d[4])
		_corner_check(img, fname)
		frames[fname] = {"img": img, "rect": _save(img, enemy_dir, fname + ".png")}
	# cycle_00..02 are the idle flicker frames (the spec's toucher_00..02; the view's
	# cycle animation path reads these). Same pixels, saved under the cycle names.
	for i in 3:
		var idle_img: Image = frames["idle_0%d" % i]["img"]
		_corner_check(idle_img, "cycle_0%d" % i)
		frames["cycle_0%d" % i] = {"img": idle_img, "rect": _save(idle_img, enemy_dir, "cycle_0%d.png" % i)}
	return frames

func _build_floor(root: String, enemy_dir: String) -> Dictionary:
	var src := _load_src(root, "glitchedground.jpeg")
	if src == null:
		return {}
	var keyed := _key_out(src, Color(1.0, 1.0, 1.0), FLOOR_TOL)
	var body := _crop_body(keyed)
	if body == null:
		_failures.append("glitchedground.jpeg: no body after background removal")
		return {}
	var base := _fit_canvas(body, DECAL_TARGET_H)
	# name -> [pulse, cool, shift bands, scan_every, scan_mul, flashes]
	var defs := {
		"floor_00": [1.00, 0.0, [], 0, 1.0, []],
		"floor_01": [1.16, 0.0, [
			{"y0": 88, "y1": 96, "dx": 8}, {"y0": 150, "y1": 158, "dx": -7}], 6, 0.75, []],
		"floor_02": [1.25, 0.05, [
			{"y0": 72, "y1": 82, "dx": -12}, {"y0": 120, "y1": 127, "dx": 10}, {"y0": 180, "y1": 190, "dx": 6}], 4, 0.6, []],
		"floor_03": [1.12, 0.0, [
			{"y0": 96, "y1": 104, "dx": 14}, {"y0": 136, "y1": 142, "dx": -9}], 0, 1.0, [
			{"y0": 70, "y1": 74, "color": Color(1.0, 0.816, 1.0), "s": 0.5},
			{"y0": 110, "y1": 116, "color": Color(1.0, 0.816, 1.0), "s": 0.6}]],
		"floor_04": [1.30, 0.2, [
			{"y0": 84, "y1": 100, "dx": -16}], 5, 0.8, [
			{"y0": 128, "y1": 132, "color": Color(1.0, 0.165, 0.165), "s": 0.7},
			{"y0": 160, "y1": 168, "color": Color(1.0, 1.0, 1.0), "s": 0.5}]],
	}
	var frames := {}
	for fname in ["floor_00", "floor_01", "floor_02", "floor_03", "floor_04"]:
		var d: Array = defs[fname]
		var img := _floor_recolor(base, float(d[0]), float(d[1]))
		img = _shift_rows(img, d[2])
		img = _xform(img, Vector3.ONE, Vector3.ZERO, int(d[3]), float(d[4]), d[5])
		_corner_check(img, fname)
		frames[fname] = {"img": img, "rect": _save(img, enemy_dir, fname + ".png")}
	return frames


func _anim_row(name: String, fps: float, loop: bool, frames: Array, rects: Array) -> Dictionary:
	return {"body_rect": rects, "fps": fps, "frames": frames, "loop": loop, "name": name}


func _update_json(enemy_dir: String, finger: Dictionary, floor_f: Dictionary) -> void:
	var path := enemy_dir + "/sprites.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_failures.append("cannot read %s" % path)
		return
	var doc = JSON.parse_string(f.get_as_text())
	f.close()
	if not (doc is Dictionary):
		_failures.append("sprites.json does not parse")
		return
	# --- top-level animations[]: update cycle/floor body_rects, (re)append ours ---
	var anims: Array = doc.get("animations", [])
	var cycle_frames: Array = []
	var cycle_rects: Array = []
	for i in 3:
		cycle_frames.append("sprites/cycle_0%d.png" % i)
		cycle_rects.append(_rect_json(finger["cycle_0%d" % i]["rect"]))
	var floor_frames: Array = []
	var floor_rects: Array = []
	for i in 5:
		floor_frames.append("sprites/floor_0%d.png" % i)
		floor_rects.append(_rect_json(floor_f["floor_0%d" % i]["rect"]))
	var kept: Array = []
	for a in anims:
		var aname := str(a.get("name", ""))
		if aname in ["spawn", "idle", "telegraph", "attack_infect"]:
			continue   # our own rows from a previous run; rebuilt below
		if aname == "cycle":
			a["frames"] = cycle_frames
			a["body_rect"] = cycle_rects
		elif aname == "floor":
			a["frames"] = floor_frames
			a["body_rect"] = floor_rects
		kept.append(a)
	kept.append(_anim_row("spawn", 2.0, false, ["sprites/spawn_00.png"], [_rect_json(finger["spawn_00"]["rect"])]))
	kept.append(_anim_row("idle", 10.0, true,
		["sprites/idle_00.png", "sprites/idle_01.png", "sprites/idle_02.png"],
		[_rect_json(finger["idle_00"]["rect"]), _rect_json(finger["idle_01"]["rect"]), _rect_json(finger["idle_02"]["rect"])]))
	kept.append(_anim_row("telegraph", 20.0, false,
		["sprites/telegraph_00.png", "sprites/telegraph_01.png", "sprites/telegraph_02.png"],
		[_rect_json(finger["telegraph_00"]["rect"]), _rect_json(finger["telegraph_01"]["rect"]), _rect_json(finger["telegraph_02"]["rect"])]))
	kept.append(_anim_row("attack_infect", 1.0, false, ["sprites/attack_00.png"], [_rect_json(finger["attack_00"]["rect"])]))
	doc["animations"] = kept
	# --- the T-083 anim block: states point at the per-state files; frame_map stays
	# keyed by the pinned spec frame names (toucher_00..02) onto the cycle files ---
	var anim: Dictionary = doc.get("anim", {})
	anim["_doc"] = "T-083 (research/fable-tickets.md section 1.8 - the table is the spec; ENEMIES.md frozen, D-040). One entry per state of the section 1.8 table. Real art landed (game/tools/art/toucher.gd): the states' frames are the per-state files (spawn_00, idle_00..02, telegraph_00..02, attack_00) derived from toucher.jpeg; spec frame names toucher_00..02 resolve through frame_map onto cycle_00..02 (the same finger art) and floor_00..04 are the glitched-floor decal derived from glitchedground.jpeg (a section 2.2 world decal, not a body state). The frame counts, ticks, loops and effect parameters are exactly as the table says. Driven by the SIM state and its tick counter, never a wall-clock timer."
	var states: Dictionary = anim.get("states", {})
	if states.has("spawn"):
		states["spawn"]["frames"] = ["sprites/spawn_00.png"]
	if states.has("idle_chase"):
		states["idle_chase"]["frames"] = ["sprites/idle_00.png", "sprites/idle_01.png", "sprites/idle_02.png"]
	if states.has("telegraph"):
		states["telegraph"]["frames"] = ["sprites/telegraph_00.png", "sprites/telegraph_01.png", "sprites/telegraph_02.png"]
	if states.has("attack_infect"):
		states["attack_infect"]["frames"] = ["sprites/attack_00.png"]
	var new_anim := {}
	for k in anim.keys():
		new_anim[k] = anim[k]
		if k == "section":
			new_anim["frame_map"] = {
				"toucher_00": "sprites/cycle_00.png",
				"toucher_01": "sprites/cycle_01.png",
				"toucher_02": "sprites/cycle_02.png",
			}
	if not new_anim.has("frame_map"):
		new_anim["frame_map"] = {
			"toucher_00": "sprites/cycle_00.png",
			"toucher_01": "sprites/cycle_01.png",
			"toucher_02": "sprites/cycle_02.png",
		}
	doc["anim"] = new_anim
	# --- sources: the two images landed ---
	var sources: Array = doc.get("sources", [])
	for s in sources:
		s["state"] = "OK"
	doc["sources"] = sources
	doc["tbd"] = false
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		_failures.append("cannot write %s" % path)
		return
	out.store_string(JSON.stringify(doc, "\t") + "\n")
	out.close()


func _init() -> void:
	var root := _repo_root()
	var game_dir := root + "/game"
	var enemy_dir := game_dir + "/content/enemies/toucher"
	var finger := _build_finger(root, enemy_dir)
	var floor_f := _build_floor(root, enemy_dir)
	if not finger.is_empty() and not floor_f.is_empty():
		_update_json(enemy_dir, finger, floor_f)
	for fname in finger.keys():
		print("FINGER %s rect=%s" % [fname, finger[fname]["rect"]])
	for fname in floor_f.keys():
		print("FLOOR  %s rect=%s" % [fname, floor_f[fname]["rect"]])
	if _failures.is_empty():
		print("ART-TOUCHER OK (17 frames + sprites.json updated)")
		quit(0)
	else:
		for msg in _failures:
			print("ART-TOUCHER FAILED: %s" % msg)
		quit(1)
