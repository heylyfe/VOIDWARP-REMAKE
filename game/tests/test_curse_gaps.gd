extends RefCounted
#
# W12-B - the three curse gaps the coverage audit (out/coverage_map.md) found:
#
#   hasty        brutal (min 9, 2 stacks): every enemy telegraph 15% shorter per
#                stack. It has no module at all (hooks is empty in its JSON) -
#                the change is the declarative modifier it carries, applied to
#                the run's stats at build and read by the enemy runtime as
#                telegraph_mul. Only a modifier-path unit test existed; nothing
#                proved the WORLD applies it. This leg builds a real world at
#                the curse's own min level, spawns a probe enemy whose
#                behavior announces a fixed telegraph, and reads the LIVE
#                telegraph back after world.step() ticks.
#   unannounced  brutal (min 10, 1 stack): no trumpet - only the sprite and the
#                rumble. Proven at module/consumer level only; nothing
#                world-level. This leg builds a real world with the enemy
#                voted in, lets the appearance happen through world.step(), and
#                proves the cue list contract THROUGH THE REAL CONSUMER
#                (view/audio/address_me_audio.gd, the exact static the shipped
#                view calls) fed the world's OWN dispatcher state - the exact
#                dict the world carries and hands its views. It does NOT bake
#                in the live trumpet path; see the report.
#   no_refunds   "shop reroll plinth is gone". The negative control existed at
#                view level only. This leg drives the REAL lobby/shop path the
#                app drives (sim/intermission.gd: the altar table, the select
#                through lobby.step([PlayerInput]), the purse deduction and
#                the redraw events) and the plinth gate the shop's consumer
#                calls with the lobby's OWN carried curses.
#
# Each leg twins the held build against the un-cursed control, and every
# held-assertion set is ALSO run against the control (the failures are counted
# as the leg's negative control, test_app_enemy_views.gd's pattern). The test
# fails if any control passes.

const WorldScript := preload("res://app/world.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const InputScript := preload("res://sim/input.gd")
const AddressMeAudioScript := preload("res://view/audio/address_me_audio.gd")
const NoRefundsScript := preload("res://content/curses/no_refunds.gd")
const OffersScript := preload("res://sim/offers.gd")
const RT := preload("res://sim/enemy_runtime.gd")
const Unannounced := preload("res://content/curses/unannounced.gd")

const SEED := 1
const LEVEL_HASTY := 9       # hasty's own min level
const LEVEL_ADDR := 9        # address me's own min level
const DT := 1.0 / 60.0
const LOBBY_SEED := 77

var negative_failures := 0


class TellBehavior:
	extends RT.EnemyBehavior

	var age := 0

	func tick(row: Dictionary, api, _dt_ticks: int) -> void:
		if age == 3:
			api.telegraph("hasty_probe", {"shape": "circle", "cx": 0.0, "cz": 0.0, "r": 1.0}, 100)
		age += 1


# ---- shared helpers ----------------------------------------------------------

func _ledger(votes: Dictionary, curses: Dictionary) -> Dictionary:
	return {"class": "dasher", "votes": votes, "curses": curses, "stacks": {},
			"purse": 0, "tithes": 0, "hunger": 0, "last_vote": ""}


func _build(votes: Dictionary, curses: Dictionary, level: int):
	var world = WorldScript.new()
	if not world.build(SEED, level, _ledger(votes, curses)):
		world.free()
		return null
	return world


func _drop(world) -> void:
	if world != null:
		var root := _root()
		world.teardown()
		if root != null and world.get_parent() == root:
			root.remove_child(world)
		world.free()


func _root() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root
	return null


func _cue_seen(world, cue: String) -> bool:
	for e in world.telegraph_view.cue_log:
		if str(e.get("cue", "")) == cue:
			return true
	return false


func _host_of(world, id: String):
	for host in world.enemy_views:
		if host != null and str(host.id) == id:
			return host.view
	return null


# ---- hasty -------------------------------------------------------------------

# Read the curse's own JSON for what it changes; the proof is that object, not
# a test-local copy of the rule.
func _hasty_doc() -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			"res://content/curses/hasty.json"))
	if doc is Dictionary:
		return doc
	return {}


func _hasty_values() -> Array:
	var doc: Dictionary = _hasty_doc()
	for m in doc.get("modifiers", []):
		if str(m.get("stat", "")) == "telegraph_mul" and str(m.get("op", "")) == "mul":
			return [float(m.get("value", 1.0)), int(doc.get("max_stacks", 1))]
	return [0.85, 2]


# The expectations, run twice per build: appended on the held half (f must stay
# empty), counted on the control half (the count is the leg's negative control).
func _hasty_expect(world, stacks: int) -> Array[String]:
	var errs: Array[String] = []
	var vals: Array = _hasty_values()
	var per_stack := float(vals[0])
	var want := pow(per_stack, float(stacks)) if stacks > 0 else 1.0
	var mul := float(world.rt.telegraph_mul)
	if absf(mul - want) > 1e-6:
		errs.append("hasty x%d: rt.telegraph_mul %.4f, want %.4f (JSON declares %.2f/stack)"
				% [stacks, mul, want, per_stack])
	# through world.step: a probe body announces a fixed 100-tick telegraph
	var c = world.ctl
	world.rt.spawn_at("fixture", "hasty probe", TellBehavior.new(),
			{"contact_kill": false, "id": "fixture", "name": "hasty probe"},
			Vector3(float(c.x) + 20.0, float(c.y), float(c.z)))
	for _i in range(10):
		world.step(DT)
	var got := -1
	for t in world.rt.telegraphs:
		if str(t.get("kind", "")) == "hasty_probe":
			got = int(t.get("total", -1))
			break
	var want_ticks := int(round(100.0 * want))
	if got != want_ticks:
		errs.append("hasty x%d: live telegraph total %d ticks, want %d" % [stacks, got, want_ticks])
	return errs


func _hasty(f: Array[String]) -> int:
	var neg := 0
	for stacks in [1, 2]:
		var world = _build({}, {"hasty": stacks}, LEVEL_HASTY)
		if world == null:
			f.append("hasty x%d: the held world failed to build" % stacks)
			continue
		for line in _hasty_expect(world, stacks):
			f.append(line)
		_drop(world)
	# control: the identical build with the curse absent (its expectations must hold)
	var ctrl = _build({}, {}, LEVEL_HASTY)
	if ctrl == null:
		f.append("hasty: the control world failed to build")
	else:
		for line in _hasty_expect(ctrl, 0):
			f.append(line)
		# NEGATIVE CONTROL: the held assertions against the control must FAIL
		var a1: Array[String] = _hasty_expect(ctrl, 1)
		var a2: Array[String] = _hasty_expect(ctrl, 2)
		neg += a1.size() + a2.size()
		_drop(ctrl)
	return neg


# ---- unannounced -------------------------------------------------------------

# The expectations, run twice: appended held, counted on the control. The
# contract (content/curses/unannounced.gd + view/audio/address_me_audio.gd):
# with the curse held the cue list drops the spawn trumpet; the sprite and
# the rumble stay. The state fed here is the world's OWN dispatcher state
# (world._curses.state) - the exact dict the world hands its views.
func _unannounced_expect(world, stacks: int) -> Array[String]:
	var errs: Array[String] = []
	var held: Dictionary = world._curses.state.get("curses_held", {})
	if int(held.get("unannounced", 0)) != stacks:
		errs.append("unannounced x%d: the world's curse state holds %s, want %d stacks"
				% [stacks, str(held), stacks])
	# let the appearance happen through world.step() itself
	var host = null
	var appeared := false
	for _i in range(800):
		world.step(DT)
		if not appeared and _cue_seen(world, "rumble_build"):
			appeared = true
		if host == null:
			host = _host_of(world, "address_me")
		if appeared and host != null:
			break
	if not appeared:
		errs.append("unannounced: the appearance never fired within 800 steps")
	var state: Dictionary = world._curses.state
	var cues: Array = AddressMeAudioScript.allowed_cues(state)
	var want_trumpet := stacks <= 0
	if cues.has("spawn_trumpet") != want_trumpet:
		if want_trumpet:
			errs.append("unannounced: the cue list lost the trumpet on a curse-free run (%s)" % str(cues))
		else:
			errs.append("unannounced: the cue list still carries the spawn trumpet (%s)" % str(cues))
	if not cues.has("rumble_build"):
		errs.append("unannounced: the cue list lost the rumble (%s)" % str(cues))
	if host == null:
		errs.append("unannounced: the world hosts no view for the row (the body would never draw)")
	else:
		var p: AudioStreamPlayer = AddressMeAudioScript.play_cue(host, "spawn_trumpet", state)
		if (p != null) != want_trumpet:
			if want_trumpet:
				errs.append("unannounced: the real consumer silenced the trumpet on a curse-free run")
			else:
				errs.append("unannounced: the real consumer played the trumpet with the curse held")
		var r: AudioStreamPlayer = AddressMeAudioScript.play_cue(host, "rumble_build", state)
		if r == null:
			errs.append("unannounced: the real consumer silenced the rumble")
	if not bool(Unannounced.sprite_visible(state)):
		errs.append("unannounced: sprite_visible answered false - the sprite must stay")
	return errs


func _unannounced(f: Array[String]) -> int:
	var neg := 0
	var root := _root()
	var world = _build({"address_me": 1}, {"unannounced": 1}, LEVEL_ADDR)
	if world == null:
		f.append("unannounced: the held world failed to build")
	else:
		if root != null:
			root.add_child(world)
		for line in _unannounced_expect(world, 1):
			f.append(line)
		_drop(world)
	# control: the identical build with the curse absent (its expectations must hold)
	var ctrl = _build({"address_me": 1}, {}, LEVEL_ADDR)
	if ctrl == null:
		f.append("unannounced: the control world failed to build")
	else:
		if root != null:
			root.add_child(ctrl)
		for line in _unannounced_expect(ctrl, 0):
			f.append(line)
		# NEGATIVE CONTROL: the held assertions against the control must FAIL
		var a: Array[String] = _unannounced_expect(ctrl, 1)
		neg += a.size()
		_drop(ctrl)
	return neg


# ---- no_refunds --------------------------------------------------------------

# The level-1 lobby (the one with a U / REST bay whose reroll plinth is the
# curse's target) the way lobby_scene.gd builds it: the same create() call,
# the same carried curses. stacks <= 0 = the control polarity.
func _no_refunds_expect(api, curses: Dictionary, stacks: int) -> Array[String]:
	var errs: Array[String] = []
	var lb: RefCounted = IntermissionScript.create(api, 1, 100, LOBBY_SEED,
			{}, curses, {}, "dasher", 0, 0, "", {})
	if lb == null:
		errs.append("no_refunds: the lobby failed to build")
		return errs
	# the lobby carries the run's curses, the same dict every consumer reads
	var held: Dictionary = lb.curses_held
	if int(held.get("no_refunds", 0)) != stacks:
		errs.append("no_refunds x%d: the lobby holds %s, want %d stacks" % [stacks, str(held), stacks])
	# the shop's reroll row sits in the real altar table (the pools are untouched)
	var table: Array = lb.altar_table()
	var reroll := -1
	for i in table.size():
		if str(table[i]["kind"]) == "reroll":
			reroll = i
			break
	if reroll < 0:
		errs.append("no_refunds: no reroll row in the altar table")
	else:
		var open_plinth := bool(NoRefundsScript.reroll_plinth_visible({"curses_held": held}))
		if open_plinth == (stacks > 0):
			if stacks > 0:
				errs.append("no_refunds: the plinth gate answered true with the curse held - the reroll is offered")
			else:
				errs.append("no_refunds: the plinth gate answered false on a curse-free run")
	# through the real money path (control polarity only): the redraw is charged
	# the plinth's own seeded price and the events fire, exactly as lobby_scene
	# feeds them from the hall's confirm.
	if stacks <= 0 and reroll >= 0:
		var cost := int(OffersScript.reroll_cost(0, api))
		var events: Array = lb.step([InputScript.new(0, 0, 0, reroll)])
		if events.is_empty():
			errs.append("no_refunds: the control's reroll produced no altar_selected event")
		else:
			var ev: Dictionary = events[0]
			if str(ev.get("kind", "")) != "reroll" or str(ev.get("bay", "")) != "U":
				errs.append("no_refunds: the control's reroll event is bay=%s kind=%s, want U/reroll"
						% [str(ev.get("bay", "")), str(ev.get("kind", ""))])
			if int(ev.get("cost", -1)) != cost:
				errs.append("no_refunds: the control's reroll cost %d, want %d" % [int(ev.get("cost", -1)), cost])
		if int(lb.purse) != 100 - cost:
			errs.append("no_refunds: the control's purse reads %d after the redraw, want %d"
					% [int(lb.purse), 100 - cost])
	return errs


func _no_refunds(f: Array[String]) -> int:
	var neg := 0
	var api: RefCounted = ContentApiScript.load()
	if api == null or not api.is_ok():
		f.append("no_refunds: the content api failed to boot")
		return 0
	# HELD twin: the curse carried in the lobby's own ledger
	for line in _no_refunds_expect(api, {"no_refunds": 1}, 1):
		f.append(line)
	# CONTROL twin: the identical lobby, curse absent (its expectations must hold)
	for line in _no_refunds_expect(api, {}, 0):
		f.append(line)
	# NEGATIVE CONTROL: the held assertions against the control must FAIL
	var a: Array[String] = _no_refunds_expect(api, {}, 1)
	neg += a.size()
	if neg == 0:
		f.append("no_refunds: NEGATIVE CONTROL passed with the curse absent - the assertions prove nothing")
	return neg


func run() -> Array[String]:
	var f: Array[String] = []
	var per_leg := {}
	var h := _hasty(f)
	per_leg["hasty"] = h
	var u := _unannounced(f)
	per_leg["unannounced"] = u
	var n := _no_refunds(f)
	per_leg["no_refunds"] = n
	negative_failures = h + u + n
	if h == 0:
		f.append("hasty: NEGATIVE CONTROL passed with the curse absent - the assertions prove nothing")
	if u == 0:
		f.append("unannounced: NEGATIVE CONTROL passed with the curse absent - the assertions prove nothing")
	print("NEGATIVE CONTROL failures=%d per leg %s" % [negative_failures, str(per_leg)])
	return f
