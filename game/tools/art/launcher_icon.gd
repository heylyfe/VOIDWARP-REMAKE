extends SceneTree
#
# game/tools/art/launcher_icon_a.gd - the VOIDWRAP launcher icon, cycle 7 (track T3).
#
#   <godot> --headless --path game --script res://tools/art/launcher_icon.gd
#
# Renders the icon at 512/256/128/64/48/32/16 px into assets/icons/launcher/ as
# voidwrap_<size>.png (the 512 px png is the project icon; game/tools/art/pack_ico.py
# packs the other six into voidwrap.ico for the Windows exe). No randomness, no wall
# clock, no external art: the whole set is reproducible with the one command above.
#
# Motif: the blue jump pad (the owner's ref, game/out/owner_refs/jumppad_ref.png) seen
# top-down - a glossy blue rounded slab floating over the dark void plate, its two cyan
# launch rings spreading across the tile. Flat fills, no gradients, quantised to the
# house-icon palette (docs/classes/*.svg, tools/art/icons.gd) plus the pad's own
# saturated blue and its lit cyan top-face highlight.
#
# Drawn per pixel from signed-distance functions with analytic coverage, so every
# size renders from the same geometry (strokes have px floors so the small tiles
# keep the rim, the rings and the blue diamond).

const SIZES := [512, 256, 128, 64, 48, 32, 16]
const OUT_DIR := "assets/icons/launcher"

# Palette (floats 0..1): #0A2E30 deep ground, PLATE_SHADE #072326 the shaded lower
# band, RIM #2FB7B0, HI #7CFFF4, PAD #1A2BFF the pad's blue, PAD_TOP #4E5EFF the
# lit top face, VOID #041416 the deepest tone (unused layer, kept for completeness).
const VOID := Color(0.016, 0.078, 0.086)
const PLATE := Color(0.0392, 0.1804, 0.1882)
const PLATE_SHADE := Color(0.0275, 0.1373, 0.149)
const RIM := Color(0.1843, 0.7176, 0.6902)
const HI := Color(0.4863, 1.0, 0.9569)
const PAD := Color(0.1020, 0.1686, 1.0)
const PAD_TOP := Color(0.3059, 0.3686, 1.0)
const CLEAR := Color(0, 0, 0, 0)


func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var out: String = game_dir + "/" + OUT_DIR
	DirAccess.make_dir_recursive_absolute(out)
	var written := 0
	for size in SIZES:
		var img := _render(size)
		var path := "%s/voidwrap_%d.png" % [out, size]
		if img == null or img.save_png(path) != OK:
			print("LAUNCHERICON FAILED: cannot write %s" % path)
			quit(1)
			return
		written += 1
		print("LAUNCHERICON wrote %s (%d px)" % [path, size])
	if written != SIZES.size():
		print("LAUNCHERICON FAILED: wrote %d of %d sizes" % [written, SIZES.size()])
		quit(1)
		return
	print("LAUNCHERICON OK: %d pngs in %s" % [written, out])
#
# Rendering. All distances are signed-distance values in unit coordinates,
# converted to px for the coverage test; strokes are px with floors so the
# small tiles keep the rim, the rings and the blue diamond.


func _render(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var fy := (y + 0.5) / size
		for x in size:
			var fx := (x + 0.5) / size
			img.set_pixel(x, y, _pixel(Vector2(fx, fy), size))
	return img


## The painter's order: plate, shade band, rim, shadow, launch rings, pad slab,
## lit top face, lit far edge. Every layer composites over the previous one.
func _pixel(p: Vector2, s: int) -> Color:
	var col := CLEAR
	# the rounded dark plate fills the tile
	var plate_d := _px(sd_round_rect(p - Vector2(0.5, 0.5), Vector2(0.48, 0.48), 0.22), s)
	col = _blend(col, PLATE, _aa(plate_d))
	# a flat darker band below the pad line gives the tile its two tones
	var shade := (p.y - 0.58) * s
	col = _blend(col, PLATE_SHADE, _aa(plate_d) * clampf(shade + 0.5, 0.0, 1.0))
	# the cyan rim: a stroke just inside the plate's edge, lit along the top
	var rim_w := maxf(0.020 * s, 1.5)
	var rim_outer := plate_d
	var rim_inner := _px(sd_round_rect(p - Vector2(0.5, 0.5), Vector2(0.48 - rim_w / s, 0.48 - rim_w / s), 0.22), s)
	var rim_cov := _aa(rim_outer) * _aa(-rim_inner)
	var rim_col := HI if p.y < 0.32 else RIM
	col = _blend(col, rim_col, rim_cov)
	return _pixel_pad(p, s, col, plate_d, rim_w)


## The pad layers, on top of the plate: shadow, the two launch rings (both clipped
## to the plate and painted before the slab so the slab floats in front of them),
## then the slab itself, its lit top face and its lit far edge.
func _pixel_pad(p: Vector2, s: int, col: Color, plate_d: float, rim_w: float) -> Color:
	var inside_plate := _aa(plate_d + rim_w)
	# the slab's shadow on the plate
	var shadow_d := _px(sd_ellipse(p - Vector2(0.5, 0.615), Vector2(0.34, 0.10)), s)
	col = _blend(col, PLATE_SHADE.darkened(0.35), _aa(plate_d) * _aa(shadow_d) * 0.8)
	# the two launch rings: a thin bright ellipse outside a wider cyan one
	var ring1_d := _px(sd_ellipse(p - Vector2(0.5, 0.56), Vector2(0.44, 0.34)), s)
	var ring1_w := maxf(0.020 * s, 1.4)
	col = _blend(col, HI, inside_plate * _aa(ring1_d) * _aa(-ring1_d - ring1_w))
	var ring2_d := _px(sd_ellipse(p - Vector2(0.5, 0.56), Vector2(0.37, 0.27)), s)
	var ring2_w := maxf(0.028 * s, 2.2)
	col = _blend(col, RIM, inside_plate * _aa(ring2_d) * _aa(-ring2_d - ring2_w))
	# the blue pad: a rounded slab tilted over the void
	var q := (p - Vector2(0.5, 0.545)).rotated(-0.18)
	var pad_r := maxf(0.10 * s, 2.2)
	var pad_d_round := _px(sd_round_rect(q, Vector2(0.270 - pad_r / s, 0.205 - pad_r / s), 0.0), s) - pad_r
	col = _blend(col, PAD, _aa(pad_d_round))
	# the lit top face: the same slab shape raised, clipped to the slab
	var sheen_d := _px(sd_round_rect(q - Vector2(0.0, 0.035), Vector2(0.270 - pad_r / s, 0.205 - pad_r / s), 0.0), s) - pad_r
	col = _blend(col, PAD_TOP, _aa(sheen_d) * _aa(-pad_d_round))
	# the lit far edge: a bright stroke along the slab's upper boundary,
	# fading out down its sides
	var edge_w := maxf(0.022 * s, 1.3)
	var edge := _aa(pad_d_round + edge_w) * _aa(-pad_d_round)
	col = _blend(col, HI, edge * (1.0 - clampf((q.y + 0.08) * s + 0.5, 0.0, 1.0)))
	return col
#
# Signed-distance helpers. Distances are in unit coordinates (multiply by the
# render size for the px-domain coverage test).


## Distance to a rectangle with corner radius r, centred on the origin. The callers
## bake their own px-floored corner radius into `half` and pass r = 0, so the
## rounded corners stay rounded at every size.
static func sd_round_rect(p: Vector2, half: Vector2, r: float) -> float:
	var qx := absf(p.x) - half.x + r
	var qy := absf(p.y) - half.y + r
	var outside := Vector2(maxf(qx, 0.0), maxf(qy, 0.0)).length()
	return outside + minf(maxf(qx, qy), 0.0) - r


## Approximate distance to an axis-aligned ellipse, exact on the axes: good
## enough for the rings' pixel band, and cheap enough to run per pixel at 512 px.
static func sd_ellipse(p: Vector2, r: Vector2) -> float:
	var d := (p / r).length()
	return (d - 1.0) * minf(r.x, r.y)
