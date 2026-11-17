extends RefCounted
#
# menu_howto.gd - the HOW TO PLAY panel text (ticket MENU).
#
# Written against the SHIPPED systems, not a doc: every number below is read at runtime from
# the code or data file that the simulation itself reads, so the panel cannot drift from the
# build.
#   void charges, respawn, invulnerability, Last Light  sim/controller.gd load_constants()
#                                                       (data/player.json over its DEFAULTS)
#   beacon trigger radius                               sim/beacon.gd RADIUS
#   tripmine contact radius                             sim/mines.gd CONTACT_R
#   gold value, chain window/step/cap, stipend          sim/economy.gd over data/economy.json
#   overtime period and per-tier speed                  sim/enemy_runtime.gd constants
#   controls                                            data/bindings.json via app/input_capture.gd
#
# Where the docs and the code disagree, the code wins here and the disagreement is recorded
# in DECISIONS.md D-MENU-7 (e.g. DESIGN.md section 3.1 lets Field Dressing make a fall free; no
# sim path does that yet - PARKED.md #3 - so the panel does not promise it).

const ControllerScript := preload("res://sim/controller.gd")
const BeaconScript := preload("res://sim/beacon.gd")
const MinesScript := preload("res://sim/mines.gd")
const EconomyScript := preload("res://sim/economy.gd")
const EnemyRuntimeScript := preload("res://sim/enemy_runtime.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")

const GOLD := "#FFC83D"
const WHITE := "#E8FFFF"
const MUTED := "#9AABC0"
const DANGER := "#FF2A2A"
const PINK := "#FF4FD8"
const RIM := "#7CFFF4"


## The duck-typed data source sim/economy.gd create() reads ("economy" -> data/economy.json).
class _EconomyData extends RefCounted:
	func data(p_name: String) -> Dictionary:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % p_name))
		if typeof(parsed) != TYPE_DICTIONARY:
			return {}
		return parsed


## Display name of a key code ("W", "SPACE", "ESCAPE").
static func key_name(code: int) -> String:
	return OS.get_keycode_string(code).to_upper()


## "W", or "SPACE / F" when an action has several keys; "-" when unbound.
static func keys_for(bindings: Dictionary, action: String) -> String:
	var kb: Dictionary = bindings.get("key_bindings", {})
	var names: Array[String] = []
	for code in kb.get(action, []):
		names.append(key_name(int(code)))
	return " / ".join(names) if not names.is_empty() else "-"


static func _num(v: float) -> String:
	# 2 -> "2", 0.8 -> "0.8", 1.5 -> "1.5" (no trailing zeros)
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return str(snappedf(v, 0.01))


static func _gold(centi: int) -> String:
	return "%d.%02d" % [centi / 100, centi % 100]


## The facts the panel states, as plain values (also what the test asserts against).
static func facts() -> Dictionary:
	var c: Dictionary = ControllerScript.load_constants()
	var econ = EconomyScript.create({}, _EconomyData.new())
	return {
		"charges_start": int(c["void_charges"]),
		"charge_cap": int(c["charge_cap"]),
		"respawn_delay": float(c["respawn_delay"]),
		"respawn_invuln": float(c["respawn_invuln"]),
		"last_light_invuln": float(c["last_light_invuln"]),
		"beacon_radius": float(BeaconScript.RADIUS),
		"mine_contact": float(MinesScript.CONTACT_R),
		"gift_centi": int(econ.base_gift_centi),
		"chain_window": float(econ.window_s),
		"chain_step_centi": int(econ.increment_centi),
		"chain_cap_centi": int(econ.cap_centi),
		"stipend_base": int(econ.stipend_base),
		"stipend_per_level": int(econ.stipend_per_level),
		"overtime_period": float(EnemyRuntimeScript.OVERTIME_PERIOD),
		"overtime_speed": float(EnemyRuntimeScript.OVERTIME_SPEED_PER_TIER),
		"overtime_max": int(EnemyRuntimeScript.OVERTIME_MAX_TIER),
	}


## The panel's sections, in order: [{title, body}] with BBCode bodies.
static func sections(bindings: Dictionary = {}) -> Array:
	if bindings.is_empty():
		bindings = InputCaptureScript.load_bindings()
	var f := facts()
	var pips := ""
	for i in int(f["charge_cap"]):
		pips += "[color=%s]●[/color] " % GOLD
	var out: Array = []
	out.append({"title": "THE LEVEL", "body": (
		"You start on the beacon dais. The beacon is [b]closed[/b].\n"
		+ "Collect every [b]black gift[/b]. The last one [color=%s]opens the beacon[/color]: a white column of light visible through the fog.\n" % WHITE
		+ "Step into the open beacon (within %s u of it) to clear the level. Nothing else ends a level - there is no timer." % _num(f["beacon_radius"]))})
	out.append({"title": "VOID CHARGES  %s" % pips.strip_edges(), "body": (
		"A run starts with [color=%s]%d void charges[/color]. Falling into the void spends one: the player respawns on the last safe tile after %s s, untouchable for %s s.\n" % [GOLD, int(f["charges_start"]), _num(f["respawn_delay"]), _num(f["respawn_invuln"])]
		+ "A fall with [b]0 charges[/b] ends the run. Charges carry over between levels.\n"
		+ "[color=%s]Entering the open beacon restores 1 charge[/color] (never above %d). Nothing else gives one back." % [GOLD, int(f["charge_cap"])])})
	out.append({"title": "CONTACT KILLS", "body": (
		"[color=%s]Most enemies kill on contact - instantly.[/color] No health bar, no second hit. Others kill with what they fire, drop or set off, after a tell worth learning.\n" % DANGER
		+ "Tripmines sit on gift slots: a black box with a six-pointed star and [color=%s]pink sparks[/color]. Coming within %s u is fatal - even mid-jump. Walk around them.\n" % [PINK, _num(f["mine_contact"])]
		+ "[b]Last Light[/b]: once per run, while the player holds at least 1 charge, a killing blow sends the player back to the beacon dais instead, untouchable for %s s. At 0 charges it does nothing." % _num(f["last_light_invuln"]))})
	out.append({"title": "GOLD - STAY OR GO", "body": (
		"When the beacon opens, every black gift's slot turns into a [color=%s]gold gift[/color] worth %s g.\n" % [GOLD, _gold(int(f["gift_centi"]))]
		+ "Take the next one within %s s to grow the chain +%s x, up to %s x. A void fall breaks the chain.\n" % [_num(f["chain_window"]), _gold(int(f["chain_step_centi"])), _gold(int(f["chain_cap_centi"]))]
		+ "Every %s s the player stays, enemies move %d%% faster (up to %d times). Leaving pays %d + %d x level g." % [_num(f["overtime_period"]), int(roundf(float(f["overtime_speed"]) * 100.0)), int(f["overtime_max"]), int(f["stipend_base"]), int(f["stipend_per_level"])])})
	var mv := "%s %s %s %s" % [keys_for(bindings, "move_forward"), keys_for(bindings, "move_left"),
			keys_for(bindings, "move_back"), keys_for(bindings, "move_right")]
	out.append({"title": "CONTROLS", "body": (
		"[color=%s]%s[/color]  move    [color=%s]%s[/color]  jump (Glider: hold to glide)    [color=%s]%s[/color]  class ability\n" % [WHITE, mv, WHITE, keys_for(bindings, "jump"), WHITE, keys_for(bindings, "ability")]
		+ "[color=%s]%s[/color]  interact    [color=%s]%s[/color]  HUD rows    [color=%s]%s[/color]  pause" % [WHITE, keys_for(bindings, "interact"), WHITE, keys_for(bindings, "hud_toggle"), WHITE, keys_for(bindings, "pause")])})
	return out


## The whole panel as one BBCode document.
static func bbcode(bindings: Dictionary = {}) -> String:
	var parts: Array[String] = []
	for s in sections(bindings):
		var sd: Dictionary = s
		parts.append("[font_size={h}][color=%s]%s[/color][/font_size]\n[color=%s]%s[/color]" % [GOLD, str(sd["title"]), MUTED, str(sd["body"])])
	return "\n\n".join(parts)


## Plain text (BBCode stripped) - for tests and for anything that cannot render BBCode.
static func plain_text(bindings: Dictionary = {}) -> String:
	var rx := RegEx.new()
	rx.compile("\\[[^\\]]*\\]")
	return rx.sub(bbcode(bindings), "", true)
