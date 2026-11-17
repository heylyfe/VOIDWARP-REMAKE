extends SceneTree
#
# game/tools/art/gin.gd - gin ichimaru's sprite art module (ticket T-ART-GIN; ENEMIES.md
# "gin ichimaru", DESIGN.md section 5.12, research/fable-tickets.md section 1.12).
#
#   tools\godot\godot.exe --headless --path game --script res://tools/art/gin.gd
#
# The shared sprite_pipeline.gd cannot cut out these two sources (an opaque near-white
# photo/logo - its 24/255 corner fill eats the whole image and reports NO BODY), so this
# module owns gin's frames; the pipeline skips any enemy that has this file.
#
# Deterministic (no unseeded randomness):
#   1. Loads the two owner sources from assets_src/enemies/ (path resolved against the
#      game dir; never res://, never a hardcoded absolute path).
#   2. Removes the background: distance-to-border-colour threshold + a 4-connected flood
#      fill from the border. gin idle.png: border (247,247,247), tolerance 70 (eats the
#      soft drop shadow and the glare arc, keeps the cel-shaded outline; the robe's
#      near-white pixels are only reachable through the dark outline, so they stay).
#      ginsword.png: border (255,255,255), tolerance 32 (the silver blade reads ~198 and
#      must survive; the background goes).
#   3. Crops tight to alpha > 16, fits onto a 512x512 canvas (<= 512, power of two) with
#      a transparent margin of at least 2 px. Body frames are bottom-anchored (gin stands
#      on the ground), the sword launch frame is centred.
#   4. One DISTINCT frame per state of the T-083 anim block (attack_void_zone lists no
#      frames and keeps none), derived from the base body:
#        idle_00      the base body, unchanged
#        spawn_00     materialize tint - pale energy tint + brighten (the fade itself is
#                     the state's runtime effect; this is the body mid-assembly)
#        telegraph_00 stretch (squash & stretch) + red charge tint + brightness flash
#        launch_00    the sword source, brightness flash + white-hot tint (the shing)
#        recover_00   desaturated + dimmed - he ghosts out after the launch
#   5. Rewrites content/enemies/gin/sprites.json in place: each anim state's frames and
#      frame_map point at the new files, every listed frame gets its tight-bbox
#      body_rect, animations[] gains the new entries appended (existing entries keep
#      their order and names; several views/tests read animations[0]), tbd=false.
#      attack_void_zone stays empty as it is. Tick counts, loop flags and effect
#      parameters are NOT touched (the T-083 table is binding, D-040).
#
# HITBOXES hard rule: a frame's body_rect is always recomputed as the tight bbox of
# alpha > 16 of that frame.

const SRC_IDLE_REL := "assets_src/enemies/gin idle.png"
const SRC_SWORD_REL := "assets_src/enemies/ginsword.png"
const FOLDER_REL := "content/enemies/gin"
const SPRITES_SUBDIR := "sprites"

const CANVAS := 512
const FIT_BODY := 500          # body height cap on the canvas (bottom-anchored)
const FIT_BOX := 500           # sword max side on the canvas (centred); > 2 px margin keeps (2,2) transparent
const MARGIN := 2              # no opaque pixel within 2 px of the canvas edge
const ALPHA_THR := 16          # alpha > 16 = body, the HITBOXES rule

# source background model (border colour, flood tolerance, per source)
const IDLE_BG := Color8(247, 247, 247)
const IDLE_TOL := 70.0
const SWORD_BG := Color8(255, 255, 255)
const SWORD_TOL := 32.0

var _repo_root := ""
var _game_dir := ""
var _data := PackedByteArray()
var _w := 0
var _h := 0
var _visited := PackedByteArray()
var _queue := PackedInt64Array()
var _tail := 0


func _initialize() -> void:
	_game_dir = ProjectSettings.globalize_path("res://").trim_suffix("/")
	_repo_root = _game_dir.get_base_dir()
	quit(run())


func _repo_path(rel: String) -> String:
	return _repo_root.path_join(rel)


func _out_path(file_name: String) -> String:
	return _game_dir.path_join(FOLDER_REL).path_join(SPRITES_SUBDIR).path_join(file_name)


## Loads, cuts out and crops a source; returns null on failure.
func _cut_source(rel: String, bg: Color, tol: float) -> Image:
	var img := Image.load_from_file(_repo_path(rel))
	if img == null or img.is_empty():
		printerr("ART gin: cannot load source %s" % _repo_path(rel))
		return null
	img.convert(Image.FORMAT_RGBA8)
	_flood_cut(img, bg, tol)
	var cut := _tight_rect(img)
	if cut.size.x <= 0 or cut.size.y <= 0:
		printerr("ART gin: NO BODY after background removal for %s" % rel)
		return null
	return img.get_region(cut)


func run() -> int:
	var body := _cut_source(SRC_IDLE_REL, IDLE_BG, IDLE_TOL)
	if body == null:
		return 1
	var sword := _cut_source(SRC_SWORD_REL, SWORD_BG, SWORD_TOL)
	if sword == null:
		return 1
	print("ART gin: body %dx%d (from %s), sword %dx%d (from %s)" % [body.get_width(),
		body.get_height(), SRC_IDLE_REL, sword.get_width(), sword.get_height(), SRC_SWORD_REL])

	# frames: state -> canvas (attack_void_zone lists no frames and keeps none)
	var frames := {}
	frames["idle_00.png"] = _compose(body, true, FIT_BODY, FIT_BOX)

	var spawn_body := body.duplicate()
	_tint(spawn_body, Color8(207, 246, 255), 0.35)   # pale energy tint: mid-assembly
	_brightness(spawn_body, 0.08)
	frames["spawn_00.png"] = _compose(spawn_body, true, FIT_BODY, FIT_BOX)

	var tele_body := body.duplicate()
	_stretch(tele_body, 0.94, 1.08)                  # squashed wide -> stretched tall
	_tint(tele_body, Color8(255, 74, 60), 0.14)      # red charge tint (the mark is #FF2A2A)
	_brightness(tele_body, 0.10)                     # brightness flash (the rumble)
	frames["telegraph_00.png"] = _compose(tele_body, true, FIT_BODY, FIT_BOX)

	var launch := sword.duplicate()
	_tint(launch, Color8(255, 255, 255), 0.12)       # white-hot edge
	_brightness(launch, 0.18)                        # the shing
	frames["launch_00.png"] = _compose(launch, false, FIT_BOX, FIT_BOX)

	var rec_body := body.duplicate()
	_desaturate(rec_body, 0.45)                      # ghosting out after the launch
	_brightness(rec_body, -0.25)
	frames["recover_00.png"] = _compose(rec_body, true, FIT_BODY, FIT_BOX)

	var rects := {}
	for fname in frames:
		var canvas: Image = frames[fname]
		var r := _tight_rect(canvas)
		rects[fname] = [r.position.x, r.position.y, r.size.x, r.size.y]
		var err := canvas.save_png(_out_path(fname))
		if err != OK:
			printerr("ART gin: cannot write %s (err %d)" % [_out_path(fname), err])
			return 1
		print("ART gin: wrote %s body_rect [%d, %d, %d, %d]" % [fname, r.position.x,
			r.position.y, r.size.x, r.size.y])

	if not _update_sprites_json(rects):
		return 1
	print("ART gin: sprites.json updated (5 frames, tbd=false)")
	return 0


## Points the anim block at the new per-state frames, fixes every body_rect, appends the
## new animations[] entries (existing entries keep order, names, fps and loop), and sets
## tbd=false. Tick counts, loop flags and effect params are never touched (D-040).
func _update_sprites_json(rects: Dictionary) -> bool:
	var json_path := _game_dir.path_join(FOLDER_REL).path_join("sprites.json")
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not (parsed is Dictionary):
		printerr("ART gin: sprites.json does not parse")
		return false
	var doc: Dictionary = parsed

	var anim: Dictionary = doc.get("anim", {})
	var states: Dictionary = anim.get("states", {})
	var state_frames := {
		"spawn": ["sprites/spawn_00.png"],
		"idle": ["sprites/idle_00.png"],
		"telegraph": ["sprites/telegraph_00.png"],
		"attack_launch": ["sprites/launch_00.png"],
		"recover": ["sprites/recover_00.png"],
	}
	for sid in state_frames:
		var st: Dictionary = states.get(sid, {})
		st["frames"] = state_frames[sid]
		states[sid] = st
	# attack_void_zone: no frames on disk, left empty as it is
	anim["states"] = states
	anim["frame_map"] = {
		"gin_idle_00": "sprites/idle_00.png",
		"gin_launch_00": "sprites/launch_00.png",
	}
	var anim_doc := str(anim.get("_doc", ""))
	anim_doc = anim_doc.replace(
		"All art is TBD placeholders today (tbd=true), so the timings stay exactly as the table says.",
		"Art is real (game/tools/art/gin.gd, ticket T-ART-GIN); the timings stay exactly as the table says.")
	anim["_doc"] = anim_doc
	doc["anim"] = anim

	var animations: Array = doc.get("animations", [])
	var existing_rect := {
		"sprites/idle_00.png": rects["idle_00.png"],
		"sprites/launch_00.png": rects["launch_00.png"],
	}
	for entry in animations:
		var fr: Array = entry.get("frames", [])
		if fr.size() == 1 and existing_rect.has(str(fr[0])):
			entry["body_rect"] = [existing_rect[str(fr[0])]]
	var have := {}
	for entry in animations:
		have[str(entry.get("name", ""))] = true
	var appended := [
		{"body_rect": [rects["spawn_00.png"]], "fps": 2,
			"frames": ["sprites/spawn_00.png"], "loop": false, "name": "spawn"},
		{"body_rect": [rects["telegraph_00.png"]], "fps": 1,
			"frames": ["sprites/telegraph_00.png"], "loop": false, "name": "telegraph"},
		{"body_rect": [rects["recover_00.png"]], "fps": 1,
			"frames": ["sprites/recover_00.png"], "loop": true, "name": "recover"},
	]
	for entry in appended:
		if not have.has(str(entry["name"])):
			animations.append(entry)
	doc["animations"] = animations

	var sources: Array = doc.get("sources", [])
	for s in sources:
		if str(s.get("state", "")) == "MISSING -> TBD":
			s["state"] = "real art (game/tools/art/gin.gd)"
	doc["sources"] = sources
	doc["tbd"] = false

	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f == null:
		printerr("ART gin: cannot write %s" % json_path)
		return false
	f.store_string(JSON.stringify(doc, "  ", false) + "\n")
	f.close()
	return true


# --- background removal ---------------------------------------------------------------

func _dist2(i: int, br: float, bg: float, bb: float) -> float:
	var dr := float(_data[i]) - br
	var dg := float(_data[i + 1]) - bg
	var db := float(_data[i + 2]) - bb
	return dr * dr + dg * dg + db * db


func _try_push(idx: int, br: float, bg: float, bb: float, tol2: float) -> void:
	if _visited[idx] == 1:
		return
	if _dist2(idx * 4, br, bg, bb) > tol2:
		return
	_visited[idx] = 1
	_queue[_tail] = idx
	_tail += 1


## Flood fill from the border through pixels within tol of the background colour;
## every reached pixel becomes alpha 0. Modifies img in place.
func _flood_cut(img: Image, bg: Color, tol: float) -> void:
	var src := img.duplicate()
	src.convert(Image.FORMAT_RGBA8)
	_w = src.get_width()
	_h = src.get_height()
	var raw: PackedByteArray = src.get_data()
	_data = raw
	var tol2 := tol * tol
	var br := float(bg.r8)
	var bg8 := float(bg.g8)
	var bb := float(bg.b8)
	_visited = PackedByteArray()
	_visited.resize(_w * _h)
	_queue = PackedInt64Array()
	_queue.resize(_w * _h)
	_tail = 0
	for x in _w:
		_try_push(x, br, bg8, bb, tol2)
		_try_push((_h - 1) * _w + x, br, bg8, bb, tol2)
	for y in _h:
		_try_push(y * _w, br, bg8, bb, tol2)
		_try_push(y * _w + _w - 1, br, bg8, bb, tol2)
	var head := 0
	while head < _tail:
		var idx := _queue[head]
		head += 1
		var x := idx % _w
		var y := idx / _w
		if x > 0:
			_try_push(idx - 1, br, bg8, bb, tol2)
		if x < _w - 1:
			_try_push(idx + 1, br, bg8, bb, tol2)
		if y > 0:
			_try_push(idx - _w, br, bg8, bb, tol2)
		if y < _h - 1:
			_try_push(idx + _w, br, bg8, bb, tol2)
	for i in _w * _h:
		if _visited[i] == 1:
			_data[i * 4 + 3] = 0
	var out := Image.create_from_data(_w, _h, false, Image.FORMAT_RGBA8, _data)
	img.copy_from(out)
	_data = PackedByteArray()
	_visited = PackedByteArray()
	_queue = PackedInt64Array()


## Tight bbox of pixels with alpha > ALPHA_THR, or an empty Rect2i.
func _tight_rect(img: Image) -> Rect2i:
	var data := img.get_data()
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		var row := y * w * 4
		for x in w:
			if data[row + x * 4 + 3] > ALPHA_THR:
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


# --- derivation helpers (all keep alpha untouched) -----------------------------------

func _each_pixel(img: Image, fn: Callable) -> void:
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var px: Array = fn.call(float(data[i]), float(data[i + 1]), float(data[i + 2]))
		data[i] = clampi(int(round(float(px[0]))), 0, 255)
		data[i + 1] = clampi(int(round(float(px[1]))), 0, 255)
		data[i + 2] = clampi(int(round(float(px[2]))), 0, 255)
	var out := Image.create_from_data(img.get_width(), img.get_height(), false,
		Image.FORMAT_RGBA8, data)
	img.copy_from(out)


## Blend every opaque-ish pixel toward tint by k (0..1).
func _tint(img: Image, tint: Color, k: float) -> void:
	var tr := tint.r * 255.0
	var tg := tint.g * 255.0
	var tb := tint.b * 255.0
	_each_pixel(img, func(r, g, b):
		return [r * (1.0 - k) + tr * k, g * (1.0 - k) + tg * k, b * (1.0 - k) + tb * k])


## Multiply channels by (1 + b); b > 0 brightens.
func _brightness(img: Image, b: float) -> void:
	var f := 1.0 + b
	_each_pixel(img, func(r, g, b_):
		return [r * f, g * f, b_ * f])


## Pull every pixel toward its own luma by s (0..1).
func _desaturate(img: Image, s: float) -> void:
	_each_pixel(img, func(r, g, b):
		var lum: float = 0.2126 * float(r) + 0.7152 * float(g) + 0.0722 * float(b)
		return [r * (1.0 - s) + lum * s, g * (1.0 - s) + lum * s, b * (1.0 - s) + lum * s])


## Squash & stretch: resize in place by (sx, sy), bilinear.
func _stretch(img: Image, sx: float, sy: float) -> void:
	var nw := maxi(1, int(round(img.get_width() * sx)))
	var nh := maxi(1, int(round(img.get_height() * sy)))
	img.resize(nw, nh, Image.INTERPOLATE_BILINEAR)


## Fit `body` onto a CANVERxCANVAS transparent canvas. Body frames bottom-anchor (gin
## stands on the ground), the sword centres. Guarantees >= MARGIN px transparent edge.
func _compose(body: Image, bottom_anchor: bool, fit_h: int, fit_w: int) -> Image:
	var bw := float(body.get_width())
	var bh := float(body.get_height())
	var s := minf(float(fit_w) / bw, float(fit_h) / bh)
	var nw := maxi(1, int(round(bw * s)))
	var nh := maxi(1, int(round(bh * s)))
	var scaled := body.duplicate()
	scaled.resize(nw, nh, Image.INTERPOLATE_BILINEAR)
	var canvas := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var x0 := int((CANVAS - nw) / 2)
	var y0 := CANVAS - MARGIN - nh if bottom_anchor else int((CANVAS - nh) / 2)
	canvas.blit_rect(scaled, Rect2i(0, 0, nw, nh), Vector2i(x0, y0))
	return canvas
