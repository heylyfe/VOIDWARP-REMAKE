# Gap 27: the two stats the world computes but nothing consumed now have view consumers.
#   thick_fog  fog_density       0.012 -> 0.018 (one stack) -> 0.024 (two stacks)
#   lights_out fill_light_range  18 -> 11 (op set)
# The stats dict the world computes (core/content_api.gd apply_modifiers over the
# controller base, where absent stats start from StatsScript.DEFAULTS) is fed straight
# into the view setters; the view never sees a literal.
# fog_check.gd is untouched: it checks the BIOME palette through resolve_palette(),
# which these setters do not modify - the curse rides on the Environment node instead.
#
# Run: tools/godot/godot.exe --headless --path game --script res://out/one.gd -- res://tests/test_curse_view_stats.gd

extends RefCounted

const FogEnvScript := preload("res://view/fog_env.gd")
const LobbyPlayerScript := preload("res://view/lobby/lobby_player.gd")
const AntechamberScript := preload("res://view/lobby/antechamber.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const StatsScript := preload("res://core/stats.gd")

const FOG_EPS := 0.0001


func run() -> Array[String]:
	var failures: Array[String] = []
	_check_fog(failures)
	_check_fill_light(failures)
	_check_end_to_end(failures)
	return failures


func _check_fog(failures: Array[String]) -> void:
	var biome := FogEnvScript.biome_id_for_level(1)
	var fog := FogEnvScript.new()
	fog.configure(biome, 1)
	var base := float(fog.environment.fog_density)
	var stat_base := float(StatsScript.DEFAULTS["fog_density"])
	# identical stats: no change
	fog.apply_stats({"fog_density": stat_base})
	_check(failures, absf(float(fog.environment.fog_density) - base) < FOG_EPS,
		"fog_density identical to default must leave the biome fog alone (got %.4f, base %.4f)" % [fog.environment.fog_density, base])
	# one thick_fog stack: +0.006 over the biome base, never an absolute overwrite
	fog.apply_stats({"fog_density": stat_base + 0.006})
	_check(failures, absf(float(fog.environment.fog_density) - (base + 0.006)) < FOG_EPS,
		"one thick_fog stack must add 0.006 over the biome fog base (got %.4f, want %.4f)" % [fog.environment.fog_density, base + 0.006])
	# two stacks (max): +0.012
	fog.apply_stats({"fog_density": stat_base + 0.012})
	_check(failures, absf(float(fog.environment.fog_density) - (base + 0.012)) < FOG_EPS,
		"two thick_fog stacks must add 0.012 over the biome fog base (got %.4f, want %.4f)" % [fog.environment.fog_density, base + 0.012])
	# re-applying with the identity stats removes the delta again (no accumulation)
	fog.apply_stats({"fog_density": stat_base})
	_check(failures, absf(float(fog.environment.fog_density) - base) < FOG_EPS,
		"re-applying the default stats must drop the curse delta (got %.4f, base %.4f)" % [fog.environment.fog_density, base])
	# empty stats dict: untouched
	var fog2 := FogEnvScript.new()
	fog2.configure(biome, 1)
	var base2 := float(fog2.environment.fog_density)
	fog2.apply_stats({})
	_check(failures, absf(float(fog2.environment.fog_density) - base2) < FOG_EPS,
		"empty stats dict must leave the fog alone (got %.4f, base %.4f)" % [fog2.environment.fog_density, base2])
	fog.free()
	fog2.free()

func _check_fill_light(failures: Array[String]) -> void:
	var player := LobbyPlayerScript.new()
	player.build(Vector3.ZERO)
	if not _check(failures, player._fill != null, "lobby player build() created no fill light"):
		player.free()
		return
	var default_range := float(player._fill.omni_range)
	# empty stats dict: untouched
	player.apply_stats({})
	_check(failures, absf(float(player._fill.omni_range) - default_range) < FOG_EPS,
		"empty stats dict must leave the fill light alone (got %.2f, base %.2f)" % [player._fill.omni_range, default_range])
	# lights_out (op set): absolute 11, exactly the modified stat
	player.apply_stats({"fill_light_range": 11.0})
	_check(failures, absf(float(player._fill.omni_range) - 11.0) < FOG_EPS,
		"lights_out must set the fill light range to the stat (got %.2f, want 11.0)" % player._fill.omni_range)
	player.free()
	# the antechamber hall carries the same palette role on its spawn fill light;
	# the setter exists and is a safe no-op before _lights() built the light
	var hall := AntechamberScript.new()
	hall.apply_stats({"fill_light_range": 11.0})
	hall.free()


func _check_end_to_end(failures: Array[String]) -> void:
	var api: RefCounted = ContentApiScript.load()
	if not _check(failures, bool(api.call("is_ok")),
			"content api boot failed: %s" % " / ".join(api.call("boot_errors"))):
		return
	# the real modifier path, the same call shape world.gd makes (base {} -> DEFAULTS)
	var lights_out: Dictionary = api.call("curse", "lights_out")
	var thick_fog: Dictionary = api.call("curse", "thick_fog")
	var lo_stats: Dictionary = ContentApiScript.apply_modifiers({},
		ContentApiScript.mods_for_stacks(lights_out.get("modifiers", []), 1), {})
	var fog1: Dictionary = ContentApiScript.apply_modifiers({},
		ContentApiScript.mods_for_stacks(thick_fog.get("modifiers", []), 1), {})
	var fog2: Dictionary = ContentApiScript.apply_modifiers({},
		ContentApiScript.mods_for_stacks(thick_fog.get("modifiers", []), 2), {})
	# the stats dicts must carry the two stats at all (they were "computed and dropped")
	_check(failures, lo_stats.has("fill_light_range"),
		"apply_modifiers dropped fill_light_range (lights_out) - the world computes it, the view never sees it")
	_check(failures, fog1.has("fog_density") and fog2.has("fog_density"),
		"apply_modifiers dropped fog_density (thick_fog) - the world computes it, the view never sees it")
	# feed the computed stats into the view consumers, exactly the wiring world.gd owes
	var biome := FogEnvScript.biome_id_for_level(1)
	var env := FogEnvScript.new()
	env.configure(biome, 1)
	var base := float(env.environment.fog_density)
	env.apply_stats(fog2)
	_check(failures, absf(float(env.environment.fog_density) - (base + 0.012)) < FOG_EPS,
		"two thick_fog stacks through the real modifier path must add 0.012 (got %.4f, base %.4f)" % [env.environment.fog_density, base])
	env.free()
	var player := LobbyPlayerScript.new()
	player.build(Vector3.ZERO)
	player.apply_stats(lo_stats)
	_check(failures, absf(float(player._fill.omni_range) - float(lo_stats["fill_light_range"])) < FOG_EPS,
		"lights_out through the real modifier path must set the fill range to %.2f (got %.2f)" % [lo_stats["fill_light_range"], player._fill.omni_range])
	player.free()


func _check(failures: Array[String], ok: bool, msg: String) -> bool:
	if not ok:
		failures.append(msg)
	return ok