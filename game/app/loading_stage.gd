extends Control
#
# Loading-screen stage (TICKET LOADING; D-LOAD-1..4). A flat 2D stage in the game's palette - the
# deliberately unserious twin of the 3D void - that draws the items of app/loading_gags.gd:
# real enemy PNG sprites posed procedurally (position / rotation / squash / tint / frame swap) plus
# a few drawn props. It owns no timing: loading_screen.gd feeds it the display time via set_time().
# A sprite whose PNG is missing renders as a magenta TBD checker (FLEET_PACK R7), never an error.
#
# Drawing happens in _draw() only, so the headless tests never reach it; the model it renders is
# the pure, tested loading_gags.items().

const GagsScript := preload("res://app/loading_gags.gd")

## D-GUI-1: a flat backdrop in the house void (#010B0C, data/palette.json `void`) - no
## gradient - and a deep-teal floor slab under the bright lip. The gags keep their own
## colours (the cartoon register, D-LOAD-1); only the room around them is the house's.
const BG_TOP := Color(0.0039, 0.0431, 0.0471)       # #010B0C
const BG_BOTTOM := BG_TOP
const FLOOR_TOP := Color(0.486, 1.0, 0.957, 0.9)    # #7CFFF4
const FLOOR_BODY := Color(0.0392, 0.1804, 0.1882)   # #0A2E30
const CONFETTI_SOFT := Color(0.5608, 0.9098, 0.8784)  # #8FE8E0

var gag_id: String = ""
var stage_time: float = 0.0

var _tex_cache: Dictionary = {}      # "enemy/name" -> {"tex": Texture2D, "rect": Rect2, "tbd": bool}
var _bubble_box := StyleBoxFlat.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_box.bg_color = GagsScript.PAPER
	_bubble_box.set_corner_radius_all(14)
	_bubble_box.set_border_width_all(3)
	_bubble_box.border_color = GagsScript.INK


func set_gag(id: String) -> void:
	gag_id = id
	queue_redraw()


func set_time(t: float) -> void:
	stage_time = t
	queue_redraw()


## Texture + opaque rectangle for one enemy sprite; a magenta checker (tbd = true) when the PNG is
## missing. Never null.
func sprite_info(enemy_id: String, sprite_name: String) -> Dictionary:
	var key := enemy_id + "/" + sprite_name
	if _tex_cache.has(key):
		return _tex_cache[key]
	var info := {}
	var path := GagsScript.sprite_path(enemy_id, sprite_name)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex != null:
		var rect := Rect2(Vector2.ZERO, tex.get_size())
		var img := tex.get_image()
		if img != null and not img.is_empty():
			var used := img.get_used_rect()
			if used.size.x > 0 and used.size.y > 0:
				rect = Rect2(used)
		info = {"tex": tex, "rect": rect, "tbd": false}
	else:
		var img2 := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for py in 64:
			for px in 64:
				var on := ((px / 16) + (py / 16)) % 2 == 0
				img2.set_pixel(px, py, Color(1.0, 0.0, 1.0) if on else Color(0.1, 0.0, 0.1))
		info = {"tex": ImageTexture.create_from_image(img2), "rect": Rect2(0, 0, 64, 64), "tbd": true}
	_tex_cache[key] = info
	return info


func _draw() -> void:
	var sc := minf(size.x / GagsScript.STAGE_W, size.y / GagsScript.STAGE_H)
	if sc <= 0.0:
		return
	var origin := (size - Vector2(GagsScript.STAGE_W, GagsScript.STAGE_H) * sc) * 0.5
	_draw_backdrop(origin, sc)
	var its := GagsScript.items(gag_id, stage_time)
	var shake := Vector2.ZERO
	for it in its:
		if str(it.get("k", "")) == "shake":
			var amp := float(it.get("amp", 0.0))
			shake = Vector2(sin(stage_time * 97.0), cos(stage_time * 83.0)) * amp * sc
	var font := ThemeDB.fallback_font
	for it in its:
		var d: Dictionary = it
		match str(d.get("k", "")):
			"sprite":
				_draw_sprite(d, origin + shake, sc)
			"gift":
				_draw_gift(d, origin + shake, sc)
			"lid":
				_draw_lid(d, origin + shake, sc)
			"puff":
				var pc: Color = d["color"]
				pc.a = float(d["a"])
				draw_circle(origin + shake + Vector2(float(d["x"]), float(d["y"])) * sc, float(d["r"]) * sc, pc)
			"ring":
				var rc: Color = d["color"]
				rc.a = float(d["a"])
				draw_set_transform(origin + shake + Vector2(float(d["x"]), float(d["y"])) * sc, 0.0,
						Vector2(1.0, 0.28))
				draw_arc(Vector2.ZERO, float(d["r"]) * sc, 0.0, TAU, 48, rc, 5.0 * sc)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"text":
				_draw_text(font, d, origin + shake, sc)
			"bubble":
				_draw_bubble(font, d, origin + shake, sc)


func _draw_backdrop(origin: Vector2, sc: float) -> void:
	var pts := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)])
	var cols := PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM])
	draw_polygon(pts, cols)
	# drifting motes in the house palette: bright, soft, white
	for i in 46:
		var fx := fposmod(float(i) * 197.0 + stage_time * (9.0 + float(i % 7) * 5.0), GagsScript.STAGE_W)
		var fy := fposmod(float(i) * 91.0 + stage_time * 6.0, GagsScript.GROUND_Y - 20.0)
		var c := GagsScript.CYAN
		if i % 3 == 1:
			c = CONFETTI_SOFT
		elif i % 3 == 2:
			c = GagsScript.PAPER
		c.a = 0.10 + 0.10 * (0.5 + 0.5 * sin(stage_time * 2.0 + float(i)))
		draw_circle(origin + Vector2(fx, fy) * sc, (2.0 + float(i % 4)) * sc, c)
	# the floor: a slab with a bright lip and tile seams
	var gy := origin.y + GagsScript.GROUND_Y * sc
	draw_rect(Rect2(0.0, gy, size.x, 28.0 * sc), FLOOR_BODY)
	draw_rect(Rect2(0.0, gy, size.x, 4.0 * sc), FLOOR_TOP)
	for j in 24:
		var sx := origin.x + float(j) * 120.0 * sc
		draw_line(Vector2(sx, gy + 4.0 * sc), Vector2(sx - 14.0 * sc, gy + 28.0 * sc),
				Color(0.486, 1.0, 0.957, 0.18), 2.0 * sc)


func _draw_sprite(d: Dictionary, origin: Vector2, sc: float) -> void:
	var a := float(d["a"])
	if a <= 0.001:
		return
	var sxm := float(d["sx"])
	var sym := float(d["sy"])
	if sxm <= 0.001 or sym <= 0.001:
		return
	var info := sprite_info(str(d["enemy"]), str(d["name"]))
	var rect: Rect2 = info["rect"]
	var hh := float(d["h"])
	var ww := hh * rect.size.x / maxf(rect.size.y, 1.0)
	var p := float(d["p"])
	var pos := origin + Vector2(float(d["x"]), float(d["y"])) * sc
	# soft shadow on the floor, shrinking and fading as the sprite leaves the ground
	if bool(d["shadow"]):
		var lift := clampf((GagsScript.GROUND_Y - float(d["y"]) - p * hh) / 420.0, 0.0, 1.0)
		draw_set_transform(origin + Vector2(float(d["x"]), GagsScript.GROUND_Y + 14.0) * sc, 0.0,
				Vector2(1.0, 0.16))
		draw_circle(Vector2.ZERO, ww * 0.42 * sc * (1.0 - 0.5 * lift) * sxm, Color(0, 0, 0, 0.35 * (1.0 - lift) * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var flip := -1.0 if bool(d["flip"]) else 1.0
	draw_set_transform(pos, float(d["rot"]), Vector2(sc * sxm * flip, sc * sym))
	var tint: Color = d["tint"]
	tint.a *= a
	draw_texture_rect_region(info["tex"], Rect2(-ww * 0.5, -hh * (1.0 - p), ww, hh), rect, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_gift(d: Dictionary, origin: Vector2, sc: float) -> void:
	var w := float(d["w"])
	var pos := origin + Vector2(float(d["x"]), float(d["y"])) * sc
	draw_set_transform(pos, float(d["rot"]), Vector2(sc, sc * float(d["sy"])))
	var body := Rect2(-w * 0.5, -w, w, w)
	draw_rect(body.grow(7.0), Color(GagsScript.CYAN.r, GagsScript.CYAN.g, GagsScript.CYAN.b, 0.22))
	draw_rect(body, Color(0.02, 0.02, 0.04))
	draw_rect(body, GagsScript.CYAN, false, 4.0)
	draw_rect(Rect2(-w * 0.07, -w, w * 0.14, w), GagsScript.CYAN)
	draw_rect(Rect2(-w * 0.5, -w * 0.57, w, w * 0.14), GagsScript.CYAN)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_lid(d: Dictionary, origin: Vector2, sc: float) -> void:
	var w := float(d["w"]) * 1.1
	var h := float(d["w"]) * 0.28
	var pos := origin + Vector2(float(d["x"]), float(d["y"])) * sc
	draw_set_transform(pos, float(d["rot"]), Vector2(sc, sc))
	var body := Rect2(-w * 0.5, -h, w, h)
	draw_rect(body.grow(6.0), Color(GagsScript.CYAN.r, GagsScript.CYAN.g, GagsScript.CYAN.b, 0.22))
	draw_rect(body, Color(0.02, 0.02, 0.04))
	draw_rect(body, GagsScript.CYAN, false, 4.0)
	draw_rect(Rect2(-w * 0.06, -h, w * 0.12, h), GagsScript.CYAN)
	draw_circle(Vector2(-w * 0.1, -h - 9.0), 11.0, GagsScript.CYAN)
	draw_circle(Vector2(w * 0.1, -h - 9.0), 11.0, GagsScript.CYAN)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_text(font: Font, d: Dictionary, origin: Vector2, sc: float) -> void:
	var s := float(d["s"])
	if s <= 0.01:
		return
	var fs := int(float(d["size"]) * sc * s)
	if fs < 4:
		return
	var txt := str(d["text"])
	var col: Color = d["color"]
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := origin + Vector2(float(d["x"]), float(d["y"])) * sc + Vector2(-tw * 0.5, 0.0)
	draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(8.0 * sc), GagsScript.INK)
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_bubble(font: Font, d: Dictionary, origin: Vector2, sc: float) -> void:
	var s := float(d["s"])
	if s <= 0.01:
		return
	var fs := int(30.0 * sc)
	var txt := str(d["text"])
	var tsz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pad := 16.0 * sc
	var tail := origin + Vector2(float(d["x"]), float(d["y"])) * sc
	var w := (tsz.x + pad * 2.0) * s
	var h := (tsz.y + pad * 1.2) * s
	var rect := Rect2(tail.x - w * 0.5, tail.y - h - 22.0 * sc * s, w, h)
	# keep the bubble on screen
	rect.position.x = clampf(rect.position.x, 8.0, maxf(size.x - w - 8.0, 8.0))
	draw_polygon(PackedVector2Array([Vector2(tail.x - 14.0 * sc * s, rect.end.y - 2.0),
			Vector2(tail.x + 14.0 * sc * s, rect.end.y - 2.0), tail]),
			PackedColorArray([GagsScript.PAPER, GagsScript.PAPER, GagsScript.PAPER]))
	draw_style_box(_bubble_box, rect)
	if s > 0.97:   # text only at full size: mid-pop the scaled bubble is narrower than its text
		draw_string(font, Vector2(rect.position.x + pad, rect.position.y + pad * 0.6 + tsz.y * 0.8),
				txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, GagsScript.INK)
