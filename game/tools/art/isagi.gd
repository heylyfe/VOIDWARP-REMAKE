extends SceneTree
# game/tools/art/isagi.gd - Isagi's sprite art generator (T-016 art module for Isagi;
# ENEMIES.md "Attachment mapping" images 4/5/6). Run headless:
#
#   tools\godot\godot.exe --headless --path game --script res://tools/art/isagi.gd
#
# The shared pipeline (game/tools/sprite_pipeline.gd) removes backgrounds with a flood fill
# from the four corners at colour tolerance 24/255 - on an opaque photo/logo that fill eats
# the whole image ("NO BODY AFTER BACKGROUND REMOVAL -> TBD"). This module owns the isagi
# frames instead (the pipeline skips any enemy with tools/art/<id>.gd):
#   1. loads assets_src/enemies/isagi_idle.jpeg (192x500, opaque white),
#      ISAGI_SHOOT.webp (855x1168, opaque white) and blueballprojectile.webp
#      (1255x1255, corners already alpha 0);
#   2. removes the background: border-sampled reference colour + distance threshold,
#      flood fill from the border (alpha channel kept where the source already has one),
#      tight crop to alpha > 16 with a transparent margin of MARGIN px so no opaque pixel
#      touches the canvas edge;
#   3. fits the body onto a power-of-two canvas (each side <= 512), bottom-anchored for
#      the standing body frames, centred for the ball;
#   4. derives a DISTINCT frame per anim-block state (spawn / idle / telegraph / attack /
#      recover) and per frames[] entry, deterministically (squash, brightness, red rim, dim);
#   5. rewrites content/enemies/isagi/sprites.json (frames, frame_map, per-frame body_rect,
#      animations[] appended, tbd=false) and SOURCES.md.
#
# Deterministic: no randomness at all - a re-run reproduces byte-identical PNGs.
# The derivation recipe and its [CONTESTABLE] art numbers are DECISIONS.md D-ART-ISAGI-1.

const MARGIN := 8
const CANVAS_MAX := 512
const POT_MIN := 64
const BODY_ALPHA := 16.0     # the validator's body rule: alpha > 16 counts as body
const BG_TOL := 72.0         # euclidean distance from the border reference colour

var failures: Array[String] = []

func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var root := game_dir.get_base_dir()
	var src_dir := root + "/assets_src/enemies"
	var out_dir := game_dir + "/content/enemies/isagi"
	var sprite_dir := out_dir + "/sprites"
	DirAccess.make_dir_recursive_absolute(sprite_dir)

	var idle_src := Image.load_from_file(src_dir + "/isagi_idle.jpeg")
	var shoot_src := Image.load_from_file(src_dir + "/ISAGI_SHOOT.webp")
	var ball_src := Image.load_from_file(src_dir + "/blueballprojectile.webp")
	var loaded := [["isagi_idle.jpeg", idle_src], ["ISAGI_SHOOT.webp", shoot_src], ["blueballprojectile.webp", ball_src]]
	for pair in loaded:
		if pair[1] == null:
			print("ISAGI ART FAILED: cannot load %s" % str(pair[0]))
			quit(1)
			return

	var idle_body := _lift(_crop_body(_strip_bg_white(idle_src)), 0.55)
	var shoot_body := _lift(_crop_body(_strip_bg_white(shoot_src)), 0.45)
	var ball_body := _crop_body(_strip_alpha(ball_src))
	var bodies := [["isagi_idle.jpeg", idle_body], ["ISAGI_SHOOT.webp", shoot_body], ["blueballprojectile.webp", ball_body]]
	for pair in bodies:
		if pair[1] == null:
			print("ISAGI ART FAILED: no body after background removal for %s" % str(pair[0]))
			quit(1)
			return

	# canvas-fitted frames; every state in the anim block (and every frame its states list)
	# gets a distinct image. fire_00/fire_02 are the idle/shoot art under the legacy names.
	var frames := {}
	frames["idle_00"] = _fit(idle_body, true)
	frames["spawn_00"] = _fit(_spawn_fx(idle_body), true)
	frames["telegraph_00"] = _fit(_red_rim(idle_body), true)
	frames["shoot_00"] = _fit(shoot_body, true)
	frames["recover_00"] = _fit(_dim(idle_body, 0.7), true)
	frames["shot_00"] = _fit(ball_body, false)
	frames["fire_00"] = frames["idle_00"]
	frames["fire_01"] = _fit(_squash(idle_body, 0.90, 1.06), true)
	frames["fire_02"] = frames["shoot_00"]

	var rects := {}
	for fname in frames.keys():
		var img: Image = frames[fname]
		var err := img.save_png(sprite_dir + "/" + str(fname) + ".png")
		if err != OK:
			failures.append("save %s.png: error %d" % [str(fname), err])
		rects[fname] = _body_rect(img)

	var src_pixels := {"idle": idle_body.get_width() * idle_body.get_height(),
		"shoot": shoot_body.get_width() * shoot_body.get_height(),
		"shot": ball_body.get_width() * ball_body.get_height()}

	_write_sprites_json(out_dir, rects, src_pixels)
	_write_sources_md(out_dir)

	if not failures.is_empty():
		for msg in failures:
			print("ISAGI ART FAILED: %s" % msg)
		quit(1)
		return
	for fname in frames.keys():
		var r: Rect2i = rects[fname]
		print("ISAGI ART frame %s.png body_rect [%d, %d, %d, %d]" % [str(fname), r.position.x, r.position.y, r.size.x, r.size.y])
	print("ISAGI ART OK (%d frames)" % frames.size())
	quit(0)

# ---- fitting, derived frames, bbox -----------------------------------------------------------

static func _pot(n: int) -> int:
	var p := POT_MIN
	while p < n and p < CANVAS_MAX:
		p *= 2
	return mini(p, CANVAS_MAX)

func _fit(body: Image, bottom: bool) -> Image:
	var w := body.get_width()
	var h := body.get_height()
	var max_side := CANVAS_MAX - 2 * MARGIN
	var src := body
	if maxi(w, h) > max_side:
		var scale := float(max_side) / float(maxi(w, h))
		src = body.duplicate()
		src.resize(maxi(1, int(round(w * scale))), maxi(1, int(round(h * scale))), Image.INTERPOLATE_LANCZOS)
		w = src.get_width()
		h = src.get_height()
	var cw := _pot(w + 2 * MARGIN)
	var ch := _pot(h + 2 * MARGIN)
	var canvas := Image.create_empty(cw, ch, false, Image.FORMAT_RGBA8)
	var dx := (cw - w) / 2
	var dy := (ch - h - MARGIN) if bottom else (ch - h) / 2
	canvas.blit_rect(src, Rect2i(0, 0, w, h), Vector2i(dx, dy))
	return canvas

static func _squash(body: Image, sy: float, sx: float) -> Image:
	var out: Image = body.duplicate()
	out.resize(maxi(1, int(round(body.get_width() * sx))), maxi(1, int(round(body.get_height() * sy))), Image.INTERPOLATE_LANCZOS)
	return out

static func _lift(body: Image, strength: float) -> Image:
	# lerp toward white: c' = c + (1 - c) * strength. Stronger on darks than a pow curve,
	# which the idle's dark manga mass needs; the recover frame is this lifted body at the
	# binding x0.7, so the lift is what buys recover its fog-contrast margin; alpha untouched
	var out: Image = body.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(c.r + (1.0 - c.r) * strength, c.g + (1.0 - c.g) * strength, c.b + (1.0 - c.b) * strength, c.a))
	return out

static func _dim(body: Image, factor: float) -> Image:
	var out: Image = body.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x, y, Color(minf(1.0, c.r * factor), minf(1.0, c.g * factor), minf(1.0, c.b * factor), c.a))
	return out

static func _spawn_fx(body: Image) -> Image:
	# materialize look under the binding common_fade (runtime alpha 0 -> 1): brighter body
	# lerped toward the palette player_fill_light cyan-white
	var out: Image = body.duplicate()
	var tint := Color(0.75, 1.0, 0.97)
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				var r := lerpf(minf(1.0, c.r * 1.3), tint.r, 0.35)
				var g := lerpf(minf(1.0, c.g * 1.3), tint.g, 0.35)
				var b := lerpf(minf(1.0, c.b * 1.3), tint.b, 0.35)
				out.set_pixel(x, y, Color(r, g, b, c.a))
	return out

static func _red_rim(body: Image) -> Image:
	# red rim flash baked around the silhouette: Chebyshev 2 px ring, #FF2A2A
	var w := body.get_width()
	var h := body.get_height()
	var thr := BODY_ALPHA / 255.0
	var opaque := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= w or y >= h:
			return false
		return body.get_pixel(x, y).a > thr
	var out: Image = body.duplicate()
	for y in h:
		for x in w:
			if opaque.call(x, y):
				continue
			var best := 3
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if dx == 0 and dy == 0:
						continue
					var d := maxi(absi(dx), absi(dy))
					if d >= best:
						continue
					if opaque.call(x + dx, y + dy):
						best = d
			if best <= 2:
				var a := 0.85 if best == 1 else 0.45
				out.set_pixel(x, y, Color(1.0, 0.165, 0.165, a))
	return out

static func _body_rect(img: Image) -> Rect2i:
	# tight bbox of alpha > BODY_ALPHA - the same rule the validator uses
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

static func _rect_json(r: Rect2i) -> Array:
	return [r.position.x, r.position.y, r.size.x, r.size.y]

# ---- background removal --------------------------------------------------------------------

static func _dist(r: float, g: float, b: float, ref: Color) -> float:
	var dr := r - ref.r
	var dg := g - ref.g
	var db := b - ref.b
	return sqrt(dr * dr + dg * dg + db * db)

func _strip_bg_white(src: Image) -> Image:
	# Opaque-white sources: border-sampled reference colour, flood fill from the border.
	var img: Image = src.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var c0 := img.get_pixel(0, 0)
	var c1 := img.get_pixel(w - 1, 0)
	var c2 := img.get_pixel(0, h - 1)
	var c3 := img.get_pixel(w - 1, h - 1)
	var ref := Color((c0.r + c1.r + c2.r + c3.r) * 0.25,
		(c0.g + c1.g + c2.g + c3.g) * 0.25,
		(c0.b + c1.b + c2.b + c3.b) * 0.25)
	var visited := PackedByteArray()
	visited.resize(w * h)
	var stack: Array[Vector2i] = []
	for x in w:
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	for y in h:
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(w - 1, y))
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if visited[idx] == 1:
			continue
		visited[idx] = 1
		var c := img.get_pixel(p.x, p.y)
		if _dist(c.r, c.g, c.b, ref) > BG_TOL / 255.0:
			continue
		img.set_pixel(p.x, p.y, Color(c.r, c.g, c.b, 0.0))
		stack.append(Vector2i(p.x + 1, p.y))
		stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1))
		stack.append(Vector2i(p.x, p.y - 1))
	# pin near-transparent pixels to exactly 0 so the 15% fully-transparent metric sees them
	var thr := BODY_ALPHA / 255.0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and c.a <= thr:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
	return img

func _strip_alpha(src: Image) -> Image:
	# Sources whose corners are already alpha 0: keep the alpha channel, pin a <= 16 to 0.
	var img: Image = src.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var thr := BODY_ALPHA / 255.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= thr:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
	return img

func _crop_body(img: Image) -> Image:
	# Tight crop to the pixels with alpha > BODY_ALPHA (the validator's body rule).
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
	var out := Image.create_empty(x1 - x0 + 1, y1 - y0 + 1, false, Image.FORMAT_RGBA8)
	out.blit_rect(img, Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1), Vector2i.ZERO)
	return out

# ---- writers -------------------------------------------------------------------------------

func _write_sprites_json(out_dir: String, rects: Dictionary, src_pixels: Dictionary) -> void:
	var json_path := out_dir + "/sprites.json"
	var prev := {}
	if FileAccess.file_exists(json_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if parsed is Dictionary:
			prev = parsed

	# animations[]: keep the existing fire/shot entries (order and names), refresh their
	# per-frame body_rect, then APPEND idle/spawn/telegraph/attack/recover. Re-running the
	# module must not duplicate the appended entries, so drop any of ours before re-adding.
	const APPENDED_NAMES := ["idle", "spawn", "telegraph", "attack", "recover"]
	var anims: Array = []
	for a in prev.get("animations", []):
		if not (a is Dictionary):
			continue
		if APPENDED_NAMES.has(str(a.get("name", ""))):
			continue
		var a2: Dictionary = (a as Dictionary).duplicate(true)
		var fs: Array = a2.get("frames", [])
		var brs: Array = []
		for f in fs:
			var key := str(f).trim_prefix("sprites/").trim_suffix(".png")
			brs.append(_rect_json(rects[key]))
		a2["body_rect"] = brs
		anims.append(a2)
	var appended := [
		["idle", true, "sprites/idle_00.png"],
		["spawn", false, "sprites/spawn_00.png"],
		["telegraph", false, "sprites/telegraph_00.png"],
		["attack", false, "sprites/shoot_00.png"],
		["recover", true, "sprites/recover_00.png"],
	]
	for row in appended:
		var key := str(row[2]).trim_prefix("sprites/").trim_suffix(".png")
		anims.append({"name": str(row[0]), "fps": 8, "loop": bool(row[1]),
			"frames": [str(row[2])],
			"body_rect": [_rect_json(rects[key])]})

	# sources[]: same rows, real-art state now
	var pixels_by_file := {"isagi_idle.jpeg": src_pixels["idle"],
		"ISAGI_SHOOT.webp": src_pixels["shoot"],
		"blueballprojectile.webp": src_pixels["shot"]}
	var src_rows: Array = []
	for row in prev.get("sources", []):
		if not (row is Dictionary):
			continue
		var r: Dictionary = (row as Dictionary).duplicate(true)
		r["state"] = "OK"
		r["pixels"] = int(pixels_by_file.get(str(r.get("file", "")), 0))
		src_rows.append(r)

	# anim (T-083): timings, loop flags, effect params are binding and untouched;
	# only frames[] and frame_map point at the new art, and _doc is re-worded
	var anim: Dictionary = prev.get("anim", {}).duplicate(true)
	var states: Dictionary = anim.get("states", {})
	var state_frames := {"spawn": "sprites/spawn_00.png", "idle": "sprites/idle_00.png",
		"telegraph": "sprites/telegraph_00.png", "attack": "sprites/shoot_00.png",
		"recover": "sprites/recover_00.png"}
	for sid in state_frames.keys():
		if states.has(sid) and states[sid] is Dictionary:
			(states[sid] as Dictionary)["frames"] = [state_frames[sid]]
	anim["frame_map"] = {
		"isagi_idle_00": "sprites/idle_00.png",
		"isagi_shoot_00": "sprites/shoot_00.png",
		"isagi_ball_00": "sprites/shot_00.png",
	}
	anim["_doc"] = "T-083. Spec: research/fable-tickets.md section 1.4 (the 1.x tables are the spec; ENEMIES.md behavior sentences are frozen per D-040). One entry per table row, keyed by a snake_case state id; 'row' repeats the exact table row label. spec_frames are the section 1.4 frame names in table order; timings are in 60 Hz ticks and are binding (attack tick_ranges are local to that state; 0 = global tick 72). Effects are shader/transform effects on the billboard and never change body_rect. Real art since tools/art/isagi.gd (T-016 art module; the shared pipeline skips isagi and cannot regress these frames): frame_map isagi_idle_00 -> sprites/idle_00.png, isagi_shoot_00 -> sprites/shoot_00.png, isagi_ball_00 -> sprites/shot_00.png; fire_01.png exists on disk (legacy fire animation, animations[0]) but is unreferenced by the states."

	var json := {
		"_doc": "Generated by game/tools/art/isagi.gd (T-016 art module for Isagi; the shared pipeline skips this enemy). Schema: id, name, tbd, world_height (DESIGN.md section 5 body-size table, SR-2; null where the section gives the enemy no row), animations[] {name, fps, loop, frames[] (paths relative to this folder), body_rect[] (tight bbox of alpha > 16 per frame, the HITBOXES shape), world_height per animation/frame where it differs}, sources[] = the ENEMIES.md 'Attachment mapping' state. Resourced at res://content/enemies/<id>/sprites.json.",
		"id": "isagi",
		"name": "Isagi",
		"tbd": false,
		"world_height": prev.get("world_height", 1.8),
		"animations": anims,
		"sources": src_rows,
		"anim": anim,
	}
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		failures.append("cannot write %s" % json_path)
		return
	f.store_string(JSON.stringify(json, "\t") + "\n")
	f.close()

func _write_sources_md(out_dir: String) -> void:
	var lines: Array[String] = []
	lines.append("# Isagi - SOURCES")
	lines.append("")
	lines.append("Generated by `game/tools/art/isagi.gd` (T-016 art module for Isagi; the shared")
	lines.append("pipeline skips this enemy, so a later pipeline rebuild cannot regress these frames).")
	lines.append("Spec: ENEMIES.md (roster + \"Attachment mapping\", by image number AND exact filename)")
	lines.append("and DESIGN.md section 5 (world sizes). PNG frames under `sprites/` are committed build")
	lines.append("artifacts with their sources documented here.")
	lines.append("")
	lines.append("| image | exact filename | path (repo-relative) | art state |")
	lines.append("|---|---|---|---|")
	lines.append("| 4 | `isagi_idle.jpeg` | `assets_src/enemies/isagi_idle.jpeg` | REAL ART (background removed: border-sampled reference + distance-threshold flood fill) |")
	lines.append("| 5 | `ISAGI_SHOOT.webp` | `assets_src/enemies/ISAGI_SHOOT.webp` | REAL ART (background removed: border-sampled reference + distance-threshold flood fill) |")
	lines.append("| 6 | `blueballprojectile.webp` | `assets_src/enemies/blueballprojectile.webp` | REAL ART (source alpha channel kept; corners already alpha 0) |")
	lines.append("")
	lines.append("Derivation (every frame is a deterministic overlay of the base body - no randomness anywhere):")
	lines.append("`idle_00` base idle, `spawn_00` brightened + cyan-white lerp (under the binding common_fade),")
	lines.append("`telegraph_00` red rim baked around the silhouette (under the binding red_rim_flash),")
	lines.append("`shoot_00` the kick pose, `recover_00` brightness x0.7 (the binding dim), `shot_00` the ball,")
	lines.append("`fire_00/01/02` the legacy `fire` animation (animations[0]): idle, squash 0.90/1.06, shoot.")
	lines.append("Recipe and its [CONTESTABLE] art numbers: DECISIONS.md D-ART-ISAGI-1.")
	lines.append("")
	lines.append("HITBOXES hard rule: a frame's `body_rect` in sprites.json (tight bbox of alpha > 16) is the")
	lines.append("only solid part of the sprite; the transparent padding and margins never hit.")
	lines.append("")
	lines.append("DISCLAIMER (ENEMIES.md hard rule): this is a personal, non-commercial project with no money")
	lines.append("involved; it is not affiliated with, endorsed by, or connected to any person, brand,")
	lines.append("character, or IP referenced or depicted here.")
	var f := FileAccess.open(out_dir + "/SOURCES.md", FileAccess.WRITE)
	if f == null:
		failures.append("cannot write SOURCES.md")
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()
