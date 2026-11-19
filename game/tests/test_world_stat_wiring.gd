extends RefCounted
#
# test_world_stat_wiring.gd: every stat consumer is CALLED by the shipped game.
#
# out/review_alpha.md finding 2: the consumers (mines / gifts / enemy runtime / intermission /
# fog / fill lights / Field Dressing) were each green in their own unit test while nothing in
# the shipped path called them. This test never calls a consumer itself. It builds the real
# world (app/world.gd build()) twice from carried ledgers - one owning nothing, one owning the
# upgrades and curses below - and asserts that each stat's number differs between the two,
# read back from the live objects world.build() / step() made. The shop price goes one step
# further: the lobby is built (view/lobby/lobby_scene.gd build()) from world.run_ledger().
#
#   defuse_chance     lstate.mines.defuse_chance            (Defuse Kit)
#   pickup_radius     lstate.gifts.pickup_radius()          (Long Reach)
#   enemy_speed_mul   rt.curse_speed_mul                    (Rush Hour)
#   telegraph_mul     rt.telegraph_mul                      (Early Warning)
#   fog_density       fog.environment.fog_density           (Thick Fog)
#   fill_light_range  the world's player light + the lobby's two fill lights (Lights Out)
#   shop_price_mul    the lobby's U / REST altar prices     (Inflation)
#   field_dressing    a real void fall through step(): no charge spent, the pip flashes
#
# Also pins the gold-phase edge: _apply_phase_stats() re-feeds the same consumers, so a stat
# survives the phase flip rather than snapping back to the canon base.

const WorldScript := preload("res://app/world.gd")
const LobbySceneScript := preload("res://view/lobby/lobby_scene.gd")

const SEED := 1
const LEVEL := 2
const DT := 1.0 / 60.0
const SHOP_LOBBY := 1   # data/offering_schedule.json: lobby 1 lights a U bay

const OWNED_STACKS := {"defuse_kit": 1, "long_reach": 1, "early_warning": 1,
		"field_dressing": 1}
const HELD_CURSES := {"rush_hour": 1, "thick_fog": 1, "lights_out": 1, "inflation": 1}


func _ledger(p_stacks: Dictionary, p_curses: Dictionary) -> Dictionary:
	return {"class": "", "votes": {}, "curses": p_curses.duplicate(),
			"stacks": p_stacks.duplicate(), "purse": 500, "tithes": 0, "hunger": 0,
			"last_vote": ""}


func run() -> Array[String]:
	var f: Array[String] = []
	var base = WorldScript.new()
	var cursed = WorldScript.new()
	if not base.build(SEED, LEVEL, _ledger({}, {})):
		f.append("setup: base world failed to build")
	if not cursed.build(SEED, LEVEL, _ledger(OWNED_STACKS, HELD_CURSES)):
		f.append("setup: stat world failed to build")
	if f.is_empty():
		_leg_sim_stats(f, base, cursed)
		_leg_view_stats(f, base, cursed)
		_leg_gold_edge(f, cursed)
		_leg_shop(f, base, cursed)
		_leg_field_dressing(f, base, cursed)
	base.teardown()
	cursed.teardown()
	base.free()
	cursed.free()
	return f


func _differs(f: Array[String], what: String, a: float, b: float, want_bigger: bool) -> void:
	var ok := b > a + 1e-6 if want_bigger else b < a - 1e-6
	if not ok:
		f.append("%s: base %.4f -> owned %.4f (expected %s)" % [what, a, b,
				"bigger" if want_bigger else "smaller"])


# ---- the sim consumers, read back from the objects build() made ---------------------------

func _leg_sim_stats(f: Array[String], base, cursed) -> void:
	_differs(f, "defuse_chance (lstate.mines)", maxf(0.0, float(base.lstate.mines.defuse_chance)),
			float(cursed.lstate.mines.defuse_chance), true)
	_differs(f, "pickup_radius (lstate.gifts)", float(base.lstate.gifts.pickup_radius()),
			float(cursed.lstate.gifts.pickup_radius()), true)
	_differs(f, "enemy_speed_mul (rt.curse_speed_mul)", float(base.rt.curse_speed_mul),
			float(cursed.rt.curse_speed_mul), true)
	_differs(f, "telegraph_mul (rt.telegraph_mul)", float(base.rt.telegraph_mul),
			float(cursed.rt.telegraph_mul), true)


# ---- the view consumers ---------------------------------------------------------------------

func _leg_view_stats(f: Array[String], base, cursed) -> void:
	if base.fog == null or cursed.fog == null or base.fog.environment == null \
			or cursed.fog.environment == null:
		f.append("fog_density: world built no fog environment")
	else:
		_differs(f, "fog_density (fog.environment)", float(base.fog.environment.fog_density),
				float(cursed.fog.environment.fog_density), true)
	if base._player_light == null or cursed._player_light == null:
		f.append("fill_light_range: world built no player light")
	else:
		_differs(f, "fill_light_range (world player light)",
				float(base._player_light.omni_range), float(cursed._player_light.omni_range),
				false)


# ---- the gold-phase edge re-feeds the same consumers ---------------------------------------

func _leg_gold_edge(f: Array[String], cursed) -> void:
	var tm := float(cursed.rt.telegraph_mul)
	var dc := float(cursed.lstate.mines.defuse_chance)
	cursed.rt.telegraph_mul = 1.0
	cursed.lstate.mines.defuse_chance = 0.0
	if cursed._economy == null:
		f.append("gold edge: world built no economy")
		return
	cursed._economy.gold_phase = true
	cursed._apply_phase_stats()
	if not is_equal_approx(float(cursed.rt.telegraph_mul), tm):
		f.append("gold edge: rt.telegraph_mul %.4f, expected %.4f (not re-fed)"
				% [float(cursed.rt.telegraph_mul), tm])
	if not is_equal_approx(float(cursed.lstate.mines.defuse_chance), dc):
		f.append("gold edge: mines.defuse_chance %.4f, expected %.4f (not re-fed)"
				% [float(cursed.lstate.mines.defuse_chance), dc])
	cursed._economy.gold_phase = false
	cursed._apply_phase_stats()


# ---- shop_price_mul + the lobby's fill lights, through world.run_ledger() -> lobby build() --

func _shop_total(scene) -> int:
	var total := 0
	for bay in scene.lobby.bays:
		var kind := str(bay.get("kind", ""))
		if kind != "U" and kind != "REST":
			continue
		for altar in (bay.get("altars", []) as Array):
			total += int(altar.get("price", 0))
	return total


func _leg_shop(f: Array[String], base, cursed) -> void:
	# Same ledger in both lobbies except the world-computed stats: the draw is identical,
	# so a price difference can only come from the stats the world handed over.
	var plain: Dictionary = base.run_ledger()
	var priced: Dictionary = plain.duplicate(true)
	var cstats: Variant = cursed.run_ledger().get("stats", null)
	if not (cstats is Dictionary):
		f.append("shop_price_mul: world.run_ledger() carries no stats dict")
		return
	priced["stats"] = (cstats as Dictionary).duplicate()
	var a = LobbySceneScript.new()
	var b = LobbySceneScript.new()
	if not a.build(SEED, SHOP_LOBBY, plain) or not b.build(SEED, SHOP_LOBBY, priced):
		f.append("shop_price_mul: lobby failed to build")
	else:
		var pa := _shop_total(a)
		var pb := _shop_total(b)
		if pa <= 0:
			f.append("shop_price_mul: lobby %d has no priced U / REST altar to compare" % SHOP_LOBBY)
		else:
			_differs(f, "shop_price_mul (lobby altar prices)", float(pa), float(pb), true)
		_differs(f, "fill_light_range (lobby hall light)", float(a.hall.fill_light.omni_range),
				float(b.hall.fill_light.omni_range), false)
		_differs(f, "fill_light_range (lobby player light)", float(a.player._fill.omni_range),
				float(b.player._fill.omni_range), false)
	a.free()
	b.free()


# ---- Field Dressing: a real void fall through world.step() ----------------------------------

## Drops the player under the kill plane and steps the world until the controller starts
## its respawn. Returns the charges held before the fall (-1 when the fall never happened).
func _fall_once(world) -> int:
	var before := int(world.ctl.charges)
	world.ctl.y = float(world.ctl.C["kill_plane_y"]) - 5.0
	world.ctl.vy = -10.0
	world.ctl.grounded = false
	world.ctl.invuln = 0.0
	for i in 5:
		world.step(DT)
		if float(world.ctl.respawn_t) >= 0.0:
			return before
	return -1


func _leg_field_dressing(f: Array[String], base, cursed) -> void:
	if int(base.ctl.field_dressing_uses) != 0:
		f.append("field_dressing: base world grants %d free falls, expected 0"
				% int(base.ctl.field_dressing_uses))
	if int(cursed.ctl.field_dressing_uses) != 1:
		f.append("field_dressing: world.build() granted %d free falls, expected 1 (one stack)"
				% int(cursed.ctl.field_dressing_uses))
	var b0 := _fall_once(base)
	var c0 := _fall_once(cursed)
	if b0 < 0 or c0 < 0:
		f.append("field_dressing: the void fall never happened (base %d, owned %d)" % [b0, c0])
		return
	if int(base.ctl.charges) != b0 - 1:
		f.append("field_dressing: control fall cost %d charges, expected 1"
				% (b0 - int(base.ctl.charges)))
	if int(cursed.ctl.charges) != c0:
		f.append("field_dressing: the owned fall cost %d charges, expected 0 (free)"
				% (c0 - int(cursed.ctl.charges)))
	if float(base.hud.void_pips._free_t) >= 0.0:
		f.append("field_dressing: the paid fall flashed the FREE pip")
	if float(cursed.hud.void_pips._free_t) < 0.0:
		f.append("field_dressing: the free fall never reached void_pips.pip_free_fall()")
