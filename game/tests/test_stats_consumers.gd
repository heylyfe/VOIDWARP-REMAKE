# The two dropped stats test (ticket-less follow-up to the modifiers task):
#   - defuse_chance (upgrade defuse_kit) is consumed by sim/mines.gd's defuse roll;
#   - pickup_radius  (upgrade long_reach) is consumed by sim/gifts.gd's pickup ring.
#
# The stats dict is the one world.gd computes at build through
# core/content_api.gd's apply_modifiers() over the owned upgrade stacks (and held
# curses). The dict is built HERE the same way world.gd builds it - a real
# controller's base_stats() as `base`, sorted owned-id modifier lists - but the
# consumers are driven directly through their apply_stats() setters, exactly the
# seam the app uses. This file does NOT touch world.gd; the one-line wiring the
# lead still has to add there is reported alongside.
#
# Per stat, two halves: WITH the upgrade owned the behaviour changes (the stat
# decides the outcome where the bare stacks path would not), and WITHOUT it the
# canon base holds (0.4 u ring; no defuse at 0.0).

const MinesScript := preload("res://sim/mines.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const LevelStateScript := preload("res://sim/level_state.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const ControllerScript := preload("res://sim/controller.gd")

const TEST_LEVEL := 7


func run() -> Array[String]:
	var f: Array[String] = []
	_test_defuse_chance(f)
	_test_pickup_radius(f)
	return f


# ---- fixtures (the test_mines.gd / test_gifts.gd contracts, re-used) ------------

## A Level dict with a mixed slot table: occs[i] == 1 -> mine slot; else a real
## gift slot. Slot id i sits at world x = i * 10 + 0.5, z = 0.5, y = 0.
static func _level(occs: Array) -> Dictionary:
	var slots: Array = []
	for i in occs.size():
		slots.append({"id": i, "x": i * 10, "z": 0, "y": 0, "piece": 0, "tier": 0, "occ": occs[i]})
	return {"gifts": slots}


static func _ctl_at(height: float = 0.0) -> RefCounted:
	var ctl = ControllerScript.new()
	ctl.setup("dasher", ControllerScript.load_constants())
	ctl.x = 0.5
	ctl.y = height
	ctl.z = 0.5
	return ctl


## The minimal sim-context holder MinesScript.tick reads.
static func _holder(m: RefCounted, ctls: Array) -> Dictionary:
	var players: Array = []
	for c in ctls:
		players.append({"x": float(c.x), "y": float(c.y), "z": float(c.z)})
	return {"mines": m, "players": players, "beacon": null}


## One mine-tick pass over a fresh mine at slot 0; returns [consumed, dead, events].
## stacks is always [0]: only the stats dict can defuse on this path.
static func _resolve(seed: int, stats: Dictionary) -> Array:
	var m: RefCounted = MinesScript.create(_level([1]), TEST_LEVEL, seed)
	if not stats.is_empty():
		m.apply_stats(stats)
	var ctl := _ctl_at(0.0)
	ctl.last_light_spent = true          # D-057: a kill assertion is only valid when
	ctl.charges = 0                      # the save cannot fire
	var ev: Array = []
	MinesScript.tick(_holder(m, [ctl]), [ctl], {"dais": [0, 0, 1], "enemies": []},
			[0], 7, ev)
	return [m.is_consumed(0), bool(ctl.dead), ev]


## The stats dict world.gd computes at build for the given owned upgrades and held
## curses: a real controller's base_stats() as `base`, the owned ids' modifiers
## repeated per stack, sorted - the exact _run_modifiers() + apply_modifiers() pair.
static func _stats_for(stacks: Dictionary, curses: Dictionary) -> Dictionary:
	var api: RefCounted = ContentApiScript.load()
	var ctl = ControllerScript.new()
	ctl.setup("dasher", ControllerScript.load_constants())
	var mods: Array = []
	var curse_ids: Array = curses.keys()
	curse_ids.sort()
	for id in curse_ids:
		mods.append_array(ContentApiScript.mods_for_stacks(
				api.curse(str(id)).get("modifiers", []), int(curses[id])))
	var upgrade_ids: Array = stacks.keys()
	upgrade_ids.sort()
	for id in upgrade_ids:
		mods.append_array(ContentApiScript.mods_for_stacks(
				api.upgrade(str(id)).get("modifiers", []), int(stacks[id])))
	return ContentApiScript.apply_modifiers(ctl.base_stats(), mods,
			{"phase": "", "class": "dasher"})


static func _kind(ev: Array, k: String) -> int:
	var n := 0
	for e in ev:
		if str(e.get("e", e.get("type", ""))) == k:
			n += 1
	return n


static func _check(f: Array[String], ok: bool, msg: String) -> bool:
	if not ok:
		f.append(msg)
	return ok

# ---- defuse_chance: the mines consumer ----------------------------------------

func _test_defuse_chance(f: Array[String]) -> void:
	# the base dict (no upgrades, no curses) carries no defuse_chance at all
	var base_stats := _stats_for({}, {})
	_check(f, not base_stats.has("defuse_chance"),
			"defuse_chance: the base stats dict unexpectedly carries the stat")
	# ... and with the Defuse Kit owned the stat is there, +0.2 per stack
	var kit1 := _stats_for({"defuse_kit": 1}, {})
	var kit3 := _stats_for({"defuse_kit": 3}, {})
	_check(f, absf(float(kit1.get("defuse_chance", -1.0)) - 0.2) <= 1e-9,
			"defuse_kit x1: the stats dict carries defuse_chance %s, want 0.2" % str(kit1.get("defuse_chance")))
	_check(f, absf(float(kit3.get("defuse_chance", -1.0)) - 0.6) <= 1e-9,
			"defuse_kit x3: the stats dict carries defuse_chance %s, want 0.6" % str(kit3.get("defuse_chance")))

	# the roll itself agrees with the stack roll it replaces (0.2 == 1 stack, etc.)
	var agree := true
	for k in range(2000):
		var s: int = 1000 + k
		if MinesScript.defuse_roll_chance(s, TEST_LEVEL, 2, 0.2) != MinesScript.defuse_roll(s, TEST_LEVEL, 2, 1):
			agree = false
		if MinesScript.defuse_roll_chance(s, TEST_LEVEL, 2, 0.4) != MinesScript.defuse_roll(s, TEST_LEVEL, 2, 2):
			agree = false
		if MinesScript.defuse_roll_chance(s, TEST_LEVEL, 2, 0.6) != MinesScript.defuse_roll(s, TEST_LEVEL, 2, 3):
			agree = false
	_check(f, agree, "defuse_chance: the probability roll disagrees with the stack roll")
	_check(f, not MinesScript.defuse_roll_chance(1234, TEST_LEVEL, 0, 0.0),
			"defuse_chance: a 0.0 chance passed the roll")
	_check(f, MinesScript.defuse_roll_chance(1234, TEST_LEVEL, 0, 1.0),
			"defuse_chance: a 1.0 chance failed the roll")

	# BASE BEHAVIOUR HOLDS: no stats applied, the bare stacks path at 0 stacks
	# defuses never (world passes [0] until the lead wires apply_stats).
	var bare_defused := 0
	for seed in range(100):
		var r := _resolve(seed, {})
		if _kind(r[2], "mine_defused") == 1:
			bare_defused += 1
	_check(f, bare_defused == 0,
			"defuse_chance: the unwired stacks path defused %d times at 0 stacks, want 0" % bare_defused)

	# ... and a stats dict WITHOUT the stat behaves the same (0.0 = no defuse)
	var zero := _resolve(1234, {"run_speed": 1.0})
	_check(f, _kind(zero[2], "mine_defused") == 0 and bool(zero[1]),
			"defuse_chance: a dict without the stat defused, want the 0.0 base behaviour")

	# WITH THE UPGRADE OWNED THE BEHAVIOUR CHANGES: the stat decides, stacks [0]
	# is passed, so any defuse comes from the long/short odds the stat carries.
	var hit := 0
	var total := 0
	for seed in range(300):
		for slot in range(10):
			total += 1
			if MinesScript.defuse_roll_chance(seed, TEST_LEVEL, slot, 0.2):
				hit += 1
	var rate := float(hit) / float(total)
	_check(f, absf(rate - 0.2) <= 0.02,
			"defuse_kit x1: the observed rate is %.4f, want 0.20 +/-0.02 (%d/%d)" % [rate, hit, total])

	# the full ladder through tick() with the stat live and stacks [0]:
	# seeds whose 0.2 roll passes must defuse; the rest must die (D-057).
	var stats_defused := 0
	for seed in range(200):
		var r := _resolve(seed, kit1)
		var want_defuse := MinesScript.defuse_roll_chance(seed, TEST_LEVEL, 0, 0.2)
		var got_defuse := _kind(r[2], "mine_defused") == 1
		if got_defuse != want_defuse:
			f.append("defuse_chance: seed %d resolved to defuse=%s, the stat roll says %s"
					% [seed, str(got_defuse), str(want_defuse)])
			break
		if got_defuse:
			stats_defused += 1
			if bool(r[1]):
				f.append("defuse_chance: seed %d defused AND died" % seed)
				break
			if _kind(r[2], "mine_detonated") != 0:
				f.append("defuse_chance: seed %d defused AND detonated" % seed)
				break
	_check(f, stats_defused > 0,
			"defuse_chance: 200 seeds with defuse_kit x1 saw no defuse at all")

	# the event carries the stat that decided the outcome
	var ev_ok := false
	for seed in range(500):
		var r := _resolve(seed, kit1)
		if _kind(r[2], "mine_defused") == 1:
			for e in r[2]:
				if str(e.get("e", e.get("type", ""))) == "mine_defused" \
						and absf(float(e.get("chance", -1.0)) - 0.2) <= 1e-9:
					ev_ok = true
			break
	_check(f, ev_ok, "defuse_chance: the mine_defused event does not carry chance=0.2")

	# the stats dict wins over the stacks argument once applied (stacks [0] passed,
	# the stat decided) - and an empty dict resets to the 0.0 base
	var applied := MinesScript.create(_level([1]), TEST_LEVEL, 11)
	applied.apply_stats(kit1)
	_check(f, absf(float(applied.defuse_chance) - 0.2) <= 1e-9,
			"defuse_chance: apply_stats did not store the stat")
	var emptied := MinesScript.create(_level([1]), TEST_LEVEL, 11)
	emptied.apply_stats({"run_speed": 1.0})
	_check(f, absf(float(emptied.defuse_chance)) <= 1e-9,
			"defuse_chance: a dict without the stat left defuse_chance at %s, want 0.0" % str(emptied.defuse_chance))
	print("STATS defuse_chance: stacks path intact, stats path live, event carries the stat")

# ---- pickup_radius: the gifts consumer ----------------------------------------

## A minimal synthetic level: one 1x1 tile per gift slot at y 0.
static func _synthetic(occs: Array) -> Dictionary:
	var gifts: Array = []
	var tiles: Array = []
	for i in occs.size():
		var z: int = i * 3
		gifts.append({"id": i, "x": 3, "z": z, "y": 0, "piece": 0, "tier": 0, "occ": occs[i]})
		tiles.append([3, z, 0, 0, 0])
	return {
		"gen_version": 0, "seed": 0, "level": 1, "players": 1, "extra_mines": 0, "attempt": 0,
		"beacon": [0, 0, 1], "spawns": [[0, 0, 1]], "arms": [], "pieces": [],
		"tiles": tiles, "props": [], "edges": [], "gifts": gifts, "anchors": [], "pads": [],
	}


## A fresh level state; the player row is moved to the probe point before ticking.
static func _gift_state() -> RefCounted:
	return LevelStateScript.build(_synthetic([0]), 1, 1)


## Tick the pickup at the probe point used across this test: 0.55 u horizontal +
## 0.1 u vertical off the slot (world 3.5, 1.0, 0.5) - outside the canon 0.4 u
## ring, inside a x1.4 Long Reach ring (0.56). Returns true when slot 0 collected.
static func _probe(g_level: RefCounted) -> bool:
	var p: Dictionary = g_level.players[0]
	p["x"] = 2.95
	p["y"] = 0.0
	p["z"] = 0.5
	var ev: Array = []
	GiftsScript.tick(g_level, 0, ev)
	return GiftsScript.bit_get(g_level.gifts.black_taken, 0)


func _test_pickup_radius(f: Array[String]) -> void:
	# the base dict (no upgrades, no curses) carries no pickup_radius at all
	var base_stats := _stats_for({}, {})
	_check(f, not base_stats.has("pickup_radius"),
			"pickup_radius: the base stats dict unexpectedly carries the stat")

	# BASE BEHAVIOUR HOLDS: no stats applied -> the canon 0.4 u ring, and the
	# probe point is out of reach
	var base := _gift_state()
	_check(f, absf(float(base.gifts.pickup_radius()) - 0.4) <= 1e-9,
			"pickup_radius: base ring %.4f, want 0.4" % float(base.gifts.pickup_radius()))
	_check(f, not _probe(base),
			"pickup_radius: the probe point collected inside the base 0.4 u ring")

	# ... and a stats dict WITHOUT the stat keeps the canon ring
	var plain := _gift_state()
	plain.gifts.apply_stats({"run_speed": 1.0})
	_check(f, absf(float(plain.gifts.pickup_radius()) - 0.4) <= 1e-9,
			"pickup_radius: a dict without the stat widened the ring to %.4f, want 0.4"
					% float(plain.gifts.pickup_radius()))
	_check(f, not _probe(plain),
			"pickup_radius: the probe point collected with no pickup_radius stat")

	# WITH THE UPGRADE OWNED THE BEHAVIOUR CHANGES: Long Reach is +40% per stack.
	var reach1 := _stats_for({"long_reach": 1}, {})
	_check(f, absf(float(reach1.get("pickup_radius", -1.0)) - 1.4) <= 1e-9,
			"long_reach x1: the stats dict carries pickup_radius %s, want 1.4" % str(reach1.get("pickup_radius")))
	var r1 := _gift_state()
	r1.gifts.apply_stats(reach1)
	_check(f, absf(float(r1.gifts.pickup_radius()) - 0.56) <= 1e-9,
			"long_reach x1: the ring is %.4f, want 0.56 (0.4 x 1.4)" % float(r1.gifts.pickup_radius()))
	_check(f, _probe(r1),
			"long_reach x1: the probe point did NOT collect inside the 0.56 u ring")

	var reach2 := _stats_for({"long_reach": 2}, {})
	var r2 := _gift_state()
	r2.gifts.apply_stats(reach2)
	_check(f, absf(float(r2.gifts.pickup_radius()) - 0.4 * 1.96) <= 1e-9,
			"long_reach x2: the ring is %.4f, want 0.784 (0.4 x 1.4 x 1.4)" % float(r2.gifts.pickup_radius()))

	var reach3 := _stats_for({"long_reach": 3}, {})
	var r3 := _gift_state()
	r3.gifts.apply_stats(reach3)
	_check(f, absf(float(r3.gifts.pickup_radius()) - 0.4 * 2.744) <= 1e-9,
			"long_reach x3: the ring is %.4f, want 1.0976 (0.4 x 1.4^3)" % float(r3.gifts.pickup_radius()))

	# curse-shaped stats (the drop-in fixture curse runs 1.1 x per stack): a
	# widening curse widens the ring the same way, a shrinking one narrows it
	var cur := _gift_state()
	cur.gifts.apply_stats({"pickup_radius": 1.1})
	_check(f, absf(float(cur.gifts.pickup_radius()) - 0.44) <= 1e-9,
			"pickup_radius: a 1.1 curse stat gave a %.4f ring, want 0.44" % float(cur.gifts.pickup_radius()))
	var shrink := _gift_state()
	shrink.gifts.apply_stats({"pickup_radius": 0.5})
	_check(f, absf(float(shrink.gifts.pickup_radius()) - 0.2) <= 1e-9,
			"pickup_radius: a 0.5 curse stat gave a %.4f ring, want 0.2" % float(shrink.gifts.pickup_radius()))
	var clamped := _gift_state()
	clamped.gifts.apply_stats({"pickup_radius": -2.0})
	_check(f, absf(float(clamped.gifts.pickup_radius())) <= 1e-9,
			"pickup_radius: a negative curse stat gave a %.4f ring, want 0.0 (clamped)" % float(clamped.gifts.pickup_radius()))

	# the dict is the full truth once applied: re-applying an empty dict resets
	# the ring to canon, not to the previous value
	var reset := _gift_state()
	reset.gifts.apply_stats(reach1)
	reset.gifts.apply_stats({})
	_check(f, absf(float(reset.gifts.pickup_radius()) - 0.4) <= 1e-9,
			"pickup_radius: re-applying an empty dict gave %.4f, want the 0.4 reset" % float(reset.gifts.pickup_radius()))

	# the pickup through tick() really flips the slot (the only real gift -> gold)
	var flipped := _gift_state()
	flipped.gifts.apply_stats(reach1)
	_probe(flipped)
	_check(f, flipped.gifts.phase == GiftsScript.PHASE_GOLD,
			"pickup_radius: the widened ring collected the gift but the phase did not flip to gold")
	print("STATS pickup_radius: base ring holds, Long Reach widens, curse-shaped mul honoured")
