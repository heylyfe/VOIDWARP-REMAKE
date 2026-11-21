extends RefCounted
#
# Curse and upgrade icon art (TBD.md row 21).
#
# Leg 1 - every content id resolves. For every id the content registry boots with, the
#   SAME lookup the views use (view/icon_art.gd texture_for) returns a real Texture2D of
#   the expected size. A new upgrade or curse shipped without an icon fails here instead
#   of shipping a blank cell in the HUD or a dark face on an altar.
# Leg 2 - the house palette. Every pixel of every icon is either fully transparent or
#   exactly one of the five house colours (docs/classes/*.svg). There is no tolerance:
#   game/tools/art/icons.gd quantises every icon to the palette, so an anti-aliased edge
#   or a stray colour is a real failure, not noise.
# Leg 3 - the negative control. Both checks are run against deliberately wrong input and
#   must report EXACTLY the stated number of failures: one bogus id in a two-id list, and
#   one off-palette pixel in a synthetic image. Without this leg a check that silently
#   passes everything would look green.
#
# The art is generated, not drawn by hand: game/tools/art/icons.gd emits every PNG from
# SVG built in code, so the whole set is reproducible with one command.

const IconArtScript := preload("res://view/icon_art.gd")
const ContentApiScript := preload("res://core/content_api.gd")

const SIZE := 128
const PALETTE := ["#0A2E30", "#1C6E70", "#2FB7B0", "#7CFFF4", "#8FE8E0"]
const KINDS := ["upgrades", "curses"]


func run() -> Array[String]:
	var f: Array[String] = []
	var api = ContentApiScript.load()
	if api == null or not api.is_ok():
		f.append("icon art: content boot failed: %s" % " / ".join(api.boot_errors() if api != null else []))
		return f
	var ids := {"upgrades": api.upgrade_ids(), "curses": api.curse_ids()}
	for kind in KINDS:
		var list: Array = ids[kind]
		if list.is_empty():
			f.append("icon art: no %s ids registered - the leg proves nothing" % kind)
			continue
		f.append_array(resolve_failures(kind, list))
		f.append_array(palette_failures_for(kind, list))
	f.append_array(negative_control())
	return f


## Leg 1: every id in the list resolves to a real texture through the views' lookup.
func resolve_failures(kind: String, ids: Array) -> Array[String]:
	var f: Array[String] = []
	for raw in ids:
		var id := str(raw)
		var tex := IconArtScript.texture_for(kind, id)
		if tex == null:
			f.append("icon art: %s/%s has no icon (expected %s)" % [kind, id, IconArtScript.path_for(kind, id)])
			continue
		var img := tex.get_image()
		if img == null:
			f.append("icon art: %s/%s loaded but carries no image" % [kind, id])
			continue
		if img.get_width() != SIZE or img.get_height() != SIZE:
			f.append("icon art: %s/%s is %dx%d, want %dx%d" % [
				kind, id, img.get_width(), img.get_height(), SIZE, SIZE])
	return f


## Leg 2: every pixel of every icon is transparent or exactly a house colour.
func palette_failures_for(kind: String, ids: Array) -> Array[String]:
	var f: Array[String] = []
	for raw in ids:
		var id := str(raw)
		var tex := IconArtScript.texture_for(kind, id)
		if tex == null:
			continue   # leg 1 already reported it
		f.append_array(palette_failures(tex.get_image(), "%s/%s" % [kind, id]))
	return f


## The palette check itself, so the negative control can run it on a synthetic image.
## Returns one failure line per offending image, naming the count and the first pixel.
func palette_failures(img: Image, label: String) -> Array[String]:
	var f: Array[String] = []
	if img == null:
		f.append("icon art: %s carries no image" % label)
		return f
	var copy := img.duplicate() as Image
	copy.convert(Image.FORMAT_RGBA8)
	var data := copy.get_data()
	var want := copy.get_width() * copy.get_height() * 4
	if data.size() != want:
		f.append("icon art: %s data is %d bytes, want %d" % [label, data.size(), want])
		return f
	var allowed := {}
	for hex in PALETTE:
		allowed[_key(Color(hex))] = true
	var bad := 0
	var first := ""
	var i := 0
	while i < data.size():
		var a := data[i + 3]
		# A fully transparent pixel shows nothing, so its RGB is irrelevant. Anything
		# visible must be opaque (the set is hard-edged: no partial alpha) and exactly a
		# house colour.
		if a != 0:
			var key := (data[i] << 24) | (data[i + 1] << 16) | (data[i + 2] << 8) | a
			if a != 255 or not allowed.has(key):
				bad += 1
				if first == "":
					first = "#%02X%02X%02X alpha %d at pixel %d" % [
						data[i], data[i + 1], data[i + 2], a, i / 4]
		i += 4
	if bad > 0:
		f.append("icon art: %s has %d pixel(s) outside the house palette, first %s" % [label, bad, first])
	return f


static func _key(c: Color) -> int:
	return (int(round(c.r * 255.0)) << 24) | (int(round(c.g * 255.0)) << 16) | \
		(int(round(c.b * 255.0)) << 8) | int(round(c.a * 255.0))


## Leg 3: the negative control. Each check is fed input it MUST reject, and the failure
## count is asserted exactly - so a check that stopped checking cannot pass this leg.
func negative_control() -> Array[String]:
	var f: Array[String] = []

	# 3a. a bogus id: exactly one failure, naming the id. An empty list: none. The control
	# is deliberately independent of the shipped set, so it still means something when an
	# icon is missing (leg 1 reports that on its own).
	var bogus := resolve_failures("upgrades", ["no_such_upgrade"])
	if bogus.size() != 1:
		f.append("negative control: a bogus upgrade id produced %d failure(s), want exactly 1 (%s)" % [
			bogus.size(), " | ".join(bogus)])
	elif not str(bogus[0]).contains("no_such_upgrade"):
		f.append("negative control: the bogus-id failure does not name the id: %s" % str(bogus[0]))
	var none := resolve_failures("upgrades", [])
	if not none.is_empty():
		f.append("negative control: an empty id list produced %d failure(s), want 0" % none.size())

	# 3b. a clean synthetic image: zero failures (the check is not simply always-failing).
	var clean := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	clean.fill(Color(PALETTE[0]))
	clean.set_pixel(0, 0, Color(0, 0, 0, 0))
	var clean_f := palette_failures(clean, "synthetic-clean")
	if not clean_f.is_empty():
		f.append("negative control: a palette-only image was rejected: %s" % " | ".join(clean_f))

	# 3c. one off-palette pixel: exactly one failure, and it reports exactly one pixel.
	var dirty := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	dirty.fill(Color(PALETTE[2]))
	dirty.set_pixel(3, 4, Color("#FF00EF"))
	var dirty_f := palette_failures(dirty, "synthetic-dirty")
	if dirty_f.size() != 1:
		f.append("negative control: one off-palette pixel produced %d failure(s), want exactly 1 (%s)" % [
			dirty_f.size(), " | ".join(dirty_f)])
	elif not str(dirty_f[0]).contains("1 pixel(s)"):
		f.append("negative control: the off-palette failure does not report 1 pixel: %s" % str(dirty_f[0]))

	# 3d. a one-step-off colour must be caught too: the check is exact, not approximate.
	var near := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	near.fill(Color(PALETTE[0]))
	near.set_pixel(1, 1, Color(0.0392, 0.1804, 0.1882))   # #0A2E30 with blue +1
	var near_f := palette_failures(near, "synthetic-near")
	if near_f.size() != 1:
		f.append("negative control: a one-step-off colour produced %d failure(s), want exactly 1 (%s)" % [
			near_f.size(), " | ".join(near_f)])

	# 3e. a half-transparent pixel must be caught: the set is hard-edged, no partial alpha.
	var soft := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	soft.fill(Color(PALETTE[1]))
	soft.set_pixel(2, 2, Color(PALETTE[1], 0.5))
	var soft_f := palette_failures(soft, "synthetic-soft")
	if soft_f.size() != 1:
		f.append("negative control: a half-transparent pixel produced %d failure(s), want exactly 1 (%s)" % [
			soft_f.size(), " | ".join(soft_f)])

	# 3f. the resolver's missing-art path: an unknown kind and an empty id are both null.
	if IconArtScript.texture_for("no_such_kind", "brace") != null:
		f.append("negative control: an unknown kind resolved to a texture")
	if IconArtScript.texture_for("upgrades", "") != null:
		f.append("negative control: an empty id resolved to a texture")
	return f
