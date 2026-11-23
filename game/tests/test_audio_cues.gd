extends RefCounted
#
# The threat cue layer (PARKED.md rows 12-15; view/audio/threat_cues.gd driven through
# view/vfx/telegraph_view.gd). Every leg runs the REAL sim (EnemyRuntime + the shipped
# behavior) and feeds each step's events and rows to a real telegraph view, exactly as
# app/world.gd does (on_events(rt.step()) then sync(live, rt.tick, ...)). The attack
# ticks are read from the sim (event / row state); the cue ticks from the view's
# cue_log. Every expected offset is read from the enemy's own enemy.json.
#
#   coil    coil_boing on the coil_ring telegraph tick, 201 ticks (lethal_attacks
#           attack_offset_ticks) before the coil_land kill tick (row 13)
#   claude  the CYCLE 7 revamp: the two anger warnings. The sim is the real clawd runtime
#           (sim/clawds.gd) and the view is the real view/claude_view.gd - the sim's
#           clawd_warning event names the cue, on_warning() plays it. Warning 1 at exactly
#           3600 ticks (60 s), warning 2 at exactly 7200 (120 s), and both cue files exist
#           (D-T4-5, D-T4-8)
#   gin     crack_rumble on the mark tick, shing + whoosh binding_cue_ticks (18) before
#           the zone opens, zone_open on the zone-open (kill) tick, the zone 138 ticks
#           after the mark (row 15)
#
# Negative control: each leg re-runs with its cue UNWIRED (the threat cue layer off;
# coil's sim audio event stripped before the view sees it) and the same checker must
# then report failures - a checker that passes with no cue proves nothing.

const EnemyRuntime := preload("res://sim/enemy_runtime.gd")
const CoilEnemy := preload("res://content/enemies/coil/enemy.gd")
const ClaudeEnemy := preload("res://content/enemies/claude/enemy.gd")
const GinBehavior := preload("res://content/enemies/gin/enemy.gd")
const TelegraphView := preload("res://view/vfx/telegraph_view.gd")
const ThreatCues := preload("res://view/audio/threat_cues.gd")
const Util := preload("res://tests/sim_testutil.gd")
const ClawdsScript := preload("res://sim/clawds.gd")
const BeaconScript := preload("res://sim/beacon.gd")
const ClaudeViewScript := preload("res://view/claude_view.gd")

const DT := 1.0 / 60.0
## The two anger thresholds the owner named, in ticks at the fixed 60 Hz sim rate.
const WARN_1 := 3600
const WARN_2 := 7200


func run() -> Array[String]:
	var f: Array[String] = []
	_table(f)
	_coil(f)
	_claude(f)
	_gin(f)
	return f


# ---- fixtures -------------------------------------------------------------------

static func _json(id: String) -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			"res://content/enemies/%s/enemy.json" % id))
	return doc if doc is Dictionary else {}


static func _attack(id: String, attack: String) -> Dictionary:
	for a in _json(id).get("stats", {}).get("lethal_attacks", []):
		if str(a.get("attack", "")) == attack:
			return a
	return {}


static func _timing(id: String, cue: String) -> Dictionary:
	return _json(id).get("stats", {}).get("audio_cue_timing", {}).get(cue, {})


static func _tiles(n: int) -> Array:
	var out: Array = []
	for x in range(-n, n + 1):
		for z in range(-n, n + 1):
			out.append([x, z, 0])
	return out


static func _level(n: int) -> Dictionary:
	var padded: Array = []
	for t in _tiles(n):
		padded.append([t[0], t[1], t[2], 0, 0])
	return {"beacon": [0, 0, 0], "spawns": [[0, 0, 0]], "anchors": [],
			"tiles": padded, "props": [], "pads": []}


static func _runtime(n: int):
	var w: Dictionary = Util.world_from_tiles(_tiles(n))
	w["dais"] = [0, 0, 0]
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var rt = EnemyRuntime.new()
	rt.setup(_level(n), w, [ctl], 4242)
	return rt


## A telegraph view wired the way app/world.gd wires it. wired == false unwires the
## cue under test (the layer off, and the sim's own audio events stripped).
static func _view(rt, wired: bool):
	var tv = TelegraphView.new()
	tv.rt_source = rt
	tv.threat_cues.enabled = wired
	return tv


## One world-order step: rt.step -> on_events -> sync. Returns the step tick.
static func _step(rt, tv, wired: bool, all: Array) -> int:
	var ev: Array = rt.step(DT)
	all.append_array(ev)
	var feed: Array = ev
	if not wired:
		feed = ev.filter(func(e): return str(e.get("e", "")) != "audio")
	tv.on_events(feed)
	tv.sync(rt.live_telegraphs(), int(rt.tick), 0.0, Vector3(0.0, 0.9, 0.0))
	return int(rt.tick) - 1


static func _cues(tv, cue: String, full: int = -1) -> Array:
	# full: -1 any gain, 1 full gain only, 0 quieter only
	var out: Array = []
	for e in tv.cue_log:
		if str(e["cue"]) != cue:
			continue
		var g := float(e.get("gain", 1.0))
		if full == 1 and g < 0.999:
			continue
		if full == 0 and g >= 0.999:
			continue
		out.append(int(e["tick"]))
	return out


# ---- the table is the data --------------------------------------------------------

func _table(f: Array[String]) -> void:
	var tc = ThreatCues.new()
	for pair in [["mark", "shing"], ["mark", "crack_rumble"], ["mark", "zone_open"],
			["coil_ring", "coil_boing"],
			["ground_ring", "rocket_booster_roar"], ["teleport", "thicc_ben_chime"]]:
		var found := false
		for entry in tc.by_kind.get(pair[0], []):
			if str(entry["cue"]) == pair[1]:
				found = true
		if not found:
			f.append("table: telegraph '%s' carries no '%s' cue (by_kind %s)"
					% [pair[0], pair[1], str(tc.by_kind.keys())])
	var shing: Dictionary = _timing("gin", "shing")
	for entry in tc.by_kind.get("mark", []):
		if str(entry["cue"]) == "shing" and int(entry["offset"]) != int(shing.get("offset_ticks", -1)):
			f.append("table: shing offset %d, enemy.json says %s"
					% [int(entry["offset"]), str(shing.get("offset_ticks"))])
	if not tc.by_appear.has("address_me"):
		f.append("table: address me's appear cues (rumble_build) not loaded")


# ---- coil (PARKED.md #13) ---------------------------------------------------------

## Problems with coil's landing cue in one run; empty = the cue is wired and leads.
func _coil_check(wired: bool) -> Array[String]:
	var p: Array[String] = []
	var rt = _runtime(5)
	var tv = _view(rt, wired)
	var cfg := {"world_height": 1.0, "frame_w": 512, "frame_h": 512,
			"body_rect": [0, 0, 256, 256], "contact_kill": true, "preferred_kind": "lane",
			"cycle_s": 405.0 / 60.0, "cycle_ticks": 405, "idle_s": 3.0}
	rt.spawn_at("coil", "coil", CoilEnemy.behavior(), cfg, Vector3(3.5, 0.0, 0.5))
	var all: Array = []
	var ring_at := -1
	var land_at := -1
	for _i in range(520):
		var t := _step(rt, tv, wired, all)
		for e in rt.events:
			if str(e.get("e", "")) == "telegraph" and str(e.get("kind", "")) == "coil_ring" \
					and ring_at < 0:
				ring_at = t
			if str(e.get("e", "")) == "coil_land" and land_at < 0:
				land_at = t
		if land_at >= 0:
			break
	var atk: Dictionary = _attack("coil", "landing_kill")
	var want_lead := int(atk.get("attack_offset_ticks", -1))
	if ring_at < 0 or land_at < 0:
		p.append("coil: the sim never ran a jump (ring %d, land %d)" % [ring_at, land_at])
	else:
		if land_at - ring_at != want_lead:
			p.append("coil: ring -> landing %d ticks, enemy.json attack_offset_ticks %d"
					% [land_at - ring_at, want_lead])
		var boing: Array = _cues(tv, "coil_boing")
		if boing.is_empty():
			p.append("coil: coil_boing never played (log %s)" % str(tv.cue_log))
		else:
			var c := int(boing[0])
			if c != ring_at:
				p.append("coil: coil_boing at tick %d, the cue starts on the ring tick %d"
						% [c, ring_at])
			if not (c < land_at) or land_at - c != want_lead:
				p.append("coil: coil_boing leads the landing kill by %d ticks, want %d"
						% [land_at - c, want_lead])
	tv.free()
	return p


func _coil(f: Array[String]) -> void:
	f.append_array(_coil_check(true))
	if _coil_check(false).is_empty():
		f.append("coil negative control: the checker passed with the boing unwired")


# ---- claude (the CYCLE 7 revamp: the two anger warnings) --------------------------

## Problems with Claude's two anger warnings in one run. The sim is the real clawd runtime
## (sim/clawds.gd) at 60 Hz with the player standing still; the cue names come from the sim's own
## clawd_warning event, and the view is the real view/claude_view.gd - on_warning() is what plays
## them. wired == false leaves the view unwired (the cue layer off), so the same checker must fail.
func _claude_check(wired: bool) -> Array[String]:
	var p: Array[String] = []
	var L: Dictionary = _level(10)
	# the clawd placement stream is seeded from the Level (D-T4-4): the fixture needs the four keys
	L["seed"] = 4242
	L["level"] = 1
	L["gen_version"] = 1
	L["attempt"] = 0
	ClawdsScript.attach(L, ClaudeEnemy.clawd_cfg())
	var lv := {"clawds": ClawdsScript.create(L), "beacon": BeaconScript.create(L)}
	var w: Dictionary = Util.world_from_tiles(_tiles(10))
	w["dais"] = [0, 0, 0]
	var ctl = Util.ControllerScript.new()
	ctl.setup("dasher", Util.consts())
	ctl.place(w)
	ctl.last_light_spent = true
	var v = ClaudeViewScript.new()
	v.setup()
	var warn_at: Array = []
	var warn_cue: Array = []
	var ev: Array = []
	for t in range(1, WARN_2 + 1):
		ev.clear()
		ClawdsScript.tick(lv, [ctl], w, t, ev)
		for e in ev:
			if str((e as Dictionary).get("type", "")) != "clawd_warning":
				continue
			warn_at.append(t)
			warn_cue.append(str(e["cue"]))
			if wired:
				v.on_warning(int(e["level"]))
	if warn_at.size() != 2:
		p.append("claude: %d warnings in %d ticks, want 2 (at %d and %d)"
				% [warn_at.size(), WARN_2, WARN_1, WARN_2])
	else:
		if int(warn_at[0]) != WARN_1 or int(warn_at[1]) != WARN_2:
			p.append("claude: the warnings fired at %s, want [%d, %d] (60 s and 120 s)"
					% [str(warn_at), WARN_1, WARN_2])
		if str(warn_cue[0]) != "claude_warning_1" or str(warn_cue[1]) != "claude_warning_2":
			p.append("claude: the sim named the cues %s, want the two new synth cues" % str(warn_cue))
		# the cue names ARE the file names (T-055's contract): both files must exist
		for cue in warn_cue:
			var path := "res://assets/audio/enemies/claude/%s.wav" % str(cue)
			if not ResourceLoader.exists(path):
				p.append("claude: the cue file %s is missing" % path)
		# the view's own record: it played both warnings (the negative control fails here)
		if int(v._last_warned) != 2:
			p.append("claude: the view recorded %d warnings, want 2 (the cue layer is off)"
					% int(v._last_warned))
		if int(v._flash) <= 0:
			p.append("claude: the view left no warning flash on the logo")
	v.free()
	return p


func _claude(f: Array[String]) -> void:
	f.append_array(_claude_check(true))
	if _claude_check(false).is_empty():
		f.append("claude negative control: the checker passed with the cue layer off")


# ---- gin (PARKED.md #15) ----------------------------------------------------------

## Problems with gin's zone-kill cues in one run. The attack tick is the step the row
## enters the void phase (the zone opens: enemy.json attack_offset_ticks after the mark).
func _gin_check(wired: bool) -> Array[String]:
	var p: Array[String] = []
	var rt = _runtime(5)
	var tv = _view(rt, wired)
	var row: Dictionary = rt.spawn_at("gin", "gin ichimaru", GinBehavior.new(), {},
			Vector3(2.1, 0.0, 0.5))
	var all: Array = []
	var mark_at := -1
	var void_at := -1
	for _i in range(900):
		var t := _step(rt, tv, wired, all)
		for e in rt.events:
			if str(e.get("e", "")) == "telegraph" and str(e.get("kind", "")) == "mark" \
					and mark_at < 0:
				mark_at = t
		if mark_at >= 0 and void_at < 0 and str(row.get("phase", "")) == GinBehavior.VOID:
			void_at = t
		if void_at >= 0 and t >= void_at + 2:
			break
	var atk: Dictionary = _attack("gin", "zone_kill")
	if mark_at < 0 or void_at < 0:
		p.append("gin: the sim never ran a mark -> zone (mark %d, zone %d)" % [mark_at, void_at])
		tv.free()
		return p
	if void_at - mark_at != int(atk.get("attack_offset_ticks", -1)):
		p.append("gin: mark -> zone %d ticks, enemy.json attack_offset_ticks %s"
				% [void_at - mark_at, str(atk.get("attack_offset_ticks"))])
	var lead := int(atk.get("binding_cue_ticks", -1))   # shing: 18
	var want := {"crack_rumble": mark_at, "shing": void_at - lead,
			"whoosh": void_at - lead, "zone_open": void_at}
	for cue in want.keys():
		var got: Array = _cues(tv, cue)
		if not got.has(int(want[cue])):
			p.append("gin: %s at %s, want tick %d (mark %d, zone %d)"
					% [cue, str(got), int(want[cue]), mark_at, void_at])
	for cue in ["crack_rumble", "shing", "whoosh"]:
		for c in _cues(tv, cue):
			if not (int(c) < void_at):
				p.append("gin: %s at %d does not precede the zone kill at %d" % [cue, c, void_at])
	tv.free()
	return p


func _gin(f: Array[String]) -> void:
	f.append_array(_gin_check(true))
	if _gin_check(false).is_empty():
		f.append("gin negative control: the checker passed with the cue layer off")
