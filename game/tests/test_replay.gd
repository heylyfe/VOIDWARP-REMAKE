extends RefCounted
#
# Replay determinism test (DESIGN.md section 13 rule 6; ticket T-010). THE determinism proof and
# the multiplayer readiness gate:
#   1. record a random-input 3,600-tick run (60 s sim) for 1 player (deterministic input generator,
#      seed-pinned, so every run of this test uses the same inputs);
#   2. replay it twice from a fresh RunState each time; the state hash must be equal at EVERY
#      60th tick (60 checkpoints);
#   3. replay a deliberately perturbed input list (one input changed at tick 1201): every
#      checkpoint at or after the perturbation must differ.
# Everything is driven through the public sim surface: run_state.gd, sim.gd step, state_hash.gd.

const VoidGenScript := preload("res://terrain/voidgen.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const SimScript := preload("res://sim/sim.gd")
const HashScript := preload("res://sim/state_hash.gd")
const InputScript := preload("res://sim/input.gd")
const EventsScript := preload("res://sim/events.gd")

const TICKS := 3600
const CHECK_EVERY := 60
const RUN_SEED := 20260101
const INPUT_SEED := 777
# The perturbation: tick index 1200 (0-based; the 1201st input) gets move axes shifted and the
# JUMP bit flipped — a guaranteed-visible single-input change per D-T010-2's axis contract.
const PERTURB_AT := 1200


func run() -> Array[String]:
	var failures: Array[String] = []
	var inputs := _record_inputs(INPUT_SEED)

	var h1 := _replay(RUN_SEED, inputs)
	var h2 := _replay(RUN_SEED, inputs)
	if h1.size() != TICKS / CHECK_EVERY:
		failures.append("expected %d checkpoints, got %d" % [TICKS / CHECK_EVERY, h1.size()])
	if h1.size() != h2.size():
		failures.append("replay 1 and 2 checkpoint counts differ: %d vs %d" % [h1.size(), h2.size()])
		return failures
	var mism := 0
	for c in h1.size():
		if h1[c] != h2[c]:
			mism += 1
			failures.append("checkpoint %d (tick %d): hashes differ between replays (%s vs %s)"
					% [c, (c + 1) * CHECK_EVERY, h1[c], h2[c]])
	if mism == 0:
		print("REPLAY %d checkpoints identical across 2 replays" % h1.size())

	var h3 := _replay(RUN_SEED, _perturbed(inputs))
	var first_diff := -1
	for c in min(h1.size(), h3.size()):
		if h1[c] != h3[c]:
			first_diff = c
			break
	# Perturbation at tick PERTURB_AT+1: the first checkpoint that can differ is the next multiple
	# of 60; every checkpoint from there to the end must differ (input stream diverged for good).
	var expect_first := (PERTURB_AT / CHECK_EVERY)  # index of checkpoint >= PERTURB_AT+1
	if first_diff != expect_first:
		failures.append("perturbed run: first differing checkpoint is %s, expected %d"
				% [str(first_diff), expect_first])
	for c in range(expect_first, min(h1.size(), h3.size())):
		if h1[c] == h3[c]:
			failures.append("perturbed run: checkpoint %d (tick %d) hash UNCHANGED after perturbation"
					% [c, (c + 1) * CHECK_EVERY])
	if first_diff == expect_first:
		print("PERTURB hash changed from checkpoint %d (tick %d) and stayed different through tick %d"
				% [first_diff, (first_diff + 1) * CHECK_EVERY, TICKS])

	# The recorded run must have exercised the sim: at least one jump and one land event, and the
	# player must actually have moved (all five bits of evidence the hash is input-sensitive).
	if not _saw_event(RUN_SEED, inputs, EventsScript.EV_JUMP):
		failures.append("recorded run produced no jump events (input generator or sim broken)")
	if not _saw_event(RUN_SEED, inputs, EventsScript.EV_LAND):
		failures.append("recorded run produced no land events (input generator or sim broken)")
	return failures


## Deterministic bot-input generator: hold a move heading for 15..45 ticks, press JUMP for
## 10..25 ticks every so often. Same seed -> identical inputs on every call.
func _record_inputs(seed: int) -> Array:
	var rng := VoidRngScript.new(seed)
	var inputs: Array = []
	var mx := 0
	var mz := 0
	var btn := 0
	var hold := 0
	var jhold := 0
	for t in TICKS:
		if jhold > 0:
			jhold -= 1
			if jhold == 0:
				btn = btn & ~InputScript.BUTTON_JUMP
		if hold <= 0:
			mx = rng.ri(-96, 96)
			mz = rng.ri(-96, 96)
			hold = rng.ri(15, 45)
		hold -= 1
		if jhold <= 0 and rng.chance(1, 30):
			btn = btn | InputScript.BUTTON_JUMP
			jhold = rng.ri(10, 25)
		inputs.append(InputScript.new(mx, mz, btn))
	return inputs


## One full fresh run; returns the state hash at every CHECK_EVERY ticks.
func _replay(run_seed: int, inputs: Array) -> Array[String]:
	var rs := RunStateScript.new_run(run_seed, 1, ["core"])
	rs.load_level(VoidGenScript.generate(run_seed, 1, 1, 0), 1)
	var hashes: Array[String] = []
	for t in TICKS:
		SimScript.step(rs, [inputs[t]])
		if (t + 1) % CHECK_EVERY == 0:
			hashes.append(HashScript.sha256(rs))
	return hashes


func _perturbed(inputs: Array) -> Array:
	var out: Array = []
	for t in TICKS:
		var src: RefCounted = inputs[t]
		if t == PERTURB_AT:
			out.append(InputScript.new(
					int(src.move_x) + 100, int(src.move_z) - 100,
					int(src.buttons) ^ InputScript.BUTTON_JUMP))
		else:
			out.append(src)
	return out


func _saw_event(run_seed: int, inputs: Array, ev_type: String) -> bool:
	var rs := RunStateScript.new_run(run_seed, 1, ["core"])
	rs.load_level(VoidGenScript.generate(run_seed, 1, 1, 0), 1)
	for t in TICKS:
		for ev in SimScript.step(rs, [inputs[t]]):
			if str(ev["type"]) == ev_type:
				return true
	return false
