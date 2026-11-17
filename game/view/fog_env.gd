extends WorldEnvironment
#
# Fog / environment controller (ticket T-011; TERRAIN_SPEC.md section 12, DESIGN.md section 10).
#
# The world is a coloured atmosphere, never a skybox: background = the biome void colour,
# exponential depth fog at the biome density, ambient colour light, no sun, no directional
# shadows. Colours come from game/data/palette.json (the full Deepwater role set) overridden by
# game/content/biomes/<id>.json for the act roles platform/walkway light+dark, fog and void.
#
# Static helpers are the single source of the biome -> act -> palette mapping, so the mesher and
# tools can share it:
#   biome_id_for_level(level) -> String          (act table; 31+ cycles acts I..V, D-T014c-1)
#   resolve_palette(biome_id, level) -> Dictionary (merged roles + fog facts, see below)
#
# resolve_palette(biome_id) shape:
#   "roles": { role_name: { "hex": "#RRGGBB", "emission": float } }   (merged over the biome)
#   "fog": "#RRGGBB", "fog_density": float, "void": "#RRGGBB",
#   "ambient": "#RRGGBB", "ambient_energy": float

const CYCLE_DENSITY := 0.015  # levels 31+ keep the densest density, D-T014c-1

const PALETTE_PATH := "res://data/palette.json"
const BIOME_DIR := "res://content/biomes"
const RosterScript := preload("res://core/roster.gd")

var biome_id := ""  # "" = the act-I biome (resolved from content)
var level := 0


# ---- biome / palette resolution ---------------------------------------------------------------


## The biome ids in act order (DESIGN.md section 10), derived from the content tree:
## biomes sorted by their first level (core/roster.gd). No biome id is named here.
static func biome_order() -> Array[String]:
	return RosterScript.biome_order()


static func biome_id_for_level(level_: int) -> String:
	var order := biome_order()
	if order.is_empty():
		return ""
	if level_ <= 30:
		var act: int = clampi((level_ - 1) / 6, 0, order.size() - 1)
		return order[act]
	# 31+: acts cycle I..V again with the 31+ density pinned (D-T014c-1)
	return order[(level_ - 31) % order.size()]


static func load_palette() -> Dictionary:
	var text := FileAccess.get_file_as_string(PALETTE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("fog_env: cannot parse %s" % PALETTE_PATH)
		return {}
	return parsed


static func load_biome(biome_id: String) -> Dictionary:
	var path := "%s/%s.json" % [BIOME_DIR, biome_id]
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("fog_env: cannot parse %s" % path)
		return {}
	return parsed


## Merged palette for one biome. Every role becomes { "hex": String, "emission": float }.
## Emission factors follow the section 12.2 notes (0.35 x albedo on checker lights, x1.5/x2.0/x4.0
## where stated); roles with no stated emission use 0.0.
static func resolve_palette(biome_id: String, level: int = -1) -> Dictionary:
	var pal := load_palette()
	if pal.is_empty():
		return {}
	var roles: Dictionary = {}
	for role_name in pal["roles"]:
		var entry: Dictionary = pal["roles"][role_name]
		roles[role_name] = {
			"hex": entry["hex"],
			"emission": float(entry.get("emission", 0.0)),
		}
		for extra in ["sigil_hex", "trim_hex"]:
			if entry.has(extra):
				roles[role_name][extra] = entry[extra]
	var fog: Dictionary = pal["fog"]
	var fog_density: float = float(fog["density"])
	var fog_hex: String = fog["color"]
	var void_hex: String = pal["void_clear"]
	if biome_id != "":
		var biome := load_biome(biome_id)
		if not biome.is_empty():
			for role_name in biome["palette"]:
				var hex: String = biome["palette"][role_name]
				if roles.has(role_name):
					roles[role_name]["hex"] = hex
				else:
					roles[role_name] = { "hex": hex, "emission": 0.0 }
			fog_hex = biome["palette"]["fog"]
			void_hex = biome["palette"]["void"]
			if level < 31:
				fog_density = float(biome["fog_density"])
	if level >= 31:
		fog_density = CYCLE_DENSITY  # D-T014c-1
	var ambient: Dictionary = roles["ambient"]
	return {
		"roles": roles,
		"fog": fog_hex,
		"fog_density": fog_density,
		"void": void_hex,
		"ambient": ambient["hex"],
		"ambient_energy": float(ambient.get("energy", 1.0)),
	}


# ---- WorldEnvironment node -------------------------------------------------------------------


func configure(biome_id_: String, level_: int = 0) -> void:
	if biome_id_ == "":
		biome_id_ = biome_id_for_level(max(level_, 1))
	biome_id = biome_id_
	level = level_
	var pal := resolve_palette(biome_id, level)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(pal["void"])
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(pal["ambient"])
	env.ambient_light_energy = pal["ambient_energy"]
	env.ambient_light_sky_contribution = 0.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(pal["fog"])
	env.fog_density = pal["fog_density"]
	env.fog_aerial_perspective = 0.0
	environment = env


func _ready() -> void:
	if environment == null:
		configure(biome_id, level)