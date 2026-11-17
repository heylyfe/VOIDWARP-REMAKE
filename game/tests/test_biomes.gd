extends RefCounted
#
# Act -> biome wiring (ticket T-054; DESIGN.md section 10 + TERRAIN_SPEC section 12).
# Pins, headlessly:
#   1. biome_id_for_level maps every act boundary level to DESIGN.md section 10's biome and
#      cycles acts I..V for levels 31+ (density pinned at 0.015, D-T014c-1);
#   2. BIOME_ORDER is acts I..V;
#   3. resolve_palette returns each biome file's palette roles (platform/walkway/fog/void) and
#      fog density VERBATIM - the DESIGN.md section 10 table as shipped in content/biomes/*.json;
#      deepwater's walkway_light is #3A74FF per D-T011-6 (the spec's #2A5BFF failed its own
#      section 12.3 check and was raised by the orchestrator, not by this ticket);
#   4. the 31+ fog density override (D-T014c-1) and the deepwater density path;
#   5. the merged palettes still resolve with every role fog_check.gd needs (non-empty roles).
#
# Failures are strings in run()'s return array (run_all convention).

const FogEnvScript := preload("res://view/fog_env.gd")

## The DESIGN.md section 10 table as data (hexes verbatim; deepwater walkway excepted, D-T011-6).
const DESIGN_BIOMES: Dictionary = {
	"deepwater":     {"act": "I",   "levels": [1, 6],   "fog_density": 0.012, "platform_light": "#2FB7B0", "platform_dark": "#0A2E30", "walkway_light": "#3A74FF", "walkway_dark": "#0B1A66", "fog": "#021416", "void": "#010B0C"},
	"verdigris":     {"act": "II",  "levels": [7, 12],  "fog_density": 0.012, "platform_light": "#5E9E6A", "platform_dark": "#0E2A14", "walkway_light": "#B45CFF", "walkway_dark": "#2E0F52", "fog": "#04140A", "void": "#020A05"},
	"violet_hour":   {"act": "III", "levels": [13, 18], "fog_density": 0.013, "platform_light": "#C13CFF", "platform_dark": "#2A0A3A", "walkway_light": "#FF3C7A", "walkway_dark": "#4A0A22", "fog": "#12021A", "void": "#0A0110"},
	"indigo_trench": {"act": "IV",  "levels": [19, 24], "fog_density": 0.014, "platform_light": "#4C6BFF", "platform_dark": "#0A1040", "walkway_light": "#2FE0D0", "walkway_dark": "#06332F", "fog": "#03061C", "void": "#02030F"},
	"pale_abyss":    {"act": "V",   "levels": [25, 30], "fog_density": 0.015, "platform_light": "#B8C7CC", "platform_dark": "#1E2A2E", "walkway_light": "#6FA8FF", "walkway_dark": "#14284A", "fog": "#0A1114", "void": "#05090B"},
}


func run() -> Array[String]:
	var failures: Array[String] = []
	_check_level_table(failures)
	_check_biome_order(failures)
	_check_biome_files(failures)
	_check_resolve_palette(failures)
	_check_cycle_density(failures)
	return failures


func _check_level_table(failures: Array[String]) -> void:
	var expected := {1: "deepwater", 6: "deepwater", 7: "verdigris", 12: "verdigris", 13: "violet_hour", 18: "violet_hour", 19: "indigo_trench", 24: "indigo_trench", 25: "pale_abyss", 30: "pale_abyss"}
	for level in expected:
		var got := FogEnvScript.biome_id_for_level(int(level))
		if got != str(expected[level]):
			failures.append("biome_id_for_level(%d) = %s, want %s" % [int(level), got, str(expected[level])])
	# 31+ cycles acts I..V in order (D-T014c-1)
	var cycle := ["deepwater", "verdigris", "violet_hour", "indigo_trench", "pale_abyss"]
	for i in 10:
		var level := 31 + i
		var got := FogEnvScript.biome_id_for_level(level)
		if got != cycle[i % 5]:
			failures.append("biome_id_for_level(%d) = %s, want %s (31+ cycle)" % [level, got, cycle[i % 5]])


func _check_biome_order(failures: Array[String]) -> void:
	var order := FogEnvScript.BIOME_ORDER
	var want := ["deepwater", "verdigris", "violet_hour", "indigo_trench", "pale_abyss"]
	if order != want:
		failures.append("BIOME_ORDER = %s, want %s" % [str(order), str(want)])


func _check_biome_files(failures: Array[String]) -> void:
	for id in DESIGN_BIOMES:
		var path := "res://content/biomes/%s.json" % id
		var text := FileAccess.get_file_as_string(path)
		if text == "":
			failures.append("cannot read %s" % path)
			continue
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			failures.append("%s does not parse to a dictionary" % path)
			continue
		var b: Dictionary = parsed
		var spec: Dictionary = DESIGN_BIOMES[id]
		if str(b.get("act", "")) != str(spec["act"]):
			failures.append("%s act = %s, want %s" % [id, str(b.get("act")), str(spec["act"])])
		var levels: Array = b.get("levels", [])
		var levels_ok := levels.size() == 2
		if levels_ok:
			levels_ok = int(levels[0]) == int(spec["levels"][0]) and int(levels[1]) == int(spec["levels"][1])
		if not levels_ok:
			failures.append("%s levels = %s, want %s" % [id, str(levels), str(spec["levels"])])
		if absf(float(b.get("fog_density", -1.0)) - float(spec["fog_density"])) > 0.0001:
			failures.append("%s fog_density = %s, want %s" % [id, str(b.get("fog_density")), str(spec["fog_density"])])
		var pal: Dictionary = b.get("palette", {})
		for role in ["platform_light", "platform_dark", "walkway_light", "walkway_dark", "fog", "void"]:
			if str(pal.get(role, "")).to_upper() != str(spec[role]).to_upper():
				failures.append("%s palette.%s = %s, want %s (DESIGN.md section 10)" % [id, role, str(pal.get(role)), str(spec[role])])


func _check_resolve_palette(failures: Array[String]) -> void:
	for id in DESIGN_BIOMES:
		var spec: Dictionary = DESIGN_BIOMES[id]
		var level := int(spec["levels"][0])
		var pal := FogEnvScript.resolve_palette(id, level)
		if pal.is_empty():
			failures.append("resolve_palette(%s, %d) returned {}" % [id, level])
			continue
		var roles: Dictionary = pal.get("roles", {})
		for role in ["platform_light", "platform_dark", "walkway_light", "walkway_dark"]:
			var got := str(roles.get(role, {}).get("hex", "")).to_upper()
			if got != str(spec[role]).to_upper():
				failures.append("resolve_palette(%s) roles.%s = %s, want %s" % [id, role, got, str(spec[role])])
		if str(pal.get("fog", "")).to_upper() != str(spec["fog"]).to_upper():
			failures.append("resolve_palette(%s) fog = %s, want %s" % [id, str(pal.get("fog")), str(spec["fog"])])
		if str(pal.get("void", "")).to_upper() != str(spec["void"]).to_upper():
			failures.append("resolve_palette(%s) void = %s, want %s" % [id, str(pal.get("void")), str(spec["void"])])
		if absf(float(pal.get("fog_density", -1.0)) - float(spec["fog_density"])) > 0.0001:
			failures.append("resolve_palette(%s) fog_density = %s, want %s" % [id, str(pal.get("fog_density")), str(spec["fog_density"])])
		# fog_check.gd depends on every one of these roles being present and well-formed
		for required in ["platform_light", "platform_dark", "walkway_light", "walkway_dark", "dead_end_light", "slab_side", "slab_trim", "ambient", "black_gift_rim", "gold_gift", "tripmine_particles", "beacon_open"]:
			if not roles.has(required):
				failures.append("resolve_palette(%s) is missing role %s" % [id, required])
			elif str(roles[required].get("hex", "")).length() != 7:
				failures.append("resolve_palette(%s) role %s hex = %s, want #RRGGBB" % [id, required, str(roles[required].get("hex"))])


func _check_cycle_density(failures: Array[String]) -> void:
	# 31+ keeps the pinned 0.015 density for every cycled act (D-T014c-1), whatever the act.
	for id in DESIGN_BIOMES:
		var pal := FogEnvScript.resolve_palette(id, 33)
		if absf(float(pal.get("fog_density", -1.0)) - FogEnvScript.CYCLE_DENSITY) > 0.0001:
			failures.append("resolve_palette(%s, 33) fog_density = %s, want %.3f (31+ cycle, D-T014c-1)" % [id, str(pal.get("fog_density")), FogEnvScript.CYCLE_DENSITY])
	# level 31 (act I again) and 60 (act V) both take the CYCLE density, not the act's own
	if absf(float(FogEnvScript.resolve_palette("deepwater", 31).get("fog_density", -1.0)) - FogEnvScript.CYCLE_DENSITY) > 0.0001:
		failures.append("resolve_palette(deepwater, 31) fog_density != %.3f" % FogEnvScript.CYCLE_DENSITY)
	if absf(float(FogEnvScript.resolve_palette("pale_abyss", 60).get("fog_density", -1.0)) - FogEnvScript.CYCLE_DENSITY) > 0.0001:
		failures.append("resolve_palette(pale_abyss, 60) fog_density != %.3f" % FogEnvScript.CYCLE_DENSITY)


