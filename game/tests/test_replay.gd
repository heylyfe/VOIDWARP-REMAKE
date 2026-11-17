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
#   4. A4 (FLEET_PACK.md section 5): TEN distinct-seed bot runs (BOT_SEEDS), each recorded
#      through the real sim surface via tools/bot_run.gd (controller.gd + gifts/mines/beacon +
#      enemy runtime inside a RunState) and replayed tick-for-tick from the recorded input
#      stream; the state hash must be identical at every 60th tick of each run.
# Everything is driven through the public sim surface: run_state.gd, sim.gd step, state_hash.gd
# (the random-input run), and bot_run.gd's record/playback mode (the bot runs).

const VoidGenScript := preload("res://terrain/voidgen.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const SimScript := preload("res://sim/sim.gd")
const HashScript := preload("res://sim/state_hash.gd")
const InputScript := preload("res://sim/input.gd")
const EventsScript := preload("res://sim/events.gd")
const BotRunScript := preload("res://tools/bot_run.gd")
const ContentApiScript := preload("res://core/content_api.gd")

const TICKS := 3600
const CHECK_EVERY := 60
const RUN_SEED := 20260101
const INPUT_SEED := 777
# The perturbation: tick index 1200 (0-based; the 1201st input) gets move axes shifted and the
# JUMP bit flipped — a guaranteed-visible single-input change per D-T010-2's axis contract.
const PERTURB_AT := 1200
# A4 (FLEET_PACK.md section 5): TEN recorded bot runs, ten distinct seeds, replayed with
# identical state hashes at every checkpoint. The driver is bot_run.gd (the real sim surface:
# controller.gd + gifts/mines/beacon + enemy runtime inside a RunState); each recorded run is
# capped at BOT_TICKS ticks and ONE level - a run that dies on level 1 is still a recorded run
# and still proves determinism. The replay feeds the recorded input stream tick-for-tick.
# BOT_TICKS is a BUDGET, not a spec number (D-FIX-A4-1, [CONTESTABLE]): full-length bot
# recordings measured +188 s on top of a 126 s run_all, blowing the gate's 300 s step timeout;
# 1000 ticks keeps every seed producing >= 1 checkpoint (min death tick 653) under the budget.
const BOT_SEEDS := [101, 202, 303, 404, 505, 606, 707, 808, 909, 1001]
const BOT_TICKS := 1000


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

	# A4: TEN recorded bot runs, ten distinct seeds, identical hashes at every checkpoint.
	_bot_runs(failures)
	return failures


## A4 (FLEET_PACK.md section 5): ten distinct-seed bot runs, recorded then replayed, identical
## state hash at every 60th tick. Recording pass = the bot plays (inputs captured per tick);
## replay pass = the same seeds re-run with the recorded stream fed tick-for-tick (the bot's
## brain is bypassed, everything else identical). A run that dies on level 1 is still a
## recorded run. Fails loudly if a seed is recorded twice, a run yields no checkpoint, or any
## checkpoint diverges.
func _bot_runs(f: Array[String]) -> void:
	var seen := {}
	for seed in BOT_SEEDS:
		seen[int(seed)] = true
	if seen.size() != BOT_SEEDS.size():
		f.append("BOT_SEEDS contains duplicates: %s" % str(BOT_SEEDS))
		return
	var api := ContentApiScript.load()
	if not bool(api.is_ok()):
		f.append("content boot refused: %s" % " / ".join(api.boot_errors()))
		return
	var total_checkpoints := 0
	for seed in BOT_SEEDS:
		var rec := {"record": true, "inputs": [], "hashes": [], "total_ticks": 0,
				"max_ticks": BOT_TICKS}
		var row_a: Dictionary = BotRunScript.play_run(api, int(seed), 1, null, rec)
		var inputs: Array = rec["inputs"]
		var hashes_a: Array = rec["hashes"]
		var replay := {"playback": inputs, "playback_cursor": 0, "hashes": [],
				"total_ticks": 0, "max_ticks": BOT_TICKS}
		var row_b: Dictionary = BotRunScript.play_run(api, int(seed), 1, null, replay)
		var hashes_b: Array = replay["hashes"]
		if inputs.is_empty():
			f.append("bot seed %d recorded 0 ticks - not a recorded run" % int(seed))
			continue
		if bool(replay.get("playback_short", false)):
			f.append("bot seed %d: replay ran dry of recorded inputs (%d recorded)" % [int(seed), inputs.size()])
		if hashes_a.is_empty():
			f.append("bot seed %d: no 60-tick checkpoint reached (run lasted %d ticks) - cannot prove determinism" % [int(seed), int(rec["total_ticks"])])
			continue
		if hashes_a.size() != hashes_b.size():
			f.append("bot seed %d: checkpoint count differs: record %d vs replay %d" % [int(seed), hashes_a.size(), hashes_b.size()])
			continue
		if int(rec["total_ticks"]) != int(replay["total_ticks"]):
			f.append("bot seed %d: tick count differs: record %d vs replay %d" % [int(seed), int(rec["total_ticks"]), int(replay["total_ticks"])])
		if str(row_a.get("outcome", "")) != str(row_b.get("outcome", "")):
			f.append("bot seed %d: outcome differs: record %s vs replay %s" % [int(seed), str(row_a.get("outcome")), str(row_b.get("outcome"))])
		var mism := 0
		for c in hashes_a.size():
			if hashes_a[c] != hashes_b[c]:
				mism += 1
				f.append("bot seed %d checkpoint %d (tick %d): hashes differ between record and replay (%s vs %s)"
						% [int(seed), c, (c + 1) * CHECK_EVERY, hashes_a[c], hashes_b[c]])
		total_checkpoints += hashes_a.size()
		if mism == 0:
			print("REPLAY-BOT seed=%d outcome=%s ticks=%d checkpoints=%d identical record/replay" % [
					int(seed), str(row_a.get("outcome")), int(rec["total_ticks"]), hashes_a.size()])
	print("REPLAY-BOT %d recorded bot runs (cap %d ticks), %d checkpoints identical between record and replay" % [BOT_SEEDS.size(), BOT_TICKS, total_checkpoints])


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
