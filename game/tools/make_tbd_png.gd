extends SceneTree

# game/tools/make_tbd_png.gd - the TBD placeholder generator (ENEMIES.md hard rule
# "TBD FALLBACK", FLEET_PACK.md T-016).
#
#   tools\godot\godot.exe --headless --path game --script res://tools/make_tbd_png.gd -- <out.png>
#
# Writes a 256x256 fully transparent PNG whose only content is a magenta block body
# (a plain rounded-off rectangle with a darker rim) carrying black "TBD" letters in a
# 5x7 pixel font. The body sits behind a margin, so the canvas corners are transparent
# and no opaque 1-px border exists - the sprite validator's geometric checks pass on it.
#
# The sprite pipeline (sprite_pipeline.gd) calls build() directly for every source
# image that is missing from assets_src/enemies/, so a missing asset never stalls the
# run: the placeholder is the body, "tbd": true goes into sprites.json, one row lands
# in TBD.md, and dropping the real PNG in later is a rebuild and nothing else.

const BODY := 0xFF00FFFF          # magenta #FF00FF, opaque
const BODY_EDGE := 0xA800A8FF     # darker magenta rim
const INK := 0x050505FF           # the letters
const BODY_MARGIN := 16           # px of transparent canvas around the block body
const RIM := 4                    # px of darker rim inside the body
const GLYPH_SCALE := 4            # px per font pixel at 256x256

# 5x7 pixel font, one row of 5 characters per glyph line.
const GLYPHS := {
	"T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
	"B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
}


# Builds the placeholder at the given square size. Static so the sprite pipeline can
# call it without instancing a SceneTree.
static func build(size: int = 256) -> Image:
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	# the block body: a square behind a margin, with the darker rim on its edge
	var x0 := BODY_MARGIN
	var y0 := BODY_MARGIN
	var x1 := size - 1 - BODY_MARGIN
	var y1 := size - 1 - BODY_MARGIN
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c: int = BODY
			if x < x0 + RIM or x > x1 - RIM or y < y0 + RIM or y > y1 - RIM:
				c = BODY_EDGE
			img.set_pixel(x, y, Color(c))
	# the letters: T B D, scaled, centred inside the body
	var font := ["T", "B", "D"]
	var gw: int = 5 * GLYPH_SCALE
	var gap: int = 2 * GLYPH_SCALE
	var total_w: int = len(font) * gw + (len(font) - 1) * gap
	var glyph_h: int = 7 * GLYPH_SCALE
	var ox: int = (size - total_w) / 2
	var oy: int = y0 + ((y1 - y0 + 1) - glyph_h) / 2
	for g in range(len(font)):
		var rows: Array = GLYPHS[font[g]]
		var gx: int = ox + g * (gw + gap)
		for row in range(len(rows)):
			for col in range(len(rows[row])):
				if rows[row][col] == "#":
					for dy in GLYPH_SCALE:
						for dx in GLYPH_SCALE:
							img.set_pixel(gx + col * GLYPH_SCALE + dx, oy + row * GLYPH_SCALE + dy, Color(INK))
	return img


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1:
		print("TBD PNG USAGE: -- <out.png>  (writes one 256x256 TBD placeholder PNG)")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[0].get_base_dir())
	var img := build(256)
	if img.save_png(args[0]) != OK:
		print("TBD PNG FAILED: %s" % args[0])
		quit(1)
		return
	print("TBD PNG OK %s" % args[0])
	quit(0)
