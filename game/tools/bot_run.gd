extends SceneTree
#
# bot_run.gd - difficulty band probe (ticket T-060; DESIGN.md section 9 "Targets for the
# tuning bot"). Runs the REAL sim against a scripted "competent" bot for N runs with
# seeded random votes and reports the reach-rates for levels 6 / 12 / 18 against the
# frozen bands (DESIGN.md section 9; FROZEN - never changed, terrain thresholds never
# changed):
#
#   <godot> --headless --path game --script res://tools/bot_run.gd -- [--dodge] [--runs N] [--seed-base S] [--max-level N]
#
#   --dodge      the only dodge policy there is; accepted explicitly because the ticket
#                names it (FLEET_PACK.md section 6, T-060). The bot always dodges.
#   --runs N     runs to play (default 200). The gate never calls this; the T-060 test
#                calls run_probe(3, ...) directly.
#   --seed-base  first run seed (default SEED_BASE). Run i uses seed_base + i, so the
#                whole sweep is reproducible; every per-run line prints the seed.
#   --max-level  stop a run once it ENTERS this level (default 18; the bands need no more).
#
# The bot (the whole spec, nothing more):
#   - drives the real sim per tick: controller.gd for the player (the T-012 controller;
#     sim/sim.gd's T-010 placeholder kinematics is superseded by it, its header says so),
#     enemy_runtime.gd for enemies, mines.gd / gifts.gd / beacon.gd through their
#     controller-driven contracts (the caller drives them, as designed), LevelState for
#     the level slice, intermission.gd for the lobby (votes ARE inputs, DESIGN.md
#     section 13 rule 2). The bot is a client of the sim: no "bot mode" is added to it,
#     nothing is forked or reimplemented.
#   - nearest-gift routing: pathfinds on the TERRAIN_SPEC section 5.2 movement graph
#     (walk + jump edges, reused from terrain/voidgen.gd's own movement()) from the
#     player's tile to the nearest REACHABLE uncollected black gift (weighted route,
#     tie-break slot id); re-paths on collection / phase change / every REPLAN_TICKS /
#     after any landing; when the beacon is open, routes to the beacon tile instead.
#     Edge discipline (FIX-A3, D-FIX-A3-1): every edge that is not a same-level walk
#     is a committed manoeuvre over air, so the route pays for air time (Dijkstra
#     costs; the walkable route is preferred, a deep drop costs the most) and a
#     non-walk edge is only followed when the controller's own jump physics (the
#     TERRAIN_SPEC section 5.1 envelope, forward-simulated in _jump_arc) validates an
#     arc that lands on a tile - otherwise the edge is banned and the route re-plans.
#     The bot never "walks off and prays", and the dodge escape is picked so it keeps
#     ground support instead of running straight off a ledge into the void.
#   - dodges telegraphs with a 250 ms reaction: the enemy runtime's telegraph dicts
#     (the ones the view draws) are tracked from the tick they first appear; the bot
#     reacts REACT_TICKS = 15 ticks LATER (60 Hz; a bot that reacts on the tick a
#     telegraph appears measures nothing). Only real footprints count (circle r > 0,
#     ring, box; zero-radius cues like "meow"/"dash_line" are not footprints). The
#     feet point inside the (body-inflated) footprint picks the most imminent strike;
#     the escape runs straight out of the shape (circle/ring) or across its thinnest
#     side (box). Hazards that never telegraph (contact kills, mines, the nuke's
#     descent) are part of the game the bot plays; they are not telegraph-dodged.
#   - seeded random votes: every lobby bay is resolved by a uniform random draw from
#     the run's own seeded stream (class included), so the 200 runs are reproducible
#     and every printed seed reproduces its run. The bot buys nothing (no upgrade /
#     REST purchase policy is invented); curses with a direct sim knob are applied
#     (rush_hour + hunger -> curse_speed_mul; long_night -> overtime_period;
#     brittle -> respawn delay/invulnerability; hungry_void -> charge cap 1;
#     early_bird -> 2 s spawn delay; understudies -> +4 flat extra mines per stack);
#     every other curse/upgrade has no knob in the sim today and is NOT applied -
#     see DECISIONS.md (D-T060-x) and tickets/T-060.response.md.
#   - hurdles a contact-kill enemy within 1.6 u horizontally while grounded (the roster's
#     own counter-play: a human jumps the cat; the bot never jumps THROUGH one on purpose).
#   - death = the run ends. Dying is the outcome the bands measure; it is never
#     treated as an error of the probe.
#
# Determinism: run i uses seed SEED_BASE + i; level gen, lobby draws, bot votes,
# enemy spawns/rows and tile paths are all functions of that seed. Same seed set,
# same numbers, twice in a row (asserted by game/tests/test_bot_run.gd with 3 runs).
#
const ContentApiScript := preload("res://core/content_api.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const CollisionScript := preload("res://sim/collision.gd")
const ControllerScript := preload("res://sim/controller.gd")
const RunStateScript := preload("res://sim/run_state.gd")
const Intermission := preload("res://sim/intermission.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const MinesScript := preload("res://sim/mines.gd")
const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const RunLogScript := preload("res://app/run_log.gd")
const HashScript := preload("res://sim/state_hash.gd")

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
const SEED_BASE := 60717          # run i uses SEED_BASE + i; fixed, so 200 runs reproduce
const MAX_TICKS_PER_LEVEL := 18000  # 5 min of sim per level; a run past it is "stuck"
const REPLAY_CHECK_EVERY := 60    # checkpoint cadence for the A4 replay proof (every 60 ticks)
const REPLAN_TICKS := 45          # route refresh cadence (also on collect / phase flip)
const REACT_TICKS := 15           # 250 ms at 60 Hz (DESIGN.md section 9)
const FOOT_INFLATE := 0.45        # body radius applied to telegraph footprints
const MAX_LEVEL_DEFAULT := 18
const RUNS_DEFAULT := 200
const BUTTON_JUMP := 1
## The player's real body height (sim/enemy_runtime.gd body_contact: py1 = ctl.y + 1.8).
## The avoid layer and the hurdle use it as their vertical band (was 1.5 u: bodies whose
## feet sat 1.5-1.8 u above the player's feet were lethal but invisible to the bot).
const BODY_H := 1.8
## Tripmine model (sim/mines.gd: height-blind 0.9 u trigger cylinder on the slot tile).
## The steering guard keeps the centre >= MINE_SAFE u from a live mine (just under the
## 1.0 u of an orthogonally adjacent tile centre, so a 1-wide bypass stays walkable);
## a jump arc may not pass within MINE_ARC_SAFE u of one at ANY height.
const MINE_SAFE := 0.97
const MINE_ARC_SAFE := 0.95
const MINE_COL_COST := 100000   # route cost of a tile in a live mine's column (lethal ground)
const MINE_NEAR_COST := 8       # the 8 neighbour columns: a diagonal cut passes 0.71 u away

## FROZEN bands (DESIGN.md section 9) - never changed, never weakened. Level -> [lo, hi, label]
const BANDS := [
	[6, 0.80, 1.00, ">= 80%"],
	[12, 0.40, 0.60, "40-60%"],
	[18, 0.15, 0.30, "15-30%"],
]

# ---------------------------------------------------------------- report helpers (pure) --

## Aggregate one sweep's per-run dicts into the report rows. Pure - the test asserts on it.
static func summarize(results: Array) -> Dictionary:
	var out := {"runs": results.size(), "reached": {}, "stuck": 0, "forced_gate": 0,
			"class_counts": {}}
	for lv in [6, 12, 18]:
		(out["reached"] as Dictionary)[lv] = 0
	for r in results:
		var rd: Dictionary = r
		for lv in [6, 12, 18]:
			if bool(rd.get("reached_%d" % lv, false)):
				(out["reached"] as Dictionary)[lv] = int((out["reached"] as Dictionary)[lv]) + 1
		if str(rd.get("outcome", "")) == "stuck":
			out["stuck"] = int(out["stuck"]) + 1
		# A12: a run that crossed at least one lobby on a forced-open gate
		if not (rd.get("forced_gate", []) as Array).is_empty():
			out["forced_gate"] = int(out["forced_gate"]) + 1
		var cls := str(rd.get("class", "?"))
		(out["class_counts"] as Dictionary)[cls] = int((out["class_counts"] as Dictionary).get(cls, 0)) + 1
	return out


## The band table text. Pure - game/tests/test_bot_run.gd asserts every row parses.
static func format_report(agg: Dictionary) -> String:
	var lines: Array[String] = []
	var runs: int = maxi(int(agg.get("runs", 0)), 0)
	lines.append("runs=%d seed_base=%d" % [runs, int(agg.get("seed_base", SEED_BASE))])
	for band in BANDS:
		var lv: int = int(band[0])
		var hit: int = int((agg["reached"] as Dictionary).get(lv, 0))
		var pct: float = 100.0 * float(hit) / float(maxi(runs, 1))
		var ok: bool = pct >= float(band[1]) * 100.0 - 1e-9 and pct <= float(band[2]) * 100.0 + 1e-9
		lines.append("level %d: %5.1f%% (%d/%d)  band %s  %s" % [
				lv, pct, hit, runs, str(band[3]), "PASS" if ok else "FAIL"])
	lines.append("bot runs completed: %d (outcome death/timeout/stuck are normal results, not errors)" % runs)
	# A12: runs that entered a level through a lobby whose gate never opened (the sim
	# would have held the player there); their reach counts are not ordinary levels
	lines.append("forced open-gate runs: %d" % int(agg.get("forced_gate", 0)))
	return "\n".join(lines)


# ---------------------------------------------------------------- the sweep entry point --

## Runs `runs` full probes (run i = seed seed_base + i). Returns the aggregate dict
## (summarize() output + seed_base + per-run rows under "rows"). Used by _init and by the
## T-060 test (3-run smoke). Deterministic: identical inputs -> identical report text.
static func run_probe(runs: int, seed_base: int, max_level: int = MAX_LEVEL_DEFAULT,
		p_log_every_run: bool = false, p_log_dir: String = "") -> Dictionary:
	var api := ContentApiScript.load()
	var rows: Array = []
	if not bool(api.is_ok()):
		return {"ok": false, "boot_errors": api.boot_errors(), "rows": rows}
	for i in range(runs):
		var seed: int = seed_base + i
		# T-081 (D-T081-3): --log writes a T-080 run log per run. run_start.class is ""
		# here: the class is chosen by the run's own pre-run lobby, which runs after
		# run_started, and the picks carry it in the log (the CLASS bay's altar id).
		var lg = null
		if p_log_every_run:
			lg = RunLogScript.new()
			if p_log_dir != "":
				lg.dir_base = p_log_dir
			lg.run_started(seed, "", 0)
		var row: Dictionary = play_run(api, seed, max_level, lg)
		if lg != null:
			lg.close()
		row["seed"] = seed
		rows.append(row)
	var agg: Dictionary = summarize(rows)
	agg["ok"] = true
	agg["seed_base"] = seed_base
	agg["rows"] = rows
	return agg


# ---------------------------------------------------------------- one run, one level --

## One full probe run. Returns {"reached_6","reached_12","reached_18","outcome","entered","class",
## "forced_gate": [level_completed of every lobby the bot left with the gate still closed]}
## outcome: "dead" | "stuck" | "timeout" | "complete" | "cut".
##
## p_rec (optional, A4 replay proof; FIX-A4): when non-empty, the run is RECORDED or REPLAYED
## instead of merely played:
##   record   {"record": true, "max_ticks": N, ...} - every tick's bot input dict is appended to
##             p_rec["inputs"]; a 60-tick checkpoint hash (state_hash.gd over the level's RunState)
##             is appended to p_rec["hashes"] at every 60th GLOBAL tick of the run; the run stops
##             at max_ticks total ticks (0 = no cap) and returns with outcome "cut".
##   playback {"playback": [input dicts], "playback_cursor": 0, ...} - the recorded input stream
##             is fed tick-for-tick instead of the bot's brain; everything else (lobbies, level
##             gen, enemy runtime, gifts/mines/beacon) runs identically, so the checkpoints must
##             equal the recording's. p_rec["playback_short"] is set if the stream runs dry.
## The RunState the bot drives carries the player's x/y/z/vx/vz as before, plus vy / grounded /
## prev_buttons (additive; nothing reads them), so state_hash.gd captures the kinematic state.
static func play_run(api: RefCounted, seed: int, max_level: int, p_log = null,
		p_rec: Dictionary = {}) -> Dictionary:
	var ledger := {
		"votes": {}, "curses": {}, "stacks": {}, "purse": 0, "tithes": 0,
		"hunger": 0, "last_vote": "", "class": "",
	}
	# T-080: with an app/run_log.gd instance handed in, the run is logged - the lobby
	# rows as offer/pick records, the levels as sim-event streams. Null (the default,
	# and T-060's own probe path) logs nothing and behaves identically.
	if p_log != null:
		p_log.lobby_entered(0)
	# A12: lobbies left with the gate still closed (level_completed values)
	var forced_gate: Array = []
	# the pre-run lobby (level_completed 0; picks the class + the first enemy vote)
	if not _resolve_lobby(api, ledger, 0, seed, p_log):
		_note_forced_gate(forced_gate, seed, 0)
	if p_log != null:
		p_log.lobby_left()
	var entered := 1
	var outcome := "complete"
	var l1_tick := -1
	var death_tick := -1
	var death_killer := ""
	var death_code := ""
	while entered <= max_level:
		var result: Dictionary = _play_level(api, ledger, seed, entered, p_log, p_rec)
		var res := str(result.get("result", "dead"))
		if res == "complete":
			if entered == 1:
				l1_tick = int(result.get("complete_tick", -1))
			if entered >= max_level:
				break
			entered += 1
			# the lobby AFTER completing `entered - 1` (votes/curses/purse carry over)
			if p_log != null:
				p_log.lobby_entered(entered - 1)
			if not _resolve_lobby(api, ledger, entered - 1, seed, p_log):
				_note_forced_gate(forced_gate, seed, entered - 1)
			if p_log != null:
				p_log.lobby_left()
			continue
		outcome = res
		death_tick = int(result.get("death_tick", -1))
		death_killer = str(result.get("death_killer", ""))
		death_code = str(result.get("death_code", ""))
		break
	# T-080: the run ENDS here whatever the outcome (the harness stops, or the player died)
	if p_log != null:
		p_log.run_finished(entered, int(ledger["purse"]))
	# T-080: the harness's final pip state (a stuck run never wrote it - default 2)
	return {
		"reached_6": entered >= 6, "reached_12": entered >= 12, "reached_18": entered >= 18,
		"outcome": outcome, "entered": entered, "class": str(ledger["class"]),
		"l1_tick": l1_tick,
		"death_tick": death_tick, "death_killer": death_killer, "death_code": death_code,
		"charges": int(ledger.get("charges", 2)),
		"forced_gate": forced_gate,
	}


## Resolve one intermission the bot way: every mandatory bay gets a seeded uniform random
## pick among its offer altars (CLASS/E/C), rerolling the E x2 bay between votes via the
## sim's own select path. U / REST bays are never touched (the bot buys nothing). A C bay
## whose draw is empty can only be tithe-passed (DESIGN.md section 7) - paid when
## affordable. When it is NOT affordable (or the 80-select cap runs out, or a select is
## refused) the gate is still closed on return. The bot does NOT stall there and the run
## is NOT reported "stuck": play_run goes on into the next level as if the gate had
## opened. Returns gate_open() so the caller can label that level honestly - play_run
## prints a "BOT LOBBY FORCED-GATE" line and records the level in the row's
## "forced_gate" list, and summarize() counts such runs (A12).
static func _resolve_lobby(api: RefCounted, ledger: Dictionary, level_completed: int,
		seed: int, p_log = null) -> bool:
	var lb = Intermission.create(api, level_completed, int(ledger["purse"]),
			VoidRngScript.mix(seed, 5000 + level_completed),
			ledger["votes"], ledger["curses"], ledger["stacks"],
			str(ledger["class"]), int(ledger["tithes"]), int(ledger["hunger"]),
			str(ledger["last_vote"]))
	# T-080: one offer record per unresolved bay at presentation (bay kind + the three
	# altar ids; an Ex2 bay's between-votes redraw is not a new offer row - D-T080-5).
	if p_log != null:
		for bay in lb.bays:
			var bd: Dictionary = bay
			if bool(bd.get("resolved", false)):
				continue
			var bay_ids: Array = []
			for a in bd.get("altars", []):
				bay_ids.append(str((a as Dictionary).get("id", "")))
			p_log.offer_shown(str(bd.get("kind", "")), bay_ids)
	var rng := VoidRngScript.new(VoidRngScript.mix(VoidRngScript.mix(seed, 0xB07),
			level_completed + 1))
	var sel_events: Array = []   # T-080: the altar_selected events of the latest select
	for _i in range(80):
		if bool(lb.gate_open()):
			break
		var table: Array = lb.altar_table()
		var picks: Array[int] = []
		var tithes: Array[int] = []
		for i in table.size():
			var entry: Dictionary = table[i]
			var bay: Dictionary = lb.bays[int(entry["bay_index"])]
			if bool(bay.get("resolved", false)):
				continue
			var kind := str(entry["kind"])
			var bay_kind := str(bay["kind"])
			if kind == "offer" and (bay_kind == "CLASS" or bay_kind == "E" or bay_kind == "C"):
				picks.append(i)
			elif kind == "tithe" and bay_kind == "C":
				tithes.append(i)
		if not picks.is_empty():
			sel_events = []
			lb.apply_select(0, picks[rng.urange(picks.size())], sel_events)
			if p_log != null:
				p_log.feed_lobby(sel_events)
		elif not tithes.is_empty():
			# the only mandatory bay is an empty C draw: pass it with a tithe
			sel_events = []
			if not bool(lb.apply_select(0, tithes[0], sel_events)):
				break
			if p_log != null:
				p_log.feed_lobby(sel_events)
		else:
			break
	ledger["votes"] = lb.votes
	ledger["curses"] = lb.curses_held
	ledger["stacks"] = lb.upgrade_stacks
	ledger["purse"] = int(lb.purse)
	ledger["tithes"] = int(lb.tithes)
	ledger["hunger"] = int(lb.hunger)
	ledger["last_vote"] = str(lb.last_vote)
	ledger["class"] = str(lb.class_chosen)
	return bool(lb.gate_open())


## A12: a lobby _resolve_lobby left with the gate still closed. The level after it is
## NOT an ordinary level (the real sim would never let the player through), so it gets
## its own log line and a row entry instead of passing silently.
static func _note_forced_gate(forced: Array, seed: int, level_completed: int) -> void:
	forced.append(level_completed)
	print("BOT LOBBY FORCED-GATE seed=%d after_level=%d (the gate is still closed after the bot's lobby pass - e.g. an empty C draw with the tithe unaffordable; level %d is played on a forced-open gate, not an ordinary level)"
			% [seed, level_completed, level_completed + 1])


## Carry the run's cross-level survival state onto a fresh controller. Void charges and
## Last Light carry between levels (DESIGN.md D-063); a fresh controller would otherwise
## reset both. Hungry Void (curse) re-applies its cap every level.
static func _carry_controller(ctl, ledger: Dictionary, curses: Dictionary) -> void:
	if curses.has("hungry_void"):
		ctl.set_charge_cap(1)
	if ledger.has("charges"):
		ctl.charges = mini(int(ledger["charges"]), int(ctl.charge_cap))
	if bool(ledger.get("last_light_spent", false)):
		ctl.last_light_spent = true
	var brit := int(curses.get("brittle", 0))
	if brit > 0:
		ctl.C["respawn_delay"] = float(ctl.C["respawn_delay"]) + 0.8 * float(brit)
		ctl.C["respawn_invuln"] = maxf(0.0, float(ctl.C["respawn_invuln"]) - 0.5 * float(brit))


## Build the TERRAIN_SPEC section 5.2 movement graph exactly the way sim/enemy_runtime.gd
## does it (the generator's own code; sim may import terrain).
static func _build_graph(L: Dictionary) -> Dictionary:
	var w := VoidGenScript.World.new()
	for t in L.get("tiles", []):
		w.tiles.append([int(t[0]), int(t[1]), int(t[2]), int(t[3]), int(t[4])])
	for p in L.get("props", []):
		w.props.append([int(p[0]), int(p[1]), int(p[2]), int(p[3]), int(p[4]), int(p[5])])
	for p in L.get("pads", []):
		w.pads.append([int(p[0]), int(p[1]), int(p[2]), int(p[3]), int(p[4]), int(p[5])])
	var col: Dictionary = {}
	for i in range(w.tiles.size()):
		var t2: Array = w.tiles[i]
		var key := Vector2i(int(t2[0]), int(t2[1]))
		if not col.has(key):
			col[key] = []
		col[key].append(i)
	w.col = col
	var pcol: Dictionary = {}
	for i in range(w.props.size()):
		var p2: Array = w.props[i]
		var key2 := Vector2i(int(p2[0]), int(p2[1]))
		if not pcol.has(key2):
			pcol[key2] = []
		pcol[key2].append(i)
	w.pcol = pcol
	var mv: Array = VoidGenScript.movement(w)
	return {"world": w, "adj": mv[1], "tiles": w.tiles}


## One weighted route from `start` (Dijkstra; FIX-A3, D-FIX-A3-1). Edge costs make the
## router prefer ground: a same-level walk is free-ish, any edge over air is paid for,
## and a drop onto far-below ground costs the most (one-way, no recovery). Returns
## {"dist": PackedInt32Array, "parent": PackedInt32Array}; banned edges ("a>b" keys)
## are never relaxed. Deterministic: ties break FIFO like the BFS it replaces.
const COST_WALK := 1
const COST_STEP_DOWN := 2    # 4-neighbour, 1 HU down: the controller lands instantly
const COST_STEP_UP := 3      # 4-neighbour, 1 HU up: auto step-up
const COST_HOP := 6          # small rise/drop over a gap
const COST_DROP := 60        # drop onto ground far below (one-way, follow it badly and you die)

static func _edge_cost(a: Array, b: Array) -> int:
	var dx := absi(int(b[0]) - int(a[0]))
	var dz := absi(int(b[1]) - int(a[1]))
	var dy := int(b[2]) - int(a[2])
	var man := dx + dz
	if man == 1:
		if dy == 0:
			return COST_WALK
		if dy == -1:
			return COST_STEP_DOWN
		if dy == 1:
			return COST_STEP_UP
	var gap := maxi(dx, dz)
	if dy > 0:
		return COST_HOP + 2 * gap
	if dy < -2:
		return COST_DROP
	return COST_HOP if gap <= 2 else COST_HOP + 2 * gap


static func _h_lt(a: Array, b: Array) -> bool:
	if int(a[0]) != int(b[0]):
		return int(a[0]) < int(b[0])
	return int(a[1]) < int(b[1])


static func _h_push(heap: Array, e: Array) -> void:
	heap.append(e)
	var c := heap.size() - 1
	while c > 0:
		var p := (c - 1) >> 1
		if _h_lt(heap[c], heap[p]):
			var tmp: Array = heap[p]
			heap[p] = heap[c]
			heap[c] = tmp
			c = p
		else:
			break


static func _h_pop(heap: Array) -> Array:
	var top: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var n := heap.size()
		var c := 0
		while true:
			var l := 2 * c + 1
			var r := 2 * c + 2
			var m := c
			if l < n and _h_lt(heap[l], heap[m]):
				m = l
			if r < n and _h_lt(heap[r], heap[m]):
				m = r
			if m == c:
				break
			var tmp: Array = heap[m]
			heap[m] = heap[c]
			heap[c] = tmp
			c = m
	return top


static func _route(adj: Array, tiles: Array, start: int, banned: Dictionary,
		menace: Dictionary = {}) -> Dictionary:
	var n: int = adj.size()
	var dist := PackedInt32Array()
	var parent := PackedInt32Array()
	dist.resize(n)
	parent.resize(n)
	for i in range(n):
		dist[i] = -1
		parent[i] = -1
	dist[start] = 0
	var heap: Array = []
	var seq := 0
	_h_push(heap, [0, 0, start])
	while not heap.is_empty():
		var top: Array = _h_pop(heap)
		var c: int = int(top[0])
		var u: int = int(top[2])
		if c != int(dist[u]):
			continue   # stale heap entry
		for v in adj[u]:
			if banned.has("%d>%d" % [u, v]):
				continue
			var nd: int = c + _edge_cost(tiles[u], tiles[v])
			# tiles a contact-kill body is on or near cost extra: the ROUTE curves
			# around a chaser's position (D-FIX-A3-2) instead of meeting it head-on
			nd += int(menace.get(v, 0))
			if int(dist[v]) < 0 or nd < int(dist[v]):
				dist[v] = nd
				parent[v] = u
				seq += 1
				_h_push(heap, [nd, seq, v])
	return {"dist": dist, "parent": parent}


## Reconstruct the tile path from `start` to `goal` (inclusive).
static func _path_to(parent: PackedInt32Array, start: int, goal: int) -> Array[int]:
	var out: Array[int] = []
	var cur := goal
	while cur != -1:
		out.append(cur)
		if cur == start:
			break
		cur = parent[cur]
	out.reverse()
	return out


## Play one level. Returns {"result": "complete" | "dead" | "stuck" | "timeout" | "cut"}.
## p_rec: see play_run - record or playback bookkeeping, threaded to the tick loop.
static func _play_level(api: RefCounted, ledger: Dictionary, seed: int, level: int,
		p_log = null, p_rec: Dictionary = {}) -> Dictionary:
	var votes: Dictionary = ledger["votes"]
	var curses: Dictionary = ledger["curses"]
	var extra: int = E_GIFT_LARPER.extra_mines(int(votes.get("gift_larper", 0)))
	extra += 4 * int(curses.get("understudies", 0))
	var L: Dictionary = VoidGenScript.generate(seed, level, 1, extra)
	if L.is_empty():
		return {"result": "stuck"}
	var rs = RunStateScript.new_run(seed, 1, api.content_ids())
	rs.load_level(L, level)
	var lv = rs.level
	var w := CollisionScript.make_world(L["tiles"], L["props"], L["pads"], {"dais": L["beacon"]})
	var graph: Dictionary = _build_graph(L)
	var gtiles: Array = graph["tiles"]
	var adj: Array = graph["adj"]
	var w2 = graph["world"]
	# the collection slots as tile indices (gifts hang 1.0 u above their tile);
	# the T-080 level_start counts ride the same walk (slots / real gifts / mines)
	var slot_tiles: Array[int] = []
	var slots_n := 0
	var real_n := 0
	var mine_n := 0
	for s in lv.gifts.slots:
		var sd: Dictionary = s
		if int(sd["occ"]) == 0:
			real_n += 1
		elif int(sd["occ"]) == 1:
			mine_n += 1
		slots_n += 1
		slot_tiles.append(VoidGenScript.find_tile(w2, int(sd["x"]), int(sd["z"]), int(sd["y"])))
	# the player controller, same class the lobby picked, charges carried between levels
	var ctl = ControllerScript.new()
	var consts := ControllerScript.load_constants()
	var cls := str(ledger["class"])
	ctl.setup(cls, consts)
	ctl.place(w)
	_carry_controller(ctl, ledger, curses)
	# the enemy runtime: votes are the spawn plan (VOTING RULES canon; one row per vote)
	var opts := {}
	if curses.has("early_bird"):
		opts["spawn_delay_ticks"] = 120
	var rt = EnemyRuntime.new()
	rt.setup(L, w, [ctl], int((rs.rng["enemy_ai"] as RefCounted).s), opts)
	rt.curse_speed_mul = pow(1.08, int(curses.get("rush_hour", 0))) * pow(1.05, int(ledger["hunger"]))
	if curses.has("long_night"):
		rt.overtime_period = 14.0
	var planned_enemies := 0
	for id in votes.keys():
		var n := int(votes[id])
		if n <= 0:
			continue
		var entry: Dictionary = api.enemy(str(id))
		if entry.is_empty():
			continue
		var beh = _make_behavior(str(id))
		if beh == null:
			continue
		rt.plan(str(id), str(entry.get("name", id)), beh, _cfg_for(entry, str(id), level, n), n)
		planned_enemies += n
	# T-080: the level_start record - slots from the level dict, "enemies in play" =
	# the enemy vote COPIES just planned (the votes ARE the DESIGN section 6 column)
	if p_log != null:
		p_log.level_started(level, slots_n, real_n, mine_n, planned_enemies)
	# the per-level bot memory
	var mem := _fresh_mem()
	mem["slot_tiles"] = slot_tiles
	while lv.tick < MAX_TICKS_PER_LEVEL:
		var a_in: Dictionary
		if p_rec.has("playback"):
			var cursor: int = int(p_rec.get("playback_cursor", 0))
			var stream: Array = p_rec["playback"]
			if cursor < stream.size():
				a_in = stream[cursor]
			else:
				p_rec["playback_short"] = true
				a_in = {"move_x": 0, "move_z": 0, "buttons": 0, "aim_x": 0.0, "aim_z": 1.0}
			p_rec["playback_cursor"] = cursor + 1
		else:
			# D-FIX-A3-2: tiles near a contact-kill body cost the router extra, so the
			# walking line curves away from a live chaser instead of meeting it head-on
			var menace := {}
			for e2 in rt.enemies:
				if not bool(e2.get("contact_kill", true)):
					continue
				var ecx := int(floor(float(e2["x"])))
				var ecz := int(floor(float(e2["z"])))
				for ddx in range(ecx - 2, ecx + 3):
					for ddz in range(ecz - 2, ecz + 3):
						var lst: Array = w2.col.get(Vector2i(ddx, ddz), [])
						for ti in lst:
							menace[ti] = 30
			# tripmines are lethal ground: every tile in a live mine's column (the
			# trigger is height-blind) is all but closed to the router, and the 8
			# neighbour columns cost a little so the route prefers the wide bypass
			var mpts: Array = _live_mines(lv)
			mem["mines"] = mpts
			for mp in mpts:
				var mcx := int(floor((mp as Vector2).x))
				var mcz := int(floor((mp as Vector2).y))
				for ddx2 in range(mcx - 1, mcx + 2):
					for ddz2 in range(mcz - 1, mcz + 2):
						var mc: int = MINE_COL_COST if (ddx2 == mcx and ddz2 == mcz) else MINE_NEAR_COST
						for ti2 in w2.col.get(Vector2i(ddx2, ddz2), []):
							menace[ti2] = int(menace.get(ti2, 0)) + mc
			mem["menace"] = menace
			a_in = _bot_input(mem, lv, rt, ctl, w, w2, gtiles, adj, L)
			if bool(p_rec.get("record", false)):
				(p_rec["inputs"] as Array).append(a_in.duplicate(true))
		var ev: Array = []
		for e in ctl.step(DT, a_in, w):
			ev.append(e)
		if bool(ctl.grounded):
			mem["ground_tile"] = _tile_under(w, ctl)
		# the bot's own enemy-velocity estimate (rows carry no velocity field):
		# last tick's position delta per enemy INSTANCE (_ekey; keying by content id let
		# two copies of one enemy write each other's previous position), read by the
		# avoid/hurdle layer
		var eprev: Dictionary = mem.get("eprev", {})
		var evel: Dictionary = {}
		for e2 in rt.enemies:
			var eid := _ekey(e2)
			var p2: Variant = eprev.get(eid, null)
			if p2 != null and p2 is Dictionary:
				evel[eid] = Vector2((float(e2["x"]) - float((p2 as Dictionary)["x"])) * 60.0,
						(float(e2["z"]) - float((p2 as Dictionary)["z"])) * 60.0)
			eprev[eid] = {"x": float(e2["x"]), "z": float(e2["z"])}
		mem["eprev"] = eprev
		mem["e_vel"] = evel
		var p0: Dictionary = lv.players[0]
		p0["x"] = ctl.x
		p0["y"] = ctl.y
		p0["z"] = ctl.z
		p0["vx"] = ctl.vx
		p0["vz"] = ctl.vz
		p0["vy"] = ctl.vy
		p0["grounded"] = ctl.grounded
		p0["prev_buttons"] = int(a_in["buttons"])
		lv.tick += 1
		GiftsScript.tick(lv, 0, ev)
		var minev: Array = []
		MinesScript.tick(lv, [ctl], w, [0], lv.tick, minev)
		for e in minev:
			ev.append(e)
		lv.beacon.try_enter(ctl, lv.tick, 0, ev)
		if lv.beacon.is_open() and not bool(mem["overtime_on"]):
			rt.on_beacon_open()
			mem["overtime_on"] = true
		for e in rt.step(DT):
			ev.append(e)
		_track_telegraphs(mem, rt, lv.tick)
		# T-080: the tick's event list is complete here (controller + gifts + mines +
		# beacon + enemies) - one feed call per sim tick, then the clock advances.
		if p_log != null:
			p_log.feed_tick(ev)
		if TRACE and lv.tick % 30 == 0:
			print("POS t=%d x=%.2f y=%.2f z=%.2f grounded=%s cur=%d gifts=%d charges=%d" % [
				lv.tick, ctl.x, ctl.y, ctl.z, ctl.grounded, _tile_under(w, ctl),
				lv.gifts.remaining(), ctl.charges])
		# A4 replay proof bookkeeping: one global tick counter across levels; a checkpoint
		# hash at every REPLAY_CHECK_EVERY-th tick, taken after the tick's full event stream
		# so controller + gifts + mines + beacon + enemies are all reflected.
		if not p_rec.is_empty():
			var total: int = int(p_rec.get("total_ticks", 0)) + 1
			p_rec["total_ticks"] = total
			if total % REPLAY_CHECK_EVERY == 0:
				(p_rec["hashes"] as Array).append(HashScript.sha256(rs))
			var cap: int = int(p_rec.get("max_ticks", 0))
			if cap > 0 and total >= cap:
				p_rec["cut"] = true
				ledger["charges"] = int(ctl.charges)
				ledger["last_light_spent"] = bool(ctl.last_light_spent)
				return {"result": "cut"}
		if ctl.dead:
			if TRACE:
				print("DEATHFORENSIC t=%d p=(%.2f,%.2f,%.2f) enemies:" % [lv.tick, float(ctl.x), float(ctl.y), float(ctl.z)])
				for e in rt.enemies:
					var dxd := float(e["x"]) - float(ctl.x)
					var dzd := float(e["z"]) - float(ctl.z)
					if dxd * dxd + dzd * dzd < 400.0:
						print("  %s d=%.2f ep=(%.2f,%.2f,%.2f) ev=(%.2f,%.2f)" % [
							str(e.get("id", "?")), sqrt(dxd * dxd + dzd * dzd),
							float(e["x"]), float(e["y"]), float(e["z"]),
							_e_vel(mem, e).x, _e_vel(mem, e).y])
			ledger["charges"] = int(ctl.charges)
			ledger["last_light_spent"] = bool(ctl.last_light_spent)
			return {"result": "dead", "death_tick": lv.tick, "death_killer": str(ctl.dead_killer),
					"death_code": str(ctl.dead_code)}
		if bool(lv.beacon.completed):
			ledger["charges"] = int(ctl.charges)
			ledger["last_light_spent"] = bool(ctl.last_light_spent)
			return {"result": "complete", "complete_tick": int(lv.tick)}
		for e in ev:
			var ek := str(e.get("e", ""))
			if ek == "gift_collected" or ek == "respawn" or ek == "last_light_save":
				mem["repath"] = true
			if ek == "push":
				# an enemy overwrote the player's velocity: whatever arc was committed
				# no longer exists - the air layer steers to the nearest footing, and no
				# new jump is validated from a state the next push will overwrite again
				mem["flight"] = {}
				mem["pushed_at"] = int(lv.tick)
			if ek == "void_fall":
				# a charge just bought a respawn: make the burned fall unrepeatable
				# (D-FIX-A3-1) - ban the edge the bot was following when it fell
				var gt2 := int(mem.get("ground_tile", -1))
				var lwp := int(mem.get("last_wp", -1))
				if gt2 >= 0 and lwp >= 0 and gt2 != lwp:
					var bk := "%d>%d" % [gt2, lwp]
					if not bool((mem["banned"] as Dictionary).get(bk, false)):
						(mem["banned"] as Dictionary)[bk] = true
						mem["repath"] = true
			if TRACE:
				if ek == "respawn" or ek == "last_light_save" or ek == "mine_detonated" \
						or ek == "death" or ek == "void_fall" or ek == "chain_reset" or ek == "screen_blur":
					print("EV t=%d %s %s" % [lv.tick, ek, JSON.stringify(e)])
		if _stuck_window(mem, ctl):
			return {"result": "stuck"}
	ledger["charges"] = int(ctl.charges)
	ledger["last_light_spent"] = bool(ctl.last_light_spent)
	return {"result": "timeout"}


static func _fresh_mem() -> Dictionary:
	return {
		"path": [], "path_i": 0, "goal_kind": "", "goal_tile": -1, "goal_slot": -1,
		"repath": true, "replan_in": 0,
		"tracked": [],   # live telegraphs registered so far: [{"t": Dictionary, "fs": tick}]
		"overtime_on": false, "jump_hold": 0,
		"stuck_timer": 0, "last_pos": Vector2(-9999.0, -9999.0),
		"slot_tiles": [], "cur_tile": -1,
		"air_ticks": 0, "air_released": {},   # gifts this level we gave up reaching (thicc_ben pin)
		"banned": {}, "lift_at": 0,           # refused edges (D-FIX-A3-1) + the lift cooldown
		"was_grounded": true,
	}


## True when the player has shown no meaningful movement over a 600-tick window.
static func _stuck_window(mem: Dictionary, ctl) -> bool:
	var pos := Vector2(float(ctl.x), float(ctl.z))
	var last: Vector2 = mem["last_pos"]
	mem["stuck_timer"] = int(mem["stuck_timer"]) + 1
	if pos.distance_to(last) > 0.5:
		mem["last_pos"] = pos
		mem["stuck_timer"] = 0
		return false
	return int(mem["stuck_timer"]) >= 600


# ---------------------------------------------------------------- enemy cfg factory --

## Instantiates the behavior for a content id. Handles the three shapes the roster uses:
## the script itself extends EnemyBehavior (address_me/claude/gin/nuke/you), the script
## exposes a behavior()/new_behavior() factory (coil/toucher/thicc_ben), or the behavior
## is an inner class (gift_larper/isagi/kiwi_cat/seal).
static func _make_behavior(id: String) -> RefCounted:
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


## The runtime cfg for one enemy: the enemy.json stats block (flat), with the top-level
## contact_kill / preferred_kind / arbiter keys the runtime reads, stamped with id / name /
## votes / level_number. isagi additionally wants the nested "stats" dict (it reads
## cfg["stats"] internally); address_me wants "votes" for its return-interval discount.
static func _cfg_for(entry: Dictionary, id: String, level: int, votes: int) -> Dictionary:
	var stats: Dictionary = (entry.get("stats", {}) as Dictionary).duplicate(true)
	for key in ["contact_kill", "preferred_kind", "arbiter"]:
		if entry.has(key) and not stats.has(key):
			stats[key] = entry[key]
	stats["id"] = id
	stats["name"] = str(entry.get("name", id))
	stats["votes"] = votes
	stats["level_number"] = level
	if id == "isagi":
		stats["stats"] = (entry.get("stats", {}) as Dictionary).duplicate(true)
	return stats


# ---------------------------------------------------------------- telegraph dodge --

## Register newly appeared telegraph dicts. The liveness filter is the same one the
## game uses (rt.live_telegraphs()): footprints whose telegraph has ended are never
## seen here, so the bot never dodges a ghost. Tracked by telegraph dict (order is
## unstable across live filters), storing the tick each was first registered.
static func _track_telegraphs(mem: Dictionary, rt, tick: int) -> void:
	var tracked: Array = mem["tracked"]
	var live: Array = rt.live_telegraphs()
	for t in live:
		var found := false
		for entry in tracked:
			if entry["t"] == t:
				found = true
				break
		if not found:
			tracked.append({"t": t, "fs": tick})
	# bound the bookkeeping the same way the old index-keyed map was pruned
	for i in range(tracked.size() - 1, -1, -1):
		var e: Dictionary = tracked[i]
		if tick - int(e["fs"]) > int(e["t"].get("total", 0)) + 120:
			tracked.remove_at(i)


## A telegraph footprint worth dodging: a real area, not a zero-radius cue.
static func _real_footprint(shape: Dictionary) -> bool:
	match str(shape.get("shape", "circle")):
		"circle": return float(shape.get("r", 0.0)) > 0.0
		"ring": return float(shape.get("r1", 0.0)) > 0.0
		"box": return float(shape.get("x1", 0.0)) > float(shape.get("x0", 0.0)) \
				and float(shape.get("z1", 0.0)) > float(shape.get("z0", 0.0))
	return false


## True when feet (+x/y/z, y inflated by FOOT_INFLATE) are inside the footprint.
static func _inside_footprint(shape: Dictionary, px: float, py: float, pz: float) -> bool:
	var kind := str(shape.get("shape", "circle"))
	var y0 := float(shape.get("y0", -INF))
	var y1 := float(shape.get("y1", INF))
	if py < y0 - FOOT_INFLATE or py > y1 + FOOT_INFLATE:
		return false
	if kind == "circle":
		var dx := px - float(shape["cx"])
		var dz := pz - float(shape["cz"])
		var r := float(shape["r"]) + FOOT_INFLATE
		return dx * dx + dz * dz <= r * r
	if kind == "ring":
		var dxr := px - float(shape["cx"])
		var dzr := pz - float(shape["cz"])
		var d2 := dxr * dxr + dzr * dzr
		var r0 := maxf(0.0, float(shape["r0"]) - FOOT_INFLATE)
		var r1 := float(shape["r1"]) + FOOT_INFLATE
		return d2 >= r0 * r0 and d2 <= r1 * r1
	# box
	return px >= float(shape["x0"]) - FOOT_INFLATE and px <= float(shape["x1"]) + FOOT_INFLATE \
		and pz >= float(shape["z0"]) - FOOT_INFLATE and pz <= float(shape["z1"]) + FOOT_INFLATE


## The escape direction out of a footprint (XZ, normalized).
static func _escape_vector(shape: Dictionary, px: float, pz: float) -> Vector2:
	var kind := str(shape.get("shape", "circle"))
	if kind == "circle":
		var d := Vector2(px - float(shape["cx"]), pz - float(shape["cz"]))
		if d.length() < 1e-4:
			return Vector2(1.0, 0.0)
		return d.normalized()
	if kind == "ring":
		var d2 := Vector2(px - float(shape["cx"]), pz - float(shape["cz"]))
		var a := d2.length()
		if a < 1e-4:
			return Vector2(1.0, 0.0)
		var r0 := float(shape["r0"])
		var r1 := float(shape["r1"])
		return d2.normalized() if a >= (r0 + r1) * 0.5 else -d2.normalized()
	# box: out the axis of least penetration
	var left := px - float(shape["x0"])
	var right := float(shape["x1"]) - px
	var back := pz - float(shape["z0"])
	var front := float(shape["z1"]) - pz
	var m := minf(minf(left, right), minf(back, front))
	if m == left: return Vector2(-1.0, 0.0)
	if m == right: return Vector2(1.0, 0.0)
	if m == back: return Vector2(0.0, -1.0)
	return Vector2(0.0, 1.0)


## A contact-kill body's estimated velocity from the bot's own last-tick tracking
## (mem["e_vel"], filled in _play_level); Vector2.ZERO when unknown.
static func _e_vel(mem: Dictionary, e: Dictionary) -> Vector2:
	var v: Variant = (mem.get("e_vel", {}) as Dictionary).get(_ekey(e), Vector2.ZERO)
	return v if v is Vector2 else Vector2.ZERO


## A stable per-instance key for one enemy row. Every spawned row carries its own rng
## object (enemy_runtime._spawn_one), whose instance id is unique for the row's life;
## the fallback (content id + copy index + spawn tick) is unique per spawned copy too.
static func _ekey(e: Dictionary) -> String:
	var r: Variant = e.get("rng", null)
	if r is Object:
		return "i%d" % (r as Object).get_instance_id()
	return "%s#%d#%d" % [str(e.get("id", "")), int(e.get("copy_index", 0)), int(e.get("spawn_tick", 0))]


## Live (unconsumed) tripmine centres as XZ points, read straight from the level's
## mine state (sim/mines.gd point(); the trigger only uses x/z).
static func _live_mines(lv) -> Array:
	var out: Array = []
	var mines = lv.mines
	if mines == null:
		return out
	for slot_id in mines.ids:
		if mines.is_consumed(int(slot_id)):
			continue
		var p: Vector3 = mines.point(int(slot_id))
		out.append(Vector2(p.x, p.z))
	return out


## True when the straight run from the feet toward `dir` keeps the centre clear of
## every live mine over the next ~1.2 u: each sample must stay >= MINE_SAFE from a
## mine, or (when the feet are already closer than that) must not get any closer.
static func _mine_clear(px: float, pz: float, dir: Vector2, mines: Array) -> bool:
	for m in mines:
		var mp: Vector2 = m
		var cur := Vector2(px, pz).distance_to(mp)
		if cur > 3.0:
			continue
		var need := minf(MINE_SAFE, cur - 1e-3)
		for d in [0.3, 0.6, 0.9, 1.2]:
			var q := Vector2(px + dir.x * d, pz + dir.y * d)
			if q.distance_to(mp) < need:
				return false
	return true


## The mine guard: the final move, bent away from live mines. The commanded heading is
## kept when its next ~1.2 u stays clear; otherwise it is rotated in 15-degree steps
## (nearest first, both ways) to the closest clear heading that keeps ground support
## (when grounded); no clear heading -> stand still. A tripmine always kills (DESIGN.md
## 3.3), so standing beats any other risk the bot knows about.
static func _mine_guard(w, ctl, move: Vector2, mines: Array) -> Vector2:
	if move == Vector2.ZERO or mines.is_empty():
		return move
	var px := float(ctl.x)
	var pz := float(ctl.z)
	var mag := move.length()
	var n := move / mag
	if _mine_clear(px, pz, n, mines):
		return move
	var grounded := bool(ctl.grounded)
	for k in range(1, 12):
		var ang := float(k) * PI / 12.0
		for s in [1.0, -1.0]:
			var d2 := n.rotated(ang * s)
			if not _mine_clear(px, pz, d2, mines):
				continue
			if grounded and not _step_safe(w, ctl, d2):
				continue
			return d2 * mag
	return Vector2.ZERO


## YOU?!'s shockwave rings (row["rings"], released when the telegraphed rumble ENDS and
## never telegraphed themselves - they outlive the telegraph by up to 94 ticks). The
## hit rule mirrors the behavior's own check: feet inside (ring_y - RING_BELOW,
## ring_y + RING_HEIGHT) and within RING_RADIAL_WINDOW of the expanding edge.
## Returns {"threat": bool, "jump": bool, "tall": bool, "out": Vector2}: threat = a ring reaches the
## feet within the next second; jump = press now so the feet clear the band's top while
## it passes (the counter-play, "jump as the ring reaches you"); out = the radial escape
## for a ring too tall to jump.
static func _ring_threat(rt, ctl) -> Dictionary:
	var res := {"threat": false, "jump": false, "tall": false, "out": Vector2.ZERO}
	var best_t := INF
	var px := float(ctl.x)
	var pz := float(ctl.z)
	var feet := float(ctl.y)
	var win: float = E_YOU.RING_RADIAL_WINDOW
	var spd: float = E_YOU.RING_SPEED
	var g := 32.0
	var vj := 12.0
	for e in rt.enemies:
		var rings: Variant = e.get("rings", null)
		if not (rings is Array):
			continue
		for ring in rings:
			var rd: Dictionary = ring
			if bool(rd.get("done", false)):
				continue
			var ry := float(rd["y"])
			if feet <= ry - E_YOU.RING_BELOW - 0.2 or feet >= ry + E_YOU.RING_HEIGHT + 0.2:
				continue
			var dx := px - float(rd["x"])
			var dz := pz - float(rd["z"])
			var dist := sqrt(dx * dx + dz * dz)
			var r := float(rd["r"])
			if dist < r - win or dist - win > E_YOU.RING_MAX:
				continue   # already passed, or beyond the ring's last radius
			var radial := Vector2(dx, dz) / dist if dist > 1e-4 else Vector2(1.0, 0.0)
			var v_in := -(float(ctl.vx) * radial.x + float(ctl.vz) * radial.y)
			var closing := maxf(spd + v_in, 1.0)
			var t_a := maxf(dist - (r + win), 0.0) / closing
			if t_a > 1.0 or t_a >= best_t:
				continue
			best_t = t_a
			res["threat"] = true
			res["out"] = radial
			# rise needed for the feet to clear the band's top while it passes
			var h := ry + E_YOU.RING_HEIGHT + 0.05 - feet
			var disc := vj * vj - 4.0 * (g * 0.5) * h
			res["jump"] = false
			res["tall"] = disc < 0.0
			if disc < 0.0:
				continue   # too tall to jump: the caller runs outward instead
			var sq := sqrt(disc)
			var t1 := maxf((vj - sq) / g, 0.0)
			var t2 := (vj + sq) / g
			var t_pass := 2.0 * win / spd
			if t_a <= t1 + 0.03 and t_a + t_pass <= t2:
				res["jump"] = true
	return res


## The dodge input for this tick, or null when no telegraph demands one.
## Reacts REACT_TICKS (250 ms) after a telegraph appears - never on the tick it appears.
## The escape direction is ledge-checked (D-FIX-A3-1): if the straight escape runs off
## the walkway into the void, the bot rotates it in 30-degree steps (both ways, nearest
## first) to a direction that keeps ground support - a strike beats a D-VOID fall
## (T-060/T-081: 60% of deaths were void falls, and a straight-out dodge caused many).
static func _dodge_vector(mem: Dictionary, rt, ctl, tick: int, w) -> Variant:
	var best_strike := 1 << 30
	var best_shape: Dictionary = {}
	var tracked: Array = mem["tracked"]
	for t in rt.live_telegraphs():
		var fs := -1
		for entry in tracked:
			if entry["t"] == t:
				fs = int(entry["fs"])
				break
		if fs < 0:
			continue
		var strike := fs + int(t.get("total", 0))
		var t_now := int(t.get("ticks", 0))
		if strike < tick or t_now <= 0:
			# strike has landed (or the entry died): forget it
			continue
		if tick - fs < REACT_TICKS:
			continue
		var shape: Dictionary = t.get("shape", {})
		if not _real_footprint(shape):
			continue
		if not _inside_footprint(shape, float(ctl.x), float(ctl.y), float(ctl.z)):
			continue
		if strike < best_strike:
			best_strike = strike
			best_shape = shape
	if best_shape.is_empty():
		return null
	return _safe_dir(w, ctl, _escape_vector(best_shape, float(ctl.x), float(ctl.z)))


# ---------------------------------------------------------------- routing brain --

static var TRACE := false

## Tile index of the tile the player's feet stand in (or the nearest tile below). Reads
## the player's OWN column only (not the AABB neighbours) and resolves ramp rows through
## the collision module's own ramp formula - find_tile() with y*2 rounding cannot stand
## on a ramp (interpolated height) and support_at()'s AABB scan may return a neighbour
## column's tile when the footprint straddles the boundary, so neither is used here.
static func _tile_under(w, ctl) -> int:
	var cx := int(floor(float(ctl.x)))
	var cz := int(floor(float(ctl.z)))
	var cols: Array = w["cols"].get("%d,%d" % [cx, cz], [])
	var feet := float(ctl.y)
	var best := -1
	var best_top := -INF
	for t in cols:
		var ty := int(t["y"])
		if w["removed"].has(CollisionScript.tile_key(cx, cz, ty)):
			continue
		var top: float = CollisionScript.tile_top(ty) if int(t["kind"]) == 0 \
				else CollisionScript._ramp_top_over(t, cx, cz, float(ctl.x), float(ctl.z))
		if top <= feet + 0.55 and top > best_top:
			best_top = top
			best = int(t["i"])
	return best


## The best supported direction close to `ideal`: rotated in 30-degree steps, nearest
## first, both ways, until one keeps ground support; `ideal` itself when every other
## direction runs off a ledge - a strike beats a D-VOID fall.
static func _safe_dir(w, ctl, ideal_v: Variant) -> Vector2:
	if ideal_v is Vector2:
		var ideal: Vector2 = ideal_v
		if ideal != Vector2.ZERO:
			var n := ideal.normalized()
			if _dir_has_support(w, ctl, n):
				return n
			for k in range(1, 12):
				var ang := float(k) * PI / 6.0
				for s in [1.0, -1.0]:
					var dir2 := n.rotated(ang * s)
					if _dir_has_support(w, ctl, dir2):
						return dir2
			return n
	return Vector2.ZERO


## Contact-kill enemy avoidance (D-FIX-A3-2): the router is terrain-only, so the bot
## happily walks straight into a following kiwi cat (4 of 10 probe deaths after the
## edge-discipline fix). Within AVOID_DIST of a contact-kill body (and within the
## player's BODY_H = 1.8 u of its own height) the bot steers around it instead of through it: pure flee when it
## is close, away-plus-goal-bias otherwise (the cat is slower; a circle takes the gift).
static func _avoid_vector(rt, ctl, w, move: Vector2) -> Variant:
	var mx := float(ctl.x)
	var mz := float(ctl.z)
	for e in rt.enemies:
		if not bool(e.get("contact_kill", true)):
			continue
		var dx := mx - float(e["x"])
		var dz := mz - float(e["z"])
		var d2 := dx * dx + dz * dz
		if d2 > AVOID_DIST * AVOID_DIST or d2 < 1e-8:
			continue
		if absf(float(e.get("y", 0.0)) - float(ctl.y)) > BODY_H:
			continue
		var away := Vector2(dx, dz) / sqrt(d2)
		if d2 < 1.7 * 1.7:
			# close: run AROUND it, on the side the goal lies - pure flee never takes
			# a gift out from under a cat sitting on it, and the orbit outruns a
			# 5.6 u/s chaser (D-FIX-A3-2)
			var to_goal := move.normalized() if move != Vector2.ZERO else Vector2.ZERO
			var perp := Vector2(-away.y, away.x)
			var perp2 := Vector2(away.y, -away.x)
			if to_goal != Vector2.ZERO and perp2.dot(to_goal) > perp.dot(to_goal):
				perp = perp2
			return _safe_dir(w, ctl, perp)
		if move == Vector2.ZERO:
			return _safe_dir(w, ctl, away)
		return _safe_dir(w, ctl, away + move.normalized() * 0.45)
	return null


## Real footing at (x, z) for feet at `feet`: a tile top in the point's own column no
## higher than a step up and no lower than SAFE_DROP below. _tile_under alone answers
## "is there ANY tile below", and a floor 20 u down read as ground: the avoid / dodge
## escapes happily ran off ledges over it (void-fall forensics, seed 60735).
const SAFE_DROP := 1.05   # 2 HU: the deepest drop the controller lands as a step

static func _ground_near(w, x: float, feet: float, z: float) -> bool:
	var cx := int(floor(x))
	var cz := int(floor(z))
	for t in w["cols"].get("%d,%d" % [cx, cz], []):
		var ty := int(t["y"])
		if w["removed"].has(CollisionScript.tile_key(cx, cz, ty)):
			continue
		var top: float = CollisionScript.tile_top(ty) if int(t["kind"]) == 0 \
				else CollisionScript._ramp_top_over(t, cx, cz, x, z)
		if top <= feet + 0.55 and top >= feet - SAFE_DROP:
			return true
	return false


const LAND_CLEAR := 1.25   # a landing column centre this close to an enemy body is skipped

## True when `c` lies within `r` u of any point in `pts` (Vector2 list). Pure.
static func _near_any(c: Vector2, pts: Array, r: float) -> bool:
	for p in pts:
		if c.distance_to(p) < r:
			return true
	return false


## XZ of every enemy body in play (the air layer never picks a landing column under
## one: a contact-kill body kills on touch, a non-killing ejector relaunches the bot
## from the same column for ever - seed 60717's 600-tick bounce).
static func _enemy_points(rt) -> Array:
	var out: Array = []
	for e in rt.enemies:
		out.append(Vector2(float(e["x"]), float(e["z"])))
	return out


## The widest contact radius in play: sim/enemy_runtime.gd body_contact's own test
## (diameter_u * 0.5 + the player's 0.4 half-width). A fall that passes inside it is a
## kill, so it is the corridor the landing pick must keep clear (D-B5B-1). 0.0 when no
## contact-kill body is in play.
static func _enemy_reach(rt) -> float:
	var r := 0.0
	for e in rt.enemies:
		if not bool(e.get("contact_kill", true)):
			continue
		r = maxf(r, float(e.get("diameter_u", 0.0)) * 0.5 + 0.4)
	return r


## True when the straight XZ segment from `a` to `b` stays at least `r` u from every point
## in `pts` (D-B5B-1). A landing column that is clear of a body is still a bad target when
## the fall to it passes THROUGH the body: the bot steered at a column beyond the cat and
## flew into it (level 11, seed 38, tick 2145). Pure.
static func _seg_clear(a: Vector2, b: Vector2, pts: Array, r: float) -> bool:
	var ab := b - a
	var l2 := ab.length_squared()
	for p in pts:
		var t := 0.0
		if l2 > 1e-9:
			t = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		if a.lerp(b, t).distance_to(p) < r:
			return false
	return true


## Centre of the nearest column within `r` u whose top lies below the feet (a body in the
## air can still come down on it), skipping columns within LAND_CLEAR of a point in
## `avoid` and columns whose straight fall from the feet passes within `block_r` u of one
## in `block`; Vector2(INF, INF) when there is none. Ties break on the higher top (less
## fall), then scan order. Pure.
static func _nearest_landing(w, x: float, feet: float, z: float, r: float,
		avoid: Array = [], block: Array = [], block_r: float = 0.0) -> Vector2:
	var best := Vector2(INF, INF)
	var best_d := INF
	var best_top := -INF
	var here := Vector2(x, z)
	for cx in range(int(floor(x - r)), int(floor(x + r)) + 1):
		for cz in range(int(floor(z - r)), int(floor(z + r)) + 1):
			var c := Vector2(float(cx) + 0.5, float(cz) + 0.5)
			var d := here.distance_to(c)
			if d > r or d > best_d + 1e-6 or _near_any(c, avoid, LAND_CLEAR):
				continue
			if block_r > 0.0 and not _seg_clear(here, c, block, block_r):
				continue
			for t in w["cols"].get("%d,%d" % [cx, cz], []):
				var ty := int(t["y"])
				if w["removed"].has(CollisionScript.tile_key(cx, cz, ty)):
					continue
				var top: float = CollisionScript.tile_top(ty)
				if top > feet + 0.3:
					continue
				if d < best_d - 1e-6 or top > best_top:
					best_d = d
					best_top = top
					best = c
	return best


## True when walking from the feet toward `dir` keeps ground support over the next
## ~0.9 u (a same-level straight walk may only be commanded onto ground that exists).
static func _step_safe(w, ctl, dir: Vector2) -> bool:
	var px := float(ctl.x)
	var py := float(ctl.y)
	var pz := float(ctl.z)
	for d in [0.45, 0.9]:
		if not _ground_near(w, px + dir.x * d, py, pz + dir.y * d):
			return false
	return true


## True when an escape run toward `dir` from the feet keeps support over the next
## ~1.9 u (a dodge may last several tenths of a second at run speed).
static func _dir_has_support(w, ctl, dir: Vector2) -> bool:
	var px := float(ctl.x)
	var py := float(ctl.y)
	var pz := float(ctl.z)
	for d in [0.4, 0.8, 1.3, 1.9]:
		if not _ground_near(w, px + dir.x * d, py, pz + dir.y * d):
			return false
	return true


## Simulate the horizontal speed ramp exactly as sim/controller.gd does it
## (accel 90 u/s^2 toward the target velocity), from `vz` (speed toward the
## target) toward `v_max`; returns the distance covered in t seconds.
static func _dist_at(vz: float, v_max: float, t: float) -> float:
	var v := vz
	var dist := 0.0
	var tc := 0.0
	var want := 1.5
	while tc < t - 1e-9:
		var d := v_max - v
		if d > want:
			v += want
		elif d < -want:
			v -= want
		else:
			v = v_max
		dist += v * DT
		tc += DT
	return dist

## Solve v_max so the horizontal distance over t seconds from `vz` matches D.
## Monotonic in v_max; returns > 9 when even full speed falls short (err carries it).
static func _solve_vmax(t: float, D: float, vz: float) -> float:
	if _dist_at(vz, 9.0, t) < D:
		return 9.0 + (D - _dist_at(vz, 9.0, t)) * 4.0
	var lo := 0.0
	var hi := 9.0
	for _i in range(24):
		var mid := (lo + hi) * 0.5
		if _dist_at(vz, mid, t) < D:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

## The in-flight steering the bot actually flies (and _jump_arc simulates): the
## controller ignores stick magnitude (target speed is always run_speed or 0), so speed
## control is bang-bang - push toward the target column while the stopping distance at
## the current closing speed is short of it, release (brake) once it is not.
## Returns a unit direction or ZERO. Pure.
static func _air_steer(px: float, pz: float, vx: float, vz: float, tx: float, tz: float,
		accel: float) -> Vector2:
	var d := Vector2(tx - px, tz - pz)
	var dist := d.length()
	if dist < 0.08:
		return Vector2.ZERO
	var n := d / dist
	var v_along := vx * n.x + vz * n.y
	if v_along > 0.0 and v_along * v_along / (2.0 * maxf(accel, 1e-3)) >= dist - 0.05:
		return Vector2.ZERO
	return n


## Forward-simulate the controller's own air tick from the CURRENT state for a jump
## pressed now (vy = jump_velocity, jump held `k + 1` ticks so the cut lands at the
## start of tick k + 1 before gravity, exactly as controller.gd orders it), with the
## horizontal input the bot will really send: neutral for `delay` ticks (a vertical
## first jump onto a high ledge), then _air_steer toward the waypoint centre. Real
## run speed / accel / friction / gravity come from the controller; a wall zeroes the
## blocked axis and a ceiling zeroes a rising vy, like controller.gd. Accepts only an
## arc that lands ON the waypoint. Returns {"hold", "delay"} or {}. Deterministic.
## The bot jumps exactly when this finds an arc - i.e., exactly when a jump would work.
static func _jump_arc(ctl, w, wp_x: float, wp_z: float, rt, mines: Array = []) -> Dictionary:
	var x0 := float(ctl.x)
	var y0 := float(ctl.y)
	var z0 := float(ctl.z)
	var vx0 := float(ctl.vx)
	var vz0 := float(ctl.vz)
	if Vector2(wp_x - x0, wp_z - z0).length() < 1e-6:
		return {}
	var C: Dictionary = ctl.C
	var spd: float = float(ctl.run_speed(w))
	var acc: float = float(C["accel"]) * float(ctl.friction_mult(w))
	var g := float(C["gravity"])
	var jv := float(C["jump_velocity"])
	var cut := float(C["jump_cut"])
	var tf := float(C["terminal_fall"])
	var bh := float(C["height"])
	var su := float(C["step_up"])
	var ct_takeoff := _tile_under(w, {"x": x0, "y": y0, "z": z0})
	var k_opts := [0, 2, 4, 8, 14, 22, 30]
	if str(ctl.kit) == "glider":
		# a JUMP still held once vy < 0 engages the glide (not modelled): never hold past the apex
		k_opts = [0, 2, 4, 8, 14, 21]
	for delay in [0, 8, 16]:
		for k in k_opts:
			var x := x0
			var y := y0
			var z := z0
			var vx := vx0
			var vz := vz0
			var vy := jv
			var grounded := false
			for tick in range(240):
				if tick == k + 1 and vy > 0.0:
					vy *= cut
				var mv := Vector2.ZERO
				if tick >= delay:
					mv = _air_steer(x, z, vx, vz, wp_x, wp_z, acc)
				var ddx: float = mv.x * spd - vx
				var ddz: float = mv.y * spd - vz
				var dlen := sqrt(ddx * ddx + ddz * ddz)
				if dlen > 1e-9:
					var s := minf(acc * DT, dlen) / dlen
					vx += ddx * s
					vz += ddz * s
				vy -= g * DT
				if vy < -tf:
					vy = -tf
				var r = CollisionScript.move_body(w, x, y, z, vx * DT, vy * DT, vz * DT,
						bh, su, grounded)
				if absf(float(r["x"]) - x - vx * DT) > 1e-6:
					vx = 0.0
				if absf(float(r["z"]) - z - vz * DT) > 1e-6:
					vz = 0.0
				if bool(r["hit_ceiling"]) and vy > 0.0:
					vy = 0.0
				x = r["x"]
				y = r["y"]
				z = r["z"]
				grounded = bool(r["grounded"])
				# mine-aware arcs: the tripmine trigger is height-blind (sim/mines.gd),
				# so an arc whose centre passes within MINE_ARC_SAFE u of a live mine at
				# ANY height detonates it - refuse this candidate (the scan goes on)
				var over_mine := false
				for m in mines:
					if Vector2(float(x), float(z)).distance_to(m) < MINE_ARC_SAFE:
						over_mine = true
						break
				if over_mine:
					break
				# enemy-aware arcs: an arc that flies through a contact-kill body's
				# closing path is refused. The chaser heads for the JUMPER, so lead it
				# along its line to the landing point at its own base_speed. A refused
				# arc refuses THIS candidate only: the scan goes on to the next
				# (delay, k) pair (an empty return here abandoned all 35 candidates on
				# the first clip, so one body in flight read as "no arc lands on a
				# tile", which banned a good edge for 300 ticks - PARKED.md row 28).
				if not grounded and rt != null:
					var clipped := false
					for e2 in rt.enemies:
						if not bool(e2.get("contact_kill", true)):
							continue
						var ep := Vector2(float(e2["x"]), float(e2["z"]))
						var to_l := Vector2(wp_x, wp_z) - ep
						var dl2 := to_l.length()
						var t_s := float(tick) * DT
						if dl2 > 1e-6:
							ep += to_l * (minf(float((e2.get("cfg", {}) as Dictionary).get("base_speed", 5.6)) * t_s, dl2) / dl2)
						var dxE := x - ep.x
						var dzE := z - ep.y
						var ey2 := float(e2.get("y", 0.0))
						var eh2 := float(e2.get("height_u", 1.0))
						if dxE * dxE + dzE * dzE < 1.1 * 1.1 \
								and y < ey2 + eh2 + 0.2 and y + 1.8 > ey2 - 0.2:
							clipped = true
							break
					if clipped:
						break
				if grounded:
					var p = {"x": x, "y": y, "z": z}
					var ti := _tile_under_sim(w, p)
					if ti >= 0 and ti != ct_takeoff:
						# ACCEPT only arcs that land ON the waypoint (D-FIX-A3-1): the old
						# "any tile but the takeoff" rule validated garbage arcs (a 5-cell
						# jump at approach speed 2 u/s lands on the takeoff's neighbour,
						# looks valid, misses the far tile, D-VOID)
						var lxz := Vector2(wp_x, wp_z).distance_to(Vector2(float(x), float(z)))
						if lxz <= 1.15:
							return {"hold": k + 1, "delay": delay}
					break
				if y < -40.0:
					break
	return {}


## Tile index under a raw {"x","y","z"} point (feet) - the same probe as _tile_under but
## for simulated points; returns -1 over the void.
static func _tile_under_sim(w, p: Dictionary) -> int:
	return _tile_under(w, p)


## Jump handling for a non-walk path edge: {"mag": float 0..1, "hold": int} - hold = how
## many ticks JUMP stays pressed (jump-cut distance control). Forward-simulates the
## controller's own physics and finds an arc that lands on a tile; the bot jumps only
## when one exists. `vz` is the player's speed toward the target at this moment.
static func _jump_plan(ct: Array, _wt: Array, wp_pos: Vector2, dir: Vector2,
		dy_hu: int, vz: float, ctl, w, rt, mines: Array = []) -> Dictionary:
	var exit := _cell_exit(ct, dir)
	var D := exit.distance_to(wp_pos)
	var rise := float(dy_hu) * 0.5
	var arc := _jump_arc(ctl, w, wp_pos.x, wp_pos.y, rt, mines)
	if arc.is_empty():
		# no arc lands on a tile from this position/orientation: refuse the edge (the
		# caller bans it and re-routes - "walk off and pray" is what produced the
		# D-VOID epidemic; FIX-A3)
		return {}
	# the stick magnitude is ignored by the controller (target speed is run_speed or 0),
	# so "mag" stays 1.0; the flight itself is flown by _air_steer after `delay` ticks
	return {"mag": 1.0, "hold": int(arc["hold"]), "delay": int(arc.get("delay", 0))}


## The point where a ray from the tile's centre toward `dir` exits the cell boundary.
static func _cell_exit(ct: Array, dir: Vector2) -> Vector2:
	var c := Vector2(float(ct[0]) + 0.5, float(ct[1]) + 0.5)
	var t_x := INF
	var t_z := INF
	if absf(dir.x) > 1e-9:
		var edge := (float(ct[0]) + 1.0) if dir.x > 0.0 else float(ct[0])
		t_x = (edge - c.x) / dir.x
	if absf(dir.y) > 1e-9:
		var edge2 := (float(ct[1]) + 1.0) if dir.y > 0.0 else float(ct[1])
		t_z = (edge2 - c.y) / dir.y
	var t := minf(t_x, t_z)
	if t == INF:
		t = 0.0
	return c + dir * t


## Goal selection + replanning. Sets mem["path"]/["path_i"]/["goal_*"]; returns nothing.
## Goal: the nearest REACHABLE uncollected black gift (weighted route distance, tie-break
## slot id), or the beacon tile once the beacon is open (DESIGN.md section 3). Edges the
## follower has refused are banned (mem["banned"], "a>b" keys) and never relaxed onto;
## when that makes every remaining gift unreachable the bans lift after a cooldown
## (D-FIX-A3-1) - a wrong ban must not soft-lock the level.
static func _replan(mem: Dictionary, lv, ctl, cur: int, w2, gtiles: Array, adj: Array,
		L: Dictionary) -> void:
	var goal_tile := -1
	var goal_slot := -1
	var goal_kind := "gift"
	var rm: Dictionary = mem.get("menace", {})
	# the goal the caller is still walking: a replan that finds nothing must not erase
	# it (the fall-through below is the promise - "keep the goal markers")
	var prev_tile := int(mem["goal_tile"])
	var prev_slot := int(mem["goal_slot"])
	if bool(lv.beacon.is_open()):
		goal_kind = "beacon"
		var b: Array = L.get("beacon", [0, 0, 1])
		goal_tile = VoidGenScript.find_tile(w2, int(b[0]), int(b[1]), int(b[2]))
		if cur >= 0 and goal_tile >= 0:
			var rb: Dictionary = _route(adj, gtiles, cur, mem.get("banned", {}), rm)
			if int((rb["dist"] as PackedInt32Array)[goal_tile]) < 0:
				# the beacon is behind a banned edge: the beacon is the level's only
				# way out, so lift the bans and try the full graph
				mem["banned"] = {}
				rb = _route(adj, gtiles, cur, {}, rm)   # the lift keeps the chaser cost
			if int((rb["dist"] as PackedInt32Array)[goal_tile]) >= 0:
				mem["path"] = _path_to(rb["parent"], cur, goal_tile)
				mem["path_i"] = 0
				mem["goal_kind"] = goal_kind
				mem["goal_tile"] = goal_tile
				mem["goal_slot"] = -1
				return
	elif cur >= 0:
		var route: Dictionary = _route(adj, gtiles, cur, mem.get("banned", {}), rm)
		var pick: Array = _nearest_gift(lv, mem, route["dist"], false)
		if int(pick[0]) < 0 and int(lv.tick) >= int(mem.get("lift_at", 0)):
			# nothing reachable: the bans (or the thicc_ben releases) over-constrained
			# the route. Lift both after a cooldown and re-pick.
			mem["banned"] = {}
			mem["air_released"] = {}
			mem["lift_at"] = int(lv.tick) + 300
			route = _route(adj, gtiles, cur, {}, rm)   # the lift keeps the chaser cost
			pick = _nearest_gift(lv, mem, route["dist"], true)
		goal_tile = int(pick[0])
		goal_slot = int(pick[1])
		if goal_tile >= 0:
			mem["path"] = _path_to(route["parent"], cur, goal_tile)
			mem["path_i"] = 0
			mem["goal_kind"] = goal_kind
			mem["goal_tile"] = goal_tile
			mem["goal_slot"] = goal_slot
			return
	# airborne over the void, or nothing reachable: keep the goal markers, clear the
	# path; the caller stands (or steers to a still-valid goal) instead of beelining
	# over the void
	# -1 markers are NOT "keep the goal markers": _goal_stale reads goal_slot < 0 as
	# stale for ever, so the router re-ran the whole Dijkstra EVERY tick instead of
	# every REPLAN_TICKS, and the follower refused to move (goal_slot < 0) until the
	# 300-tick lift cooldown ran out. Restore the markers while the goal still exists.
	if goal_kind == "gift" and goal_tile < 0 and prev_slot >= 0 \
			and lv.gifts.present(prev_slot):
		goal_tile = prev_tile
		goal_slot = prev_slot
	mem["path"] = []
	mem["path_i"] = 0
	mem["goal_kind"] = goal_kind
	mem["goal_tile"] = goal_tile
	mem["goal_slot"] = goal_slot


## Nearest reachable uncollected real gift on `dist` (route distances from the player's
## tile). Returns [goal_tile, goal_slot]; [-1, -1] when none is reachable. Pure.
static func _nearest_gift(lv, mem: Dictionary, dist_v: Variant, ignore_released: bool) -> Array:
	var dist: PackedInt32Array = dist_v
	var slots: Array = lv.gifts.slots
	var released: Dictionary = mem.get("air_released", {})
	var best_d := -1
	var goal_tile := -1
	var goal_slot := -1
	for i in range(slots.size()):
		# present() = real, not collected, not lost: a gift whose platform fell with the
		# collapse (sim/gifts.gd lose()) can never be picked up, so routing to it would
		# stall the bot on a ghost for the rest of the level.
		if not lv.gifts.present(i):
			continue
		if not ignore_released and (released as Dictionary).has(i):
			continue
		var gi: int = int((mem["slot_tiles"] as Array)[i])
		if gi < 0 or gi >= dist.size():
			continue
		var d := int(dist[gi])
		if d < 0:
			continue
		if best_d < 0 or d < best_d or (d == best_d and i < goal_slot):
			best_d = d
			goal_tile = gi
			goal_slot = i
	return [goal_tile, goal_slot]


## The goal world position (gift hover point / beacon trigger centre), XZ used by the bot.
static func _goal_point(mem: Dictionary, lv) -> Vector3:
	if str(mem["goal_kind"]) == "beacon":
		return Vector3(float(lv.beacon.cx), float(lv.beacon.base_y), float(lv.beacon.cz))
	var slot := int(mem["goal_slot"])
	if slot >= 0:
		return lv.gifts.slot_pos(slot)
	return Vector3(0.0, 0.0, 0.0)


## Is the current goal invalid (gift gone / beacon opened)?
##
## "Gone" is present(), not collected(): the collapse starts on the beacon-open tick, so the
## gold phase is exactly when a gift's platform can fall out from under it. A lost gift is not
## a collected one, so asking collected() alone left the bot routing to a ghost for the rest of
## the level - the same defect _nearest_gift had, in the staleness test instead of the chooser.
static func _goal_stale(mem: Dictionary, lv) -> bool:
	if str(mem["goal_kind"]) == "beacon":
		return false
	if bool(lv.beacon.is_open()):
		return true
	var slot := int(mem["goal_slot"])
	if slot < 0:
		return true
	return not lv.gifts.present(slot)


## Routing input for this tick: {"move": Vector2, "buttons": int}.
static func _routing(mem: Dictionary, lv, ctl, rt, w, w2, gtiles: Array, adj: Array,
		L: Dictionary) -> Dictionary:
	var tiles := gtiles
	var cur := _tile_under(w, ctl)
	if cur < 0:
		cur = int(mem.get("cur_tile", -1))
	else:
		mem["cur_tile"] = cur
	# thicc_ben's launch cycle pins a body that keeps standing under him: no ground for
	# 240 ticks at an uncollected gift goal means the gift is ungrabbable right now -
	# release it for the rest of the level and path elsewhere (a human walks off)
	var was_grounded: bool = bool(mem.get("was_grounded", true))
	if bool(ctl.grounded):
		if not was_grounded:
			# just landed (often short of or past the planned waypoint after a jump):
			# re-route from where the feet actually are (D-FIX-A3-1)
			mem["repath"] = true
		mem["air_ticks"] = 0
	else:
		mem["air_ticks"] = int(mem["air_ticks"]) + 1
		if str(mem["goal_kind"]) == "gift" and int(mem["goal_slot"]) >= 0:
			if not (mem["air_released"] as Dictionary).has(int(mem["goal_slot"])) \
					and int(mem["air_ticks"]) >= 240:
				(mem["air_released"] as Dictionary)[int(mem["goal_slot"])] = true
				mem["repath"] = true
	mem["was_grounded"] = bool(ctl.grounded)
	if bool(mem["repath"]) or _goal_stale(mem, lv) or int(mem["replan_in"]) <= 0:
		_replan(mem, lv, ctl, cur, w2, tiles, adj, L)
		mem["repath"] = false
		mem["replan_in"] = REPLAN_TICKS
	else:
		mem["replan_in"] = int(mem["replan_in"]) - 1
	var buttons := 0
	if int(mem["jump_hold"]) > 0:
		buttons |= BUTTON_JUMP
		mem["jump_hold"] = int(mem["jump_hold"]) - 1
	var path: Array = mem["path"]
	var pi := int(mem["path_i"])
	# COMMITTED FLIGHT (void-fall fix): once a validated jump leaves the ground the bot
	# flies the arc _jump_arc simulated - neutral for `delay` ticks, then _air_steer to
	# the landing column - until it lands. The old follower re-validated the edge every
	# airborne tick as if a fresh jump started mid-air, banned it when that "failed" and
	# commanded ZERO, which braked the bot out of the arc into the void.
	var acc_air: float = float(ctl.C["accel"]) * float(ctl.friction_mult(w))
	var flight: Dictionary = mem.get("flight", {})
	if bool(ctl.grounded):
		if not flight.is_empty():
			mem["flight"] = {}
	elif not flight.is_empty():
		var mvf := Vector2.ZERO
		if int(mem.get("tick", 0)) - int(flight["t0"]) >= int(flight["delay"]):
			mvf = _air_steer(float(ctl.x), float(ctl.z), float(ctl.vx), float(ctl.vz),
					float(flight["x"]), float(flight["z"]), acc_air)
		return {"move": mvf, "buttons": buttons}
	elif float(ctl.coyote) <= 0.0:
		# airborne with no committed jump (stepped off, a hurdle hop, knocked): steer
		# the landing onto the next waypoint when it is as near as any footing below,
		# else onto the nearest column with ground under the feet - never hold a
		# heading that runs on over the void
		var px_a := float(ctl.x)
		var pz_a := float(ctl.z)
		var feet_a := float(ctl.y)
		var eps_a: Array = _enemy_points(rt)
		var tgt: Vector2 = _nearest_landing(w, px_a, feet_a, pz_a, 3.0, eps_a,
				eps_a, _enemy_reach(rt))
		if tgt.x == INF:
			# D-B5B-1: every column clear of a body needs a fall THROUGH one. Take the
			# original pick rather than inventing a worse one - the point test is what
			# the bot had before, and it is right whenever the body is not in the way.
			tgt = _nearest_landing(w, px_a, feet_a, pz_a, 3.0, eps_a)
		var lpi := pi
		while lpi < path.size() and int(path[lpi]) == cur:
			lpi += 1
		if lpi < path.size():
			var lt: Array = tiles[int(path[lpi])]
			var wpc := Vector2(float(lt[0]) + 0.5, float(lt[1]) + 0.5)
			var here := Vector2(px_a, pz_a)
			if float(lt[2]) * 0.5 <= feet_a + 0.3 and not _near_any(wpc, eps_a, LAND_CLEAR) \
					and (tgt.x == INF \
					or here.distance_to(wpc) <= here.distance_to(tgt) + 0.75):
				tgt = wpc
		if tgt.x != INF:
			return {"move": _air_steer(px_a, pz_a, float(ctl.vx), float(ctl.vz),
					tgt.x, tgt.y, acc_air), "buttons": buttons}
	if path.is_empty() or pi >= path.size():
		# no waypoints left: walk straight onto the goal point (its XZ must be reached;
		# the gift's hover height is out of reach and stopping under it in 3D stops the bot
		# just short of the pickup radius - the XZ distance is what collection needs).
		# Only onto a REAL goal, and only where the straight line keeps ground support
		# (D-FIX-A3-1): with no path and no goal the old code walked toward the world
		# origin - straight into the void.
		if str(mem["goal_kind"]) == "beacon" or int(mem["goal_slot"]) >= 0:
			var gp := _goal_point(mem, lv)
			var d3 := Vector2(gp.x - float(ctl.x), gp.z - float(ctl.z))
			if d3.length() > 0.1 and _step_safe(w, ctl, d3.normalized()):
				return {"move": d3.normalized(), "buttons": buttons}
		return {"move": Vector2.ZERO, "buttons": buttons}
	while pi < path.size() and path[pi] == cur:
		pi += 1
	mem["path_i"] = pi
	if pi >= path.size():
		var gp2 := _goal_point(mem, lv)
		var d4 := Vector2(gp2.x - float(ctl.x), gp2.z - float(ctl.z))
		if d4.length() > 0.1 and _step_safe(w, ctl, d4.normalized()):
			return {"move": d4.normalized(), "buttons": buttons}
		return {"move": Vector2.ZERO, "buttons": buttons}
	var wp: int = int(path[pi])
	mem["last_wp"] = wp
	var wt: Array = tiles[wp]
	var wp0 := Vector2(float(wt[0]) + 0.5, float(wt[1]) + 0.5)
	# Enemy hold (D-FIX-A3-2): a contact-kill body parked on the NEXT waypoint must
	# not be walked or jumped into - but ONLY when it is parked (not closing on the
	# player) and the player is not already inside its reach: standing for a chaser
	# is the death spiral (seed 2/28: the hold froze the bot, the cat floated in,
	# the in-place hop did not clear it, and invulnerability ended under the cat).
	for e2 in rt.enemies:
		if not bool(e2.get("contact_kill", true)):
			continue
		var ex2 := float(e2["x"]) - wp0.x
		var ez2 := float(e2["z"]) - wp0.y
		var ey2 := absf(float(e2.get("y", 0.0)) - float(wt[2]) * 0.5)
		if not (ex2 * ex2 + ez2 * ez2 < 2.0 * 2.0 and ey2 < 2.0):
			continue
		var dxp := float(ctl.x) - float(e2["x"])
		var dzp := float(ctl.z) - float(e2["z"])
		var d2p := dxp * dxp + dzp * dzp
		if d2p < 2.2 * 2.2:
			continue   # it has found the player: avoidance/hurdle own this moment
		var evh2 := _e_vel(mem, e2)
		if d2p > 1e-8 and (evh2.x * dxp + evh2.y * dzp) / sqrt(d2p) > 0.5:
			continue   # it is coming for the player: do not stand for it
		return {"move": Vector2.ZERO, "buttons": buttons}
	var wp_pos := Vector2(float(wt[0]) + 0.5, float(wt[1]) + 0.5)
	var d2 := wp_pos - Vector2(ctl.x, ctl.z)
	var dist := d2.length()
	if dist < 0.05:
		return {"move": Vector2.ZERO, "buttons": buttons}
	var dir := d2 / dist
	var ct: Array = tiles[cur] if cur >= 0 else wt
	var dy := int(wt[2]) - int(ct[2])
	var dx := absi(int(wt[0]) - int(ct[0]))
	var dz := absi(int(wt[1]) - int(ct[1]))
	var is_walk := dx <= 1 and dz <= 1 and absi(dy) <= 1   # the movement graph's own walk definition
	var mag := 1.0
	if cur < 0:
		# airborne over the void with no tile under the feet: hold course toward the
		# waypoint (steering only - nothing else can be done mid-fall)
		pass
	elif not is_walk:
		# EDGE DISCIPLINE (D-FIX-A3-1): a non-walk edge is only followed when the
		# controller's own jump physics validate an arc from THIS state that lands on
		# a tile. No validated arc -> the edge is banned and the route re-plans; the
		# bot never steps off a takeoff tile on faith.
		var plan: Dictionary = _jump_plan(ct, wt, wp_pos, dir, dy, 0.0, ctl, w, rt,
					mem.get("mines", []))
		if plan.is_empty() and bool(ctl.grounded) \
				and Vector2(float(ctl.x), float(ctl.z)).distance_to(_cell_exit(ct, dir)) > 0.55 \
				and _step_safe(w, ctl, dir):
			# no arc from back here, but the takeoff edge is still ahead on solid
			# ground: close in on it first; the edge is only refused at the edge
			return {"move": dir, "buttons": buttons}
		if plan.is_empty() or float(plan["mag"]) <= 0.0 or int(plan["hold"]) <= 0:
			var ek := "%d>%d" % [cur, wp]
			if not bool((mem["banned"] as Dictionary).get(ek, false)) and cur != wp:
				(mem["banned"] as Dictionary)[ek] = true
				mem["repath"] = true
			return {"move": Vector2.ZERO, "buttons": buttons}
		# the validated arc carries its own approach speed (plan["mag"]); keep it
		mag = float(plan["mag"])
		var exitp := _cell_exit(ct, dir)
		var D := exitp.distance_to(wp_pos)
		var d_exit := Vector2(float(ctl.x), float(ctl.z)).distance_to(exitp)
		# Takeoff window (D-FIX-A3-1): grounded within half a tile of the cell exit
		# (the arc sim assumes takeoff at the CURRENT pos/v, so a grounded press is
		# exactly valid), or in the post-step-off coyote window. The old gate
		# (pi >= 1 AND coyote > 0) never fired on the ground, so the bot stepped off
		# every gap edge, missed the 0.1 s coyote deadline while pi was still 0, and
		# could not jump at all - the trace's grounded=false coyote=0.00 death state.
		var at_exit: bool = (bool(ctl.grounded) and d_exit <= 0.55) or float(ctl.coyote) > 0.0
		var jump: bool = (bool(ctl.grounded) or float(ctl.coyote) > 0.0) and at_exit \
				and int(plan["hold"]) > 0
		if TRACE:
			print("PLAN t=%d pi=%d cur=%d wp=%d dy=%d D=%.2f at_exit=%s grounded=%s coyote=%.2f jump=%s" % [
				mem.get("tick", -1), pi, cur, wp, dy, D, str(at_exit), str(ctl.grounded),
				float(ctl.coyote), str(jump)])
		if int(mem.get("tick", 0)) - int(mem.get("pushed_at", -100)) <= 1:
			jump = false   # mid-shove: the arc the sim validated would not be the one flown
		if jump and int(mem["jump_hold"]) == 0 and (int(ctl.prev_buttons) & BUTTON_JUMP) == 0:
			mem["jump_hold"] = int(plan["hold"])
			buttons |= BUTTON_JUMP
			mem["jump_hold"] = int(mem["jump_hold"]) - 1
			# commit the flight _jump_arc validated; this tick's input is its tick 0
			mem["flight"] = {"x": wp_pos.x, "z": wp_pos.y, "delay": int(plan["delay"]),
					"t0": int(mem.get("tick", 0))}
			if int(plan["delay"]) > 0:
				mag = 0.0
			else:
				var mv0 := _air_steer(float(ctl.x), float(ctl.z), float(ctl.vx), float(ctl.vz),
						wp_pos.x, wp_pos.y, float(ctl.C["accel"]) * float(ctl.friction_mult(w)))
				dir = mv0
				mag = 1.0
			if TRACE:
				print("JUMP t=%d cur=(%d,%d,%d) wp=(%d,%d,%d) dy=%d D=%.2f mag=%.2f" % [
					mem.get("tick", -1), int(ct[0]), int(ct[1]), int(ct[2]),
					int(wt[0]), int(wt[1]), int(wt[2]), dy, D, mag])
		elif bool(ctl.grounded) and not _step_safe(w, ctl, dir):
			# validated but not jumping THIS tick (held button, mid-shove): never walk
			# the takeoff edge off on foot - wait for the press
			return {"move": Vector2.ZERO, "buttons": buttons}
	return {"move": dir * mag, "buttons": buttons}


## One tick of bot input. Dodge overrides routing; JUMP holds from _routing apply across
## both paths (jump-cut bookkeeping must survive a dodge mid-hop). A contact-kill enemy
## on the bot's tile line is hurdled (the roster's own counter-play, enemy.json's
## "hurdle it as it arrives"): the bot jumps when one is within HURDLE_DIST horizontally.
## Contact-kill bodies within AVOID_DIST also bend the bot's heading away from them
## (D-FIX-A3-2) - the router cannot see them, and a fast player outruns a chaser.
const HURDLE_DIST := 3.0
const HURDLE_HOLD := 22   # ticks of JUMP to hold: past the 0.375 s apex (vy 12 / gravity 32)
const AVOID_DIST := 3.0

static func _bot_input(mem: Dictionary, lv, rt, ctl, w, w2, gtiles: Array, adj: Array,
		L: Dictionary) -> Dictionary:
	var tick: int = lv.tick
	mem["tick"] = tick
	var dodge = _dodge_vector(mem, rt, ctl, tick, w)
	# YOU?!'s ring outlives its telegraph: modelled separately (_ring_threat)
	var ring: Dictionary = _ring_threat(rt, ctl)
	var move := Vector2.ZERO
	var buttons := 0
	# in the air the stick only steers the landing: a committed jump is flown to its
	# validated landing, any other airborne moment (hurdle hop, step-off, knock) to the
	# nearest footing - whatever else asks for the stick. Every arc was already refused
	# if it crossed a mine or a closing body; a mid-air swerve off it, or an avoid /
	# dodge heading held over a ledge, is how the bot met the void
	var in_flight: bool = not bool(ctl.grounded) and (float(ctl.coyote) <= 0.0 \
			or not (mem.get("flight", {}) as Dictionary).is_empty())
	if in_flight:
		var rf: Dictionary = _routing(mem, lv, ctl, rt, w, w2, gtiles, adj, L)
		# the trigger is height-blind: an airborne heading still never crosses a mine
		var mvA: Vector2 = _mine_guard(w, ctl, rf["move"], mem.get("mines", []))
		return {
			"move_x": clampi(int(round(mvA.x * 127.0)), -127, 127),
			"move_z": clampi(int(round(mvA.y * 127.0)), -127, 127),
			"buttons": int(rf["buttons"]),
			"aim_x": 0.0, "aim_z": 1.0,
		}
	if dodge != null:
		move = dodge
		if int(mem["jump_hold"]) > 0:
			buttons |= BUTTON_JUMP
			mem["jump_hold"] = int(mem["jump_hold"]) - 1
	else:
		var r: Dictionary = _routing(mem, lv, ctl, rt, w, w2, gtiles, adj, L)
		move = r["move"]
		buttons = int(r["buttons"])
		if bool(ring["threat"]):
			# a ring is on its way: stop walking into it (the routing goal is usually
			# back toward its centre) and wait for the jump; a ring too tall to jump
			# is outrun radially instead
			move = Vector2.ZERO
			if bool(ring["tall"]):
				move = _safe_dir(w, ctl, ring["out"])
		var avoid = _avoid_vector(rt, ctl, w, move)
		if avoid != null:
			move = avoid
	# the ring counter-play: jump as the band reaches the feet (held to the apex)
	if bool(ring["jump"]) and bool(ctl.grounded) and (buttons & BUTTON_JUMP) == 0 			and int(mem["jump_hold"]) == 0:
		buttons |= BUTTON_JUMP
		mem["jump_hold"] = HURDLE_HOLD - 1
	# Hurdle (D-FIX-A3-2): a CLOSING contact-kill body within HURDLE_DIST - hop IN
	# PLACE (vertical separation, zero ledge risk); a body moving away needs nothing.
	if TRACE and lv.tick % 15 == 0:
		for e in rt.enemies:
			var dxn := float(e["x"]) - float(ctl.x)
			var dzn := float(e["z"]) - float(ctl.z)
			if dxn * dxn + dzn * dzn < 49.0:
				print("NEARB t=%d %s d=%.2f ep=(%.2f,%.2f,%.2f) ev=(%.2f,%.2f) g=%s" % [
					lv.tick, str(e.get("id", "?")), sqrt(dxn * dxn + dzn * dzn),
					float(e["x"]), float(e["y"]), float(e["z"]),
					_e_vel(mem, e).x, _e_vel(mem, e).y, str(ctl.grounded)])
	if bool(ctl.grounded) and (buttons & BUTTON_JUMP) == 0:
		for e in rt.enemies:
			if not bool(e.get("contact_kill", true)):
				continue
			var dxh := float(ctl.x) - float(e["x"])
			var dzh := float(ctl.z) - float(e["z"])
			var d2h := dxh * dxh + dzh * dzh
			if d2h >= HURDLE_DIST * HURDLE_DIST:
				continue
			if absf(float(e.get("y", 0.0)) - float(ctl.y)) > BODY_H:
				continue
			var evh := _e_vel(mem, e)
			var closing := (evh.x * dxh + evh.y * dzh) / sqrt(maxf(d2h, 1e-8)) > 0.5
			if evh == Vector2.ZERO or closing:
				buttons |= BUTTON_JUMP
				# hold it: a one-tick press is jump-cut (jump_cut_mul 0.5, applied on
				# the tick after the press, before gravity) to a ~0.51 u apex - never in
				# DESIGN.md section 5.1's 1.5 u window (0.16-0.59 s of the jump) and
				# never above the body's own height_u, so enemy_runtime.gd body_contact
				# (feet above row.y + height_u) never breaks and the bot hops INTO the
				# cat - the "in-place hop did not clear it" of the seed 2/28 trace.
				# HURDLE_HOLD ticks puts the release at vy ~0.3 u/s, i.e. at the apex,
				# so the cut only re-scales that and the arc is the full ~2.2 u one.
				mem["jump_hold"] = maxi(int(mem["jump_hold"]), HURDLE_HOLD)
				# keep the routing move: the leap carries momentum OVER the body
				if move != Vector2.ZERO and not _dir_has_support(w, ctl, move.normalized()):
					move = Vector2.ZERO   # forward line runs off a ledge: hop in place
				break
	# tripmines are lethal ground: the final heading never runs the centre into a
	# live mine's trigger cylinder, whichever layer chose it
	move = _mine_guard(w, ctl, move, mem.get("mines", []))
	return {
		"move_x": clampi(int(round(move.x * 127.0)), -127, 127),
		"move_z": clampi(int(round(move.y * 127.0)), -127, 127),
		"buttons": buttons,
		"aim_x": 0.0, "aim_z": 1.0,
	}


# ---------------------------------------------------------------- CLI --

func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var runs: int = int(args.get("runs", RUNS_DEFAULT))
	var seed_base: int = int(args.get("seed_base", SEED_BASE))
	var max_level: int = int(args.get("max_level", MAX_LEVEL_DEFAULT))
	var log_runs: bool = bool(args.get("log", false))
	var log_dir: String = str(args.get("log_dir", ""))
	if bool(args.get("trace", false)):
		TRACE = true
	print("BOT RUN (runs=%d seed_base=%d max_level=%d votes=seeded-random class=seeded-random log=%s)" % [
		runs, seed_base, max_level, "yes" if log_runs else "no"])
	var agg: Dictionary = run_probe(runs, seed_base, max_level, log_runs, log_dir)
	if not bool(agg.get("ok", false)):
		print("BOT_RUN FAIL (content boot refused: %s)" % " / ".join(agg.get("boot_errors", [])))
		quit(1)
		return
	for i in agg["rows"].size():
		var rd: Dictionary = agg["rows"][i]
		var extra := ""
		if str(rd["outcome"]) == "dead":
			extra = " tick=%d killer=%s code=%s" % [int(rd["death_tick"]), str(rd["death_killer"]), str(rd["death_code"])]
		print("run %d seed=%d class=%s entered=%d outcome=%s l1_tick=%s reached_6=%s reached_12=%s reached_18=%s%s" % [
			i, int(rd["seed"]), str(rd["class"]), int(rd["entered"]),
			str(rd["outcome"]), str(int(rd.get("l1_tick", -1))),
			str(rd["reached_6"]), str(rd["reached_12"]), str(rd["reached_18"]), extra])
	# FIX-A3 summary: level-1 completions, the median sim time of a COMPLETED level 1,
	# the death-code histogram, the levels reached. Informational - the criterion
	# itself lives in FLEET_PACK section 5 / DECISIONS, never weakened here.
	var comps := 0
	var times: Array = []
	var codes := {}
	var levs: Array = []
	for i in agg["rows"].size():
		var rd: Dictionary = agg["rows"][i]
		if int(rd.get("l1_tick", -1)) >= 0:
			comps += 1
			times.append(float(int(rd["l1_tick"])) / 60.0)
		if str(rd.get("outcome", "")) == "dead":
			var dc := str(rd.get("death_code", ""))
			codes[dc] = int(codes.get(dc, 0)) + 1
		levs.append(int(rd.get("entered", 0)))
	times.sort()
	levs.sort()
	var med := -1.0
	if not times.is_empty():
		var h := times.size() >> 1
		med = times[h] if times.size() % 2 == 1 else 0.5 * (times[h - 1] + times[h])
	var med_lev := -1
	if not levs.is_empty():
		med_lev = levs[levs.size() >> 1]
	print("A3 SUMMARY level 1: completed %d/%d | median sim time %.1f s (completed runs%s) | levels reached: median %d max %d" % [
		comps, agg["rows"].size(), med,
		"" if not times.is_empty() else ", n/a - none completed", med_lev, levs[levs.size() - 1]])
	var code_keys: Array = codes.keys()
	code_keys.sort()
	for c in code_keys:
		print("A3 deaths %s: %d" % [str(c), int(codes[c])])
	print(format_report(agg))
	print("BOT_RUN OK (%d runs, deterministic seed set seed_base=%d..%d)" % [runs, seed_base, seed_base + runs - 1])
	quit(0)


static func _parse_args(user_args: PackedStringArray) -> Dictionary:
	var out := {"runs": RUNS_DEFAULT, "seed_base": SEED_BASE, "max_level": MAX_LEVEL_DEFAULT,
			"trace": false, "log": false, "log_dir": ""}
	var i := 0
	while i < user_args.size():
		var a := str(user_args[i])
		if a == "--dodge":
			pass  # the one dodge policy there is; accepted explicitly (T-060 spec)
		elif a == "--log":
			out["log"] = true   # T-081: one T-080 run log per run
		elif a == "--log-dir" and i + 1 < user_args.size():
			out["log_dir"] = str(user_args[i + 1])
			i += 1
		elif a == "--runs" and i + 1 < user_args.size():
			out["runs"] = int(user_args[i + 1])
			i += 1
		elif a == "--seed-base" and i + 1 < user_args.size():
			out["seed_base"] = int(user_args[i + 1])
			i += 1
		elif a == "--max-level" and i + 1 < user_args.size():
			out["max_level"] = int(user_args[i + 1])
			i += 1
		elif a == "--trace":
			out["trace"] = true
		elif a.begins_with("--runs="):
			out["runs"] = int(a.get_slice("=", 1))
		elif a.begins_with("--seed-base="):
			out["seed_base"] = int(a.get_slice("=", 1))
		elif a.begins_with("--max-level="):
			out["max_level"] = int(a.get_slice("=", 1))
		i += 1
	return out
