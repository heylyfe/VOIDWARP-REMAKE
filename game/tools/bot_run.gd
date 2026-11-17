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

## FROZEN bands (DESIGN.md section 9) - never changed, never weakened. Level -> [lo, hi, label]
const BANDS := [
	[6, 0.80, 1.00, ">= 80%"],
	[12, 0.40, 0.60, "40-60%"],
	[18, 0.15, 0.30, "15-30%"],
]

# ---------------------------------------------------------------- report helpers (pure) --

## Aggregate one sweep's per-run dicts into the report rows. Pure - the test asserts on it.
static func summarize(results: Array) -> Dictionary:
	var out := {"runs": results.size(), "reached": {}, "stuck": 0, "class_counts": {}}
	for lv in [6, 12, 18]:
		(out["reached"] as Dictionary)[lv] = 0
	for r in results:
		var rd: Dictionary = r
		for lv in [6, 12, 18]:
			if bool(rd.get("reached_%d" % lv, false)):
				(out["reached"] as Dictionary)[lv] = int((out["reached"] as Dictionary)[lv]) + 1
		if str(rd.get("outcome", "")) == "stuck":
			out["stuck"] = int(out["stuck"]) + 1
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

## One full probe run. Returns {"reached_6","reached_12","reached_18","outcome","entered","class"}
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
	# the pre-run lobby (level_completed 0; picks the class + the first enemy vote)
	_resolve_lobby(api, ledger, 0, seed, p_log)
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
			_resolve_lobby(api, ledger, entered - 1, seed, p_log)
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
	}


## Resolve one intermission the bot way: every mandatory bay gets a seeded uniform random
## pick among its offer altars (CLASS/E/C), rerolling the E x2 bay between votes via the
## sim's own select path. U / REST bays are never touched (the bot buys nothing). A C bay
## whose draw is empty can only be tithe-passed (DESIGN.md section 11) - paid when
## affordable, otherwise the run stalls on the lobby and is reported as "stuck".
static func _resolve_lobby(api: RefCounted, ledger: Dictionary, level_completed: int,
		seed: int, p_log = null) -> void:
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


static func _route(adj: Array, tiles: Array, start: int, banned: Dictionary) -> Dictionary:
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
			a_in = _bot_input(mem, lv, rt, ctl, w, w2, gtiles, adj, L)
			if bool(p_rec.get("record", false)):
				(p_rec["inputs"] as Array).append(a_in.duplicate(true))
		var ev: Array = []
		for e in ctl.step(DT, a_in, w):
			ev.append(e)
		if bool(ctl.grounded):
			mem["ground_tile"] = _tile_under(w, ctl)
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
		"seen": 0, "first_seen": {},
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

## Register newly appeared telegraph dicts (the runtime's array is append-only).
static func _track_telegraphs(mem: Dictionary, rt, tick: int) -> void:
	var seen: int = int(mem["seen"])
	for i in range(seen, rt.telegraphs.size()):
		mem["first_seen"][i] = tick
	mem["seen"] = rt.telegraphs.size()


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


## The dodge input for this tick, or null when no telegraph demands one.
## Reacts REACT_TICKS (250 ms) after a telegraph appears - never on the tick it appears.
## The escape direction is ledge-checked (D-FIX-A3-1): if the straight escape runs off
## the walkway into the void, the bot rotates it in 30-degree steps (both ways, nearest
## first) to a direction that keeps ground support - a strike beats a D-VOID fall
## (T-060/T-081: 60% of deaths were void falls, and a straight-out dodge caused many).
static func _dodge_vector(mem: Dictionary, rt, ctl, tick: int, w) -> Variant:
	var best_strike := 1 << 30
	var best_shape: Dictionary = {}
	for i in range(int(mem["seen"])):
		var fs_v: Variant = mem["first_seen"].get(i, null)
		if fs_v == null:
			continue
		var t: Dictionary = rt.telegraphs[i]
		var fs := int(fs_v)
		var strike := fs + int(t.get("total", 0))
		var t_now := int(t.get("ticks", 0))
		if strike < tick or t_now <= 0:
			# strike has landed (or the entry died): forget it
			if tick - fs > int(t.get("total", 0)) + 120:
				mem["first_seen"].erase(i)
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
## edge-discipline fix). Within AVOID_DIST of a contact-kill body (and within 1.5 u of
## its own height) the bot steers around it instead of through it: pure flee when it
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
		if absf(float(e.get("y", 0.0)) - float(ctl.y)) > 1.5:
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


## True when walking from the feet toward `dir` keeps ground support over the next
## ~0.9 u (a same-level straight walk may only be commanded onto ground that exists).
static func _step_safe(w, ctl, dir: Vector2) -> bool:
	var px := float(ctl.x)
	var py := float(ctl.y)
	var pz := float(ctl.z)
	for d in [0.45, 0.9]:
		if _tile_under(w, {"x": px + dir.x * d, "y": py, "z": pz + dir.y * d}) < 0:
			return false
	return true


## True when an escape run toward `dir` from the feet keeps support over the next
## ~1.9 u (a dodge may last several tenths of a second at run speed).
static func _dir_has_support(w, ctl, dir: Vector2) -> bool:
	var px := float(ctl.x)
	var py := float(ctl.y)
	var pz := float(ctl.z)
	for d in [0.4, 0.8, 1.3, 1.9]:
		if _tile_under(w, {"x": px + dir.x * d, "y": py, "z": pz + dir.y * d}) < 0:
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

## Forward-simulate the controller's jump physics (vy = 12 on jump, gravity 32 on the way
## down, vy *= 0.5 on release after k ticks, accel 90 u/s^2 toward the target velocity)
## from the CURRENT state and find an arc that lands on a tile. Returns {"v": speed,
## "hold": ticks to hold JUMP} - or {} when no candidate arc lands on a tile. Deterministic.
## The bot jumps exactly when this finds an arc - i.e., exactly when a jump would work.
static func _jump_arc(ctl, w, wp_x: float, wp_z: float) -> Dictionary:
	var x0 := float(ctl.x)
	var y0 := float(ctl.y)
	var z0 := float(ctl.z)
	var vx0 := float(ctl.vx)
	var vz0 := float(ctl.vz)
	var dx := wp_x - x0
	var dz := wp_z - z0
	var dl := sqrt(dx * dx + dz * dz)
	if dl < 1e-6:
		return {}
	var dir_x := dx / dl
	var dir_z := dz / dl
	var ct_takeoff := _tile_under(w, {"x": x0, "y": y0, "z": z0})
	var v_opts := [9.0, 7.5, 6.0, 4.0, 2.0]
	var k_opts := [0, 2, 4, 8, 14, 22, 30]
	for k in k_opts:
		for v_max in v_opts:
			var x := x0
			var y := y0
			var z := z0
			var vx := vx0
			var vz := vz0
			var vy := 12.0
			var grounded := false
			for tick in range(240):
				vy -= 32.0 * DT
				if tick == k and vy > 0.0:
					vy *= 0.5
				# accel toward v_max * dir (friction 1.0)
				var tvx: float = dir_x * v_max
				var tvz: float = dir_z * v_max
				var ddx: float = tvx - vx
				var ddz: float = tvz - vz
				var dlen := sqrt(ddx * ddx + ddz * ddz)
				if dlen > 1e-9:
					var want := 1.5
					var s := 1.0 if want >= dlen else want / dlen
					vx += ddx * s
					vz += ddz * s
				var r = CollisionScript.move_body(w, x, y, z, vx * DT, vy * DT, vz * DT,
						1.8, 0.5, grounded)
				x = r["x"]
				y = r["y"]
				z = r["z"]
				grounded = bool(r["grounded"])
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
							return {"v": v_max, "hold": k + 1}
					break
				if y < -40.0:
					break
			# no arc from this candidate set was found at this position
			pass
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
		dy_hu: int, vz: float, ctl, w) -> Dictionary:
	var exit := _cell_exit(ct, dir)
	var D := exit.distance_to(wp_pos)
	var rise := float(dy_hu) * 0.5
	var arc := _jump_arc(ctl, w, wp_pos.x, wp_pos.y)
	if arc.is_empty():
		# no arc lands on a tile from this position/orientation: refuse the edge (the
		# caller bans it and re-routes - "walk off and pray" is what produced the
		# D-VOID epidemic; FIX-A3)
		return {}
	# the arc the sim validated may use a LOW approach speed (e.g. a gentle hop over a
	# 1-cell wall): the bot must keep THAT speed, not launch at 9 u/s past the tile
	return {"mag": maxf(float(arc["v"]) / 9.0, 0.25), "hold": int(arc["hold"])}


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
	if bool(lv.beacon.is_open()):
		goal_kind = "beacon"
		var b: Array = L.get("beacon", [0, 0, 1])
		goal_tile = VoidGenScript.find_tile(w2, int(b[0]), int(b[1]), int(b[2]))
		if cur >= 0 and goal_tile >= 0:
			var rb: Dictionary = _route(adj, gtiles, cur, mem.get("banned", {}))
			if int((rb["dist"] as PackedInt32Array)[goal_tile]) < 0:
				# the beacon is behind a banned edge: the beacon is the level's only
				# way out, so lift the bans and try the full graph
				mem["banned"] = {}
				rb = _route(adj, gtiles, cur, {})
			if int((rb["dist"] as PackedInt32Array)[goal_tile]) >= 0:
				mem["path"] = _path_to(rb["parent"], cur, goal_tile)
				mem["path_i"] = 0
				mem["goal_kind"] = goal_kind
				mem["goal_tile"] = goal_tile
				mem["goal_slot"] = -1
				return
	elif cur >= 0:
		var route: Dictionary = _route(adj, gtiles, cur, mem.get("banned", {}))
		var pick: Array = _nearest_gift(lv, mem, route["dist"], false)
		if int(pick[0]) < 0 and int(lv.tick) >= int(mem.get("lift_at", 0)):
			# nothing reachable: the bans (or the thicc_ben releases) over-constrained
			# the route. Lift both after a cooldown and re-pick.
			mem["banned"] = {}
			mem["air_released"] = {}
			mem["lift_at"] = int(lv.tick) + 300
			route = _route(adj, gtiles, cur, {})
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
		if not lv.gifts.is_real(i) or lv.gifts.collected(i):
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


## Is the current goal invalid (gift collected / beacon opened)?
static func _goal_stale(mem: Dictionary, lv) -> bool:
	if str(mem["goal_kind"]) == "beacon":
		return false
	if bool(lv.beacon.is_open()):
		return true
	var slot := int(mem["goal_slot"])
	if slot < 0:
		return true
	return lv.gifts.collected(slot)


## Routing input for this tick: {"move": Vector2, "buttons": int}.
static func _routing(mem: Dictionary, lv, ctl, w, w2, gtiles: Array, adj: Array,
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
	var is_walk := dx <= 1 and dz <= 1 and dy == 0   # downhill edges are hop-downs, not walks - the bot would flutter off them and never land
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
		var plan: Dictionary = _jump_plan(ct, wt, wp_pos, dir, dy, 0.0, ctl, w)
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
		if jump and int(mem["jump_hold"]) == 0:
			mem["jump_hold"] = int(plan["hold"])
			buttons |= BUTTON_JUMP
			mem["jump_hold"] = int(mem["jump_hold"]) - 1
			if TRACE:
				print("JUMP t=%d cur=(%d,%d,%d) wp=(%d,%d,%d) dy=%d D=%.2f mag=%.2f" % [
					mem.get("tick", -1), int(ct[0]), int(ct[1]), int(ct[2]),
					int(wt[0]), int(wt[1]), int(wt[2]), dy, D, mag])
	return {"move": dir * mag, "buttons": buttons}


## One tick of bot input. Dodge overrides routing; JUMP holds from _routing apply across
## both paths (jump-cut bookkeeping must survive a dodge mid-hop). A contact-kill enemy
## on the bot's tile line is hurdled (the roster's own counter-play, enemy.json's
## "hurdle it as it arrives"): the bot jumps when one is within HURDLE_DIST horizontally.
## Contact-kill bodies within AVOID_DIST also bend the bot's heading away from them
## (D-FIX-A3-2) - the router cannot see them, and a fast player outruns a chaser.
const HURDLE_DIST := 1.6
const AVOID_DIST := 3.0

static func _bot_input(mem: Dictionary, lv, rt, ctl, w, w2, gtiles: Array, adj: Array,
		L: Dictionary) -> Dictionary:
	var tick: int = lv.tick
	mem["tick"] = tick
	var dodge = _dodge_vector(mem, rt, ctl, tick, w)
	var move := Vector2.ZERO
	var buttons := 0
	if dodge != null:
		move = dodge
		if int(mem["jump_hold"]) > 0:
			buttons |= BUTTON_JUMP
			mem["jump_hold"] = int(mem["jump_hold"]) - 1
	else:
		var r: Dictionary = _routing(mem, lv, ctl, w, w2, gtiles, adj, L)
		move = r["move"]
		buttons = int(r["buttons"])
		var avoid = _avoid_vector(rt, ctl, w, move)
		if avoid != null:
			move = avoid
	# hurdle a contact-kill enemy on the tile line (grounded only; the arc clears 0.9 u
	# bodies) - but never hurdle off a ledge (D-FIX-A3-1): with a heading that has no
	# support ahead the bot jumps in place instead of leaping into the void
	if bool(ctl.grounded) and (buttons & BUTTON_JUMP) == 0:
		for e in rt.enemies:
			if not bool(e.get("contact_kill", true)):
				continue
			var dx := float(e["x"]) - float(ctl.x)
			var dz := float(e["z"]) - float(ctl.z)
			if dx * dx + dz * dz < HURDLE_DIST * HURDLE_DIST:
				if move != Vector2.ZERO and not _dir_has_support(w, ctl, move.normalized()):
					break   # no ground ahead: jump in place is the safe hurdle
				buttons |= BUTTON_JUMP
				break
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
		print("run %d seed=%d class=%s entered=%d outcome=%s reached_6=%s reached_12=%s reached_18=%s%s" % [
			i, int(rd["seed"]), str(rd["class"]), int(rd["entered"]),
			str(rd["outcome"]), str(rd["reached_6"]), str(rd["reached_12"]), str(rd["reached_18"]), extra])
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
