extends SceneTree
#
# game/tools/validate_sprites.gd - the sprite validator (FLEET_PACK.md T-016 / A8, headless).
#
#   tools\godot\godot.exe --headless --path game --script res://tools/validate_sprites.gd
#
# Walks every game/content/enemies/<id>/sprites.json and checks each listed frame PNG:
#   1. the four corners are alpha 0;
#   2. no opaque 1-px border (every edge pixel has alpha < 16);
#   3. at least 15% of the pixels are fully transparent (ENEMIES.md TRANSPARENCY);
#   4. fog contrast >= 3.0 at 40 u: mean opaque colour vs the palette fog colour,
#      visible(d) = exp(-0.012 * d) (TERRAIN_SPEC.md section 12.3, fog from
#      game/data/palette.json);
#   5. per-frame body_rect in the JSON equals the tight bbox of pixels with alpha > 16
#      (the HITBOXES hard rule: the hitbox is only the body, never the padding).
# Plus the JSON wiring: every listed frame file exists and every sprites/*.png is listed.
#
# Prints "SPRITES OK <checks> checks over <files> PNGs" and exits 0. Any failure prints
# "SPRITES FAILED: ..." lines (all of them, then one summary) and exits 1.

const CONTENT_REL := "content/enemies"
const PALETTE_REL := "data/palette.json"
const FOG_DIST := 40.0                    # TERRAIN_SPEC.md section 12.3
const FOG_DENSITY := 0.012                # per u, palette.json "fog.density"
const MIN_TRANSPARENT := 0.15             # >= 15% of the pixels fully transparent
const FOG_CONTRAST := 3.0                 # WCAG contrast at 40 u
const BORDER_ALPHA := 16                  # a border pixel with alpha >= 16 is opaque padding

var failures: Array[String] = []
var checks := 0


static func _lin(u: float) -> float:
	# sRGB -> linear
	return u / 12.92 if u <= 0.04045 else pow((u + 0.055) / 1.055, 2.4)


static func _lum(c: Color) -> float:
	# WCAG relative luminance on linear colour channels.
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


static func _fog_ratio(mean: Color, fog: Color, fog_density: float) -> float:
	# TERRAIN_SPEC.md section 12.3: on-screen colour = lerp(fog, colour, visible(d)) with
	# visible(d) = exp(-density * d); the contrast is the WCAG ratio of the two on-screen
	# colours, the sprite's mean opaque colour at d = 40 u vs the fog itself. The lerp
	# runs in linear colour space (the space Godot mixes fog in); the palette's hex is sRGB.
	var vis := exp(-fog_density * FOG_DIST)
	var l0 := _lum(fog)
	# the on-screen colour channels are already linear here (never re-linearize);
	var lr: float = _lin(fog.r) + (_lin(mean.r) - _lin(fog.r)) * vis
	var lg: float = _lin(fog.g) + (_lin(mean.g) - _lin(fog.g)) * vis
	var lb: float = _lin(fog.b) + (_lin(mean.b) - _lin(fog.b)) * vis
	var l1 := 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
	var hi := maxf(l1, l0)
	var lo := minf(l1, l0)
	if lo <= 0.0:
		return INF if hi > 0.0 else 1.0
	return (hi + 0.05) / (lo + 0.05)


static func _body_bbox(img: Image) -> Rect2i:
	# Tight bbox of alpha > 16 - the same rule the pipeline used for body_rect.
	var w := img.get_width()
	var h := img.get_height()
	var thr := 16.0 / 255.0
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


func check_frame(img: Image, label: String, expected_rect, fog: Color, fog_density: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var corners := [Vector2i(0, 0), Vector2i(w - 1, 0), Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]
	# 1. four corners alpha 0
	var corner_ok := true
	for c in corners:
		if data[((c.y * w) + c.x) * 4 + 3] != 0:
			corner_ok = false
	checks += 1
	if not corner_ok:
		failures.append("%s: a canvas corner is not alpha 0" % label)
	# 2. no opaque 1-px border
	var border_bad := 0
	for x in w:
		if data[x * 4 + 3] >= BORDER_ALPHA:
			border_bad += 1
		if data[((h - 1) * w + x) * 4 + 3] >= BORDER_ALPHA:
			border_bad += 1
	for y in h:
		if data[(y * w) * 4 + 3] >= BORDER_ALPHA:
			border_bad += 1
		if data[(y * w + w - 1) * 4 + 3] >= BORDER_ALPHA:
			border_bad += 1
	checks += 1
	if border_bad > 0:
		failures.append("%s: %d opaque border pixel(s)" % [label, border_bad])
	# 3. >= 15% fully transparent
	var transparent := 0
	var opaque := 0
	var rr := 0.0
	var gg := 0.0
	var bb := 0.0
	for pi in w * h:
		var a: int = data[pi * 4 + 3]
		if a == 0:
			transparent += 1
		if a >= 128:
			opaque += 1
			rr += data[pi * 4]
			gg += data[pi * 4 + 1]
			bb += data[pi * 4 + 2]
	var tfrac := float(transparent) / float(w * h)
	checks += 1
	if tfrac < MIN_TRANSPARENT:
		failures.append("%s: only %.1f%% transparent (need >= 15%%)" % [label, tfrac * 100.0])
	# 4. fog contrast at 40 u
	checks += 1
	if opaque == 0:
		failures.append("%s: no opaque body at all" % label)
	else:
		var mean := Color(rr / (opaque * 255.0), gg / (opaque * 255.0), bb / (opaque * 255.0))
		var ratio := _fog_ratio(mean, fog, fog_density)
		if OS.get_environment("SPRITE_DEBUG") == "1":
			print("DBG %s mean=%s fog=%s dens=%s ratio=%.3f" % [label, mean, fog, fog_density, ratio])
		if ratio < FOG_CONTRAST:
			failures.append("%s: fog contrast %.2f < 3.0 at %.0f u" % [label, ratio, FOG_DIST])
	# 5. body_rect equals the alpha > 16 bbox
	if expected_rect != null:
		checks += 1
		var bbox := _body_bbox(img)
		var want: Array = expected_rect
		var want_i := [int(want[0]), int(want[1]), int(want[2]), int(want[3])]
		var got := [bbox.position.x, bbox.position.y, bbox.size.x, bbox.size.y]
		if got != want_i:
			failures.append("%s: body_rect %s != tight bbox %s" % [label, str(want_i), str(got)])


func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var content_dir: String = game_dir + "/" + CONTENT_REL
	# fog facts straight from the palette file (TERRAIN_SPEC.md section 12.2/12.3)
	var fog := Color(2.0 / 255.0, 20.0 / 255.0, 22.0 / 255.0)
	var fog_density := FOG_DENSITY
	var pf := FileAccess.open(game_dir + "/" + PALETTE_REL, FileAccess.READ)
	if pf == null:
		print("SPRITES FAILED: cannot read %s" % PALETTE_REL)
		quit(1)
		return
	var parsed = JSON.parse_string(pf.get_as_text())
	if parsed is Dictionary and parsed.has("fog"):
		fog = Color(String(parsed["fog"]["color"]))
		fog_density = float(parsed["fog"]["density"])

	var enemy_dir := DirAccess.open(content_dir)
	if enemy_dir == null:
		print("SPRITES FAILED: cannot open %s" % CONTENT_REL)
		quit(1)
		return
	var json_count := 0
	for enemy_id in enemy_dir.get_directories():
		var edir := DirAccess.open(content_dir + "/" + enemy_id)
		if edir == null or not FileAccess.file_exists(content_dir + "/" + enemy_id + "/sprites.json"):
			continue
		json_count += 1
		var jf := FileAccess.open(content_dir + "/" + enemy_id + "/sprites.json", FileAccess.READ)
		var j: Variant = JSON.parse_string(jf.get_as_text())
		if not (j is Dictionary):
			failures.append("%s: sprites.json does not parse" % enemy_id)
			continue
		var listed := {}
		for anim in j.get("animations", []):
			var files: Array = anim.get("frames", [])
			var rects: Array = anim.get("body_rect", [])
			if files.size() != rects.size() and rects.size() > 0:
				failures.append("%s/%s: frames (%d) != body_rect (%d)" % [enemy_id, anim.get("name"), files.size(), rects.size()])
			for f in range(files.size()):
				var fpath: String = content_dir + "/" + enemy_id + "/" + str(files[f])
				listed[str(files[f])] = true
				if not FileAccess.file_exists(fpath):
					failures.append("%s: missing frame file %s" % [enemy_id, files[f]])
					continue
				var img := Image.load_from_file(fpath)
				check_frame(img, "%s/%s" % [enemy_id, str(files[f])],
					rects[f] if f < rects.size() else null, fog, fog_density)
		# every PNG on disk is listed in the json
		var sdir := DirAccess.open(content_dir + "/" + enemy_id + "/sprites")
		if sdir != null:
			for f in sdir.get_files():
				if f.ends_with(".png") and not listed.has("sprites/" + f):
					failures.append("%s: sprites/%s exists but is not listed in sprites.json" % [enemy_id, f])
	if json_count == 0:
		failures.append("no game/content/enemies/<id>/sprites.json found - nothing validated")
	for msg in failures:
		print("SPRITES FAILED: %s" % msg)
	print("SPRITES %s %d checks over %d sprites.json" % ["OK" if failures.is_empty() else "FAILED", checks, json_count])
	quit(1 if not failures.is_empty() else 0)

