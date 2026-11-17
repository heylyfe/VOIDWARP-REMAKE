extends RefCounted
#
# isagi_view.gd - the view side of the isagi enemy (ticket T-033). View layer only: it
# reads the sim enemy row and its own anim block (content/enemies/isagi/sprites.json,
# "anim": the T-083 schema), drives the billboard's animation states, computes the
# telegraph VFX (red rim flash + the re-aimed aim line) and names the placeholder audio
# hooks. No Node is required - the pure helpers are testable headless.
#
# Anim-block states are the section 1.4 table rows; the behavior's row["st"] maps 1:1.
# The wind-up flash accelerates 24 -> 12 -> 6 ticks (three thirds of the 72-tick wind-up);
# ball releases sit at global wind-up-relative ticks 0 / 9 / 18 (volleys 45 ticks apart,
# D-064) - the numbers live here as VIEW DATA and are proven by test_enemy_isagi.gd.

const RT := preload("res://sim/enemy_runtime.gd")

# The state names this view drives on the billboard (sprites.json animations[]).
const STATES := ["spawn", "idle", "telegraph", "attack", "recover"]

# Placeholder audio hooks, NAMED per the ENEMIES.md "New sound" line (T-033):
# "direct shot voice lines, Isagi shoot sae math final shot gun-shot sound when
# shooting." The real files drop in later; the hook names are the contract.
const SFX_VOICE_CUE := "isagi_voice_direct_shot"            # at wind-up start
const SFX_SHOOT_LINE := "isagi_shoot_sae_math_final_shot"   # at the burst's release
const SFX_GUNSHOT := "isagi_gunshot"                        # per ball, layered
const SFX_HOOKS := {
	"spawn": [],
	"idle": [],
	"telegraph": [SFX_VOICE_CUE],
	"attack": [SFX_SHOOT_LINE, SFX_GUNSHOT],
	"recover": [],
}

const FLASH_PERIODS := [24, 12, 6]   # the anim block: accelerating across the 72-tick wind-up
const WINDUP_TICKS := 72
const ATTACK_TICKS := 30
const RECOVER_TICKS := 150
const BALL_FRAME := "isagi_ball_00"  # the anim block's ball frame (1.0 u wide, 720 deg/s)

var doc: Dictionary = {}

func setup(p_doc: Dictionary) -> void:
	doc = p_doc

func anim_names() -> Array:
	var out: Array = []
	for a in doc.get("animations", []):
		out.append(str(a.get("name", "")))
	return out

## The T-083 "anim" block for one state (state id -> row spec).
func anim_state(p_state: String) -> Dictionary:
	var anim: Dictionary = doc.get("anim", {})
	var states: Dictionary = anim.get("states", {})
	return states.get(p_state, {})

## Flash rhythm of the wind-up: the period ticks per wind-up tick (24 -> 12 -> 6,
## one third each; accelerating thirds of the 72-tick wind-up).
static func flash_period(t: int) -> int:
	var third := int(WINDUP_TICKS / 3.0)   # 24
	if t < third:
		return int(FLASH_PERIODS[0])
	if t < 2 * third:
		return int(FLASH_PERIODS[1])
	return int(FLASH_PERIODS[2])

## Ball release ticks, relative to the burst's first ball (local tick 0), from the
## D-064 volley plan applied to the burst size: inside a volley balls sit 9 ticks
## apart; consecutive volleys start 45 ticks apart (0, 9, 18 | 45, 54, 63 | 90).
static func release_ticks(balls: int) -> Array:
	var out: Array = []
	var volley := 0
	for v in RT.volley_plan(balls):
		for j in range(int(v)):
			out.append(volley * RT.VOLLEY_GAP_TICKS + j * RT.VOLLEY_TICKS)
		volley += 1
	return out

## The aim line (the red line from his muzzle to the player's centre): re-aimed EVERY
## tick by the view - the line is never committed at wind-up start, the BALLS' lines
## are (fixed at their own release, sim side).
static func aim_line(row: Dictionary, player: Dictionary) -> Dictionary:
	return {"from": Vector3(float(row["x"]), float(row["y"]) + 1.0, float(row["z"])),
			"to": Vector3(float(player["x"]), float(player["y"]) + 0.9, float(player["z"]))}

## The VFX snapshot for the billboard this tick: {state, flash_period, aim, release_now}.
## row["st_t"] counts DOWN inside the behavior's state; the frame index derives from
## the time already spent in the state (state_ticks - st_t).
func snapshot(row: Dictionary, player: Dictionary, burst_local_tick: int) -> Dictionary:
	var st := str(row.get("st", "idle"))
	var snap := {"state": st, "flash_period": 0, "aim": null, "release_now": false,
			"sfx": []}
	if st == "telegraph":
		var t := WINDUP_TICKS - int(row.get("st_t", 0))
		snap["flash_period"] = flash_period(t)
		if player.is_empty():
			snap["aim"] = null
		else:
			snap["aim"] = aim_line(row, player)
	elif st == "attack":
		var releases := release_ticks(int(row.get("balls", 0)))
		snap["release_now"] = releases.has(burst_local_tick)
	var hooks: Array = SFX_HOOKS.get(st, [])
	snap["sfx"] = hooks.duplicate(true)
	if st == "attack" and not bool(snap["release_now"]):
		# only the release moments carry the shoot line; recovering silence stays dim
		snap["sfx"].erase(SFX_SHOOT_LINE)
		snap["sfx"].erase(SFX_GUNSHOT)
	return snap

