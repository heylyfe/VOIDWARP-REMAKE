extends RefCounted
#
# app/run_log.gd - the telemetry event log (ticket T-080; DESIGN.md sections 3 / 13;
# research/fable-funrisks.md T-080 paragraph, the owner's spec verbatim).
#
# THE HARD CONSTRAINT: this is app/view layer. Every record is derived from EVENTS -
# typed sim events, controller-layer raw dicts, and the driver's own app-level events
# (level_start / offer / lobby_enter / lobby_exit / run_end). It NEVER reads or writes
# simulation state: the values a record needs that no event carries are either derived
# from the event stream (the chain multiplier from the gold-gift beat + chain_reset
# events; pushed-in-last-120 from push events; gold collected/available from the gift
# events and level_start's payload) or supplied by the app layer, whose terrain/lobby
# inputs are pre-sim facts (the Level dict's slot rows, the votes ledger, the purse).
# The replay test stays green with the log on and off - that is the proof.
#
# One JSON object per line to user://runs/<run_seed>_<start_tick>.jsonl. Record shape:
#   {"t": int, "level": int, "phase": "black"|"gold"|"lobby", "type": String, "payload": {...}}
# t is the run-wide accumulated tick (level ticks continue past each lobby; the lobby
# consumes no sim ticks) - D-T080-3.
#
# Closed type list (owner spec): run_start, level_start, gift, void_fall, charge_spent,
# charge_restored, mine_pass, mine_contact, death, last_light, beacon_open, beacon_enter,
# level_clear, offer, pick, lobby_enter, lobby_exit, run_end.
#
# Pure app layer: no Node, no engine types beyond FileAccess/DirAccess, no RNG.

## The chain window (economy.gd's 4.0 s) in ticks, mirrored here so the gold gift's
## chain value can be reconstructed from the event stream alone (D-T080-4).
const WINDOW_TICKS := 240
## The centi-multiplier scale: chain x1.00 = 100, +5 per in-window gold gift, cap 200
## (economy.gd's CHAIN_START_CENTI / increment / cap, mirrored for the gift payload).
const CHAIN_START := 100
const CHAIN_INCREMENT := 5
const CHAIN_CAP := 200
## Push attribution window (owner spec: "pushed-in-last-120-ticks").
const PUSH_WINDOW := 120

var path: String = ""
var open_ok: bool = false
var total_t: int = 0
var level_number: int = 0
var phase: String = "lobby"
# The chain replica (fed by gold gifts, chain_reset events and the beacon_open event).
var chain_centi := CHAIN_START
var since_tick := 0      # the last tick the chain's window restarted on
# Per-level anchors (reset by level_started).
var level_start_t := -1
var beacon_open_t := -1
var gold_count := 0      # gold gifts collected this level (from gold gift events)
var gold_available := 0  # real_gifts of the level_start payload (every black slot goes gold)
var cur_overtime := 0    # the last overtime_tier event's tier
# Push history for the void_fall record: {"t", "by"} entries, pruned on read.
var push_hist: Array = []
# A mine_contact's outcome arrives later IN THE SAME tick's array (the contact ladder);
# buffered here across feed_tick's batch, flushed as "killed" if nothing else said it.
var _pending_mine_contact: int = -1

var _fh: FileAccess = null


# ---- the app-facing api ------------------------------------------------------------------

## Opens the run's file user://runs/<run_seed>_<start_tick>.jsonl and writes run_start.
## start_tick is the accumulated tick this log begins at (0 for a fresh run).
func run_started(p_run_seed: int, class_id: String, p_start_tick: int = 0) -> void:
	total_t = p_start_tick
	path = "user://runs/%d_%d.jsonl" % [p_run_seed, p_start_tick]
	DirAccess.make_dir_recursive_absolute("user://runs")
	_fh = FileAccess.open(path, FileAccess.WRITE)
	open_ok = _fh != null
	phase = "lobby"
	level_number = 0
	_record("run_start", {"seed": p_run_seed, "class": class_id})


## The app layer announces a level: the slot counts come from the Level dict (terrain,
## a pure input), enemies from the driver's own spawn-plan vote ledger. level_start_t
## anchors the per-level timing equation the done-when asserts.
func level_started(p_level: int, slots: int, real_gifts: int, mines: int,
		enemies_in_play: int) -> void:
	level_number = p_level
	phase = "black"
	level_start_t = total_t
	beacon_open_t = -1
	gold_count = 0
	gold_available = int(real_gifts)
	cur_overtime = 0
	_pending_mine_contact = -1
	_record("level_start", {"slots": int(slots), "real_gifts": int(real_gifts),
			"mines": int(mines), "enemies": int(enemies_in_play)})


## One level tick's events (typed sim events + controller raw dicts mixed, exactly the
## per-tick list the driver assembled). Advances the run clock by one tick.
func feed_tick(events: Array) -> void:
	for ev in events:
		_feed_one(ev)
	if _pending_mine_contact >= 0:
		# a contact whose ladder output this batch never carried: killed is the only
		# remaining outcome in the closed outcome set
		_record("mine_contact", {"slot": _pending_mine_contact, "outcome": "killed"})
	_pending_mine_contact = -1
	total_t += 1


## The lobby's select events (EV_ALTAR_SELECTED batch - the driver collects them from
## intermission.apply_select and hands them over; the lobby consumes no sim ticks).
func feed_lobby(events: Array) -> void:
	for ev in events:
		if str(ev.get("type", "")) == "altar_selected":
			_record("pick", {"bay": str(ev.get("bay", "")), "id": str(ev.get("id", "")),
					"price": int(ev.get("cost", 0))})


## The app layer's view events: the lobby it entered (level_completed = the level just
## finished, 0 = the pre-run lobby) and one offer row per presented bay.
func lobby_entered(p_level_completed: int) -> void:
	level_number = p_level_completed
	phase = "lobby"
	_record("lobby_enter", {})


func offer_shown(bay: String, ids: Array) -> void:
	_record("offer", {"bay": bay, "ids": ids})


func lobby_left() -> void:
	_record("lobby_exit", {})


## The run's end (the app harness stops, or the player died): level reached, purse.
func run_finished(p_level_reached: int, purse: int) -> void:
	_record("run_end", {"level_reached": int(p_level_reached), "purse": int(purse)})


## Flushes and closes the file. Records after close are dropped (open_ok stays as is).
func close() -> void:
	if _fh != null:
		_fh.flush()
		_fh.close()
	_fh = null


# ---- the event switch --------------------------------------------------------------------

func _feed_one(ev: Dictionary) -> void:
	var ty := str(ev.get("type", ""))
	if ty == "gift_collected":
		var wal := str(ev.get("phase", "black"))
		_advance_chain(wal == "gold")
		_record("gift", {"slot": int(ev.get("slot", -1)), "phase": wal,
				"chain": float(chain_centi) / float(CHAIN_START)})
		if wal == "gold":
			gold_count += 1
		return
	if ty == "beacon_opened":
		phase = "gold"
		beacon_open_t = total_t
		chain_centi = CHAIN_START
		since_tick = total_t
		_record("beacon_open", {})
		return
	if ty == "beacon_enter":
		var after: int = int(ev.get("charges", 0))
		var before: int = int(ev.get("charges_before", after))
		_record("beacon_enter", {"overtime_tier": cur_overtime,
				"gold_collected": gold_count, "gold_available": gold_available})
		_record("charge_restored", {"before": before, "after": after})
		return
	if ty == "level_complete":
		_record("level_clear", {"black_ticks": beacon_open_t - level_start_t,
				"gold_ticks": total_t - beacon_open_t,
				"total_ticks": total_t - level_start_t})
		return
	# controller/runtime raw dicts below.
	var e := str(ev.get("e", ""))
	if e == "void_fall":
		var before2: int = int(ev.get("charges_before", int(ev.get("charges", 0))))
		var after2: int = int(ev.get("charges", 0))
		while not push_hist.is_empty() and int(push_hist[0]["t"]) < total_t - PUSH_WINDOW:
			push_hist.pop_front()
		var by := ""
		var pushed := false
		if not push_hist.is_empty():
			pushed = true
			by = str(push_hist[push_hist.size() - 1]["by"])
		_record("void_fall", {"tile": str(ev.get("tile", "")),
				"nearest_enemy_dist": float(ev.get("nearest_enemy_dist", -1.0)),
				"pushed_120": pushed, "pushed_by": by})
		_record("charge_spent", {"cause": "fall", "free": before2 == after2})
	elif e == "death":
		_record("death", {"killer": str(ev.get("killer", "")),
				"code": str(ev.get("code", "")),
				"on_screen": bool(ev.get("on_screen", str(ev.get("killer", "")) != "void")),
				"charges": int(ev.get("charges", 0)),
				"last_light": str(ev.get("last_light", ""))})
	elif e == "last_light_save":
		_record("last_light", {"code": str(ev.get("code", "")),
				"killer": str(ev.get("killer", "")), "charges": int(ev.get("charges", 0))})
	elif e == "chain_reset":
		chain_centi = CHAIN_START
		since_tick = total_t
	elif e == "push":
		_push_seen(int(total_t), str(ev.get("by", "")))
	elif e == "mine_pass":
		_record("mine_pass", {"slot": int(ev.get("slot", -1)),
				"closest": float(ev.get("closest", 0.0))})
	elif e == "mine_contact":
		_pending_mine_contact = int(ev.get("slot", -1))
	elif e == "mine_defused":
		_pending_mine_contact = -1
		_record("mine_contact", {"slot": int(ev.get("slot", -1)), "outcome": "defused"})
	elif e == "mine_shielded":
		_pending_mine_contact = -1
		_record("mine_contact", {"slot": int(ev.get("slot", -1)), "outcome": "shielded"})
	elif e == "mine_detonated":
		_pending_mine_contact = -1
		var outcome := "killed" if str(ev.get("result", "death")) == "death" else "last_light"
		_record("mine_contact", {"slot": int(ev.get("slot", -1)), "outcome": outcome})
	elif e == "overtime_tier":
		cur_overtime = int(ev.get("tier", cur_overtime))


# ---- pure helpers ------------------------------------------------------------------------

## The chain replica of economy.gd: a gold gift past the window resets first (the missed
## window), the VALUE at collection is the pre-increment chain, then +5 centi capped.
func _advance_chain(is_gold: bool) -> void:
	if not is_gold:
		return
	if total_t - since_tick > WINDOW_TICKS:
		chain_centi = CHAIN_START
	chain_centi = mini(chain_centi, CHAIN_CAP)
	chain_centi = mini(chain_centi + CHAIN_INCREMENT, CHAIN_CAP)
	since_tick = total_t


func _push_seen(t: int, by: String) -> void:
	if by == "":
		return
	push_hist.append({"t": t, "by": by})
	while push_hist.size() > 64:
		push_hist.pop_front()


func _record(type: String, payload: Dictionary) -> void:
	if _fh == null:
		return
	var rec := {"t": total_t, "level": level_number, "phase": phase,
			"type": type, "payload": payload}
	_fh.store_line(JSON.stringify(rec))
