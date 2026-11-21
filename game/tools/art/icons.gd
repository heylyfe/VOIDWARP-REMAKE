extends SceneTree
#
# game/tools/art/icons.gd - the curse and upgrade icon set (TBD.md row 21).
#
#   "<godot>" --headless --path game --script res://tools/art/icons.gd
#
# Emits one 128x128 PNG per content id under assets/icons/upgrades/ and
# assets/icons/curses/, from SVG built in this file. The whole set is reproducible with the
# one command above: no randomness, no wall clock, no external art, no network.
#
# House style (docs/classes/*.svg, the three class icons): flat geometric shapes, hard
# edges, a bright cyan rim, no gradients, no text, no emoji. The palette is the five
# colours below and nothing else. Every pixel of every icon is either fully transparent or
# exactly one of them: _quantise snaps the rasteriser's anti-aliased edge to the nearest
# palette colour, which is also what gives the set its hard edges.
#
# Every icon is the same construction - a deep-ground plate with the cyan rim, and a glyph
# inside it built from the motif library below. Curses and upgrades share the plate; the
# view layer's frame colour (pink for a curse, aqua for an upgrade) is what tells the two
# sets apart, exactly as the Antechamber already draws it.
#
# The id list is read from content/upgrades/ and content/curses/ at run time, so a new
# content file with no recipe here is a hard failure: the generator refuses to write a
# partial set rather than shipping a blank. tests/test_icon_art.gd enforces the same rule
# on the shipped PNGs.
#
# Depictions are the game's own: each glyph is drawn from what the item DOES (its rule or
# effect text), not traced from any other game's art. See SOURCES.md.

const DEEP := "#0A2E30"      # deep ground
const MID := "#1C6E70"       # mid
const BRIGHT := "#2FB7B0"    # bright
const HI := "#7CFFF4"        # highlight (the rim)
const PALE := "#8FE8E0"      # pale

const SIZE := 128            # output px (the HUD cell is 40, the altar billboard ~90)
const SCALE := 2.0           # 64 units -> 128 px

const OUT_UPGRADES := "assets/icons/upgrades"
const OUT_CURSES := "assets/icons/curses"


func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var jobs := [
		{"kind": "upgrades", "dir": "res://content/upgrades", "out": game_dir + "/" + OUT_UPGRADES},
		{"kind": "curses", "dir": "res://content/curses", "out": game_dir + "/" + OUT_CURSES},
	]
	var written := 0
	var missing: Array[String] = []
	for job in jobs:
		var ids := _ids(str(job["dir"]))
		if ids.is_empty():
			print("ICONS FAILED: no content ids under %s" % str(job["dir"]))
			quit(1)
			return
		DirAccess.make_dir_recursive_absolute(str(job["out"]))
		for id in ids:
			var inner := _glyph(id)
			if inner == "":
				missing.append("%s/%s" % [str(job["kind"]), id])
				continue
			var img := _render(_svg(inner))
			if img == null:
				print("ICONS FAILED: cannot rasterise %s" % id)
				quit(1)
				return
			var path := "%s/%s.png" % [str(job["out"]), id]
			if img.save_png(path) != OK:
				print("ICONS FAILED: cannot write %s" % path)
				quit(1)
				return
			written += 1
		print("ICONS %s: %d ids" % [str(job["kind"]), ids.size()])
	if not missing.is_empty():
		for m in missing:
			print("ICONS MISSING RECIPE: %s" % m)
		print("ICONS FAILED: %d id(s) have no recipe - the set would be incomplete" % missing.size())
		quit(1)
		return
	print("ICONS OK %d icons" % written)
	quit(0)


# ---- content ids ---------------------------------------------------------------

func _ids(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for fn in d.get_files():
		if fn.ends_with(".json") and not fn.begins_with("."):
			out.append(fn.trim_suffix(".json"))
	out.sort()
	return out


# ---- SVG primitives ------------------------------------------------------------

func _f(v: float) -> String:
	return "%.2f" % v


func _rect(x: float, y: float, w: float, h: float, rx: float, fill: String,
		stroke := "", sw := 0.0) -> String:
	var s := '<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s"' % [
		_f(x), _f(y), _f(w), _f(h), _f(rx), fill]
	if stroke != "":
		s += ' stroke="%s" stroke-width="%s"' % [stroke, _f(sw)]
	return s + "/>"


func _poly(pts: Array, fill: String, stroke := "", sw := 0.0) -> String:
	var p := ""
	for pt in pts:
		p += "%s,%s " % [_f(float(pt[0])), _f(float(pt[1]))]
	var s := '<polygon points="%s" fill="%s"' % [p.strip_edges(), fill]
	if stroke != "":
		s += ' stroke="%s" stroke-width="%s" stroke-linejoin="round"' % [stroke, _f(sw)]
	return s + "/>"


func _circ(cx: float, cy: float, r: float, fill: String, stroke := "", sw := 0.0) -> String:
	var s := '<circle cx="%s" cy="%s" r="%s" fill="%s"' % [_f(cx), _f(cy), _f(r), fill]
	if stroke != "":
		s += ' stroke="%s" stroke-width="%s"' % [stroke, _f(sw)]
	return s + "/>"


func _line(pts: Array, color: String, w: float) -> String:
	var p := ""
	for pt in pts:
		p += "%s,%s " % [_f(float(pt[0])), _f(float(pt[1]))]
	return '<polyline points="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>' % [
		p.strip_edges(), color, _f(w)]


func _arc(cx: float, cy: float, r: float, a0: float, a1: float, color: String, w: float) -> String:
	var pts: Array = []
	var steps := 10
	for i in steps + 1:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / float(steps)))
		pts.append([cx + cos(a) * r, cy + sin(a) * r])
	return _line(pts, color, w)


# ---- the plate and the canvas --------------------------------------------------

func _plate() -> String:
	return _rect(2.5, 2.5, 59.0, 59.0, 11.0, DEEP, HI, 3.0)


func _svg(inner: String) -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">' + _plate() + inner + '</svg>'


func _render(svg: String) -> Image:
	var img := Image.new()
	if img.load_svg_from_string(svg, SCALE) != OK:
		return null
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != SIZE or img.get_height() != SIZE:
		img.resize(SIZE, SIZE, Image.INTERPOLATE_NEAREST)
	_quantise(img)
	return img


## Snap every pixel to the house palette (or to transparent). This is what makes the set
## hard-edged and what lets tests/test_icon_art.gd assert the palette exactly, with no
## tolerance: after this pass a pixel is either alpha 0 or one of the five colours.
func _quantise(img: Image) -> void:
	var pal: Array[Color] = [Color(DEEP), Color(MID), Color(BRIGHT), Color(HI), Color(PALE)]
	var cache: Dictionary = {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var key := c.to_rgba32()
			if cache.has(key):
				img.set_pixel(x, y, cache[key])
				continue
			var best: Color = pal[0]
			var bd := INF
			for p in pal:
				var d := (c.r - p.r) * (c.r - p.r) + (c.g - p.g) * (c.g - p.g) + (c.b - p.b) * (c.b - p.b)
				if d < bd:
					bd = d
					best = p
			var out := Color(best.r, best.g, best.b, 1.0)
			cache[key] = out
			img.set_pixel(x, y, out)


# ---- motif library -------------------------------------------------------------
# Every motif draws inside a box of half-size s about (cx, cy), in the 64-unit space.
# The dominant shape carries the cyan rim; secondary shapes stay flat, so a glyph reads
# as one silhouette at 40 px.

func _coin(cx: float, cy: float, s: float) -> String:
	return _circ(cx, cy, s, BRIGHT, HI, 2.4) + _rect(cx - s * 0.17, cy - s * 0.5, s * 0.34, s, s * 0.17, PALE)


func _arrow(cx: float, cy: float, s: float, dir: String) -> String:
	var pts: Array = []
	match dir:
		"up":
			pts = [[cx, cy - s], [cx + s * 0.85, cy + s * 0.05], [cx + s * 0.32, cy + s * 0.05],
				[cx + s * 0.32, cy + s], [cx - s * 0.32, cy + s], [cx - s * 0.32, cy + s * 0.05],
				[cx - s * 0.85, cy + s * 0.05]]
		"down":
			pts = [[cx, cy + s], [cx + s * 0.85, cy - s * 0.05], [cx + s * 0.32, cy - s * 0.05],
				[cx + s * 0.32, cy - s], [cx - s * 0.32, cy - s], [cx - s * 0.32, cy - s * 0.05],
				[cx - s * 0.85, cy - s * 0.05]]
		"right":
			pts = [[cx + s, cy], [cx - s * 0.05, cy - s * 0.85], [cx - s * 0.05, cy - s * 0.32],
				[cx - s, cy - s * 0.32], [cx - s, cy + s * 0.32], [cx - s * 0.05, cy + s * 0.32],
				[cx - s * 0.05, cy + s * 0.85]]
		_:
			pts = [[cx - s, cy], [cx + s * 0.05, cy - s * 0.85], [cx + s * 0.05, cy - s * 0.32],
				[cx + s, cy - s * 0.32], [cx + s, cy + s * 0.32], [cx + s * 0.05, cy + s * 0.32],
				[cx + s * 0.05, cy + s * 0.85]]
	return _poly(pts, BRIGHT, HI, 2.0)


func _chevron(cx: float, cy: float, s: float, col: String) -> String:
	return _line([[cx - s * 0.45, cy - s], [cx + s * 0.5, cy], [cx - s * 0.45, cy + s]], col, s * 0.5)


func _bolt(cx: float, cy: float, s: float, col: String) -> String:
	return _poly([[cx + s * 0.2, cy - s], [cx - s * 0.6, cy + s * 0.12], [cx - s * 0.05, cy + s * 0.12],
		[cx - s * 0.25, cy + s], [cx + s * 0.62, cy - s * 0.15], [cx + s * 0.05, cy - s * 0.15]], col, HI, 2.0)


func _ring(cx: float, cy: float, r: float, w: float, col: String) -> String:
	return _circ(cx, cy, r, "none", col, w)


func _burst(cx: float, cy: float, r: float, n: int, col: String) -> String:
	var pts: Array = []
	for i in n * 2:
		var a := deg_to_rad(360.0 * float(i) / float(n * 2) - 90.0)
		var rr := r if i % 2 == 0 else r * 0.52
		pts.append([cx + cos(a) * rr, cy + sin(a) * rr])
	return _poly(pts, col, HI, 2.0)


func _clock(cx: float, cy: float, r: float, ang: float, col: String) -> String:
	var a := deg_to_rad(ang)
	var out := _circ(cx, cy, r, MID, HI, 2.4)
	out += _line([[cx, cy], [cx + cos(a) * r * 0.62, cy + sin(a) * r * 0.62]], col, 3.0)
	out += _line([[cx, cy], [cx + cos(a + 1.9) * r * 0.42, cy + sin(a + 1.9) * r * 0.42]], col, 2.4)
	return out


func _gift(cx: float, cy: float, s: float) -> String:
	var out := _rect(cx - s * 0.8, cy - s * 0.35, s * 1.6, s * 1.15, 2.0, MID, HI, 2.4)
	out += _rect(cx - s * 0.95, cy - s * 0.72, s * 1.9, s * 0.42, 2.0, BRIGHT)
	out += _rect(cx - s * 0.14, cy - s * 0.72, s * 0.28, s * 1.52, 1.0, PALE)
	out += _circ(cx - s * 0.3, cy - s * 0.86, s * 0.2, PALE) + _circ(cx + s * 0.3, cy - s * 0.86, s * 0.2, PALE)
	return out


func _mine(cx: float, cy: float, s: float) -> String:
	var out := _circ(cx, cy, s * 0.72, MID, HI, 2.4)
	for i in 8:
		var a := deg_to_rad(45.0 * float(i))
		out += _line([[cx + cos(a) * s * 0.72, cy + sin(a) * s * 0.72],
			[cx + cos(a) * s, cy + sin(a) * s]], BRIGHT, 2.6)
	out += _circ(cx, cy, s * 0.22, PALE)
	return out


func _bell(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s * 0.85, cy + s * 0.55], [cx - s * 0.55, cy - s * 0.1],
		[cx - s * 0.4, cy - s * 0.75], [cx + s * 0.4, cy - s * 0.75], [cx + s * 0.55, cy - s * 0.1],
		[cx + s * 0.85, cy + s * 0.55]], BRIGHT, HI, 2.4)
	out += _rect(cx - s * 0.95, cy + s * 0.55, s * 1.9, s * 0.26, 1.0, PALE)
	out += _circ(cx, cy + s * 0.95, s * 0.2, PALE)
	return out


func _plus(cx: float, cy: float, s: float, col: String) -> String:
	return _rect(cx - s * 0.28, cy - s, s * 0.56, s * 2.0, 1.0, col) + \
		_rect(cx - s, cy - s * 0.28, s * 2.0, s * 0.56, 1.0, col)


func _crack(cx: float, cy: float, s: float, col: String) -> String:
	return _line([[cx - s * 0.1, cy - s], [cx + s * 0.25, cy - s * 0.35], [cx - s * 0.2, cy + s * 0.05],
		[cx + s * 0.2, cy + s * 0.45], [cx - s * 0.05, cy + s]], col, 2.8)


func _grid(cx: float, cy: float, s: float, n: int, col: String) -> String:
	var out := ""
	for i in n + 1:
		var t := -s + 2.0 * s * float(i) / float(n)
		out += _line([[cx + t, cy - s], [cx + t, cy + s]], col, 1.8)
		out += _line([[cx - s, cy + t], [cx + s, cy + t]], col, 1.8)
	return out


func _cat(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s * 0.85, cy - s * 0.2], [cx - s * 0.7, cy - s * 1.05],
		[cx - s * 0.15, cy - s * 0.62]], BRIGHT, HI, 2.0)
	out += _poly([[cx + s * 0.85, cy - s * 0.2], [cx + s * 0.7, cy - s * 1.05],
		[cx + s * 0.15, cy - s * 0.62]], BRIGHT, HI, 2.0)
	out += _circ(cx, cy + s * 0.1, s * 0.8, MID, HI, 2.4)
	out += _circ(cx - s * 0.3, cy, s * 0.13, PALE) + _circ(cx + s * 0.3, cy, s * 0.13, PALE)
	return out


func _seal(cx: float, cy: float, s: float) -> String:
	var out := _circ(cx, cy + s * 0.15, s * 0.72, MID, HI, 2.4)
	out += _circ(cx, cy - s * 0.55, s * 0.42, BRIGHT, HI, 2.0)
	out += _poly([[cx - s * 0.95, cy + s * 0.5], [cx - s * 0.45, cy + s * 0.35],
		[cx - s * 0.5, cy + s * 0.85]], BRIGHT)
	out += _poly([[cx + s * 0.95, cy + s * 0.5], [cx + s * 0.45, cy + s * 0.35],
		[cx + s * 0.5, cy + s * 0.85]], BRIGHT)
	out += _circ(cx - s * 0.15, cy - s * 0.62, s * 0.09, DEEP) + _circ(cx + s * 0.15, cy - s * 0.62, s * 0.09, DEEP)
	return out


func _beacon(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s * 0.55, cy + s], [cx - s * 0.3, cy - s * 0.35],
		[cx + s * 0.3, cy - s * 0.35], [cx + s * 0.55, cy + s]], MID, HI, 2.4)
	out += _circ(cx, cy - s * 0.62, s * 0.34, BRIGHT, HI, 2.0)
	out += _line([[cx - s * 0.55, cy - s * 0.95], [cx - s * 0.95, cy - s * 1.0]], PALE, 2.2)
	out += _line([[cx + s * 0.55, cy - s * 0.95], [cx + s * 0.95, cy - s * 1.0]], PALE, 2.2)
	return out


func _ell(cx: float, cy: float, rx: float, ry: float, fill: String, stroke := "", sw := 0.0) -> String:
	var s := '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s"' % [_f(cx), _f(cy), _f(rx), _f(ry), fill]
	if stroke != "":
		s += ' stroke="%s" stroke-width="%s"' % [stroke, _f(sw)]
	return s + "/>"


func _radar(cx: float, cy: float, r: float) -> String:
	var out := _ring(cx, cy, r, 2.6, HI)
	out += _ring(cx, cy, r * 0.55, 1.8, MID)
	out += _line([[cx - r, cy], [cx + r, cy]], MID, 1.6)
	out += _line([[cx, cy - r], [cx, cy + r]], MID, 1.6)
	out += _poly([[cx, cy], [cx + r * 0.95, cy - r * 0.3], [cx + r * 0.55, cy - r * 0.85]], BRIGHT)
	return out


func _shield(cx: float, cy: float, s: float) -> String:
	return _poly([[cx - s, cy - s * 0.85], [cx + s, cy - s * 0.85], [cx + s, cy + s * 0.05],
		[cx, cy + s], [cx - s, cy + s * 0.05]], MID, HI, 2.6)


func _key(cx: float, cy: float, s: float) -> String:
	var out := _ring(cx - s * 0.55, cy, s * 0.42, 3.0, HI)
	out += _rect(cx - s * 0.2, cy - s * 0.16, s * 1.2, s * 0.32, 1.0, BRIGHT)
	out += _rect(cx + s * 0.55, cy + s * 0.1, s * 0.22, s * 0.5, 1.0, BRIGHT)
	out += _rect(cx + s * 0.85, cy + s * 0.1, s * 0.22, s * 0.36, 1.0, BRIGHT)
	return out


func _feather(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx + s * 0.15, cy - s], [cx + s * 0.7, cy - s * 0.15], [cx + s * 0.45, cy + s * 0.5],
		[cx - s * 0.1, cy + s * 0.62], [cx - s * 0.55, cy + s * 0.1], [cx - s * 0.35, cy - s * 0.55]],
		BRIGHT, HI, 2.4)
	out += _line([[cx + s * 0.55, cy - s * 0.55], [cx - s * 0.45, cy + s * 0.95]], MID, 2.2)
	return out


func _flame(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx, cy - s], [cx + s * 0.55, cy - s * 0.15], [cx + s * 0.7, cy + s * 0.45],
		[cx + s * 0.25, cy + s], [cx - s * 0.25, cy + s], [cx - s * 0.7, cy + s * 0.45],
		[cx - s * 0.5, cy - s * 0.2], [cx - s * 0.1, cy - s * 0.35]], BRIGHT, HI, 2.4)
	out += _poly([[cx, cy - s * 0.1], [cx + s * 0.3, cy + s * 0.4], [cx, cy + s * 0.8],
		[cx - s * 0.3, cy + s * 0.4]], PALE)
	return out


func _chain(cx: float, cy: float, s: float, n: int) -> String:
	var out := ""
	var step := 2.0 * s / float(maxi(n, 1))
	for i in n:
		var x := cx - s + step * (float(i) + 0.5)
		out += _ell(x, cy, step * 0.62, step * 0.4, "none", HI if i % 2 == 0 else BRIGHT, 2.6)
	return out


func _drop(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx, cy - s], [cx + s * 0.62, cy + s * 0.2], [cx + s * 0.4, cy + s * 0.72],
		[cx - s * 0.4, cy + s * 0.72], [cx - s * 0.62, cy + s * 0.2]], BRIGHT, HI, 2.2)
	out += _circ(cx - s * 0.16, cy + s * 0.3, s * 0.14, PALE)
	return out


func _eye(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s, cy], [cx - s * 0.45, cy - s * 0.62], [cx + s * 0.45, cy - s * 0.62],
		[cx + s, cy], [cx + s * 0.45, cy + s * 0.62], [cx - s * 0.45, cy + s * 0.62]], MID, HI, 2.4)
	out += _circ(cx, cy, s * 0.3, BRIGHT) + _circ(cx, cy, s * 0.13, DEEP)
	return out


func _mask(cx: float, cy: float, s: float) -> String:
	var out := _rect(cx - s * 0.85, cy - s, s * 1.7, s * 2.0, s * 0.5, MID, HI, 2.6)
	out += _circ(cx - s * 0.36, cy - s * 0.25, s * 0.2, DEEP) + _circ(cx + s * 0.36, cy - s * 0.25, s * 0.2, DEEP)
	out += _arc(cx, cy + s * 0.15, s * 0.42, 20.0, 160.0, PALE, 2.6)
	return out


func _missile(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx, cy - s], [cx + s * 0.42, cy - s * 0.35], [cx + s * 0.42, cy + s * 0.5],
		[cx - s * 0.42, cy + s * 0.5], [cx - s * 0.42, cy - s * 0.35]], BRIGHT, HI, 2.4)
	out += _poly([[cx - s * 0.42, cy + s * 0.1], [cx - s * 0.95, cy + s * 0.85],
		[cx - s * 0.42, cy + s * 0.85]], MID)
	out += _poly([[cx + s * 0.42, cy + s * 0.1], [cx + s * 0.95, cy + s * 0.85],
		[cx + s * 0.42, cy + s * 0.85]], MID)
	return out


func _moon(cx: float, cy: float, r: float) -> String:
	return _circ(cx, cy, r, BRIGHT, HI, 2.4) + _circ(cx + r * 0.55, cy - r * 0.3, r * 0.85, DEEP)


func _snow(cx: float, cy: float, s: float) -> String:
	var out := ""
	for i in 3:
		var a := deg_to_rad(60.0 * float(i))
		out += _line([[cx - cos(a) * s, cy - sin(a) * s], [cx + cos(a) * s, cy + sin(a) * s]], HI, 2.4)
	for i in 6:
		var a := deg_to_rad(60.0 * float(i))
		var bx := cx + cos(a) * s * 0.62
		var by := cy + sin(a) * s * 0.62
		out += _line([[bx, by], [bx + cos(a + 0.9) * s * 0.3, by + sin(a + 0.9) * s * 0.3]], BRIGHT, 2.0)
		out += _line([[bx, by], [bx + cos(a - 0.9) * s * 0.3, by + sin(a - 0.9) * s * 0.3]], BRIGHT, 2.0)
	return out


func _spring(cx: float, cy: float, s: float) -> String:
	var pts: Array = []
	var n := 6
	for i in n + 1:
		var x := cx - s + 2.0 * s * float(i) / float(n)
		pts.append([x, cy - s * 0.55 if i % 2 == 0 else cy + s * 0.55])
	return _line(pts, HI, 3.0)


func _boot(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s * 0.5, cy - s], [cx + s * 0.15, cy - s], [cx + s * 0.15, cy + s * 0.15],
		[cx + s * 0.95, cy + s * 0.35], [cx + s * 0.95, cy + s * 0.8], [cx - s * 0.5, cy + s * 0.8]],
		MID, HI, 2.6)
	out += _rect(cx - s * 0.6, cy + s * 0.8, s * 1.65, s * 0.22, 1.0, PALE)
	return out


func _hand(cx: float, cy: float, s: float) -> String:
	var out := _rect(cx - s * 0.7, cy - s * 0.05, s * 1.4, s * 0.95, s * 0.3, MID, HI, 2.4)
	for i in 3:
		out += _rect(cx - s * 0.62 + s * 0.44 * float(i), cy - s * 0.7, s * 0.34, s * 0.7, s * 0.17, BRIGHT)
	out += _rect(cx - s * 1.05, cy + s * 0.1, s * 0.5, s * 0.34, s * 0.17, BRIGHT)
	return out


func _tag(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s * 0.55, cy - s * 0.85], [cx + s * 0.85, cy - s * 0.85],
		[cx + s * 0.85, cy + s * 0.85], [cx - s * 0.55, cy + s * 0.85], [cx - s, cy]], MID, HI, 2.6)
	out += _circ(cx - s * 0.45, cy, s * 0.17, DEEP)
	return out


func _map(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s, cy - s * 0.7], [cx - s * 0.33, cy - s], [cx + s * 0.33, cy - s * 0.7],
		[cx + s, cy - s], [cx + s, cy + s * 0.7], [cx + s * 0.33, cy + s], [cx - s * 0.33, cy + s * 0.7],
		[cx - s, cy + s]], MID, HI, 2.6)
	out += _line([[cx - s * 0.33, cy - s], [cx - s * 0.33, cy + s * 0.7]], HI, 1.8)
	out += _line([[cx + s * 0.33, cy - s * 0.7], [cx + s * 0.33, cy + s]], HI, 1.8)
	out += _circ(cx + s * 0.05, cy + s * 0.1, s * 0.2, PALE)
	return out


func _egg(cx: float, cy: float, s: float) -> String:
	return _ell(cx, cy, s * 0.72, s, BRIGHT, HI, 2.6) + _circ(cx - s * 0.22, cy - s * 0.3, s * 0.16, PALE)


func _note(cx: float, cy: float, s: float) -> String:
	var out := _rect(cx - s, cy - s * 0.62, s * 2.0, s * 1.24, 2.0, MID, HI, 2.6)
	out += _circ(cx, cy, s * 0.34, BRIGHT) + _circ(cx, cy, s * 0.16, DEEP)
	out += _line([[cx - s * 0.75, cy - s * 0.3], [cx - s * 0.45, cy - s * 0.3]], PALE, 2.0)
	out += _line([[cx + s * 0.45, cy + s * 0.3], [cx + s * 0.75, cy + s * 0.3]], PALE, 2.0)
	return out


func _weight(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s * 0.85, cy + s * 0.85], [cx - s * 0.55, cy - s * 0.35],
		[cx + s * 0.55, cy - s * 0.35], [cx + s * 0.85, cy + s * 0.85]], MID, HI, 2.6)
	out += _arc(cx, cy - s * 0.35, s * 0.42, 180.0, 360.0, HI, 3.0)
	out += _line([[cx - s * 0.5, cy + s * 0.35], [cx + s * 0.5, cy + s * 0.35]], PALE, 2.2)
	return out


func _puddle(cx: float, cy: float, s: float) -> String:
	var out := _ell(cx, cy + s * 0.35, s, s * 0.42, MID, HI, 2.6)
	out += _arc(cx - s * 0.1, cy - s * 0.15, s * 0.5, 200.0, 340.0, PALE, 2.4)
	out += _arc(cx - s * 0.1, cy - s * 0.15, s * 0.72, 205.0, 335.0, BRIGHT, 2.0)
	return out


func _fog(cx: float, cy: float, s: float) -> String:
	var out := ""
	for i in 3:
		var y := cy - s * 0.55 + s * 0.55 * float(i)
		out += _line([[cx - s, y], [cx - s * 0.45, y - s * 0.16], [cx + s * 0.1, y],
			[cx + s * 0.6, y - s * 0.16], [cx + s, y]], HI if i == 1 else BRIGHT, 3.0)
	return out


func _speech(cx: float, cy: float, s: float) -> String:
	var out := _rect(cx - s, cy - s * 0.85, s * 2.0, s * 1.35, s * 0.3, MID, HI, 2.6)
	out += _poly([[cx - s * 0.45, cy + s * 0.5], [cx - s * 0.05, cy + s * 0.5],
		[cx - s * 0.5, cy + s]], MID, HI, 2.0)
	return out


func _door(cx: float, cy: float, s: float) -> String:
	var out := _rect(cx - s * 0.7, cy - s, s * 1.4, s * 2.0, s * 0.7, MID, HI, 2.6)
	out += _rect(cx - s * 0.7, cy - s * 0.1, s * 1.4, s * 1.1, 0.0, BRIGHT)
	out += _circ(cx + s * 0.4, cy + s * 0.45, s * 0.13, PALE)
	return out


func _plush(cx: float, cy: float, s: float) -> String:
	var out := _circ(cx - s * 0.6, cy - s * 0.7, s * 0.32, BRIGHT, HI, 2.0)
	out += _circ(cx + s * 0.6, cy - s * 0.7, s * 0.32, BRIGHT, HI, 2.0)
	out += _circ(cx, cy + s * 0.15, s * 0.85, MID, HI, 2.6)
	out += _circ(cx - s * 0.3, cy, s * 0.12, PALE) + _circ(cx + s * 0.3, cy, s * 0.12, PALE)
	return out


func _fang(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s * 0.85, cy - s * 0.8], [cx - s * 0.1, cy - s * 0.8],
		[cx - s * 0.5, cy + s * 0.9]], BRIGHT, HI, 2.4)
	out += _poly([[cx + s * 0.1, cy - s * 0.8], [cx + s * 0.85, cy - s * 0.8],
		[cx + s * 0.5, cy + s * 0.9]], BRIGHT, HI, 2.4)
	return out


func _trumpet(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s * 0.95, cy - s * 0.2], [cx + s * 0.2, cy - s * 0.45],
		[cx + s * 0.2, cy + s * 0.45], [cx - s * 0.95, cy + s * 0.2]], MID, HI, 2.4)
	out += _poly([[cx + s * 0.2, cy - s * 0.85], [cx + s * 0.95, cy - s], [cx + s * 0.95, cy + s],
		[cx + s * 0.2, cy + s * 0.85]], BRIGHT, HI, 2.4)
	return out


func _anchor(cx: float, cy: float, s: float) -> String:
	var out := _ring(cx, cy - s * 0.72, s * 0.26, 2.8, HI)
	out += _rect(cx - s * 0.11, cy - s * 0.5, s * 0.22, s * 1.3, 1.0, BRIGHT)
	out += _rect(cx - s * 0.5, cy - s * 0.35, s * 1.0, s * 0.2, 1.0, BRIGHT)
	out += _arc(cx, cy - s * 0.05, s * 0.72, 20.0, 160.0, BRIGHT, 3.0)
	return out


func _scope(cx: float, cy: float, r: float) -> String:
	var out := _ring(cx, cy, r, 2.6, HI)
	out += _ring(cx, cy, r * 0.45, 1.8, MID)
	for i in 4:
		var a := deg_to_rad(90.0 * float(i))
		out += _line([[cx + cos(a) * r * 0.55, cy + sin(a) * r * 0.55],
			[cx + cos(a) * r * 1.25, cy + sin(a) * r * 1.25]], BRIGHT, 2.4)
	out += _circ(cx, cy, r * 0.12, PALE)
	return out


func _hex(cx: float, cy: float, s: float) -> String:
	var pts: Array = []
	for i in 6:
		var a := deg_to_rad(60.0 * float(i) - 90.0)
		pts.append([cx + cos(a) * s, cy + sin(a) * s])
	return _poly(pts, MID, HI, 2.8)


func _spiral(cx: float, cy: float, s: float) -> String:
	var pts: Array = []
	for i in 26:
		var t := float(i) / 25.0
		var a := t * PI * 3.4
		var r := s * (0.12 + 0.88 * t)
		pts.append([cx + cos(a) * r, cy + sin(a) * r])
	return _line(pts, HI, 3.0)


func _bars(cx: float, cy: float, s: float, n: int) -> String:
	var out := ""
	var w := 2.0 * s / float(n * 2 - 1)
	for i in n:
		var h := s * (0.35 + 1.3 * float(i) / float(maxi(n - 1, 1)))
		out += _rect(cx - s + w * 2.0 * float(i), cy + s - h, w, h, 1.0,
			BRIGHT if i == n - 1 else MID, HI if i == n - 1 else "", 2.0)
	return out


func _wave(cx: float, cy: float, s: float) -> String:
	var pts: Array = []
	for i in 13:
		var t := float(i) / 12.0
		pts.append([cx - s + 2.0 * s * t, cy + sin(t * PI * 2.0) * s * 0.55])
	return _line(pts, HI, 3.2)


func _dots(cx: float, cy: float, r: float, n: int, col: String) -> String:
	var out := ""
	for i in n:
		var a := deg_to_rad(360.0 * float(i) / float(n) - 90.0)
		out += _circ(cx + cos(a) * r, cy + sin(a) * r, 2.6, col)
	return out


func _slash(cx: float, cy: float, s: float) -> String:
	return _line([[cx - s * 0.8, cy + s * 0.8], [cx + s * 0.8, cy - s * 0.8]], HI, 4.0)


func _gear(cx: float, cy: float, r: float) -> String:
	var pts: Array = []
	for i in 8:
		var a0 := deg_to_rad(45.0 * float(i) - 90.0)
		var w := deg_to_rad(15.0)
		pts.append([cx + cos(a0 - w) * r * 0.74, cy + sin(a0 - w) * r * 0.74])
		pts.append([cx + cos(a0 - w * 0.7) * r, cy + sin(a0 - w * 0.7) * r])
		pts.append([cx + cos(a0 + w * 0.7) * r, cy + sin(a0 + w * 0.7) * r])
		pts.append([cx + cos(a0 + w) * r * 0.74, cy + sin(a0 + w) * r * 0.74])
	var out := _poly(pts, MID, HI, 2.4)
	out += _circ(cx, cy, r * 0.3, DEEP, HI, 2.2)
	return out


func _purse(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s * 0.9, cy + s * 0.85], [cx - s * 0.6, cy - s * 0.2],
		[cx + s * 0.6, cy - s * 0.2], [cx + s * 0.9, cy + s * 0.85]], MID, HI, 2.6)
	out += _arc(cx, cy - s * 0.2, s * 0.6, 180.0, 360.0, HI, 3.0)
	out += _circ(cx, cy + s * 0.35, s * 0.16, PALE)
	return out


func _bulb(cx: float, cy: float, s: float) -> String:
	var out := _circ(cx, cy - s * 0.2, s * 0.72, BRIGHT, HI, 2.6)
	out += _rect(cx - s * 0.32, cy + s * 0.45, s * 0.64, s * 0.5, 1.0, MID)
	out += _line([[cx - s * 0.3, cy + s * 0.62], [cx + s * 0.3, cy + s * 0.62]], PALE, 2.0)
	return out


func _tile(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s, cy - s * 0.55], [cx, cy - s], [cx + s, cy - s * 0.55],
		[cx + s, cy + s * 0.55], [cx, cy + s], [cx - s, cy + s * 0.55]], MID, HI, 2.6)
	out += _poly([[cx - s, cy - s * 0.55], [cx, cy - s], [cx, cy + s * 0.05], [cx - s, cy + s * 0.55]], BRIGHT)
	return out


func _beam(cx: float, cy: float, s: float) -> String:
	var out := _poly([[cx - s * 0.22, cy + s], [cx - s * 0.5, cy - s * 0.55], [cx + s * 0.5, cy - s * 0.55],
		[cx + s * 0.22, cy + s]], BRIGHT, HI, 2.4)
	out += _circ(cx, cy - s * 0.72, s * 0.3, PALE)
	return out


func _figure(cx: float, cy: float, s: float) -> String:
	var out := _circ(cx + s * 0.1, cy - s * 0.78, s * 0.26, BRIGHT, HI, 2.2)
	out += _line([[cx + s * 0.05, cy - s * 0.5], [cx - s * 0.15, cy + s * 0.15]], MID, 5.0)
	out += _line([[cx - s * 0.15, cy + s * 0.15], [cx - s * 0.75, cy + s * 0.85]], HI, 3.4)
	out += _line([[cx - s * 0.15, cy + s * 0.15], [cx + s * 0.55, cy + s * 0.85]], HI, 3.4)
	out += _line([[cx + s * 0.05, cy - s * 0.35], [cx + s * 0.8, cy - s * 0.05]], BRIGHT, 3.2)
	return out


func _refresh(cx: float, cy: float, r: float) -> String:
	var out := _arc(cx, cy, r, -60.0, 240.0, HI, 3.4)
	var a := deg_to_rad(-60.0)
	out += _poly([[cx + cos(a) * r * 1.35, cy + sin(a) * r * 1.35],
		[cx + cos(a - 0.5) * r * 0.75, cy + sin(a - 0.5) * r * 0.75],
		[cx + cos(a + 0.5) * r * 0.75, cy + sin(a + 0.5) * r * 0.75]], BRIGHT)
	return out


func _maw(cx: float, cy: float, r: float) -> String:
	var out := _circ(cx, cy, r, DEEP, HI, 3.0)
	for i in 6:
		var a := deg_to_rad(60.0 * float(i) - 90.0)
		var a1 := a - 0.42
		var a2 := a + 0.42
		out += _poly([[cx + cos(a1) * r, cy + sin(a1) * r],
			[cx + cos(a2) * r, cy + sin(a2) * r],
			[cx + cos(a) * r * 0.45, cy + sin(a) * r * 0.45]], BRIGHT)
	return out


func _check(cx: float, cy: float, s: float) -> String:
	return _line([[cx - s * 0.8, cy], [cx - s * 0.15, cy + s * 0.65], [cx + s * 0.85, cy - s * 0.7]], HI, 3.6)


func _lock(cx: float, cy: float, s: float) -> String:
	var out := _arc(cx, cy - s * 0.15, s * 0.42, 180.0, 360.0, HI, 3.0)
	out += _rect(cx - s * 0.62, cy - s * 0.15, s * 1.24, s * 0.95, 2.0, MID, HI, 2.4)
	out += _circ(cx, cy + s * 0.3, s * 0.14, PALE)
	return out

func _wedge(cx: float, cy: float, r: float, a0: float, a1: float, col: String) -> String:
	var pts: Array = [[cx, cy]]
	for i in 9:
		var a := deg_to_rad(lerpf(a0, a1, float(i) / 8.0))
		pts.append([cx + cos(a) * r, cy + sin(a) * r])
	return _poly(pts, col, HI, 2.0)


# ---- recipes -------------------------------------------------------------------
# One branch per content id. Each glyph is drawn from what the item DOES (its effect or
# rule text), so the set is the game's own depiction and not a copy of any other game's
# art. An id with no branch returns "" and the generator refuses to write the set.

func _glyph(id: String) -> String:
	match id:
		# ---- upgrades ----
		"bargain":
			return _tag(29.0, 30.0, 12.0) + _arrow(45.0, 44.0, 6.5, "down")
		"bounty_hunter":
			return _scope(32.0, 32.0, 17.0) + _coin(32.0, 32.0, 7.0)
		"brace":
			return _shield(32.0, 36.0, 13.0) + _arrow(32.0, 18.0, 6.0, "down")
		"cartographer":
			return _map(32.0, 32.0, 16.0)
		"cold_blood":
			return _ring(32.0, 32.0, 17.0, 3.0, HI) + _snow(32.0, 32.0, 9.0)
		"defuse_kit":
			return _mine(32.0, 38.0, 11.0) + _line([[32.0, 27.0], [32.0, 18.0]], HI, 3.0) + \
				_line([[28.0, 14.0], [36.0, 22.0]], BRIGHT, 2.6) + \
				_line([[36.0, 14.0], [28.0, 22.0]], BRIGHT, 2.6)
		"early_warning":
			return _eye(32.0, 32.0, 15.0) + _arc(32.0, 32.0, 21.0, -50.0, 50.0, HI, 2.6) + \
				_arc(32.0, 32.0, 21.0, 130.0, 230.0, HI, 2.6)
		"featherfall":
			return _feather(32.0, 28.0, 13.0) + _arrow(32.0, 48.0, 6.0, "down")
		"field_dressing":
			return _rect(16.0, 16.0, 32.0, 32.0, 7.0, MID, HI, 2.8) + _plus(32.0, 32.0, 9.0, BRIGHT)
		"gilded_touch":
			return _hand(32.0, 36.0, 13.0) + _coin(32.0, 16.0, 6.5)
		"high_ceiling":
			return _chain(32.0, 40.0, 14.0, 2) + _arrow(32.0, 20.0, 7.0, "up")
		"hot_streak":
			return _flame(32.0, 32.0, 17.0)
		"insulation":
			return _boot(32.0, 30.0, 13.0) + _rect(14.0, 46.0, 36.0, 6.0, 2.0, BRIGHT, HI, 2.0)
		"last_call":
			return _bell(32.0, 30.0, 15.0)
		"ledge_grace":
			return _rect(12.0, 40.0, 40.0, 7.0, 2.0, MID, HI, 2.6) + \
				_arc(32.0, 40.0, 16.0, 200.0, 340.0, HI, 2.8) + _circ(32.0, 22.0, 3.0, PALE)
		"long_reach":
			return _ring(32.0, 32.0, 8.0, 3.0, BRIGHT) + _ring(32.0, 32.0, 15.0, 2.6, MID) + \
				_circ(32.0, 32.0, 3.2, PALE)
		"marathon":
			return _figure(32.0, 32.0, 15.0)
		"more":
			return _gift(32.0, 34.0, 13.0) + _plus(47.0, 17.0, 5.0, HI)
		"nest_egg":
			return _egg(32.0, 28.0, 13.0) + _arc(32.0, 34.0, 17.0, 20.0, 160.0, HI, 3.0)
		"paycheck":
			return _note(32.0, 32.0, 16.0)
		"pocket_beacon":
			return _beacon(32.0, 36.0, 13.0) + _ring(32.0, 16.0, 6.5, 2.6, HI)
		"quick_recovery":
			return _refresh(32.0, 32.0, 15.0)
		"radar_beacon":
			return _radar(32.0, 32.0, 18.0) + _rect(29.0, 33.0, 6.0, 9.0, 1.0, BRIGHT, HI, 1.8) + \
				_poly([[32.0, 27.0], [37.0, 33.0], [27.0, 33.0]], BRIGHT, HI, 1.8)
		"radar_gifts":
			return _radar(32.0, 32.0, 18.0) + _rect(27.0, 30.0, 10.0, 10.0, 1.5, BRIGHT, HI, 1.8)
		"radar_mines":
			return _radar(32.0, 32.0, 18.0) + _circ(32.0, 35.0, 5.0, BRIGHT, HI, 1.8)
		"radar_threats":
			return _radar(32.0, 32.0, 18.0) + _poly([[32.0, 29.0], [38.0, 40.0], [26.0, 40.0]], BRIGHT, HI, 1.8)
		"skeleton_key":
			return _key(32.0, 32.0, 15.0)
		"slipstream":
			return _arrow(38.0, 32.0, 13.0, "right") + _line([[10.0, 24.0], [22.0, 24.0]], HI, 2.6) + \
				_line([[8.0, 32.0], [20.0, 32.0]], BRIGHT, 2.6) + _line([[10.0, 40.0], [22.0, 40.0]], HI, 2.6)
		"spring_heels":
			return _spring(32.0, 40.0, 14.0) + _arrow(32.0, 22.0, 7.0, "up")
		"stand_fast":
			return _anchor(32.0, 32.0, 15.0)
		"straggler_scope":
			return _scope(32.0, 26.0, 13.0) + _line([[32.0, 40.0], [32.0, 52.0]], HI, 3.0)
		"subspacial_barrier":
			return _hex(32.0, 32.0, 17.0) + _circ(32.0, 32.0, 6.0, BRIGHT, HI, 2.0)
		"sure_foot":
			return _boot(32.0, 30.0, 13.0) + _check(32.0, 48.0, 7.0)
		"twin_dash":
			return _chevron(22.0, 32.0, 13.0, HI) + _chevron(38.0, 32.0, 13.0, BRIGHT)
		"updraft":
			return _arrow(32.0, 32.0, 15.0, "up") + _arc(32.0, 40.0, 20.0, 200.0, 250.0, HI, 2.4) + \
				_arc(32.0, 40.0, 20.0, 290.0, 340.0, HI, 2.4)
		"yearn_for_speed":
			return _bolt(32.0, 32.0, 17.0, BRIGHT)
		# ---- curses ----
		"aftershock":
			return _ring(32.0, 32.0, 9.0, 3.0, BRIGHT) + _ring(32.0, 32.0, 16.0, 2.6, MID) + \
				_circ(32.0, 32.0, 3.0, PALE)
		"brittle":
			return _shield(32.0, 32.0, 16.0) + _crack(32.0, 32.0, 13.0, DEEP)
		"bunker_buster":
			return _burst(32.0, 24.0, 13.0, 8, BRIGHT) + _rect(20.0, 38.0, 24.0, 14.0, 2.0, MID, HI, 2.4)
		"cold_start":
			return _gear(32.0, 32.0, 17.0) + _snow(32.0, 32.0, 7.0)
		"crescendo":
			return _bars(32.0, 32.0, 16.0, 4)
		"crowded_dais":
			return _beacon(32.0, 36.0, 12.0) + _dots(32.0, 32.0, 19.0, 6, BRIGHT)
		"crumbling":
			return _tile(32.0, 26.0, 14.0) + _crack(32.0, 26.0, 11.0, DEEP) + \
				_poly([[20.0, 46.0], [26.0, 46.0], [23.0, 54.0]], BRIGHT) + \
				_poly([[38.0, 46.0], [44.0, 46.0], [41.0, 54.0]], BRIGHT)
		"curfew":
			return _clock(32.0, 28.0, 14.0, -90.0, PALE) + _lock(32.0, 49.0, 6.5)
		"direct_shot":
			return _circ(22.0, 40.0, 8.0, BRIGHT, HI, 2.4) + \
				_line([[30.0, 34.0], [38.0, 26.0], [46.0, 34.0]], HI, 3.0) + \
				_line([[46.0, 34.0], [52.0, 28.0]], BRIGHT, 2.6)
		"double_ring":
			return _ring(32.0, 32.0, 9.0, 3.0, BRIGHT) + _ring(32.0, 32.0, 17.0, 3.0, HI)
		"dull_gifts":
			return _gift(32.0, 32.0, 14.0) + _slash(32.0, 32.0, 18.0)
		"early_bird":
			return _clock(24.0, 32.0, 12.0, -90.0, PALE) + _chevron(42.0, 32.0, 8.0, HI) + \
				_chevron(50.0, 32.0, 8.0, BRIGHT)
		"egoist":
			return _circ(32.0, 18.0, 6.5, BRIGHT, HI, 2.2) + _circ(22.0, 42.0, 6.5, BRIGHT, HI, 2.2) + \
				_circ(42.0, 42.0, 6.5, BRIGHT, HI, 2.2) + _plus(32.0, 34.0, 4.5, PALE)
		"hasty":
			return _clock(30.0, 32.0, 15.0, -60.0, PALE) + _bolt(48.0, 20.0, 7.0, BRIGHT)
		"hungry_void":
			return _maw(32.0, 32.0, 18.0)
		"inflation":
			return _coin(32.0, 38.0, 11.0) + _arrow(32.0, 20.0, 7.0, "up")
		"leaky_purse":
			return _purse(32.0, 28.0, 13.0) + _drop(32.0, 50.0, 6.0)
		"lights_out":
			return _bulb(32.0, 30.0, 14.0) + _slash(32.0, 32.0, 18.0)
		"litter":
			return _cat(24.0, 30.0, 12.0) + _cat(44.0, 42.0, 7.0)
		"long_night":
			return _moon(28.0, 28.0, 14.0) + _clock(47.0, 47.0, 7.5, -90.0, PALE)
		"long_toll":
			return _bell(26.0, 30.0, 12.0) + _bell(44.0, 40.0, 8.0)
		"longer_speech":
			return _speech(32.0, 30.0, 15.0) + _rect(22.0, 26.0, 20.0, 4.0, 2.0, PALE) + \
				_rect(22.0, 34.0, 12.0, 4.0, 2.0, PALE)
		"method_acting":
			return _mask(32.0, 32.0, 16.0)
		"mirror_match":
			return _line([[32.0, 14.0], [32.0, 50.0]], MID, 2.0) + _arrow(22.0, 32.0, 9.0, "right") + \
				_arrow(42.0, 32.0, 9.0, "left")
		"no_refunds":
			return _ring(32.0, 32.0, 15.0, 3.4, BRIGHT) + _slash(32.0, 32.0, 17.0)
		"overwound":
			return _spiral(32.0, 32.0, 16.0)
		"pup_pack":
			return _seal(24.0, 30.0, 12.0) + _seal(44.0, 42.0, 7.0)
		"quarter_chimes":
			return _clock(32.0, 32.0, 16.0, -90.0, PALE) + _wedge(32.0, 32.0, 13.0, -90.0, 0.0, BRIGHT)
		"rearguard":
			return _beacon(26.0, 34.0, 12.0) + _poly([[44.0, 24.0], [52.0, 40.0], [36.0, 40.0]], BRIGHT, HI, 2.0)
		"rush_hour":
			return _figure(30.0, 32.0, 14.0) + _line([[12.0, 24.0], [20.0, 24.0]], HI, 2.6) + \
				_line([[10.0, 32.0], [18.0, 32.0]], BRIGHT, 2.6) + \
				_line([[12.0, 40.0], [20.0, 40.0]], HI, 2.6)
		"second_strike":
			return _missile(24.0, 26.0, 12.0) + _missile(44.0, 42.0, 8.0)
		"short_chain":
			return _chain(32.0, 32.0, 15.0, 2) + _rect(30.0, 22.0, 4.0, 20.0, 0.0, DEEP)
		"slipstream_trail":
			return _wave(32.0, 30.0, 16.0) + _drop(32.0, 48.0, 6.0)
		"slow_door":
			return _door(26.0, 32.0, 14.0) + _clock(46.0, 44.0, 8.0, -90.0, PALE)
		"spreading_rot":
			return _grid(32.0, 32.0, 15.0, 3, MID) + _rect(17.0, 17.0, 10.0, 10.0, 1.0, BRIGHT) + \
				_rect(27.0, 27.0, 10.0, 10.0, 1.0, MID) + _rect(37.0, 37.0, 10.0, 10.0, 1.0, MID)
		"tarnish":
			return _coin(32.0, 30.0, 14.0) + _wedge(32.0, 30.0, 12.0, 30.0, 150.0, DEEP)
		"thick_fog":
			return _fog(32.0, 32.0, 16.0)
		"token_limit":
			return _plush(32.0, 30.0, 13.0) + _rect(14.0, 46.0, 36.0, 5.0, 2.0, HI)
		"twin_fangs":
			return _fang(32.0, 32.0, 16.0)
		"unannounced":
			return _trumpet(32.0, 32.0, 15.0) + _slash(32.0, 32.0, 18.0)
		"understudies":
			return _mine(24.0, 30.0, 11.0) + _mine(44.0, 42.0, 7.0)
		"unmarked":
			return _beam(32.0, 32.0, 15.0) + _slash(32.0, 32.0, 18.0)
		"weighed_down":
			return _weight(32.0, 32.0, 16.0)
		"wet_floor":
			return _puddle(32.0, 34.0, 16.0)
		"wide_blast":
			return _burst(32.0, 32.0, 18.0, 10, BRIGHT) + _ring(32.0, 32.0, 20.0, 2.0, HI)
		"zoomies":
			return _cat(32.0, 32.0, 14.0) + _line([[10.0, 24.0], [18.0, 24.0]], HI, 2.6) + \
				_line([[8.0, 32.0], [16.0, 32.0]], BRIGHT, 2.6) + \
				_line([[10.0, 40.0], [18.0, 40.0]], HI, 2.6)
	return ""
