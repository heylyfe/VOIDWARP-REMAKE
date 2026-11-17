extends SceneTree
#
# game/tools/art/you.gd - YOU?! ("YOU?!", enemy id "you") real-art module.
# Ticket: art wave for YOU?! - turns assets_src/enemies/character to be corrupted.png
# (an OPAQUE render on a smooth grey gradient; the white head has no luminance edge
# against the background) into the sprite sheet + one distinct frame per state of the
# T-083 anim block in game/content/enemies/you/sprites.json.
#
#   (godot) --headless --path game --script res://tools/art/you.gd
#
# Deterministic: no unseeded randomness (frame slice displacement uses seeded RNGs).
# Re-running rewrites the same bytes and rebuilds sprites.json idempotently
# (animations[0] is rewritten in place; the per-state entries replace/append by name).
# Art decisions: DECISIONS.md D-ART-YOU-1 (segmentation) and D-ART-YOU-2 (canvas,
# lift, per-state effects). A8 thresholds are never touched; the art is lifted to pass.

const SRC_REL := "assets_src/enemies/character to be corrupted.png"
const SPRITES_DIR_REL := "content/enemies/you/sprites"
const SPRITES_JSON_REL := "content/enemies/you/sprites.json"

const CANVAS := 512          # largest power of two allowed
const FEET_Y := 496          # bottom anchor row for the feet (16 px margin)
const FIT_H := 460           # body pixel height in the canvas
const MARGIN := 16

const LIFT_MUL := 0.72       # D-ART-YOU-2 contrast lift (sRGB), cool steel cast
const LIFT_ADD := Color(0.29, 0.345, 0.39)
const SAT := 1.15            # mild saturation restore after the lift
const RIM_MIX := 0.35        # 1-px silhouette edge blended toward pale pink
const RIM_COL := Color(1.0, 0.83, 0.89)

var src: Image
var w: int
var h: int

var _keep: PackedByteArray
var _crop: Image              # RGBA crop of the kept body, pre-lift
var _crop_lifted: Image       # lifted + rimmed, ready to scale


func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var repo_root := game_dir.get_base_dir()
	var sprites_dir := game_dir + "/" + SPRITES_DIR_REL
	var sprites_json := game_dir + "/" + SPRITES_JSON_REL
	var src_path := repo_root + "/" + SRC_REL

	src = Image.load_from_file(src_path)
	if src == null:
		printerr("you.gd: cannot load %s" % src_path)
		quit(1)
		return
	w = src.get_width()
	h = src.get_height()

	_keep = _segment()
	_crop = _extract_crop()
	_crop_lifted = _lift_and_rim(_crop)

	DirAccess.make_dir_recursive_absolute(sprites_dir)

	var frames := _render_all(sprites_dir)
	_update_sprites_json(frames, sprites_json)
	print("you.gd: wrote %d frames into %s" % [frames.size(), sprites_dir])
	quit()


# ---- segmentation (D-ART-YOU-1) -------------------------------------------------

func _segment() -> PackedByteArray:
	var bg := _flood_from_border(0.025)
	var flood_keep := PackedByteArray()
	flood_keep.resize(w * h)
	for i in w * h:
		flood_keep[i] = 1 - bg[i]
	# dark core: body, limbs, crown band, mouth - kept everywhere
	var dark := PackedByteArray()
	dark.resize(w * h)
	for i in w * h:
		var c = src.get_pixel(i % w, i / w)
		dark[i] = 1 if c.get_luminance() < 0.5 else 0
	# crown zone (y < 145): the white spikes sit within 4 px of dark gaps/core
	var dil4 := _dilate(dark, 4)
	# head ellipse (hand-fitted to the owner image; the head has no colour edge)
	var keep := PackedByteArray()
	keep.resize(w * h)
	keep.fill(0)
	var ecx := 200.0
	var ecy := 171.0
	var erx := 74.0
	var ery := 46.0
	var dil2 := _dilate(dark, 2)
	for y in h:
		for x in w:
			var i := y * w + x
			if dark[i] == 1:
				keep[i] = 1
				continue
			var dx := (float(x) - ecx) / erx
			var dy := (float(y) - ecy) / ery
			if dx * dx + dy * dy <= 1.0:
				keep[i] = 1
				continue
			if y < 145 and dil4[i] == 1:
				keep[i] = 1
				continue
			# soft edge: 2-px ring around the core, verified against the border flood
			if dil2[i] == 1 and flood_keep[i] == 1:
				keep[i] = 1
	return keep


func _flood_from_border(tol: float) -> PackedByteArray:
	# local-neighbourhood flood fill from the four borders (gradient-safe)
	var bg := PackedByteArray()
	bg.resize(w * h)
	bg.fill(0)
	var queue := PackedInt32Array()
	for x in w:
		queue.append(x)
		queue.append((h - 1) * w + x)
	for y in h:
		queue.append(y * w)
		queue.append(y * w + w - 1)
	for i in queue.size():
		bg[queue[i]] = 1
	var head_i := 0
	var nb := [[1, 0], [-1, 0], [0, 1], [0, -1]]
	while head_i < queue.size():
		var idx: int = queue[head_i]
		head_i += 1
		var cx: int = idx % w
		var cy: int = idx / w
		var cc = src.get_pixel(cx, cy)
		for d in nb:
			var nx: int = cx + d[0]
			var ny: int = cy + d[1]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var nidx: int = ny * w + nx
			if bg[nidx] == 1:
				continue
			var nc = src.get_pixel(nx, ny)
			var dist: float = sqrt(
				pow(nc.r - cc.r, 2.0) + pow(nc.g - cc.g, 2.0) + pow(nc.b - cc.b, 2.0))
			if dist <= tol:
				bg[nidx] = 1
				queue.append(nidx)
	return bg


func _dilate(mask: PackedByteArray, dist: int) -> PackedByteArray:
	var cur := mask.duplicate()
	var nb := [[1, 0], [-1, 0], [0, 1], [0, -1]]
	for _i in dist:
		var nxt := cur.duplicate()
		for idx in w * h:
			if cur[idx] == 1:
				continue
			var cx: int = idx % w
			var cy: int = idx / w
			for d in nb:
				var nx: int = cx + d[0]
				var ny: int = cy + d[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				if cur[ny * w + nx] == 1:
					nxt[idx] = 1
					break
		cur = nxt
	return cur


func _extract_crop() -> Image:
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if _keep[y * w + x] == 1:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return null
	var cw := x1 - x0 + 1
	var ch := y1 - y0 + 1
	var out := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
	for y in ch:
		for x in cw:
			var c = src.get_pixel(x0 + x, y0 + y)
			c.a = 1.0 if _keep[(y0 + y) * w + x0 + x] == 1 else 0.0
			out.set_pixel(x, y, c)
	return out


func _lift_and_rim(img: Image) -> Image:
	var out := img.duplicate()
	var iw = out.get_width()
	var ih = out.get_height()
	# lift: dark blacks up into readable range (fog contrast is checked per frame)
	for y in ih:
		for x in iw:
			var c = out.get_pixel(x, y)
			if c.a == 0.0:
				continue
			c.r = clampf(c.r * LIFT_MUL + LIFT_ADD.r, 0.0, 1.0)
			c.g = clampf(c.g * LIFT_MUL + LIFT_ADD.g, 0.0, 1.0)
			c.b = clampf(c.b * LIFT_MUL + LIFT_ADD.b, 0.0, 1.0)
			var lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			c.r = clampf(lum + (c.r - lum) * SAT, 0.0, 1.0)
			c.g = clampf(lum + (c.g - lum) * SAT, 0.0, 1.0)
			c.b = clampf(lum + (c.b - lum) * SAT, 0.0, 1.0)
			out.set_pixel(x, y, c)
	# rim: boundary pixels blend toward pale pink
	for y in ih:
		for x in iw:
			var c = out.get_pixel(x, y)
			if c.a == 0.0:
				continue
			var edge := false
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = x + d[0]
				var ny: int = y + d[1]
				if nx < 0 or ny < 0 or nx >= iw or ny >= ih:
					edge = true
					break
				if out.get_pixel(nx, ny).a == 0.0:
					edge = true
					break
			if edge:
				c.r = lerpf(c.r, RIM_COL.r, RIM_MIX)
				c.g = lerpf(c.g, RIM_COL.g, RIM_MIX)
				c.b = lerpf(c.b, RIM_COL.b, RIM_MIX)
				out.set_pixel(x, y, c)
	return out


# ---- frame rendering -------------------------------------------------------------

func _render_all(sprites_dir: String) -> Dictionary:
	var scale = float(FIT_H) / float(_crop_lifted.get_height())
	var body_w = int(round(float(_crop_lifted.get_width()) * scale))
	var body := _crop_lifted.duplicate()
	body.resize(body_w, FIT_H, Image.INTERPOLATE_BILINEAR)
	body = _flatten_alpha(body)

	# the five chase-cycle looks (shared by cycle_NN and you_idle_NN content)
	var idle_specs := [
		{},                                             # 00 neutral
		{"sy": 0.94, "sx": 1.04, "bob": -6.0},           # 01 squash low
		{"sy": 1.05, "sx": 0.96, "bob": 8.0, "rot": 0.035}, # 02 stretch high, lean right
		{"sy": 0.94, "sx": 1.04, "bob": -6.0, "rot": -0.035}, # 03 squash low, lean left
		{"sy": 1.05, "sx": 0.96, "bob": 8.0},            # 04 stretch high
	]
	var specs := []
	for i in 5:
		var idle: Dictionary = idle_specs[i].duplicate()
		idle["file"] = "you_idle_%02d.png" % i
		specs.append(idle)
	specs.append({"file": "you_spawn_00.png", "flash": 0.45, "sy": 1.06,
			"slices": 4, "slice_seed": 77})
	for i in [
		[0, 1, 0.0], [1, 2, 0.08], [2, 3, 0.16], [3, 4, 0.24], [4, 6, 0.30]]:
		var t: Dictionary = {"file": "you_telegraph_%02d.png" % int(i[0]), "ghost": int(i[1]),
			"red": float(i[2])}
		if int(i[0]) >= 2:
			t["slices"] = int(i[0]) + 1
			t["slice_seed"] = 1984
		specs.append(t)
	specs.append({"file": "you_attack_00.png", "flash": 0.60, "mirror": true, "sy": 1.07})
	var rec := [[0.70, 0.94], [0.50, 0.96], [0.32, 0.97], [0.15, 0.985], [0.0, 1.0]]
	for i in 5:
		specs.append({"file": "you_recover_%02d.png" % i,
			"desat": rec[i][0], "dim": rec[i][1]})
	# cycle_00..04: identical renders of the idle set, written under the kept names
	for i in 5:
		var c: Dictionary = idle_specs[i].duplicate()
		c["file"] = "cycle_%02d.png" % i
		specs.append(c)

	var out := {}
	for spec in specs:
		var img := _render_frame(body, spec)
		var rel: String = "sprites/" + str(spec["file"])
		var dst := sprites_dir + "/" + str(spec["file"])
		img.save_png(dst)
		out[rel] = _bbox(img)
		print("you.gd: %s body_rect %s" % [rel, str(out[rel])])
	return out


func _flatten_alpha(img: Image) -> Image:
	# snap near-zero alpha to 0 so resize halos never leave a dust border
	var out := img.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c = out.get_pixel(x, y)
			if c.a < 0.09:
				c.a = 0.0
				out.set_pixel(x, y, c)
	return out


func _sample_nearest(img: Image, x: float, y: float) -> Color:
	var ix := int(floor(x))
	var iy := int(floor(y))
	if ix < 0 or iy < 0 or ix >= img.get_width() or iy >= img.get_height():
		return Color(0, 0, 0, 0)
	return img.get_pixel(ix, iy)


func _render_frame(body: Image, spec: Dictionary) -> Image:
	var img := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var src_body := body
	if bool(spec.get("mirror", false)):
		src_body = body.duplicate()
		src_body.flip_x()
	var bw = src_body.get_width()
	var bh = src_body.get_height()
	var angle := float(spec.get("rot", 0.0))
	var sx := float(spec.get("sx", 1.0))
	var sy := float(spec.get("sy", 1.0))
	var bob := float(spec.get("bob", 0.0))
	var ax := CANVAS * 0.5
	var ay := FEET_Y - bob
	var ca := cos(angle)
	var sa := sin(angle)
	# bounding box of the transformed corners, so the loop stays local
	var corners := [Vector2(0, 0), Vector2(bw, 0), Vector2(0, bh), Vector2(bw, bh)]
	var bx0 := CANVAS
	var by0 := CANVAS
	var bx1 := -1
	var by1 := -1
	for corner in corners:
		var rx: float = (corner.x - bw * 0.5) * sx
		var ry: float = (corner.y - bh) * sy
		var wx := ax + rx * ca - ry * sa
		var wy := ay + rx * sa + ry * ca
		bx0 = mini(bx0, int(floor(wx)) - 1)
		by0 = mini(by0, int(floor(wy)) - 1)
		bx1 = maxi(bx1, int(ceil(wx)) + 1)
		by1 = maxi(by1, int(ceil(wy)) + 1)
	bx0 = maxi(bx0, 0)
	by0 = maxi(by0, 0)
	bx1 = mini(bx1, CANVAS - 1)
	by1 = mini(by1, CANVAS - 1)
	for y in range(by0, by1 + 1):
		for x in range(bx0, bx1 + 1):
			var vx := float(x) - ax
			var vy := float(y) - ay
			var rx := vx * ca + vy * sa
			var ry := -vx * sa + vy * ca
			rx /= sx
			ry /= sy
			var c := _sample_nearest(src_body, rx + bw * 0.5, ry + bh)
			if c.a > 0.0:
				img.set_pixel(x, y, c)
	return _post(img, spec)


# ---- per-state post effects (D-ART-YOU-2) -------------------------------------------

func _post(img: Image, spec: Dictionary) -> Image:
	var ghost := int(spec.get("ghost", 0))
	if ghost > 0:
		var base := img.duplicate()
		var ga := _tinted(base, Color(1.0, 0.16, 0.16), 0.6)
		var gb := _tinted(base, Color(0.23, 0.78, 1.0), 0.6)
		var out := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
		out.fill(Color(0, 0, 0, 0))
		_over(out, ga, -ghost, 0)
		_over(out, gb, ghost, 0)
		_over(out, base, 0, 0)
		img = out
	var red := float(spec.get("red", 0.0))
	if red > 0.0:
		img = _mix_to(img, Color(1.0, 0.16, 0.16), red)
	var flash := float(spec.get("flash", 0.0))
	if flash > 0.0:
		img = _mix_to(img, Color(1.0, 0.95, 0.95), flash)
	var desat := float(spec.get("desat", 0.0))
	var dim := float(spec.get("dim", 1.0))
	if desat > 0.0 or dim != 1.0:
		var out := img.duplicate()
		for y in CANVAS:
			for x in CANVAS:
				var c = out.get_pixel(x, y)
				if c.a == 0.0:
					continue
				var lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				c.r = lerpf(c.r, lum, desat) * dim
				c.g = lerpf(c.g, lum, desat) * dim
				c.b = lerpf(c.b, lum, desat) * dim
				out.set_pixel(x, y, c)
		img = out
	var slices := int(spec.get("slices", 0))
	if slices > 0:
		img = _slice_shift(img, slices, int(spec.get("slice_seed", 1984)))
	return img


func _tinted(img: Image, tint: Color, alpha_mul: float) -> Image:
	var out := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	for y in CANVAS:
		for x in CANVAS:
			var c = img.get_pixel(x, y)
			if c.a == 0.0:
				continue
			out.set_pixel(x, y, Color(
				lerpf(c.r, tint.r, 0.7),
				lerpf(c.g, tint.g, 0.7),
				lerpf(c.b, tint.b, 0.7),
				c.a * alpha_mul))
	return out


func _over(dst: Image, src_img: Image, ox: int, oy: int) -> void:
	for y in CANVAS:
		for x in CANVAS:
			var sx := x - ox
			var sy := y - oy
			if sx < 0 or sy < 0 or sx >= CANVAS or sy >= CANVAS:
				continue
			var s = src_img.get_pixel(sx, sy)
			if s.a == 0.0:
				continue
			var d = dst.get_pixel(x, y)
			var sa = s.a
			var da = d.a
			var oa = sa + da * (1.0 - sa)
			if oa <= 0.0:
				continue
			dst.set_pixel(x, y, Color(
				(s.r * sa + d.r * da * (1.0 - sa)) / oa,
				(s.g * sa + d.g * da * (1.0 - sa)) / oa,
				(s.b * sa + d.b * da * (1.0 - sa)) / oa,
				oa))


func _mix_to(img: Image, col: Color, k: float) -> Image:
	var out := img.duplicate()
	for y in CANVAS:
		for x in CANVAS:
			var c = out.get_pixel(x, y)
			if c.a == 0.0:
				continue
			c.r = lerpf(c.r, col.r, k)
			c.g = lerpf(c.g, col.g, k)
			c.b = lerpf(c.b, col.b, k)
			out.set_pixel(x, y, c)
	return out


func _slice_shift(img: Image, slices: int, seed: int) -> Image:
	var out := img.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for _i in slices:
		var band_h := rng.randi_range(4, 9)
		var band_y := rng.randi_range(0, CANVAS - band_h)
		var shift := rng.randi_range(-7, 7)
		if shift == 0:
			shift = 3
		var band: Array[Color] = []
		for y in range(band_y, band_y + band_h):
			for x in CANVAS:
				band.append(out.get_pixel(x, y))
		for y in range(band_y, band_y + band_h):
			for x in CANVAS:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
		for y in range(band_y, band_y + band_h):
			for x in CANVAS:
				var src_x := x - shift
				if src_x < 0 or src_x >= CANVAS:
					continue
				out.set_pixel(x, y, band[(y - band_y) * CANVAS + src_x])
	return out


func _bbox(img: Image) -> Array:
	var thr := 16.0 / 255.0
	var x0 = img.get_width()
	var y0 = img.get_height()
	var x1 := -1
	var y1 := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > thr:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < 0:
		return [0, 0, 0, 0]
	return [x0, y0, x1 - x0 + 1, y1 - y0 + 1]


# ---- sprites.json rewrite (surgical text edit, idempotent) ----------------------
#
# The file is tab-indented JSON whose key order is deliberate for human review, and
# Godot's JSON.stringify sorts keys alphabetically - so instead of a parse/serialize
# round trip we patch the raw text. Re-running is a no-op for the anim block (the
# TBD cycle literals are already gone) and rewrites animations[] from scratch.

func _update_sprites_json(frames: Dictionary, json_path: String) -> void:
	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		printerr("you.gd: cannot read %s" % json_path)
		quit(1)
		return
	var text := f.get_as_text()
	f.close()

	var idle_files := []
	var telegraph_files := []
	var recover_files := []
	var cycle_files := []
	for i in 5:
		idle_files.append("sprites/you_idle_%02d.png" % i)
		telegraph_files.append("sprites/you_telegraph_%02d.png" % i)
		recover_files.append("sprites/you_recover_%02d.png" % i)
		cycle_files.append("sprites/cycle_%02d.png" % i)
	var single_cycle := "\"frames\": [\"sprites/cycle_00.png\"],"
	var single_cycle4 := "\"frames\": [\"sprites/cycle_04.png\"],"
	var five := "\"frames\": [\"sprites/cycle_00.png\", \"sprites/cycle_01.png\", \"sprites/cycle_02.png\", \"sprites/cycle_03.png\", \"sprites/cycle_04.png\"],"

	text = text.replace('"tbd": true', '"tbd": false')
	# anim block states, in file order: spawn, idle_chase, telegraph, attack, recover.
	# On a re-run the cycle literals are already gone and these are no-ops.
	text = _replace_nth(text, single_cycle,
		"\"frames\": [\"sprites/you_spawn_00.png\"],", 0)
	text = _replace_nth(text, five, _inline_frames(idle_files), 0)
	text = _replace_nth(text, five, _inline_frames(telegraph_files), 0)
	text = _replace_nth(text, five, _inline_frames(recover_files), 0)
	text = text.replace(single_cycle4,
		"\"frames\": [\"sprites/you_attack_00.png\"],")

	# animations[]: everything from '\t"animations": [' to the line '\t],' before '"id"'
	var a_start := text.find("\t\"animations\": [")
	var a_end := text.find("\n\t],\n\t\"id\"", a_start)
	if a_start < 0 or a_end < 0:
		printerr("you.gd: cannot locate animations[] block in sprites.json")
		quit(1)
		return
	var state_files := {
		"spawn": ["sprites/you_spawn_00.png"],
		"idle_chase": idle_files,
		"telegraph": telegraph_files,
		"attack": ["sprites/you_attack_00.png"],
		"recover": recover_files,
	}
	var fps_map := {"spawn": [8, false], "idle_chase": [8, true],
		"telegraph": [16, true], "attack": [8, false], "recover": [8, true]}
	var anims_text := "\t\"animations\": [\n"
	var entries := []
	entries.append(_anim_entry("cycle", 8, true, cycle_files, frames))
	for id in ["spawn", "idle_chase", "telegraph", "attack", "recover"]:
		entries.append(_anim_entry(id, int(fps_map[id][0]), bool(fps_map[id][1]),
			state_files[id], frames))
	anims_text += ",\n".join(entries)
	anims_text += "\n\t],"
	text = text.substr(0, a_start) + anims_text + text.substr(a_end + len("\n\t],"))

	var out := FileAccess.open(json_path, FileAccess.WRITE)
	out.store_string(text)
	out.close()
	# verify round trip before declaring success
	var check = JSON.parse_string(FileAccess.open(json_path, FileAccess.READ).get_as_text())
	if not (check is Dictionary):
		printerr("you.gd: sprites.json failed to re-parse after patching")
		quit(1)
		return
	var anims: Array = check.get("animations", [])
	if anims.is_empty() or str(anims[0].get("name", "")) != "cycle":
		printerr("you.gd: animations[0] is not 'cycle' after patching")
		quit(1)
		return
	var state_files2 := {
		"spawn": ["sprites/you_spawn_00.png"],
		"idle_chase": idle_files,
		"telegraph": telegraph_files,
		"attack": ["sprites/you_attack_00.png"],
		"recover": recover_files,
	}
	var ok := true
	for id in state_files2:
		if check["anim"]["states"][id]["frames"] != state_files2[id]:
			printerr("you.gd: state '%s' frames did not take after patching" % id)
			ok = false
	if int(check.get("tbd", 1)) != 0:
		printerr("you.gd: tbd flag did not clear")
		ok = false
	if not ok:
		quit(1)
		return
	print("you.gd: sprites.json updated (tbd=false, anim block repointed, %d animations)" % anims.size())


func _inline_frames(files: Array) -> String:
	var quoted := []
	for f in files:
		quoted.append('"' + str(f) + '"')
	return "\"frames\": [" + ", ".join(quoted) + "],"


func _replace_nth(text: String, needle: String, repl: String, n: int) -> String:
	# replace only the nth occurrence (0-based); missing occurrence = idempotent re-run
	var idx := -1
	for _i in n + 1:
		idx = text.find(needle, idx + 1)
		if idx < 0:
			print("you.gd: pattern already absent (re-run?): %s" % needle.substr(0, 40))
			return text
	return text.substr(0, idx) + repl + text.substr(idx + needle.length())


func _anim_entry(name: String, fps: int, loop: bool, files: Array, frames: Dictionary) -> String:
	var lines := []
	lines.append("\t\t{")
	lines.append("\t\t\t\"body_rect\": [")
	var rect_lines := []
	for f in files:
		var r: Array = frames[f]
		rect_lines.append("\t\t\t\t[%d, %d, %d, %d]" % [int(r[0]), int(r[1]), int(r[2]), int(r[3])])
	lines.append(",\n".join(rect_lines))
	lines.append("\t\t\t],")
	lines.append("\t\t\t\"fps\": %d," % fps)
	lines.append("\t\t\t\"frames\": [")
	var frame_lines := []
	for f in files:
		frame_lines.append("\t\t\t\t\"%s\"" % f)
	lines.append(",\n".join(frame_lines))
	lines.append("\t\t\t],")
	lines.append("\t\t\t\"loop\": %s," % ("true" if loop else "false"))
	lines.append("\t\t\t\"name\": \"%s\"" % name)
	lines.append("\t\t}")
	return "\n".join(lines)
