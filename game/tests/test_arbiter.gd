extends RefCounted
#
# T-072: the declarative scheduling gate (sim/enemy_arbiter.gd; SR-4, D-067). Fixture rows
# carry the ids - the arbiter itself names none: the gate vocabulary ("no_enemy_body_within",
# "no_targeted_telegraph", "player_grounded", "not_on_glitched_floor") is read against the
# live sim state. Assertions follow SR-4 and DESIGN.md sections 5.10 / 5.12:
#   - the stop-corresponding sentinel never comes with a body within 12 u ...
#   - ... with a bomb circle or a sword-wielding marked patch on the player ...
#   - ... or while the player is airborne;
#   - the sword-wielding row never marks while the stillness countdown runs.

const ArbiterScript := preload("res://sim/enemy_arbiter.gd")
const Util := preload("res://tests/sim_testutil.gd")

# ids live in these fixtures, never in sim/:
const STOP_ID := "address_me"   # the stillness caller (never appears in something lethal)
const MARK_ID := "gin"          # the caller needing stillness to pass (5 x 5 patch caller)


func run() -> Array[String]:
	var f: Array[String] = []
	_body_within_twelve(f)
	_ring_on_player(f)
	_patch_on_player(f)
	_airborne(f)
	_glitched_floor(f)
	_deferred_by_lived_countdown(f)
	_idless_and_optional(f)
	return f


# A player stub with exactly the surface the arbiter reads (a controller row has the same).
class PStub:
	extends RefCounted
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var grounded := true
	var cur_key := ""


# The worlds: grounded clean floor / glitched tile, body list, telegraph list.
# The stillness caller's row: every SR-4 requirement, it yields to nothing.
func _stop_cfg() -> Dictionary:
	return {
		"appear_requires": [
			{"no_enemy_body_within": 12.0},
			{"no_targeted_telegraph": true},
			{"player_grounded": true},
			{"not_on_glitched_floor": true},
		],
		"yields_to": [],
	}


# The marked-patch caller's row: it defers to the stillness caller while that countdown runs.
func _mark_cfg() -> Dictionary:
	return {"appear_requires": [], "yields_to": [STOP_ID]}


# An enemy body < 12 u from the player blocks the stillness caller's appearance; >= 12 u is
# clear (strictly within - a body exactly at the bound is clear). 3D, feet to feet (D-T072-1).
func _body_within_twelve(f: Array[String]) -> void:
	var cfg := _stop_cfg()
	for spec in [[10.0, 0.0], [3.0, 4.0], [8.0, 8.8]]:
		var p: PStub = PStub.new()
		var bd: Array = [[spec[0], 0.0, spec[1]]]
		var w := Util.world_from_tiles([[0, 0, 0]])
		var got: Dictionary = ArbiterScript.evaluate(cfg, p, w, [])
		if got["may_appear"]:
			f.append("gate: from a body at %.1f/%.1f (d=%.4f < 12)" % [spec[0], spec[1],
					Vector3(spec[0] - 0.5, 0.0, spec[1] - 0.5).length()])
			return
	var far: Array = [[15.0, 0.0, 0.0]]
	var w2 := Util.world_from_tiles([[0, 0, 0]])
	var p2: PStub = PStub.new()
	if not ArbiterScript.evaluate(_stop_cfg(), p2, w2, [])["may_appear"]:
		f.append("gate: 15.0 u away still blocked a clean appearance")
	# exactly at the bound is clear (strictly-within reading, D-T072-1)
	var w3 := Util.world_from_tiles([[0, 0, 0]])
	if not ArbiterScript.evaluate(_stop_cfg(), PStub.new(),
			{"glitched": {}, "enemies": [[12.0, 0.0, 0.0]]}, [])["may_appear"]:
		f.append("gate: a body exactly at 12.0 u blocked (within = strictly inside, D-T072-1).")
	# a body above the player still blocks (3D distance, not XZ-only)
	var w4 := Util.world_from_tiles([[0, 0, 0]])
	var pa: PStub = PStub.new()
	pa.y = 6.0
	if ArbiterScript.evaluate(_stop_cfg(), pa,
			{"glitched": {}, "enemies": [[0.5, 9.0, 0.5]]}, [])["may_appear"]:
		f.append("gate: a body 3.0 u above the player read XZ-only (3D distance required)")


# A live bomb circle on the player blocks; an expired (ticks 0) entry does not.
func _ring_on_player(f: Array[String]) -> void:
	var cfg := _stop_cfg()
	var p: PStub = PStub.new()
	var ring: Dictionary = {"shape": "ring", "cx": 0.5, "cz": 0.5, "r1": 5.0}
	var tgr: Array = [{"source": "bomb_ring", "ticks": 300, "total": 300, "shape": ring}]
	var got: Dictionary = ArbiterScript.evaluate(cfg, p, Util.world_from_tiles([[0, 0, 0]]), tgr)
	if got["may_appear"]:
		f.append("gate: the stillness caller came with a live bomb circle on the player")
	# the same circle away from the player leaves the gate open
	var tgr2: Array = [{"source": "bomb_ring", "ticks": 300, "shape":
			{"shape": "ring", "cx": 20.5, "cz": 20.5, "r1": 5.0}}]
	if not ArbiterScript.evaluate(cfg, p, Util.world_from_tiles([[0, 0, 0]]), tgr2)["may_appear"]:
		f.append("gate: a bomb circle 28.3 u away still blocked")
	# an expired circle is not a live footprint
	var tgr3: Array = [{"source": "bomb_ring", "ticks": 0, "shape": ring}]
	if not ArbiterScript.evaluate(cfg, p, Util.world_from_tiles([[0, 0, 0]]), tgr3)["may_appear"]:
		f.append("gate: an expired (ticks 0) circle still blocked")


# A marked patch (the 5 x 5 box the sword caller announces) on the player blocks.
func _patch_on_player(f: Array[String]) -> void:
	var cfg := _stop_cfg()
	var p: PStub = PStub.new()
	var patch: Dictionary = {"shape": "box", "x0": 0, "x1": 5, "z0": 0, "z1": 5}
	var tgr: Array = [{"source": MARK_ID, "ticks": 120, "total": 120, "shape": patch}]
	var got: Dictionary = ArbiterScript.evaluate(cfg, p, Util.world_from_tiles([[0, 0, 0]]), tgr)
	if got["may_appear"]:
		f.append("gate: the stillness caller came with the sword caller's patch on the player")
	# the same patch one tile away is clear
	var tgr2: Array = [{"source": MARK_ID, "ticks": 120, "shape":
			{"shape": "box", "x0": 6, "x1": 10, "z0": 0, "z1": 5}}]
	if not ArbiterScript.evaluate(cfg, p, Util.world_from_tiles([[0, 0, 0]]), tgr2)["may_appear"]:
		f.append("gate: a patch at tiles 7-10 still blocked (player tile 0,4)")


# Stillness needs the ground: the caller never comes while the player is airborne.
func _airborne(f: Array[String]) -> void:
	var cfg := _stop_cfg()
	var p: PStub = PStub.new()
	var wf := Util.world_from_tiles([[0, 0, 0]])
	p.grounded = false
	if ArbiterScript.evaluate(cfg, p, wf, [])["may_appear"]:
		f.append("gate: the stillness caller arrived while the player was airborne")
	p.grounded = true
	if not ArbiterScript.evaluate(cfg, p, wf, [])["may_appear"]:
		f.append("gate: a grounded clean player was still blocked")


# A glitched tile under the player blocks (not_on_glitched_floor).
func _glitched_floor(f: Array[String]) -> void:
	var cfg := _stop_cfg()
	var p: PStub = PStub.new()
	p.cur_key = "3,0,0"
	var w := Util.world_from_tiles([[0, 0, 0]])
	w["glitched"]["3,0,0"] = true
	if ArbiterScript.evaluate(cfg, p, w, [])["may_appear"]:
		f.append("gate: the stillness caller came onto a glitched tile")
	p.cur_key = "9,0,0"
	if not ArbiterScript.evaluate(cfg, p, w, [])["may_appear"]:
		f.append("gate: a player on a clean tile stayed blocked")


# The mark caller defers while the stillness caller's countdown runs - and only then
# (SR-4: the deferral only schedules them; the countdown itself is never stopped).
func _deferred_by_lived_countdown(f: Array[String]) -> void:
	var cfg := _mark_cfg()
	var tgr: Array = [{"source": STOP_ID, "ticks": 300, "total": 300, "shape":
			{"shape": "circle", "cx": 30.5, "cz": 30.5, "r": 3.0}}]
	if not ArbiterScript.defer_answer(cfg, tgr):
		f.append("gate: the mark caller did not defer to a live stillness countdown")
	if ArbiterScript.must_defer(cfg, ArbiterScript.busy_sources(tgr, [])) == false:
		f.append("gate: must_defer lost the countdown through busy_sources")
	# the countdown ended (the entry left the list): the deferral lifts at once
	if ArbiterScript.defer_answer(cfg, []):
		f.append("gate: the mark caller stayed deferred after the countdown ended")
	# an unrelated live countdown never defers it
	var tgr2: Array = [{"source": "some_other_row", "ticks": 99, "shape":
			{"shape": "circle", "cx": 0.0, "cz": 0.0, "r": 2.0}}]
	if ArbiterScript.defer_answer(cfg, tgr2):
		f.append("gate: an unrelated countdown deferred the mark caller")
	# neither side's timer is stopped by the other (SR-4): the deferred row's own yard
	# keeps running - the gate only answers, it never mutates a state


# Vocabulary keys gate with values; absent vocabulary is always false - an empty row
# (no arbiter block) keeps a bare yes, and an unknown vocabulary blocks. A y band holds
# only when the shape carries one.
func _idless_and_optional(f: Array[String]) -> void:
	var p: PStub = PStub.new()
	var wf := Util.world_from_tiles([[0, 0, 0]])
	# no arbiter block in the row at all
	if not ArbiterScript.evaluate({}, p, wf, [])["may_appear"]:
		f.append("gate: a row with no arbiter block was blocked")
	# an explicit empty requirement list behaves the same
	if not ArbiterScript.evaluate({"appear_requires": [], "yields_to": []}, p, wf, [])["may_appear"]:
		f.append("gate: an empty requirement list was blocked")
	# unknown vocabulary blocks (never a silent yes)
	if ArbiterScript.evaluate({"appear_requires": [{"totally_unknown_req": true}]}, p,
			wf, [])["may_appear"]:
		f.append("gate: an unknown vocabulary requirement read as a yes")
	# a false-valued vocabulary entry holds
	if ArbiterScript.evaluate({"appear_requires": [{"no_targeted_telegraph": false}]}, p,
			wf, [])["may_appear"] == false:
		f.append("gate: a false-valued vocabulary entry was read as true")
	# a shape's own y band: a mark announced 3 u over the player's feet does not cover them
	var tgr: Array = [{"source": "x", "ticks": 9, "shape":
			{"shape": "circle", "cx": 0.5, "cz": 0.5, "r": 2.0, "y0": 2.0, "y1": 5.0}}]
	if ArbiterScript.telegraph_on_player(tgr, p):
		f.append("gate: the y band of a shape never applied (a high circle covered the feet)")
