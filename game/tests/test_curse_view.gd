extends RefCounted
#
# test_curse_view.gd (W10-B) - the VIEW-side curse consumers: real view objects fed
# real sim / dispatcher state, every query with a NEGATIVE CONTROL (the same
# assertion with the curse not held). A green module test was never proof of the
# feature - the proof here goes through the real view objects (and in leg 3 through
# a real world's own build(), exactly wiring the calls world.gd owes), and the
# negatives show the un-cursed value.
#
#   1. dull_gifts.rim_glow_visible   -> view/gifts_view.gd. Held: outside 20 u the
#      black gift's base pass is swapped to the dull albedo, inside it (and exactly
#      at 20.0 u) the canon pass builds back. Negative control: an un-cursed world's
#      far gift KEEPS the glow (the dull pass is never even created). Held leg feeds
#      the world's OWN dispatcher state dict (world._curses.state) - the exact shape
#      world.gd holds and would pass at its _view_pass call.
#   2. unmarked.straggler_ids        -> view/straggler_beam.gd. Held: the world built
#      with the curse in its ledger draws NO beam once the straggler set opens; a
#      0-held state brings exactly the sim's straggler ids BACK (negative control),
#      then the held state suppresses them again. The collection leg mirrors
#      test_app_fx_wiring.gd leg 3's loop byte for byte.
#   3. no_refunds.reroll_plinth_visible -> view/lobby/antechamber.gd. Held: the
#      reroll plinth hides (root.visible false), the OTHER rows stay visible, and a
#      0-held state brings the plinth back (negative control).
#   4. litter.trail_point            -> view/kiwi_cat_view.gd. Held: the trail ring
#      sits at the module's exact trail_point(cat, player); 0-held never draws it.
#   5. module neutrality at 0 stacks - the brief's tripwire (a non-neutral answer at
#      0 stacks is a module bug): every query above answers its neutral value with
#      0 stacks in the held dict (the dispatcher keeps 0-stack ids OUT of curses_held,
#      but a consumer that calls with a raw stack count must not regress), and with
#      a plain {} (a dispatcher with no curses held).
#
# Headless, engine nodes built outside the scene tree - the same style
# test_curse_view_stats.gd and test_lobby.gd already run.

const WorldScript := preload("res://app/world.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const AntechamberScript := preload("res://view/lobby/antechamber.gd")
const KiwiCatViewScript := preload("res://view/kiwi_cat_view.gd")
const DullGiftsScript := preload("res://content/curses/dull_gifts.gd")
const UnmarkedScript := preload("res://content/curses/unmarked.gd")
const NoRefundsScript := preload("res://content/curses/no_refunds.gd")
const LitterScript := preload("res://content/curses/litter.gd")
const GiftsScript := preload("res://sim/gifts.gd")

const SEED := 1
const LEVEL := 1
const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_gifts_rim(f)
	_leg_straggler_beam(f)
	_leg_lobby_reroll(f)
	_leg_kiwi_trail(f)
	_leg_zero_stacks(f)
	return f


func _check(f: Array[String], ok: bool, why: String) -> bool:
	if not ok:
		f.append(why)
	return ok


# ---- ledgers -------------------------------------------------------------------

func _ledger(p_curses: Dictionary) -> Dictionary:
	# the same built-in shape test_app_fx_wiring.gd's _ledger() carries
	return {"class": "athletic", "votes": {}, "curses": p_curses,
			"stacks": {"bargain": 2}, "purse": 0}


# ---- leg 1: dull_gifts -> gifts_view --------------------------------------------

## First REAL gift slot's index (the occ == 1 slot mining table skips some rows).
func _first_real_slot(world) -> int:
	for i in world.lstate.gifts.slots.size():
		if world.lstate.gifts.is_real(i):
			return i
	return -1


func _black_override(gv: Node3D, slot: int) -> StandardMaterial3D:
	if gv._black[slot] == null:
		return null
	var stack: Array = [gv._black[slot]]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null \
				and (n as MeshInstance3D).get_surface_override_material(0) != null:
			return (n as MeshInstance3D).get_surface_override_material(0)
		stack.append_array(n.get_children())
	return null


func _leg_gifts_rim(f: Array[String]) -> void:
	# HELD: a real world built with dull_gifts in the ledger; the view fed the
	# world's OWN dispatcher state - the exact dict world.gd's _curses carries.
	var world = WorldScript.new()
	if not world.build(SEED, LEVEL, _ledger({"dull_gifts": 1})):
		f.append("gifts_rim: held world failed to build")
		return
	var gv: Node3D = world.gifts_view
	var slot: int = _first_real_slot(world)
	var gpos: Vector3 = world.lstate.gifts.slot_pos(slot)
	gv.set_curses_state(world._curses.state)
	# far (30 u): the glow is OFF
	gv.set_viewpoint(gpos + Vector3(0.0, 0.0, 30.0))
	gv.sync()
	_check(f, gv._dull_mat != null, "gifts_rim: the dull pass never built (far, held)")
	if gv._dull_mat != null:
		_check(f, _black_override(gv, slot) == gv._dull_mat,
				"gifts_rim: the far black gift kept the rim glow (held, 30 u)")
	# exactly 20.0 u: ON (the module's own boundary, d2 <= 400 + 1e-9)
	gv.set_viewpoint(gpos + Vector3(20.0, 0.0, 0.0))
	gv.sync()
	if gv._black_mat[slot] != null:
		_check(f, _black_override(gv, slot) == gv._black_mat[slot],
				"gifts_rim: the glow did not come back exactly at 20.0 u (held)")
	# in (3 u): ON
	gv.set_viewpoint(gpos + Vector3(3.0, 0.0, 0.0))
	gv.sync()
	if gv._black_mat[slot] != null:
		_check(f, _black_override(gv, slot) == gv._black_mat[slot],
				"gifts_rim: an in-range black gift lost the rim glow (held, 3 u)")
	# out again (20.1 u): OFF
	gv.set_viewpoint(gpos + Vector3(20.1, 0.0, 0.0))
	gv.sync()
	if gv._dull_mat != null:
		_check(f, _black_override(gv, slot) == gv._dull_mat,
				"gifts_rim: an out-of-range black gift still glows (held, 20.1 u)")
	world.free()
	# NEGATIVE CONTROL: the un-cursed world's far gift keeps the glow - the dull
	# pass is never even built (the un-cursed dispatcher state is {"curses_held":
	# {}}, the module's neutral passthrough).
	var world2 = WorldScript.new()
	if not world2.build(SEED, LEVEL, _ledger({})):
		f.append("gifts_rim: un-cursed world failed to build")
		return
	var gv2: Node3D = world2.gifts_view
	var slot2: int = _first_real_slot(world2)
	var gpos2: Vector3 = world2.lstate.gifts.slot_pos(slot2)
	gv2.set_curses_state(world2._curses.state)
	gv2.set_viewpoint(gpos2 + Vector3(0.0, 0.0, 30.0))
	gv2.sync()
	if gv2._black_mat[slot2] != null:
		_check(f, _black_override(gv2, slot2) == gv2._black_mat[slot2],
				"gifts_rim: an un-cursed far black gift lost the rim glow")
	_check(f, gv2._dull_mat == null,
			"gifts_rim: the dull pass built without the curse held")
	world2.free()


# ---- leg 2: unmarked -> straggler_beam -------------------------------------------

func _leg_straggler_beam(f: Array[String]) -> void:
	# HELD: the world built with unmarked in the ledger; the beam view fed the
	# world's OWN dispatcher state (world._curses.state).
	var world = WorldScript.new()
	if not world.build(SEED, LEVEL, _ledger({"unmarked": 1})):
		f.append("straggler_beam: held world failed to build")
		world = null
		return
	world.straggler_beam.set_curses_state(world._curses.state)
	var g: RefCounted = world.lstate.gifts
	var ev: Array = []
	for i in g.slots.size():
		if not g.straggler_ids().is_empty() or int(g.remaining()) <= 1:
			break
		if bool(g.is_real(i)) and not bool(g.collected(i)):
			g.collect(i, int(world.lstate.tick), 0, ev)
	world.step(DT)
	var want: Array = g.straggler_ids()
	if want.is_empty():
		f.append("straggler_beam: could not open the straggler set (remaining %d of %d)"
				% [int(g.remaining()), int(g.total_real)])
		world.free()
		return
	_check(f, int(world.straggler_beam._beams.size()) == 0,
			"straggler_beam: HELD world drew %d beams, want 0 - the curse suppresses every straggler beam (%d sim stragglers)"
			% [int(world.straggler_beam._beams.size()), want.size()])
	# NEGATIVE CONTROL: a 0-held state - the sim's ids byte for byte
	world.straggler_beam.set_curses_state({"curses_held": {}})
	world.straggler_beam.sync()
	_check(f, int(world.straggler_beam._beams.size()) == want.size(),
			"straggler_beam: 0-held state drew %d beams, sim reports %d stragglers"
			% [int(world.straggler_beam._beams.size()), want.size()])
	for id in want:
		_check(f, world.straggler_beam._beams.has(id),
				"straggler_beam: 0-held state missing the beam for slot %s" % str(id))
	# and back to HELD: suppressed again
	world.straggler_beam.set_curses_state(world._curses.state)
	world.straggler_beam.sync()
	_check(f, world.straggler_beam._beams.is_empty(),
			"straggler_beam: re-held state still shows beams")
	if world.straggler_beam != null and not world.straggler_beam._beams.is_empty():
		for id in world.straggler_beam._beams.keys():
			_check(f, want.has(id),
					"straggler_beam: beam for a non-straggler slot %s" % str(id))
	world.free()


# ---- leg 3: no_refunds -> the lobby shop view ------------------------------------

func _leg_lobby_reroll(f: Array[String]) -> void:
	var api: RefCounted = ContentApiScript.load()
	if not _check(f, api != null and bool(api.is_ok()), "content api boot failed"):
		return
	# the real lobby build - test_lobby.gd's exact idiom
	var lb: RefCounted = IntermissionScript.create(api, 1, 1, 77)   # completed 1: the level-1 lobby, which has a reroll bay
	if lb == null:
		f.append("lobby: no lobby scenario booted to exercise no_refunds")
		return
	var table: Array = lb.altar_table()
	var reroll_idx := -1
	for i in table.size():
		if str(table[i]["kind"]) == "reroll":
			reroll_idx = i
			break
	var hall: Node3D = AntechamberScript.new()
	hall.build_all(api, lb, "deepwater", 0)
	if reroll_idx >= 0:
		# un-cursed state ({} neutral): reroll row visible
		var wrap_root0: Node3D = hall._altars[reroll_idx]["root"]
		_check(f, wrap_root0.visible,
				"lobby: no_refunds hidden state still hides the reroll plinth")
		# HELD: the plinth is gone (root hidden); the offer rows stay visible
		hall.set_curses_state({"curses_held": {"no_refunds": 1}})
		var wrap_root: Node3D = hall._altars[reroll_idx]["root"]
		_check(f, not wrap_root.visible,
				"no_refunds: HELD reroll plinth root still visible")
		var offers_visible := 0
		for wrap in hall._altars:
			if str(wrap["kind"]) == "offer" and (wrap["root"] as Node3D).visible:
				offers_visible += 1
		_check(f, offers_visible > 0,
				"no_refunds: hiding the reroll plinth killed the offer rows")
		# NEGATIVE CONTROL: a 0-held state brings the plinth back
		hall.set_curses_state({"curses_held": {"no_refunds": 0}})
		wrap_root = hall._altars[reroll_idx]["root"]
		if wrap_root != null:
			_check(f, wrap_root.visible,
					"no_refunds: 0-held reroll plinth still hidden")
		# and the empty dict (a dispatcher with no curses held) stays neutral too
		hall.set_curses_state({})
		wrap_root = hall._altars[reroll_idx]["root"]
		if wrap_root != null:
			_check(f, wrap_root.visible,
					"no_refunds: empty state must not hide the reroll plinth")
	else:
		f.append("lobby: no reroll altar row booted for the no_refunds leg")
	hall.free()


# ---- leg 4: litter -> kiwi_cat_view ----------------------------------------------

func _leg_kiwi_trail(f: Array[String]) -> void:
	# the real kiwi view - setup() (parses the REAL kiwi sprites.json, T-030); no
	# tree, like test_curse_view_stats.gd's headless fog/player nodes
	var kv: Node3D = KiwiCatViewScript.new()
	kv.setup()
	var held := {"curses_held": {"litter": 1}}
	kv.set_curses_state(held)
	var cat := {"id": "kiwi_cat", "x": 5.0, "y": 0.0, "z": 0.0, "cfg": {}}
	var player := {"x": 0.0, "y": 0.0, "z": 0.0}
	kv.update_trail(cat, player)
	_check(f, kv._trail_marker != null and kv._trail_marker.visible,
			"litter: the trail ring never drew (litter held)")
	if kv._trail_marker != null:
		# the marker is parented to the cat view, so its position is RELATIVE to the cat:
		# trail_point() is absolute, the view's own placement is the cat's.
		var want: Vector3 = LitterScript.trail_point(cat, player) - Vector3(5.0, 0.0, 0.0)
		_check(f, kv._trail_marker.position.distance_to(want) < 0.05,
				"litter: the trail ring is not at trail_point relative to the cat (%s, want %s)"
				% [str(kv._trail_marker.position), str(want)])
	# NEGATIVE CONTROL: 0-held - the sim's ids byte for byte back
	kv.set_curses_state({})
	kv.update_trail(cat, player)
	_check(f, kv._trail_marker == null or not kv._trail_marker.visible,
			"litter: 0-held state still drew the trail ring")
	# and empty-dict neutral (a dispatcher with no curses held)
	kv.set_curses_state({"curses_held": {}})
	kv.update_trail(cat, player)
	_check(f, kv._trail_marker == null or not kv._trail_marker.visible,
			"litter: empty state still drew the trail ring")
	kv.free()


# ---- leg 5: module neutrality at 0 stacks ----------------------------------------

func _leg_zero_stacks(f: Array[String]) -> void:
	# The brief's tripwire - "if one returns a non-neutral value at 0 stacks, say
	# so loudly - that is a module bug". Two shapes: 0 stacks in the held dict
	# (sim/curse_runtime.gd keeps 0-stack ids in ledger form through
	# curse_runtime.state's own neutral reply - a consumer must never be corrupted
	# if a stack count slips through) and the plain {} (a run with no curses).
	var held := {
		"curses_held": {}, "curse_st": {}, "tick": 0, "players": [],
		"enemies": [], "events": [], "spawn_plan": [],
	}
	for id in ["dull_gifts", "unmarked", "no_refunds"]:
		held["curses_held"][id] = 0
	_check(f, DullGiftsScript.rim_glow_visible(held, 0.0, 0.0, 0.0, 90.0, 0.0, 0.0),
			"dull_gifts: 0 stacks must keep the far rim glow (module neutrality)")
	_check(f, DullGiftsScript.rim_glow_visible({}, 0.0, 0.0, 0.0, 90.0, 0.0, 0.0),
			"dull_gifts: an empty state must keep the far rim glow (module neutrality)")
	_check(f, NoRefundsScript.reroll_plinth_visible(held),
			"no_refunds: 0 stacks must keep the reroll plinth visible (module neutrality)")
	_check(f, NoRefundsScript.reroll_plinth_visible({}),
			"no_refunds: an empty state must keep the reroll plinth visible (module neutrality)")
	var g: RefCounted = GiftsScript.create(_synthetic_gifts([0, 0, 0, 0, 0, 0]))
	for i in 5:
		GiftsScript.bit_set(g.black_taken, i)   # all but the last real slot taken: the straggler window opens
	var held_straggler := held.duplicate(true)
	held_straggler["curses_held"]["unmarked"] = 1   # the control: the held answer
	_check(f, UnmarkedScript.straggler_ids(held, g).size() == g.straggler_ids().size()
			or g.straggler_ids().is_empty(),
			"unmarked: 0 stacks must leave the sim's straggler list whole (module neutrality)")
	_check(f, UnmarkedScript.straggler_ids(held_straggler, g).is_empty(),
			"unmarked: the HELD list is not empty (%s) - the curse must suppress every straggler beam" % str(UnmarkedScript.straggler_ids(held_straggler, g)))
	var cat := {"x": 5.0, "y": 0.0, "z": 0.0, "cfg": {}}
	var want: Vector3 = LitterScript.trail_point(cat, {"x": 0.0, "y": 0.0, "z": 0.0})
	_check(f, want.distance_to(Vector3(11.0, 0.0, 0.0)) < 1e-6,
			"litter: trail_point is %.3f,%.3f,%.3f, want 11,0,0 (6 u behind the cat on the cat->player line)" % [want.x, want.y, want.z])
	var no_player: Vector3 = LitterScript.trail_point(cat, {})
	_check(f, no_player.distance_to(Vector3(5.0, 0.0, 0.0)) < 1e-6,
			"litter: trail_point with no player is not the cat itself")


## A synthetic level with one gift slot per entry in `occs` (0 = a real gift). The
## same shape test_curses_scripted_general.gd's helper builds, so the straggler
## window opens the same way it does there.
func _synthetic_gifts(occs: Array) -> Dictionary:
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
