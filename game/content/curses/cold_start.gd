extends RefCounted
#
# cold_start.gd — the Cold Start script curse (DESIGN.md section 7.2, GENERAL family;
# ticket T-051; the Athletic substitute fixed by D-062).
#
# Rule: "class ability starts each level on cooldown and recharges 25% slower (Athletic: coyote time −0.05 s instead)".
#
# on_level_start hits every player controller once per level through the documented
# state surface, never engine values:
#   - dasher:  dash_ready = false with dash_cd at the FULLY SLOWED regen (the ability is
#     on cooldown at level start), and the dash regen duration itself is x1.25 —
#     "recharges 25% slower" on a time-based regen is a longer regen (3.0 -> 3.75 s of
#     data/player.json dash_regen); the controller counts dash_cd down with plain dt, so
#     scaling the duration while keeping the countdown is the whole slow.
#   - glider:  glide_energy = 0.0 (the ability starts on cooldown; its only refill path
#     is landing, per data/player.json glide_energy_refill). [CONTESTABLE] — no rule
#     sentence states a numeric reward to slow a landing-refill; D-T051-3 pins the
#     reading "0 energy at level start, refill law unchanged".
#   - athletic: coyote time −0.05 s (0.10 -> 0.05, never below 0; D-062). Athletic has
#     no active ability, so the cooldown part has nothing to bite.
#
# The ×1.25 never touches jump velocity, gravity or run speed: the section 7 safety
# rule's budget is exactly as T-050's declarative batch asserts (Cold Start charges no
# run-speed cost — D-062).

const CURSE_ID := "cold_start"
const RECHARGE_SLOW := 1.25        # 25% slower regen: the duration is x1.25
const ATHLETIC_COYOTE_LOSS_S := 0.05  # D-062, verbatim: coyote time −0.05 s


## Stacks the run holds; >= 1 while the curse is picked (the sim's {curse_id: stacks}).
static func held_stacks(state: Dictionary) -> int:
	return int(state.get("curses_held", {}).get(CURSE_ID, 0))


## on_level_start(state, api): the level-begin hook. Reads state["players"] (the
## controllers); writes nothing outside them. Not held: the constants stay canon.
static func on_level_start(state: Dictionary, _api) -> void:
	if held_stacks(state) <= 0:
		return
	for ctl_v in state.get("players", []):
		var ctl = ctl_v
		if ctl == null:
			continue
		_cold_start_one(ctl)


# The per-controller body. The keys below are the controller's own documented fields
# (sim/controller.gd T-012): C (the constants dict), dash_ready/dash_cd, glide_energy.
static func _cold_start_one(ctl) -> void:
	var kit := str(ctl.get("kit"))
	if kit == "athletic":
		ctl["C"]["coyote_time"] = maxf(0.0, float(ctl["C"]["coyote_time"]) - ATHLETIC_COYOTE_LOSS_S)
		return
	# Dash is the only class kit with a time-based ability regen (dasher); the glider's
	# "cooldown" sentence is its 0 energy (see the header, D-T051-3).
	if kit == "dasher":
		ctl["C"]["dash_regen"] = float(ctl["C"]["dash_regen"]) * RECHARGE_SLOW
		ctl["dash_ready"] = false
		ctl["dash_cd"] = float(ctl["C"]["dash_regen"])
	elif kit == "glider":
		ctl["glide_energy"] = 0.0

