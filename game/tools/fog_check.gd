extends SceneTree
#
# Fog-readability check - ticket T-011; implements TERRAIN_SPEC.md section 12.3 exactly:
#
#   <godot> --headless --path game --script res://tools/fog_check.gd -- [biome_id ...]
#
# visible(d) = exp(-density * d); on-screen colour = lerp(fog, colour, visible(d)); the required
# contrast is the WCAG relative luminance contrast ratio, computed on the fogged colours as
# displayed. Palette comes from data/palette.json with the act roles overridden by
# content/biomes/<id>.json through view/fog_env.gd's resolver (the one act-palette source).
# No biome ids on the command line: every biome file is checked.
#
# Required rows (contrast on the fogged colours, at the stated distances):
#   platform checker light vs fog                 d = 60 u  >= 3.0
#   walkway checker light vs fog                  d = 60 u  >= 3.0
#   platform light vs platform dark (both fogged) d = 40 u  >= 2.0
#   black gift rim / gold gift / tripmine particles / open beacon vs fog @ 60 u   >= 4.5
#   every enemy PNG mean opaque colour vs fog     d = 40 u  >= 3.0 (ENEMIES.md hard rule;
#                                     sprites arrive with T-016; until then the row is vacuous)
#
# Emission multipliers stated by section 12.2 are part of the on-screen radiance (checker lights
# +0.35 x albedo, black gift rim x1.5, gold gift x2.0, open beacon x4.0; the mine particles have
# none). The DESIGN.md section 10 rule "tripmine particles vs platform light >= 3.0" is printed
# as INFO only - T-054 owns any colour adjustment it might trigger.
# Prints "FOGCHECK OK (...)" and exits 0, or "FOGCHECK FAIL (...)" and exits 1.

const FogEnvScript := preload("res://view/fog_env.gd")

const BIOME_DIR := "res://content/biomes"
const D_PLANNING := 60.0   # section 12.3 rationale: ~6.7 s of running
const D_DODGE := 40.0      # the dodge horizon

static func _s2l(c: float) -> float:
	return c / 12.92 if c <= 0.04045 else pow((c + 0.055) / 1.055, 2.4)


static func _l2s(v: float) -> float:
	return 12.92 * v if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055


static func _lum(rgb: Array) -> float:
	return 0.2126 * _s2l(rgb[0] / 255.0) + 0.7152 * _s2l(rgb[1] / 255.0) + 0.0722 * _s2l(rgb[2] / 255.0)


static func _hex_rgb(h: String) -> Array:
	var t: String = h.trim_prefix("#")
	var v: int = t.hex_to_int()
	return [(v >> 16) & 255, (v >> 8) & 255, v & 255]


static func _contrast(a: Array, b: Array) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

## Fogged display colour (sRGB byte triple): the surface radiance is its linear colour times its
## stated emission TOTAL; an exponential depth fog render mixes radiances in linear space before
## the sRGB encode, hence
##   fogged = clamp( fog_lin + (colour_lin x factor - fog_lin) x visible(d) ) -> sRGB
## The fog participant of a row is the fog colour itself (fog-vs-fog fogging is the identity).
static func _fogged(hex: String, fog_hex: String, d: float, density: float, factor: float = 1.0) -> Array:
	var vis := exp(-density * d)
	var raw: Array = _hex_rgb(hex)
	var fog_raw: Array = _hex_rgb(fog_hex)
	var out: Array = []
	for i in range(3):
		var surf_lin := _s2l(raw[i] / 255.0) * factor
		var fog_lin := _s2l(fog_raw[i] / 255.0)
		var mix_lin := fog_lin + (surf_lin - fog_lin) * vis
		out.append(roundf(clampf(_l2s(minf(1.0, mix_lin)), 0.0, 1.0) * 255.0))
	return out

static func _row(name: String, a: Array, b: Array, threshold: float, failures: Array) -> void:
	var c := _contrast(a, b)
	var ok := c >= threshold
	print("FOGCHECK %s: %.3f (>= %.1f) %s" % [name, c, threshold, "OK" if ok else "FAIL"])
	if not ok:
		failures.append("%s %.3f < %.1f" % [name, c, threshold])


static func _check_biome(biome_id: String, global_failures: Array) -> int:
	var pal := FogEnvScript.resolve_palette(biome_id, 30)
	if pal.is_empty():
		global_failures.append("%s: palette resolution failed" % biome_id)
		return 0
	var R: Dictionary = pal["roles"]
	var dens: float = float(pal["fog_density"])
	var fog_hex: String = pal["fog"]
	print("FOGCHECK biome=%s fog=%s density=%.3f" % [biome_id, fog_hex, dens])
	var failures: Array = []
	# checker lights vs fog at the planning horizon
	_row("%s platform_light vs fog @60" % biome_id, _fogged(R["platform_light"]["hex"], fog_hex, D_PLANNING, dens, 1.0 + float(R["platform_light"].get("emission", 0.0))), _fogged(fog_hex, fog_hex, D_PLANNING, dens), 3.0, failures)
	_row("%s walkway_light vs fog @60" % biome_id, _fogged(R["walkway_light"]["hex"], fog_hex, D_PLANNING, dens, 1.0 + float(R["walkway_light"].get("emission", 0.0))), _fogged(fog_hex, fog_hex, D_PLANNING, dens), 3.0, failures)
	# the checker still reads at the dodge horizon
	_row("%s platform_light vs platform_dark @40 (both fogged)" % biome_id,
		_fogged(R["platform_light"]["hex"], fog_hex, D_DODGE, dens, 1.0 + float(R["platform_light"].get("emission", 0.0))),
		_fogged(R["platform_dark"]["hex"], fog_hex, D_DODGE, dens), 2.0, failures)
	# the tells: rim, gold, mine particles, open beacon
	_row("%s black_gift_rim vs fog @60" % biome_id, _fogged(R["black_gift_rim"]["hex"], fog_hex, D_PLANNING, dens, 1.0 + float(R["black_gift_rim"].get("emission", 0.0))), _fogged(fog_hex, fog_hex, D_PLANNING, dens), 4.5, failures)
	_row("%s gold_gift vs fog @60" % biome_id, _fogged(R["gold_gift"]["hex"], fog_hex, D_PLANNING, dens, 1.0 + float(R["gold_gift"].get("emission", 0.0))), _fogged(fog_hex, fog_hex, D_PLANNING, dens), 4.5, failures)
	_row("%s tripmine_particles vs fog @60" % biome_id, _fogged(R["tripmine_particles"]["hex"], fog_hex, D_PLANNING, dens, 2.0), _fogged(fog_hex, fog_hex, D_PLANNING, dens), 4.5, failures)
	_row("%s beacon_open vs fog @60" % biome_id, _fogged(R["beacon_open"]["hex"], fog_hex, D_PLANNING, dens, 1.0 + float(R["beacon_open"].get("emission", 0.0))), _fogged(fog_hex, fog_hex, D_PLANNING, dens), 4.5, failures)
	# DESIGN.md section 10 row: informational, T-054 owns any adjustment
	var info := _contrast(_fogged(R["tripmine_particles"]["hex"], fog_hex, D_DODGE, dens), _fogged(R["platform_light"]["hex"], fog_hex, D_DODGE, dens, 1.0 + float(R["platform_light"].get("emission", 0.0))))
	print("FOGCHECK INFO %s tripmine vs platform_light @40: %.3f (DESIGN section 10, target 3.0, T-054 owns)" % [biome_id, info])
	var checked := 7
	global_failures.append_array(failures)
	return checked

## Enemy sprites: every .png under res://content/enemies (T-016 will land them there next to
## enemy.json). Mean opaque colour per file (ENEMIES.md hard rule) vs fog @ 40 u.
static func _enemy_png_paths() -> Array:
	var out: Array = []
	var stack: Array = ["res://content/enemies"]
	while not stack.is_empty():
		var dirpath: String = stack.pop_back()
		var dir := DirAccess.open(dirpath)
		if dir == null:
			continue
		for f in dir.get_files():
			if (f as String).ends_with(".png"):
				out.append(dirpath + "/" + f)
		for dn in dir.get_directories():
			stack.append(dirpath + "/" + dn)
	return out


static func _biome_ids() -> Array:
	var out: Array = []
	var dir := DirAccess.open(BIOME_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if (f as String).ends_with(".json"):
			out.append((f as String).trim_suffix(".json"))
	(out as Array).sort()
	return out


static func _enemy_row(biome_id: String, failures: Array) -> int:
	var pal := FogEnvScript.resolve_palette(biome_id, 30)
	var fog_hex: String = pal["fog"]
	var dens: float = float(pal["fog_density"])
	var pngs := _enemy_png_paths()
	if pngs.is_empty():
		print("FOGCHECK INFO enemy PNGs: 0 found (pending T-016) - ENEMIES.md row vacuously OK")
		return 0
	var n := 0
	for path in pngs:
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img == null:
			failures.append("unreadable %s" % path)
			continue
		var rs := 0.0
		var gs := 0.0
		var bs := 0.0
		var cnt := 0
		for py in range(img.get_height()):
			for px in range(img.get_width()):
				var pxcol := img.get_pixel(px, py)
				if pxcol.a < 0.5:
					continue
				rs += pxcol.r8
				gs += pxcol.g8
				bs += pxcol.b8
				cnt += 1
		if cnt == 0:
			print("FOGCHECK INFO %s: fully transparent, row skipped" % path.get_file())
			continue
		var mean_hex := "#%02X%02X%02X" % [int(rs / cnt), int(gs / cnt), int(bs / cnt)]
		_row("%s enemy %s (%s) vs fog @40" % [biome_id, path.get_file(), mean_hex], [int(rs / cnt), int(gs / cnt), int(bs / cnt)], _fogged(fog_hex, fog_hex, D_DODGE, dens), 3.0, failures)
		n += 1
	return n


func _init() -> void:
	var ids: Array = OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = _biome_ids()
	var failures: Array = []
	var checked := 0
	for id in ids:
		checked += _check_biome(str(id), failures)
		checked += _enemy_row(str(id), failures)
	if failures.is_empty():
		print("FOGCHECK OK (%d checks over %d biomes)" % [checked, ids.size()])
		quit(0)
	else:
		print("FOGCHECK FAIL (%d checks over %d biomes, %d failed)" % [checked, ids.size(), failures.size()])
		for f in failures:
			print("FOGCHECK failed: %s" % f)
		quit(1)
