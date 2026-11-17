extends SceneTree
#
# answer_lab.gd - ticket T-075, piece 3 of 3: the answer lab.
#
#   <godot> --headless --path game --script res://tools/answer_lab.gd -- [--trials N]
#
# For each (enemy, micro-level) pair the section 2 pairing calls relevant: run
# TRIALS seeded trials at base stats, no upgrades, Last Light spent, with the
# answer bot playing ONLY the documented answer from answers.gd (the trigger
# event, then the inputs at their tick offsets, the 15-tick DELAY_TICKS) - then
# the same seeds with NO INPUT AT ALL. Prints, per pair: enemy, level, both
# survival rates, PASS/FAIL against the two bounds (>= 95 % answer, <= 5 %
# no-input). A failing pair is REPORTED, never tuned away.
#
# The answer bot shares answers.gd with T-026's --dodge (bot_run.gd): the table
# row's inputs ARE the bot's script; this file only picks the level, places the
# enemy, and re-anchors the row's tick offsets to the trigger event's tick.
#
# The pair list (which levels + why) and the approximations the harness makes
# are documented next to the PAIRS table and in DECISIONS.md's T-075 entries.

const Answers := preload("res://tools/bot/answers.gd")
const ControllerScript := preload("res://sim/controller.gd")
const CollisionScript := preload("res://sim/collision.gd")
const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const E_ADDRESS_ME := preload("res://content/enemies/address_me/enemy.gd")
const E_CLAUDE := preload("res://content/enemies/claude/enemy.gd")
const E_COIL := preload("res://content/enemies/coil/enemy.gd")
const E_GIFT_LARPER := preload("res://content/enemies/gift_larper/enemy.gd")
const E_GIN := preload("res://content/enemies/gin/enemy.gd")
const E_ISAGI := preload("res://content/enemies/isagi/enemy.gd")
const E_KIWI_CAT := preload("res://content/enemies/kiwi_cat/enemy.gd")
const E_NUKE := preload("res://content/enemies/nuke/enemy.gd")
const E_SEAL := preload("res://content/enemies/seal/enemy.gd")
const E_THICC_BEN := preload("res://content/enemies/thicc_ben/enemy.gd")
const E_TOUCHER := preload("res://content/enemies/toucher/enemy.gd")
const E_YOU := preload("res://content/enemies/you/enemy.gd")

const DT := 1.0 / 60.0
const TRIALS := 200
# Per-trial window (ticks). 600 = 10 s: the exchange itself (telegraph + the
# answer's 15-tick reaction + the danger's resolution) fits well inside; the
# F8 combos get 1500 because the address me episode opens through the SR-4
# gate (never in the first 600 ticks, waits for quiet). A larger window cannot
# rescue a dead player - the death is recorded the tick it happens - so the
# endpoint is well defined: alive at the window's END.
const WINDOW_TICKS := 600
const WINDOW_COMBO := 1500
const PRESS_TICKS := 3              # the jump's button hold, one press
const MOVE_TICKS_MAX := 60          # a movement input runs at most 1.0 s
# no upgrades, Last Light spent (the done-when): the controller's safety net
# is disabled for every trial.
const LAST_LIGHT_SPENT := true

static var TRACE := false           # --trace: print each trial's death cause


# --------------------------------------------------------------- pairs --

## The (enemy, level) pairs, from research/fable-enemies.md section 2's pairing
## table (its levels, mapped to the five micro-levels):
##   kiwi cat   "dead-end nook and spire; long step runs" -> nook + flat_lane
##   coil       "pad, disc, nook, the hub" -> hub + flat_lane (the 1-wide worst case)
##   thicc ben  "step/ledge walkways 1 wide" -> flat_lane
##   seal       "long straight flat/step walkways (lane)" -> flat_lane
##   YOU?!      "the hub, pad, disc" -> hub + flat_lane worst case
##   nuke       "the hub and pad/disc clusters" -> hub + flat_lane
##   gift larper "dead-end clusters and platforms" -> flat_lane + hub
##   toucher    "2-wide step walkways" -> flat_lane
##   address me "anywhere the player is committed" -> flat_lane
##   Isagi      per-walkway/pad archetypes -> flat_lane (the F6 worst case)
##              + stepped_lane (the 2 HU step good case)
##   Claude     "the hub and pad/disc" -> flat_lane (drums reach anywhere)
##   gin        "1-2 wide walkways between sub-areas" -> flat_lane
## Levels section 2 does not name are noted in DECISIONS.md (D-T075-3).
## telegraph: the row kind that starts the answer ("release" for isagi = the
## aim row's release flash, 1.2 s after the cue, answers.gd's own anchor).
## Extra knobs, each read from the doc's own arithmetic (D-T075-4, [CONTESTABLE]):
##   lag         ticks AFTER the anchor the first input lands. Default the
##               addendum's DELAY_TICKS. "ON the cue" rows (seal: "jump ON the
##               bark", claude: "jump on the beat") get 0 - the doc says ON.
##               you: 75 - the cue is the 90-tick rumble's END (the ring
##               releases there; the doc's answer times the jump to the ring,
##               "as the ring reaches you" - 5/6 of the rumble in).
##               isagi: here the lag = the aim row's wind-up (read live) + 3,
##               the release flash - the answers.gd entry's own anchor.
##   lead        body-reach triggers (the run's own arrival anchor). kiwi
##               "hurdle it as it arrives": 1.6 u (bot_run's hurdle bar). The
##               toucher's 1.4 u body needs a slightly wider lead: 2.4 u, which
##               at its 6.75 u/s is the ~0.2 s the jump's rise to 1.4 u needs.
##   move_ticks  how long a movement input persists (default 60). The nuke's
##               ring follows 2.5 s before it stops - the answer must KEEP the
##               distance until the follow ends: 220 ticks.
static func _pairs() -> Array:
	return [
		{"enemy": "kiwi_cat", "level": "flat_lane", "telegraph": "meow", "standoff": 8.0, "lead": 1.6},
		{"enemy": "kiwi_cat", "level": "nook", "telegraph": "meow", "standoff": 6.0, "lead": 1.6},
		{"enemy": "coil", "level": "flat_lane", "telegraph": "coil_ring", "standoff": 6.0},
		{"enemy": "coil", "level": "hub", "telegraph": "coil_ring", "standoff": 6.0},
		{"enemy": "thicc_ben", "level": "flat_lane", "telegraph": "teleport", "standoff": 6.0},
		{"enemy": "seal", "level": "flat_lane", "telegraph": "bark", "standoff": 5.0, "lag": 0},
		{"enemy": "you", "level": "flat_lane", "telegraph": "you_rumble", "standoff": 6.0, "lag": 75},
		{"enemy": "nuke", "level": "flat_lane", "telegraph": "ground_ring", "standoff": 10.0, "move_ticks": 220},
		{"enemy": "gift_larper", "level": "flat_lane", "telegraph": "gift_larper", "standoff": 4.0},
		{"enemy": "gift_larper", "level": "hub", "telegraph": "gift_larper", "standoff": 4.0},
		{"enemy": "toucher", "level": "flat_lane", "telegraph": "toucher_pulse", "standoff": 6.0, "lead": 2.4},
		{"enemy": "address_me", "level": "flat_lane", "telegraph": "address_me", "standoff": 0.0},
		{"enemy": "isagi", "level": "flat_lane", "telegraph": "aim", "standoff": 7.0},
		{"enemy": "isagi", "level": "stepped_lane", "telegraph": "aim", "standoff": 7.0},
		{"enemy": "claude", "level": "flat_lane", "telegraph": "drum_ring", "standoff": 8.0, "lag": 0},
		{"enemy": "gin", "level": "flat_lane", "telegraph": "mark", "standoff": 10.0},
	]


## The three F8 combination cases (section 0, F8: address me's countdown runs
## while a chaser closes / a nuke ring stops / a gin patch marks; F8's own
## scheduling gate in address_me/enemy.gd decides whether the episode may open
## at all - the combos measure the co-arrival, with the gate live as shipped).
static func _combos() -> Array:
	return [
		{"enemy": "kiwi_cat + address_me", "level": "flat_lane", "telegraph": "meow", "standoff": 8.0, "extra": "address_me"},
		{"enemy": "nuke + address_me", "level": "flat_lane", "telegraph": "ground_ring", "standoff": 10.0, "extra": "address_me"},
		{"enemy": "gin + address_me", "level": "flat_lane", "telegraph": "mark", "standoff": 10.0, "extra": "address_me"},
	]


## The stacked cases: the same enemy at the proposed cap (the per-enemy
## max_votes from data/offering_schedule.json's "enemies" gate block, the
## chaser ceiling 6 separately - the stacks below stay under it, except kiwi's
## 4 + nothing else is a chaser). Copies spawn on a line east of the spawn.
## Stacks of address me / claude are not meaningful (the one-at-a-time gate /
## cap 1 in the schedule) - skipped here, noted in D-T075-3.
static func _stacked() -> Array:
	return [
		{"enemy": "kiwi_cat", "level": "flat_lane", "telegraph": "meow", "standoff": 8.0, "lead": 1.6, "copies": 4},
		{"enemy": "coil", "level": "hub", "telegraph": "coil_ring", "standoff": 6.0, "copies": 3},
		{"enemy": "thicc_ben", "level": "flat_lane", "telegraph": "teleport", "standoff": 6.0, "copies": 2},
		{"enemy": "seal", "level": "flat_lane", "telegraph": "bark", "standoff": 5.0, "lag": 0, "copies": 3},
		{"enemy": "you", "level": "flat_lane", "telegraph": "you_rumble", "standoff": 6.0, "lag": 75, "copies": 2},
		{"enemy": "nuke", "level": "flat_lane", "telegraph": "ground_ring", "standoff": 10.0, "move_ticks": 220, "copies": 2},
		{"enemy": "isagi", "level": "flat_lane", "telegraph": "aim", "standoff": 7.0, "copies": 2},
		{"enemy": "toucher", "level": "flat_lane", "telegraph": "toucher_pulse", "standoff": 6.0, "lead": 2.4, "copies": 2},
		{"enemy": "gift_larper", "level": "hub", "telegraph": "gift_larper", "standoff": 4.0, "copies": 5},
		{"enemy": "gin", "level": "flat_lane", "telegraph": "mark", "standoff": 10.0, "copies": 3},
	]


# ------------------------------------------------------------------ main --

func _init() -> void:
	var trials := TRIALS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--trials="):
			trials = int(a.split("=")[1])
		if a == "--trace":
			TRACE = true
	print("ANSWER LAB: %d trials per pair" % trials)
	print("pairs: enemy on level | answer %% | no-input %% | PASS/FAIL")
	var failures: Array = []
	for cfg in _pairs():
		_one_pair(cfg, trials, failures)
	for cfg in _stacked():
		_one_pair(cfg, trials, failures, true)
	for cfg in _combos():
		_one_pair(cfg, trials, failures, true)
	print("")
	print("PAIRS FAILING A BOUND: %d" % failures.size())
	for fline in failures:
		print("  %s" % fline)
	print("DONE")
	quit(0)   # ...always: a measurement, not a gate (the SceneTree would idle otherwise)


# ------------------------------------------------------ test-facing API --

static func pairs() -> Array:
	return _pairs()


static func combos() -> Array:
	return _combos()


static func trial(cfg: Dictionary, seed_i: int, p_answer_mode: bool) -> Dictionary:
	return _trial(cfg, seed_i, p_answer_mode)


## The two bounds of the done-when: >= 95 % survive WITH the documented answer,
## <= 5 % survive with no input (the enemy must actually be dangerous).
static func bounds_ok(ans_pct: int, nop_pct: int) -> bool:
	return ans_pct >= 95 and nop_pct <= 5


static func _one_pair(cfg: Dictionary, trials: int, failures: Array, combo := false) -> void:
	var ans_surv := 0
	var nop_surv := 0
	for i in trials:
		if _trial(cfg, 1000 + i, true).get("survived", false):
			ans_surv += 1
		if _trial(cfg, 1000 + i, false).get("survived", false):
			nop_surv += 1
	var ans_pct := int(round(100.0 * float(ans_surv) / float(trials)))
	var nop_pct := int(round(100.0 * float(nop_surv) / float(trials)))
	var ok := ans_pct >= 95 and nop_pct <= 5
	var line := "%s on %s: answer=%d%% no-input=%d%% %s" % [
		str(cfg["enemy"]), str(cfg["level"]), ans_pct, nop_pct, "PASS" if ok else "FAIL"]
	print(line)
	if not ok:
		failures.append(line)


# --------------------------------------------------------------- the trial --

## One seeded trial. p_answer_mode: the documented answer when true, no input
## at all when false. Returns {"survived": bool, "armed": bool, "death_t": int}
## (death_t = -1 when alive) - the diagnostics let tests assert the MECHANISM
## (the trigger arms, the inputs were carried) without re-running the sweep.
static func _trial(cfg: Dictionary, seed_i: int, p_answer_mode: bool) -> Dictionary:
	var labs := load("res://tools/bot/micro_levels.gd")
	var L: Dictionary = labs.build(str(cfg["level"]))
	var w: Dictionary = CollisionScript.make_world(L["tiles"], L["props"], L["pads"],
			{"dais": L["beacon"]})
	var lv = preload("res://sim/level_state.gd").build(L, 1, 1)
	var ctl = ControllerScript.new()
	ctl.setup("dasher", ControllerScript.load_constants())
	ctl.place(w)
	ctl.last_light_spent = LAST_LIGHT_SPENT
	var rt = EnemyRuntime.new()
	rt.setup(L, w, [ctl], seed_i * 7919 + 13, {"spawn_delay_ticks": 1})
	# enemies: the pair's enemy at its standoff east of the spawn (the nuke's
	# ring follows the player wherever the launcher stands, so any tile works),
	# plus the F8 combo's address me, which spawns and gates itself. A body's
	# y is the GROUND of the tile it lands on - never a hard-coded height.
	var sx: float = float(ctl.x)
	var sz: float = float(ctl.z)
	var eid := str(cfg["enemy"]).split(" + ")[0]
	var n_copies: int = int(cfg.get("copies", 1))
	for k in n_copies:
		if float(cfg["standoff"]) <= 0.0:
			break
		var eg: Variant = lv.ground_at(sx + float(cfg["standoff"]) + 3.0 * float(k), sz)
		var ey: float = float(eg) if eg != null else 0.0
		rt.spawn_at(eid, eid, behavior_for(eid), _cfg(eid),
				Vector3(sx + float(cfg["standoff"]) + 3.0 * float(k), ey, sz))
	if cfg.has("extra"):
		rt.spawn_at(str(cfg["extra"]), str(cfg["extra"]), behavior_for(str(cfg["extra"])),
				_cfg(str(cfg["extra"])), Vector3(sx - 3.0, 0.0, sz))
	# the answer state: one documented answer, armed by the trigger event
	var window: int = WINDOW_COMBO if cfg.has("extra") else WINDOW_TICKS
	var armed := false
	var arm_at := -1
	var fired := {}
	var threat := Vector2.ZERO
	for t in range(window):
		var a_in: Dictionary = {"move_x": 0, "move_z": 0, "buttons": 0,
				"aim_x": 0.0, "aim_z": 1.0}
		if p_answer_mode:
			var trig: Variant = _trigger_tick(cfg, rt, fired, ctl)
			if trig != null and not armed:
				armed = true
				var lag_v: Variant = cfg.get("lag", fired.get("lag", Answers.DELAY_TICKS))
				arm_at = t + int(lag_v)
				threat = trig
				if TRACE:
					print("    seed %d: TRIGGER t=%d threat=(%.1f,%.1f)" % [seed_i, t, threat.x, threat.y])
			if armed:
				_play_answer(a_in, cfg, t - arm_at, ctl, threat)
		var ev: Array = []
		for e in ctl.step(DT, a_in, w):
			ev.append(e)
		var p0: Dictionary = lv.players[0]
		p0["x"] = ctl.x
		p0["y"] = ctl.y
		p0["z"] = ctl.z
		p0["vx"] = ctl.vx
		p0["vz"] = ctl.vz
		lv.tick += 1
		for e in rt.step(DT):
			ev.append(e)
		if ctl.dead:
			if TRACE:
				print("    seed %d: dead at t=%d by %s (%s) y=%.2f" % [
					seed_i, t, str(ctl.dead_killer), str(ctl.dead_code), float(ctl.y)])
			return {"survived": false, "armed": armed, "death_t": t}
	return {"survived": true, "armed": armed, "death_t": -1}


## Detect the pair's trigger. Returns the threat point (the telegraph row's own
## centre - coil's landing ring, ben's smoke, gin's patch, the ring's origin)
## or Vector2.ZERO when no trigger this tick. The release lag and no silent
## defaults: a kind the table does not implement arms nothing.
static func _trigger_tick(cfg: Dictionary, rt, fired: Dictionary, ctl) -> Variant:
	var kind := str(cfg["telegraph"])
	if kind == "address_me":
		for e in rt.enemies:
			if str(e.get("id", "")) == "address_me" and str(e.get("anim_state", "")) == "telegraph":
				return Vector2(float(e["x"]), float(e["z"]))
		return null
	if kind == "gift_larper":
		for e in rt.enemies:
			if str(e.get("id", "")) == "gift_larper":
				var d := Vector2(float(e["x"]) - float(ctl.x), float(e["z"]) - float(ctl.z))
				if d.length() < 12.0:
					var f: Variant = fired.get("larper_seen", -9999)
					if int(rt.tick) - int(f) >= 60:
						fired["larper_seen"] = int(rt.tick)
						return Vector2(float(e["x"]), float(e["z"]))
		return null
	if kind == "meow" or kind == "toucher_pulse":
		# body-reach answers ("as it arrives" / the hurdle): the trigger is the
		# enemy's body closing to the pair's lead distance, grounded. The lead
		# (the pair's own "lead") is the doc's arrival reading: kiwi 1.6 u
		# (bot_run's hurdle bar), toucher 2.4 u (its 1.4 u body needs the
		# jump's rise airtime).
		var lead: float = float(cfg.get("lead", 1.6))
		for e in rt.enemies:
			if str(e.get("id", "")) != _pair_enemy(cfg):
				continue
			var d := Vector2(float(e["x"]) - float(ctl.x), float(e["z"]) - float(ctl.z))
			if bool(ctl.grounded) and d.length() < lead:
				return Vector2(float(e["x"]), float(e["z"]))
		return null
	var key := ""
	for tg in rt.telegraphs:
		if str(tg.get("kind", "")) != kind:
			continue
		var shape: Dictionary = tg.get("shape", {})
		if kind == "ground_ring":
			# track the ring while it follows (rows never expire)
			var now := Vector2(float(shape.get("cx", float(ctl.x))), float(shape.get("cz", float(ctl.z))))
			var c1: Variant = fired.get("ring_c", null)
			if c1 != null and (c1 as Vector2).distance_to(now) < 0.01:
				fired["ring_same"] = int(fired.get("ring_same", 0)) + 1
				# the ring stopped: the answer's window opens
				if int(fired.get("ring_same", 0)) >= 30:
					fired["ring_same"] = 0
					fired["ring_c"] = null
					return now
			else:
				fired["ring_same"] = 0
			fired["ring_c"] = now
			continue
		if kind == "aim" and not fired.has("lag"):
			# isagi: the answer starts after the release flash - the aim row's
			# total is the wind-up; +3 ticks is the flash
			fired["lag"] = int(tg.get("total", 0)) + 3
			continue
		key = "seen@%s@%d" % [kind, int(tg.get("tick", -1))]
		if fired.has(key):
			continue
		fired[key] = true
		if shape.has("cx"):
			return Vector2(float(shape["cx"]), float(shape["cz"]))
		if shape.has("fx"):
			return Vector2(float(shape["fx"]), float(shape["fz"]))
		return Vector2(float(ctl.x), float(ctl.z))
	return null


## Play the documented answer: the moves in table[enemy].inputs, carried at
## (anchor + DELAY_TICKS + tick_offset). Movement persists until its clear
## distance or MOVE_TICKS_MAX; a jump is one press. step_behind_rise and
## move_out_of_patch collapse into the same run-away the table's note describes
## for them (the lanes have one escape direction); stop plays nothing.
static func _play_answer(a_in: Dictionary, cfg: Dictionary, since: int, ctl,
		threat: Vector2) -> void:
	var ins: Array = Answers.inputs_for(_pair_enemy(cfg))
	for inp in ins:
		var act: String = str(inp.get("action", ""))
		if act == "stop":
			return
		var want: int = int(inp.get("tick_offset", 0))
		if since >= want:
			if act == "jump":
				if since - want < PRESS_TICKS:
					a_in["buttons"] = 1
					return
			elif act == "move_out" or act == "move_around" \
					or act == "move_out_of_patch" or act == "step_behind_rise":
				var dur: int = int(cfg.get("move_ticks", MOVE_TICKS_MAX))
				if since - want < dur:
					var away := Vector2(float(ctl.x), float(ctl.z)) - threat
					if away.length() < 0.05:
						away = Vector2(1.0, 0.0)
					away = away.normalized()
					a_in["move_x"] = int(round(away.x * 127.0))
					a_in["move_z"] = int(round(away.y * 127.0))
					return
	# the answer's windows have all closed: inputs stay off


static func _pair_enemy(cfg: Dictionary) -> String:
	return str(cfg["enemy"]).split(" + ")[0]


## The content behavior constructor - one match, no bare class names (the
## run_all convention; the same map bot_run.gd carries).
static func behavior_for(id: String) -> RefCounted:
	match id:
		"address_me": return E_ADDRESS_ME.new()
		"claude": return E_CLAUDE.new()
		"coil": return E_COIL.behavior()
		"gift_larper": return E_GIFT_LARPER.GiftLarperBehavior.new()
		"gin": return E_GIN.new()
		"isagi": return E_ISAGI.Behavior.new()
		"kiwi_cat": return E_KIWI_CAT.KiwiCatBehavior.new()
		"nuke": return E_NUKE.new()
		"seal": return E_SEAL.SealBehavior.new()
		"thicc_ben": return E_THICC_BEN.new_behavior()
		"toucher": return E_TOUCHER.behavior()
		"you": return E_YOU.new()
	return null


## The runtime cfg (the flat enemy.json stats the behaviors read; identical to
## bot_run.gd's own reader, kept local so bots do not import tool code).
static func _cfg(id: String) -> Dictionary:
	var api = preload("res://core/content_api.gd").load()
	var entry: Dictionary = api.enemy(id)
	var stats: Dictionary = (entry.get("stats", {}) as Dictionary).duplicate(true)
	for key in ["contact_kill", "preferred_kind", "arbiter"]:
		if entry.has(key) and not stats.has(key):
			stats[key] = entry[key]
	stats["id"] = id
	stats["name"] = str(entry.get("name", id))
	stats["votes"] = 1
	stats["level_number"] = 1
	return stats


