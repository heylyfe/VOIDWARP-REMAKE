extends RefCounted
#
# enemy_runtime.gd - the enemy framework (ticket T-027; DESIGN.md section 5 + section 12;
# D-056 spawn fallback, D-057 kill tests, D-064..D-075 system rules).
#
# Pure sim layer: RefCounted only, fixed 60 Hz tick, floats through + - * / and sqrt, randomness
# only through the terrain Mulberry32 streams. Enemy LOGIC lives here (the future server);
# sprites/billboarding are view-layer only (ENEMIES.md global notes: enemies stay server-sided,
# rendered on the client). The runtime owns: the spawn rule (6.0 s, D-056 fallback order), vote
# counts, the overtime multipliers, telegraph events, projectiles, api.los, and the kill API
# (api.kill / api.push / api.lock_abilities - an enemy either kills or applies a non-killing
# effect; there is no partial-effect call).
#
# Content ids live in content/, never here: per-enemy data (anchor kinds, speeds, max votes,
# body sizes) arrives as plain cfg dictionaries from the content layer (DESIGN.md section 12).

const CollisionScript := preload("res://sim/collision.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const VoidGenScript := preload("res://terrain/voidgen.gd")
const ArbiterScript := preload("res://sim/enemy_arbiter.gd")   # T-072: the scheduling gate

# ---- spec numbers (DESIGN.md section 5, section 3.2 Overtime) ----------------------------
const TICKS_PER_SECOND := 60.0
const SPAWN_DELAY_TICKS := 360    # 6.0 s after level start (Early Bird: the caller passes 120)
const MIN_PLAYER_DIST := 25.0     # never spawn within 25 u of the player
const PREFERRED_DIST := 60.0      # farthest-but-within 60 u preference (steps a/b only)
const COPY_SEP := 30.0            # copies of one chaser are >= 30 u apart (SR-3)
const OVERTIME_PERIOD := 20.0     # beacon open -> tier rises every 20 s (Long Night 14, Cold Blood 30)
const OVERTIME_MAX_TIER := 8
const OVERTIME_SPEED_PER_TIER := 0.06   # enemy movement speed +6% per tier
const OVERTIME_CD_PER_TIER := 0.05      # enemy cooldowns -5% per tier
const FLOATER_CLIMB := 2.0        # SR-1 vertical easing cap, u/s - NEVER multiplied (D-068)
const LOS_STEP := 0.25            # api.los ray march step, u (D-T027-2)
const HIT_DIA_FRACTION := 0.8     # hit cylinder diameter = 0.8 x body width (HITBOXES)
const BASE_RUN_SPEED := 9.0       # SR-5: ceilings are fractions of BASE run speed, NEVER the
                                  # player's current speed (speed upgrades always gain ground)
const TEMPO_FLOOR := 0.6          # SR-5: a tempo-shortened cycle never below 0.6x the base cycle
const BURST_MAX_TICKS := 180      # SR-5: a telegraphed sprint lasts at most 3.0 s
const VOLLEY_MAX := 3             # D-064: at most 3 balls per volley
const VOLLEY_TICKS := 9           # D-064: balls inside one volley 0.15 s apart
const VOLLEY_GAP_TICKS := 45      # D-064: consecutive volleys 0.75 s apart (start to start)
const SALVO_MAX_TICKS := 360      # D-064: one salvo (tracking + restarts + descent) <= 6.0 s

# Anchor kinds (TERRAIN_SPEC section 6.5): 0 perch, 1 open, 2 lane, 4 nook. Kind 3 (`hop`) is
# retired and reserved - never emitted, the id is never reused (D-056).
const KIND_IDS := {"perch": 0, "open": 1, "lane": 2, "nook": 4}


# ---- EnemyBehavior base (DESIGN.md section 12: content/enemies/<id>/enemy.gd extends this) ----
# Content scripts extend the inner class: `const RT := preload("res://sim/enemy_runtime.gd")`
# then wrap their tick logic, or subclass EnemyBehavior inside their own file. Rows are plain
# dictionaries in the runtime state; a behavior touches its own row and nothing else.
class EnemyBehavior:
	extends RefCounted

	var id := ""
	var display_name := "TBD"

	func on_spawn(_row: Dictionary, _api) -> void:
		pass

	# One 60 Hz tick. _dt_ticks is the elapsed tick count (1 at 60 Hz).
	func tick(_row: Dictionary, _api, _dt_ticks: int) -> void:
		pass

	func on_vote(_row: Dictionary, _api, _count: int) -> void:
		pass


# A fixture behavior: a stationary body whose contact kills (the KILL RULE default); used by
# the T-027 tests and drop-in fixtures until real Wave-3 behaviors land.
class FixtureBehavior:
	extends EnemyBehavior

	func tick(_row: Dictionary, _api, _dt_ticks: int) -> void:
		pass


# ---- the Enemy API (DESIGN.md section 12 - the ONLY surface a behavior may call) -----------
class Api:
	extends RefCounted

	var rt: RefCounted = null   # the owning EnemyRuntime
	var row: Dictionary = {}    # the calling enemy's row

	func nearest_player(pos: Vector3) -> Dictionary:
		return rt.nearest_player(pos)

	# True when the straight segment a->b clears every tile slab and prop box (tile/prop ray).
	func los(a: Vector3, b: Vector3) -> bool:
		return rt.los(a, b)

	func anchors(kind: String) -> Array:
		return rt.anchors(kind)

	func tiles_in_radius(pos: Vector3, r: float) -> Array:
		return rt.tiles_in_radius(pos, r)

	func spawn_projectile(def: Dictionary) -> void:
		rt.spawn_projectile(row, def)

	# kind: a telegraph name from the enemy's spec; shape: a collision.gd hazard footprint
	# ({"shape": "circle"|"ring"|"box", ...}); ticks: the 60 Hz ticks before the strike lands.
	func telegraph(kind: String, shape: Dictionary, ticks: int) -> void:
		rt.telegraph(row, kind, shape, ticks)

	# The kill API. kill saves nothing and subtracts nothing: the player's controller (T-012)
	# answers - it may still be suppressed by respawn/Last Light invulnerability, which is the
	# controller's call, never the enemy's.
	func kill(player, killer_id: String, code: String = "") -> bool:
		return rt.kill(player, killer_id, code)

	func push(player, dir: Vector3, speed: float) -> void:
		rt.push(player, dir, speed, row)

	func lock_abilities(player, ticks: int) -> void:
		rt.lock_abilities(player, ticks)

	# T-072: this row's declarative scheduling gate (the cfg `arbiter` block, DATA) against
	# the live sim state - {"may_appear": bool, "deferred": bool}. `pending` carries this
	# row's own caller-side countdown ids (behaviors keep that state on their row; a rumble
	# that is not a telegraph shape passes through here) - ids are data, never this file.
	func arbiter_gate(pending: Array = []) -> Dictionary:
		return rt.arbiter_evaluate(row.get("cfg", {}), row.get("target_player", 0), pending)

	# T-032: a non-killing eject (DESIGN.md 5.3). Appends the chain_reset announcement
	# and the screen_blur announcement to the runtime's events; never kills, never damages.
	# `why` is DATA (the economy break_events whitelist); blur_ticks is data-owned too.
	func eject_player(player, why: String, blur_ticks: int) -> void:
		rt.eject_player(row, player, why, blur_ticks)

	# T-032: the ben ring cleanse (DESIGN.md 5.8). Removes glitched tiles whose
	# tile centre is within r u (horizontal) of pos; returns the count removed.
	func cleanse_glitched_within(pos: Vector3, r: float) -> int:
		return rt.cleanse_glitched_within(row, pos, r)

	# T-032: re-sync this row's body mirror (world["enemies"]) after an instant
	# reposition (the teleport) - the mirror is otherwise written once at spawn and
	# goes stale for anything that jumps (movers update the row, not the mirror).
	func sync_body() -> void:
		rt.sync_body_mirror(row)

	func rng() -> RefCounted:
		return row["rng"]

	# --- convenience helpers on top of the section 12 surface ---------------------------
	# Overtime/curse speed multiplier already applied by the caller's stack (SR-5 uses it
	# through clamp_pursuit so no multiplier can push a body past its ceiling).
	func speed_mul() -> float:
		return rt.speed_mul()

	# SR-5: clamp the multiplied pursuit speed to ceiling_fraction x base run speed.
	func clamp_pursuit(multiplied_speed: float, base_speed: float, ceiling: float) -> float:
		var cap: float = 9.0 * ceiling
		if base_speed > 0.0:
			cap = base_speed * ceiling
		return minf(multiplied_speed, cap)

	# SR-1 + floater movement: approach (tx, tz) straight through geometry and over the void at
	# h_speed u/s (the caller passes its already-multiplied, already-clamped speed); feet ease
	# toward the target's feet height at FLOATER_CLIMB u/s, never multiplied.
	func move_toward(row2: Dictionary, tx: float, tz: float, h_speed: float) -> void:
		rt.move_toward(row2, tx, tz, h_speed, rt.target_feet_y(row2))

	func cooldown_ticks(base_ticks: int) -> int:
		var t: float = float(base_ticks) * rt.cd_mul()
		var out: int = int(t)
		if t - float(out) >= 0.5:
			out += 1
		if out < 0:
			out = 0
		return out

	# T-071: the curse speed multiplier (rate curses and repeatable +5% hunger-style
	# stacks), kept by the engine layer in rt.curse_speed_mul from the stats system's
	# enemy_speed_mul. Overtime is separate (speed_mul); FloatBody multiplies BOTH before
	# the SR-5 clamp.
	func curse_speed_mul() -> float:
		return rt.curse_speed_mul

	# SR-5 overflow: the calling row's tempo multiplier (1.0 when the behavior attached no
	# FloatBody to its row - behaviors attach one with FloatBody.from_cfg in on_spawn).
	func tempo_mul() -> float:
		var fb: Variant = row.get("float", null)
		if fb == null:
			return 1.0
		return float(fb.tempo_mul)

	# SR-5: a cycle shortened by tempo, NEVER below TEMPO_FLOOR of the base cycle. The floor
	# is applied here, at the conversion, so every behavior reads the same bounded value.
	func tempo_ticks(base_ticks: int) -> int:
		var tm: float = tempo_mul()
		if tm <= 1.0:
			return maxi(int(base_ticks), 0)
		var t: float = float(base_ticks) / tm
		var out := int(round(t))
		var low := int(ceil(float(base_ticks) * TEMPO_FLOOR))
		return maxi(out, maxi(low, 0))


# ---- FloatBody (T-071: SR-1 floater kinematics + SR-5 pursuit ceilings) ----------------------
# A floating body's kinematics, driven from enemy.json data (arriving as the cfg dictionary
# until the T-073 data pass lands the files). Horizontal speed is the cfg base speed times
# EVERY speed multiplier - overtime (speed_mul), curses and repeatable speed stacks
# (curse_speed_mul), an active burst - clamped AFTER all of them to ceiling x BASE_RUN_SPEED
# (pursuit: the pursuit ceiling; a telegraphed sprint: the burst ceiling, bounded to
# BURST_MAX_TICKS). Vertical easing toward the target's feet runs at FLOATER_CLIMB u/s and
# is NEVER multiplied (D-068). Whatever part of a multiplier the ceiling removes is exposed
# as tempo_mul (capped so a tempo-shortened cycle never runs below TEMPO_FLOOR of the base
# cycle; SR-5).
class FloatBody:
	extends RefCounted

	var base_speed := 0.0          # u/s, from enemy.json ("base_speed")
	var pursuit_ceiling := 1.0     # fraction of BASE_RUN_SPEED, from enemy.json
	var burst_ceiling := 1.0       # fraction of BASE_RUN_SPEED, from enemy.json
	var burst_mult := 1.0          # the active burst's multiplier (1.0 = no burst)
	var burst_ticks_left := 0
	var h_speed := 0.0             # last computed effective horizontal speed, u/s
	var tempo_mul := 1.0           # SR-5 overflow factor, exposed to the behavior

	static func from_cfg(cfg: Dictionary) -> FloatBody:
		var b := FloatBody.new()
		b.base_speed = float(cfg.get("base_speed", 0.0))
		b.pursuit_ceiling = float(cfg.get("pursuit_ceiling", 1.0))
		b.burst_ceiling = float(cfg.get("burst_ceiling", 1.0))
		return b

	## Begin a telegraphed sprint (the +60%-for-3 s script-curse pattern): multiplier and
	## duration from the caller; the DURATION is clamped to BURST_MAX_TICKS here, the SPEED
	## is clamped per tick in _speeds against burst_ceiling x BASE_RUN_SPEED (so overtime
	## cannot push a burst past the bound either).
	func begin_burst(mult: float, ticks: int) -> void:
		burst_mult = maxf(mult, 1.0)
		burst_ticks_left = mini(maxi(ticks, 0), BURST_MAX_TICKS)

	func bursting() -> bool:
		return burst_ticks_left > 0

	## One sim tick: recompute h_speed + tempo_mul from the current multipliers and move
	## `row` toward (tx, tz) (api.move_toward applies the SR-1 vertical easing at
	## FLOATER_CLIMB, never multiplied). Call once per tick from the behavior.
	func step(row: Dictionary, api, dt_ticks: int, tx: float, tz: float) -> void:
		_speeds(api, dt_ticks)
		api.move_toward(row, tx, tz, h_speed)

	## Recompute h_speed + tempo_mul without moving (behaviors that steer themselves).
	func update(api, dt_ticks: int = 1) -> void:
		_speeds(api, dt_ticks)

	func _speeds(api, dt_ticks: int) -> void:
		var mult: float = api.speed_mul() * api.curse_speed_mul()
		var raw: float = base_speed * mult
		# SR-5 overflow -> tempo, from the PURSUIT path (a burst rides on top of it and has
		# its own bound); clamped to 1/TEMPO_FLOOR so a cycle never shortens past 0.6x base.
		var clamped: float = api.clamp_pursuit(raw, BASE_RUN_SPEED, pursuit_ceiling)
		if clamped > 1e-9:
			tempo_mul = clampf(raw / clamped, 1.0, 1.0 / TEMPO_FLOOR)
		else:
			tempo_mul = 1.0
		if burst_ticks_left > 0:
			burst_ticks_left = maxi(burst_ticks_left - dt_ticks, 0)
			h_speed = minf(raw * burst_mult, burst_ceiling * BASE_RUN_SPEED)
		else:
			burst_mult = 1.0
			h_speed = clamped


# ---- VolleyClock (T-071: the D-064 volley gap, generic - no content id) ----------------------
## Splits a burst of n projectiles into volleys of at most VOLLEY_MAX, the remainder on the
## LAST volley: 4 -> [3,1], 5 -> [3,2], 6 -> [3,3], 7 -> [3,3,1]. Balls inside one volley
## sit VOLLEY_TICKS apart (0.15 s); consecutive volleys start VOLLEY_GAP_TICKS apart
## (0.75 s - one full jump), so each volley is cleared by its own jump.
static func volley_plan(balls: int) -> Array:
	return VolleyClock.plan_for(balls)


class VolleyClock:
	extends RefCounted

	var plan: Array = []           # volley sizes, e.g. [3, 3, 1] for 7
	var idx := 0                   # next volley
	var in_volley := 0             # balls already released of the current volley
	var wait := 0                  # ticks until the next release

	# (a static on the class: an inner class cannot call the outer script's statics)
	static func plan_for(balls: int) -> Array:
		var out: Array = []
		var left := maxi(int(balls), 0)
		while left > VOLLEY_MAX:
			out.append(VOLLEY_MAX)
			left -= VOLLEY_MAX
		if left > 0:
			out.append(left)
		return out

	func start(balls: int) -> void:
		plan = plan_for(balls)
		idx = 0
		in_volley = 0
		wait = 0

	func active() -> bool:
		return idx < plan.size()

	## Advance one tick; returns how many balls to release NOW (0 or 1 - releases are
	## staggered inside the volley, never two on the same tick). A release schedules the
	## next one VOLLEY_TICKS - 1 ticks later (wait counts down on the ticks BETWEEN
	## releases), so balls sit VOLLEY_TICKS apart and a volley's first balls sit
	## VOLLEY_GAP_TICKS apart start to start.
	func tick(dt_ticks: int = 1) -> int:
		var fired := 0
		for _i in range(maxi(dt_ticks, 0)):
			if idx >= plan.size():
				break
			if wait > 0:
				wait -= 1
				continue
			fired += 1
			in_volley += 1
			if in_volley >= int(plan[idx]):
				# next volley starts a full VOLLEY_GAP_TICKS after THIS volley started
				wait = VOLLEY_GAP_TICKS - (int(plan[idx]) - 1) * VOLLEY_TICKS - 1
				idx += 1
				in_volley = 0
			else:
				wait = VOLLEY_TICKS - 1
		return fired


# ---- SalvoClock (T-071: the D-064 salvo life limit, generic - no content id) -----------------
## One salvo = tracking (including EVERY restart after a broken lock) plus the descent, at
## most SALVO_MAX_TICKS from its FIRST tracking tick; a restart does not reset the budget.
## When the clock expires the salvo dies harmlessly: the caller stops tracking/descending
## and starts its pause.
class SalvoClock:
	extends RefCounted

	var ticks := 0
	var active := false
	var expired := false

	func start() -> void:
		# a restart (broken lock -> re-track) never resets the salvo's budget (D-064)
		if not active:
			active = true
			ticks = 0
			expired = false

	func tick(dt_ticks: int = 1) -> bool:
		## Advances the clock; true while the salvo may still act.
		if not active or expired:
			return false
		ticks += dt_ticks
		if ticks >= SALVO_MAX_TICKS:
			expired = true
			active = false
			return false
		return true


## SR-3 / F7: copy k of n starts its cycle offset by k/n of the cycle length (same unit as
## the cycle passed in - ticks or seconds; the caller rounds ticks).
static func stack_phase(cycle: float, k: int, n: int) -> float:
	if n <= 0 or cycle <= 0.0:
		return 0.0
	return cycle * float(k) / float(n)


# ---- the runtime itself ---------------------------------------------------------------------

var level: Dictionary = {}          # the level dict (terrain input, read-only)
var world: Dictionary = {}          # the T-012 collision world (live state: glitched/removed/enemies/projectiles)
var controllers: Array = []         # one T-012 controller per player, index = player index
var tick := 0                       # runtime tick (starts at 0 on level start, not the lv tick)
var spawn_delay_ticks := SPAWN_DELAY_TICKS
var events: Array = []              # the current step's events (controller.try_kill appends here)
var rt_set: Dictionary = {}         # round-trip-reachable tile index -> true (built once at setup)

# live enemy state:
var planned: Array = []             # spawn queue from the votes: [{"id","name","behavior","cfg","copies"}]
var enemies: Array = []             # rows (see _spawn_one)
var projectiles: Array = []         # live projectile rows
var telegraphs: Array = []          # {"kind","shape","ticks","total","source"}
var votes: Dictionary = {}          # content id -> vote count (insertion order = vote order)
var spawn_deferred := false         # true when the spawn tick passed but no legal tile existed yet
var overtime_tier := 0
var overtime_running := false
var overtime_t := 0.0
var overtime_period := OVERTIME_PERIOD
var curse_speed_mul := 1.0         # curse + repeatable-stack speed multiplier, kept here by
                                   # the engine layer from core stats; FloatBody multiplies
                                   # it with overtime BEFORE the SR-5 clamp
var seed_base := 0                  # the run's enemy_ai stream state at setup (D-T010-3)


# opts: spawn_delay_ticks (Early Bird 120), overtime_period.
func setup(p_level: Dictionary, p_world: Dictionary, p_controllers: Array,
		p_seed_base: int, opts: Dictionary = {}) -> void:
	level = p_level
	world = p_world
	controllers = p_controllers
	seed_base = p_seed_base
	spawn_delay_ticks = int(opts.get("spawn_delay_ticks", SPAWN_DELAY_TICKS))
	overtime_period = float(opts.get("overtime_period", OVERTIME_PERIOD))
	rt_set = round_trip_set(level)


# ---- votes (DESIGN.md section 5 vote table; the per-id numbers live in enemy.json) ----------

## One vote for a content id. Returns the new count, 0 when the id already sits at max_votes.
func add_vote(id: String, max_votes: int) -> int:
	var cur: int = int(votes.get(id, 0))
	if cur >= max_votes:
		return 0
	cur += 1
	votes[id] = cur
	return cur


# ---- spawn planning (the winner of the pre-run/intermission votes feeds this) ----------------

func plan(id: String, display_name: String, behavior: RefCounted, cfg: Dictionary,
		copies: int) -> void:
	planned.append({"id": id, "name": display_name, "behavior": behavior, "cfg": cfg,
			"copies": copies})


## Direct spawn at an explicit world position (tests, drop-in fixtures, engine callers that
## need a body now - e.g. the launcher). Same row shape as the D-056 rule produces.
func spawn_at(id: String, display_name: String, behavior: RefCounted, cfg: Dictionary,
		pos: Vector3, copy_index: int = 0, copies: int = 1) -> Dictionary:
	var spot := {"x": pos.x, "y": pos.y, "z": pos.z}
	_spawn_one({"id": id, "name": display_name, "behavior": behavior, "cfg": cfg,
			"copies": copies}, spot, copy_index, copies)
	return enemies[enemies.size() - 1]


# ---- one 60 Hz tick. Returns this tick's events (same convention as sim/controller.gd). -------

func step(dt: float) -> Array:
	events = []
	# spawn rule: the whole plan spawns on the spawn tick (or the first tick a legal tile
	# exists - D-T027-4), in plan order (vote order, D-056 candidate order per copy).
	if tick >= spawn_delay_ticks and not planned.is_empty():
		_spawn_planned()
	# overtime (section 3.2): begins at beacon open, +1 tier every period, cap 8 (D-T027-4).
	if overtime_running:
		overtime_t += dt
		while overtime_t >= overtime_period and overtime_tier < OVERTIME_MAX_TIER:
			overtime_t -= overtime_period
			overtime_tier += 1
			# T-080 telemetry event: the tier rise, so a log keeps the tier current
			# from events alone (beacon_enter records it). Additive.
			events.append({"e": "overtime_tier", "tier": overtime_tier, "tick": tick})
	# behaviors
	var dt_ticks := 1
	for e in enemies:
		var api := Api.new()
		api.rt = self
		api.row = e
		e["anim_t"] = float(e["anim_t"]) + dt
		var beh: RefCounted = e["behavior"]
		beh.tick(e, api, dt_ticks)
	# projectiles, then body-contact kills (the KILL RULE: the framework checks contact).
	_step_projectiles(dt)
	_contact_kills()
	# T-080: proximity sampling (the death records' on-screen field) and the death
	# enrichment; both AFTER the kills, additive, no behavior change.
	_update_near()
	_annotate_deaths()
	tick += 1
	return events


# ---- the D-056 spawn rule --------------------------------------------------------------------

## Spawns every planned entry:
##   (a) the enemy's preferred anchor kind; (b) a `lane` anchor; (c) any round-trip tile
##   >= 25 u from the spawn point. Never within 25 u of the player; farthest-from-the-player
##   first; the within-60 u preference applies at (a)/(b) only; tie-break lowest anchor index
##   ((a)/(b)) or lowest tile index ((c)). Copies of one chaser spread >= 30 u (SR-3).
##   preferred_kind "none" (DESIGN.md section 5's `none` rows) skips BOTH (a) and (b): the
##   enemy's initial position is fallback (c). "" keeps T-027's merged semantics (skips (a),
##   still runs (b)); see PARKED.md row 5.
func _spawn_planned() -> void:
	var queue: Array = planned
	planned = []
	for plan_row in queue:
		var id: String = plan_row["id"]
		var cfg: Dictionary = plan_row["cfg"]
		var kind: String = str(cfg.get("preferred_kind", ""))
		var copies: int = int(plan_row["copies"])
		# SR-3: "copies of one chaser are >= 30 u apart" - the separation runs against THIS
		# entry's own already-spawned copies (D-T061-6), not against the whole roster: with
		# all 22 bodies excluded at 30 u a dense vote list starves (no round-trip tile ever
		# clears every circle) and the plan never completes. _pick_round_trip's own comment
		# already states the same reading ("the earlier copies").
		# A partially-spawned entry tracks how many copies exist, so a deferral reschedules
		# only the MISSING copies (never re-spawns the placed ones) and never drops the
		# entries behind it - the old code `return`-ed on the first deferral, silently
		# dropping the whole tail of the plan (D-T061-6).
		var k: int = int(plan_row.get("spawned_copies", 0))
		while k < copies:
			# re-read the live copies each round: copy 1 must clear copy 0 (and so on)
			var exclude: Array = _copy_positions(id)
			var spot: Variant = pick_spawn_tile(level, kind, _player_pos(0), exclude,
					COPY_SEP if copies > 1 else 0.0)
			if spot == null:
				spawn_deferred = true
				plan_row["spawned_copies"] = k
				planned.append(plan_row)   # the entry's remaining copies retry next tick
				break
			spawn_deferred = false
			_spawn_one(plan_row, spot, k, copies)
			k += 1


## The live copies of one planned entry (SR-3's "the earlier copies").
func _copy_positions(id: String) -> Array:
	var out: Array = []
	for e in enemies:
		if str(e["id"]) == id:
			out.append(Vector3(float(e["x"]), float(e["y"]), float(e["z"])))
	return out


func _spawn_one(plan_row: Dictionary, spot: Dictionary, copy_index: int, copies: int) -> void:
	var cfg: Dictionary = plan_row["cfg"]
	var body: Dictionary = cylinder_from_sheet(cfg.get("world_height", 1.0),
			cfg.get("frame_w", 256), cfg.get("frame_h", 256), cfg.get("body_rect", [0, 0, 256, 256]))
	# D-T030-2: an explicit cfg hit_diameter (world u) pins the row's diameter -
	# DESIGN.md SR-2's FINAL per-enemy values win over the art derivation (the T-016
	# placeholder body_rect is interchangeable stand-in art)
	var diameter_u: float = float(body["diameter_u"])
	if cfg.has("hit_diameter"):
		diameter_u = maxf(float(cfg["hit_diameter"]), 0.0)
	var row := {
		"id": plan_row["id"], "name": plan_row["name"], "behavior": plan_row["behavior"],
		"cfg": cfg, "x": float(spot["x"]), "y": float(spot["y"]), "z": float(spot["z"]),
		"height_u": body["height_u"], "diameter_u": diameter_u,
		"contact_kill": bool(cfg.get("contact_kill", true)),
		"cycle_ticks": int(cfg.get("cycle_ticks", 0)),
		"copy_index": copy_index, "copies": copies,
		# SR-3: copy k of n starts its cycle offset by k/n of the cycle length
		"anim_phase": float(copy_index) / float(maxi(copies, 1)),
		"anim_t": 0.0,
		"rng": VoidRngScript.new(VoidRngScript.mix(seed_base, enemies.size() + 1)),
		"spawn_tick": tick,
	}
	row["anim_t"] = stack_phase(float(cfg.get("cycle_s", 0.0)), copy_index, maxi(copies, 1))
	row["phase_ticks"] = int(round(stack_phase(float(cfg.get("cycle_ticks", 0)),
			copy_index, maxi(copies, 1))))
	# T-071: a floater cfg carries its kinematics (base_speed / pursuit_ceiling /
	# burst_ceiling); the runtime attaches the FloatBody so tests and behaviors read one
	# instance from the row. Behaviors may still build their own.
	if cfg.has("base_speed"):
		row["float"] = FloatBody.from_cfg(cfg)
	enemies.append(row)
	var mirror := {"x": row["x"], "y": row["y"], "z": row["z"], "r": row["diameter_u"] * 0.5}
	row["body_mirror"] = mirror
	world["enemies"].append(mirror)
	var api := Api.new()
	api.rt = self
	api.row = row
	var beh: RefCounted = row["behavior"]
	beh.on_spawn(row, api)
	# diegetic spawn text (deliverable 4): the world shows the enemy's own name at its spawn
	# point; the view layer renders the event's text in-world (view/billboard.gd spawn_text()).
	events.append({"e": "enemy_spawn", "id": row["id"], "name": row["name"],
			"text": str(row["name"]), "x": row["x"], "y": row["y"], "z": row["z"], "tick": tick})


## The D-056 fallback order, pure function of the level dict + the player position.
## preferred_kind: "" keeps T-027's merged semantics (skip (a), still run (b)); "none"
## skips (a) AND (b) so the initial position is fallback (c) - DESIGN.md section 5's
## `none` rows (thicc ben's initial position is fallback (c)); see PARKED.md row 5.
## exclude: positions (Vector3) already used by this enemy's copies (SR-3), min_sep apart.
## Returns {"x","y","z","kind","anchor_index" | "tile_index"} or null when nothing qualifies
## (the caller retries next tick - D-T027-4).
static func pick_spawn_tile(lv: Dictionary, preferred_kind: String, player_pos: Vector3,
		exclude: Array = [], min_sep: float = 0.0) -> Variant:
	var anchors: Array = lv.get("anchors", [])
	if preferred_kind == "none":
		# DESIGN.md section 5: `none` skips (a) and (b) - straight to (c).
		return _pick_round_trip(lv, player_pos, exclude, min_sep)
	# candidates at steps (a)/(b): anchors of the kind, >= 25 u from the player, >= min_sep
	# from excluded positions; farthest from the player first, then the lowest anchor index.
	if preferred_kind != "" and KIND_IDS.has(preferred_kind):
		var pick: Variant = _pick_anchor(anchors, int(KIND_IDS[preferred_kind]), player_pos, exclude, min_sep)
		if pick != null:
			return pick
	var pick2: Variant = _pick_anchor(anchors, int(KIND_IDS["lane"]), player_pos, exclude, min_sep)
	if pick2 != null:
		return pick2
	# step (c): any round-trip tile >= 25 u from the spawn point and >= 25 u from the player;
	# the within-60 u preference is dropped here (D-056). Farthest from the player first, then
	# the lowest tile index in the level's tile order.
	return _pick_round_trip(lv, player_pos, exclude, min_sep)


static func _pick_round_trip(lv: Dictionary, player_pos: Vector3,
		exclude: Array, min_sep: float) -> Variant:
	var rts := round_trip_set(lv)
	var tiles: Array = lv.get("tiles", [])
	var spawn_pt: Array = lv["spawns"][0] if not lv.get("spawns", []).is_empty() else [0, 0, 1]
	var sx: float = float(spawn_pt[0]) + 0.5
	var sz: float = float(spawn_pt[1]) + 0.5
	var sy: float = float(spawn_pt[2]) * 0.5
	var best: Variant = null
	var best_d := -1.0
	for idx in rts.keys():
		var t: Array = tiles[int(idx)]
		var wx := float(int(t[0])) + 0.5
		var wy := float(int(t[2])) * 0.5
		var wz := float(int(t[1])) + 0.5
		var d := Vector3(wx - player_pos.x, wy - player_pos.y, wz - player_pos.z).length()
		if d < MIN_PLAYER_DIST:
			continue
		if Vector3(wx - sx, wy - sy, wz - sz).length() < MIN_PLAYER_DIST:
			continue
		# SR-3/T-071: copies must clear min_sep against the EXCLUDED positions (the earlier
		# copies), not against the player - the player floor is the MIN_PLAYER_DIST check
		# above. (T-027's step (c) compared against the player here; a 2-copy plan with no
		# anchors could then land both copies 5 u apart at the far end of the level.)
		var too_close := false
		for ex in exclude:
			if Vector3(wx - float(ex.x), 0.0, wz - float(ex.z)).length() < min_sep:
				too_close = true
				break
		if too_close:
			continue
		if best == null or d > best_d or (absf(d - best_d) < 1e-12 and int(idx) < int(best["tile_index"])):
			best = {"x": wx, "y": wy, "z": wz, "kind": "round_trip", "tile_index": int(idx)}
			best_d = d
	return best


static func _pick_anchor(anchors: Array, kind: int, player_pos: Vector3, exclude: Array,
		min_sep: float) -> Variant:
	var best: Variant = null
	var best_d := -1.0
	for i in range(anchors.size()):
		var a: Array = anchors[i]
		if int(a[0]) != kind:
			continue
		var wx := float(int(a[1])) + 0.5
		var wy := float(int(a[3])) * 0.5
		var wz := float(int(a[2])) + 0.5
		var d := Vector3(wx - player_pos.x, wy - player_pos.y, wz - player_pos.z).length()
		if d < MIN_PLAYER_DIST or d > PREFERRED_DIST:
			continue
		var skip := false
		for ex in exclude:
			if Vector3(wx - float(ex.x), 0.0, wz - float(ex.z)).length() < min_sep:
				skip = true
				break
		if skip:
			continue
		# farthest from the player first, then the lowest anchor index (exact-tie only)
		if best == null or d > best_d or (absf(d - best_d) < 1e-12 and i < int(best["anchor_index"])):
			best = {"x": wx, "y": wy, "z": wz, "kind": _kind_name(kind), "anchor_index": i}
			best_d = d
	return best


static func _kind_name(kind: int) -> String:
	for k in KIND_IDS.keys():
		if int(KIND_IDS[k]) == kind:
			return str(k)
	return "lane"


# ---- round-trip set (DESIGN.md section 5 step (c); D-T027-3) ----------------------------------
# The movement graph is the TERRAIN_SPEC reachability graph, rebuilt here from the level dict
# with the generator's own code (sim may import terrain): round-trip = forward- AND
# backward-reachable from the beacon tile. H7 (zero soft-lock tiles) makes forward and backward
# agree on real levels; synthetic test levels keep the same rule.

static func round_trip_set(lv: Dictionary) -> Dictionary:
	if lv.is_empty():
		return {}
	var w := VoidGenScript.World.new()
	for t in lv.get("tiles", []):
		w.tiles.append([int(t[0]), int(t[1]), int(t[2]), int(t[3]), int(t[4])])
	for p in lv.get("props", []):
		w.props.append([int(p[0]), int(p[1]), int(p[2]), int(p[3]), int(p[4]), int(p[5])])
	for p in lv.get("pads", []):
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
	var adj: Array = mv[1]
	var b: Array = lv.get("beacon", [0, 0, 1])
	var start: int = VoidGenScript.find_tile(w, int(b[0]), int(b[1]), int(b[2]))
	if start < 0:
		return {}
	var fwd: Array = VoidGenScript.bfs(adj, start)
	var radj: Array = []
	radj.resize(adj.size())
	for i in range(radj.size()):
		radj[i] = []
	for i in range(adj.size()):
		for j in adj[i]:
			radj[j].append(i)
	var back: Array = VoidGenScript.bfs(radj, start)
	var out := {}
	for i in range(fwd.size()):
		if fwd[i] and back[i]:
			out[i] = true
	return out


# ---- the kill API plumbing -----------------------------------------------------------------

func _resolve_player(p) -> Variant:
	if p is RefCounted:
		return p
	if p is int and int(p) >= 0 and int(p) < controllers.size():
		return controllers[int(p)]
	return null


func kill(player, killer_id: String, code: String = "") -> bool:
	var ctl = _resolve_player(player)
	if ctl == null or world.is_empty():
		return false
	# death code: an explicit cfg death_code (passed verbatim by the caller, D-T030-1) wins
	# over the name derivation; DESIGN.md section 3.1's FINAL code list is the contract
	var death_code := code
	if death_code == "":
		death_code = "D-%s" % str(killer_id).to_upper().replace(" ", "_")
	return ctl.try_kill(death_code, str(killer_id), world, events)


func push(player, dir: Vector3, speed: float, src_row: Dictionary = {}) -> void:
	var ctl = _resolve_player(player)
	if ctl == null:
		return
	var d := dir
	if d.length() < 1e-9:
		d = Vector3(0.0, 0.0, 1.0)
	else:
		d = d.normalized()
	# a push is a non-killing effect: velocity only, no damage, no lock, no death
	ctl.vx = d.x * speed
	ctl.vy = d.y * speed
	ctl.vz = d.z * speed
	if d.y > 0.0:
		ctl.grounded = false
	# T-080 telemetry event (the void_fall record's "pushed in the last 120 ticks / by
	# which enemy" reads these): additive, no behavior change. Keyed by content id.
	events.append({"e": "push", "by": str(src_row.get("id", "")), "tick": tick,
			"player": controllers.find(ctl) if controllers.has(ctl) else -1})


func lock_abilities(player, ticks: int) -> void:
	var ctl = _resolve_player(player)
	if ctl == null:
		return
	# T-072: the controller's data-driven entry (player.json, ability_lock.lock_effect)
	# carries which class abilities the window disables - the dispatch lives there
	ctl.lock_abilities(int(ticks))


func _player_index(p) -> int:
	if p is int:
		var i := int(p)
		return i if i >= 0 and i < controllers.size() else -1
	for i in range(controllers.size()):
		if controllers[i] == p:
			return i
	return -1


## T-032: keep this row's mirror entry (world["enemies"]) in sync after an instant
## reposition. The mirror is otherwise written once at spawn; movers update the row
## only, so anything that TELEPORTS must call this or the safe-tile / dais-push
## distance checks (which read the mirror) see the stale point.
func sync_body_mirror(row: Dictionary) -> void:
	var m: Variant = row.get("body_mirror", null)
	if not (m is Dictionary):
		return
	m["x"] = float(row["x"])
	m["y"] = float(row["y"])
	m["z"] = float(row["z"])
	m["r"] = float(row["diameter_u"]) * 0.5


## T-032: a non-killing eject (DESIGN.md 5.3, section 5.0 KILL RULE's third listed
## non-killing effect). Appends the two events the engine caller consumes - the
## chain_reset (economy.break_chain(why)) and the HUD blur announcement. `why` is
## DATA (the economy break_events whitelist); nothing else may reset the chain.
func eject_player(source_row: Dictionary, player, why: String, blur_ticks: int) -> void:
	var idx := _player_index(player)
	if idx < 0:
		return
	events.append({"e": "chain_reset", "why": str(why), "tick": tick, "player": idx})
	events.append({"e": "screen_blur", "ticks": int(blur_ticks), "tick": tick,
			"player": idx, "source": str(source_row.get("id", ""))})
	# T-080: an eject is a push in the void_fall record's sense (the launch is the
	# danger). Same additive event, also counted toward on-screen evidence.
	events.append({"e": "push", "by": str(source_row.get("id", "")), "tick": tick,
			"player": idx})


## T-032: the ben ring cleanse (DESIGN.md 5.8: "thicc ben's ring cleanses
## glitched tiles within 8 u"; T-083 anim block attack_ring expands the ring to
## 8 u in 18 ticks). D-T-032-3: horizontal (XZ) distance from the tile centre.
func cleanse_glitched_within(source_row: Dictionary, pos: Vector3, r: float) -> int:
	if world.is_empty():
		return 0
	var g: Dictionary = world.get("glitched", {})
	var dead: Array = []
	for key in g.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 2:
			continue
		var tx := float(int(parts[0])) + 0.5
		var tz := float(int(parts[1])) + 0.5
		var dx := tx - pos.x
		var dz := tz - pos.z
		if dx * dx + dz * dz <= r * r:
			dead.append(key)
	for key in dead:
		g.erase(key)
	events.append({"e": "glitched_cleanse", "count": dead.size(), "r": float(r),
			"tick": tick, "x": pos.x, "z": pos.z,
			"source": str(source_row.get("id", ""))})
	return dead.size()


# T-072: this row's declarative scheduling gate - its cfg `arbiter` block (plain DATA:
# appear_requires + yields_to) evaluated against the live sim state, {"may_appear",
# "deferred"}. The player is the row's target (player 0 - the nearest player, D-T072-5);
# deferral answers this row's yields_to ids (DATA) against the live telegraph/caller
# countdown sources: no id is named here, this runtime only assembles the state.
func arbiter_evaluate(cfg: Dictionary, player_index: int = 0, pending: Array = []) -> Dictionary:
	var target = null
	if player_index >= 0 and player_index < controllers.size():
		target = controllers[player_index]
	# The gate's own data is the cfg `arbiter` block (T-072's response, SR-4), not the whole
	# row cfg - evaluate() reads appear_requires/yields_to at the top of what it is given.
	# `pending` is the caller's own countdown ids (Api.arbiter_gate forwards them here);
	# evaluate() folds them into busy_sources() itself, so they are passed through, not
	# pre-computed. Passing a pre-computed busy list here double-counted the telegraphs.
	var gate: Dictionary = cfg.get("arbiter", {})
	return ArbiterScript.evaluate(gate, target, world, telegraphs, pending)


# ---- body contact (the KILL RULE: every body contact kills) ---------------------------------
# Hit shape: upright cylinder, diameter = 0.8 x body width, height = body height (HITBOXES),
# feet at row["y"]. Contact vs the player's 0.4 half-width AABB: horizontal circle distance
# (expanded by the player half-width) + a y-band overlap.

static func cylinder_from_sheet(world_height: float, frame_w: int, frame_h: int,
		body_rect: Array) -> Dictionary:
	# body_rect = [bx, by, bw, bh] pixels; the sprite is scaled so the BODY is world_height u
	# tall - never the PNG frame (D-T027-6). World width follows from the same scale.
	var brh: float = float(maxi(int(body_rect[3]), 1))
	var brw: float = float(maxi(int(body_rect[2]), 1))
	var scale: float = float(world_height) / brh
	var width_u: float = brw * scale
	return {"height_u": float(world_height), "width_u": width_u,
			"diameter_u": HIT_DIA_FRACTION * width_u}


static func cylinder_hit_point(row: Dictionary, px: float, py: float, pz: float) -> bool:
	var r: float = float(row["diameter_u"]) * 0.5
	if r <= 0.0:
		return false
	var dx: float = px - float(row["x"])
	var dz: float = pz - float(row["z"])
	if dx * dx + dz * dz > r * r:
		return false
	return py >= float(row["y"]) and py <= float(row["y"]) + float(row["height_u"])


static func body_contact(row: Dictionary, ctl) -> bool:
	# player body: half-width 0.4, height 1.8, feet at ctl.y (DESIGN.md section 4)
	var r: float = float(row["diameter_u"]) * 0.5 + 0.4
	var dx: float = float(ctl.x) - float(row["x"])
	var dz: float = float(ctl.z) - float(row["z"])
	if dx * dx + dz * dz > r * r:
		return false
	var py0: float = float(ctl.y)
	var py1: float = py0 + 1.8
	return py0 <= float(row["y"]) + float(row["height_u"]) and py1 >= float(row["y"])


func _contact_kills() -> void:
	for e in enemies:
		if not bool(e["contact_kill"]) or float(e["diameter_u"]) <= 0.0:
			continue
		for i in range(controllers.size()):
			var ctl = controllers[i]
			if ctl == null or ctl.dead or ctl.respawn_t >= 0.0:
				continue
			if body_contact(e, ctl):
				var api := Api.new()
				api.rt = self
				api.row = e
				# D-T030-1: cfg death_code (verbatim) wins over the name derivation
				api.kill(i, str(e["name"]), str(e["cfg"].get("death_code", "")))


# ---- T-080: the death records' on-screen evidence ----------------------------------------------

## View-free "on screen" proxy (D-T080-2 [CONTESTABLE]): the killer had a body or a
## telegraph footprint within this radius of the player's centre during the last 120
## ticks (the 2 s the owner's spec names). 24 u sits between the fill-light range
## (18 u) and the Radar: Threats marker range (30 u); there is no camera in sim.
const ON_SCREEN_R := 24.0

## Last tick each killer was within ON_SCREEN_R of each player's centre:
## {player_index: {"<death code>": tick, "<content id>": tick}}. Keys come from the
## LIVE rows only (cfg death_code + content id) - this file never names a content id
## (the boundary rule; the roster's data carries the pairing, not this code).
## Runtime-owned telemetry (not part of the state hash).
var near_seen: Dictionary = {}


func _update_near() -> void:
	for i in range(controllers.size()):
		var ctl = controllers[i]
		if ctl == null:
			continue
		var seen: Dictionary = near_seen.get(i, {})
		near_seen[i] = seen
		var cy: float = float(ctl.y) + 0.9
		for e in enemies:
			if float(e["diameter_u"]) <= 0.0:
				continue
			var dx: float = float(e["x"]) - float(ctl.x)
			var dy: float = float(e["y"]) + float(e["height_u"]) * 0.5 - cy
			var dz: float = float(e["z"]) - float(ctl.z)
			if dx * dx + dy * dy + dz * dz <= ON_SCREEN_R * ON_SCREEN_R:
				seen[str(e["id"])] = tick
				var dc: String = str((e["cfg"] as Dictionary).get("death_code", ""))
				if dc != "":
					seen[dc] = tick
		# a LIVE telegraph's footprint is on screen by the view's own language (the
		# client draws exactly these) - the no-body killers' evidence (the ring,
		# the patch, the rumble cues). Rows in rt.telegraphs never expire (the
		# glitch-floor test's finding), so liveness is filtered by start tick + duration.
		for t in telegraphs:
			if tick < int(t["tick"]) or tick >= int(t["tick"]) + maxi(int(t["total"]), 1):
				continue
			var sh: Dictionary = t["shape"]
			var tx: float = float(sh.get("cx", -1e9))
			var tz: float = float(sh.get("cz", -1e9))
			var r: float = maxf(float(sh.get("r", 0.0)), 0.0)
			var lim := ON_SCREEN_R + r
			var dx2: float = tx - float(ctl.x)
			var dz2: float = tz - float(ctl.z)
			if dx2 * dx2 + dz2 * dz2 <= lim * lim:
				seen[str(t.get("source", ""))] = tick


## True when the death code's killer was within ON_SCREEN_R of any player's centre in
## the last 120 ticks. The code -> id resolution reads the live plan rows' cfg
## (death_code) - never a literal id here. "D-VOID" has no body: false by construction.
func _killer_on_screen(code: String) -> bool:
	if code == "" or code == "D-VOID":
		return false
	if code.begins_with("D-CURSE:"):
		return false
	var window := tick - 120
	for i in near_seen.keys():
		var seen: Dictionary = near_seen[i]
		if int(seen.get(code, -999999)) >= window:
			return true
		# the code's content id via the plan's cfg (the contact path stores the code
		# there; the kill-idiom constants in content reach the same key)
		for p in planned:
			var cfg: Dictionary = (p["cfg"] as Dictionary)
			if str(cfg.get("death_code", "")) == code and int(seen.get(str(p["id"]), -999999)) >= window:
				return true
	return false


func _annotate_deaths() -> void:
	for ev in events:
		var d: Dictionary = ev
		if str(d.get("e", "")) == "death" and not d.has("on_screen"):
			d["on_screen"] = _killer_on_screen(str(d.get("code", "")))


# ---- projectiles (kill on hit - KILL RULE; no partial effect) --------------------------------

func spawn_projectile(source_row: Dictionary, def: Dictionary) -> void:
	var p := {
		"name": def.get("name", source_row.get("name", "")),
		"x": float(def.get("x", source_row.get("x", 0.0))),
		"y": float(def.get("y", source_row.get("y", 0.0))),
		"z": float(def.get("z", source_row.get("z", 0.0))),
		"vx": float(def.get("vx", 0.0)), "vy": float(def.get("vy", 0.0)),
		"vz": float(def.get("vz", 0.0)),
		"r": float(def.get("r", 0.25)),
		"life_ticks": int(def.get("life_ticks", 600)),
		"alive": true,
	}
	projectiles.append(p)
	events.append({"e": "projectile_spawn", "name": p["name"], "x": p["x"], "y": p["y"],
			"z": p["z"], "tick": tick})


func _step_projectiles(dt: float) -> void:
	var keep: Array = []
	for p in projectiles:
		if not bool(p["alive"]):
			continue
		p["x"] = float(p["x"]) + float(p["vx"]) * dt
		p["y"] = float(p["y"]) + float(p["vy"]) * dt
		p["z"] = float(p["z"]) + float(p["vz"]) * dt
		p["life_ticks"] = int(p["life_ticks"]) - 1
		var cause := ""
		if int(p["life_ticks"]) <= 0:
			cause = "life"
		elif _point_solid(float(p["x"]), float(p["y"]), float(p["z"])):
			# died on a tile slab or prop box (includes every pad: a spire pad is tiles -
			# a descending missile meets the slab and detonates there, D-064)
			cause = "solid"
		if cause == "":
			for i in range(controllers.size()):
				var ctl = controllers[i]
				if ctl == null or ctl.dead or ctl.respawn_t >= 0.0:
					continue
				var r: float = float(p["r"]) + 0.4
				var dx: float = float(ctl.x) - float(p["x"])
				var dz: float = float(ctl.z) - float(p["z"])
				var dy_hit: bool = float(ctl.y) <= float(p["y"]) + float(p["r"]) \
						and float(ctl.y) + 1.8 >= float(p["y"]) - float(p["r"])
				if dx * dx + dz * dz <= r * r and dy_hit:
					var api := Api.new()
					api.rt = self
					api.row = p
					api.kill(i, str(p["name"]))
					cause = "hit"
					break
		if cause != "":
			# T-071: where and why the projectile ended - the view detonates/explores the
			# effect there; tests read it instead of guessing positions
			events.append({"e": "projectile_end", "name": p["name"], "cause": cause,
					"x": p["x"], "y": p["y"], "z": p["z"], "tick": tick})
		else:
			keep.append(p)
	projectiles = keep
	# mirror for the controller's safe-tile checks (valid_safe_tile reads w["projectiles"])
	var mirror: Array = []
	for p2 in projectiles:
		mirror.append({"x": p2["x"], "y": p2["y"], "z": p2["z"], "r": p2["r"]})
	world["projectiles"] = mirror


func _point_solid(px: float, py: float, pz: float) -> bool:
	var boxes: Array = []
	CollisionScript._boxes_in_column(world, int(floor(px)), int(floor(pz)), boxes)
	for b in boxes:
		if float(b["lo"]) < py and float(b["hi"]) > py:
			return true
	return false


# ---- telegraphs (api.telegraph; the view renders them, hazards land with the strike) --------

func telegraph(source_row: Dictionary, kind: String, shape: Dictionary, ticks: int) -> void:
	var t := {"kind": str(kind), "shape": shape, "ticks": maxi(int(ticks), 0),
			"total": maxi(int(ticks), 0), "source": source_row.get("id", ""), "tick": tick}
	telegraphs.append(t)
	events.append({"e": "telegraph", "kind": t["kind"], "shape": shape, "ticks": t["ticks"],
			"source": t["source"], "tick": tick})


# ---- overtime multipliers (DESIGN.md section 3.2) --------------------------------------------

func on_beacon_open() -> void:
	overtime_running = true
	overtime_t = 0.0


func add_overtime_tier(n: int) -> void:
	overtime_tier = mini(overtime_tier + int(n), OVERTIME_MAX_TIER)


func speed_mul() -> float:
	if not overtime_running:
		return 1.0
	return 1.0 + OVERTIME_SPEED_PER_TIER * float(overtime_tier)


func cd_mul() -> float:
	if not overtime_running:
		return 1.0
	var out: float = 1.0 - OVERTIME_CD_PER_TIER * float(overtime_tier)
	return maxf(out, 0.0)


# ---- API surface queries ---------------------------------------------------------------------

func nearest_player(pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_d := -1.0
	for i in range(controllers.size()):
		var ctl = controllers[i]
		if ctl == null:
			continue
		var d := Vector3(float(ctl.x) - pos.x, float(ctl.y) - pos.y, float(ctl.z) - pos.z).length()
		if best_d < 0.0 or d < best_d:
			best = {"index": i, "dist": d, "x": float(ctl.x), "y": float(ctl.y), "z": float(ctl.z),
					"vx": float(ctl.vx), "vy": float(ctl.vy), "vz": float(ctl.vz)}
			best_d = d
	return best


func anchors(kind: String) -> Array:
	var want: Variant = KIND_IDS.get(str(kind), -1)
	var out: Array = []
	for i in range(level.get("anchors", []).size()):
		var a: Array = level["anchors"][i]
		if int(a[0]) != int(want):
			continue
		out.append({"x": float(int(a[1])) + 0.5, "y": float(int(a[3])) * 0.5,
				"z": float(int(a[2])) + 0.5, "index": i})
	return out


func tiles_in_radius(pos: Vector3, r: float) -> Array:
	var out: Array = []
	for i in range(level.get("tiles", []).size()):
		var t: Array = level["tiles"][i]
		var wx := float(int(t[0])) + 0.5
		var wy := float(int(t[2])) * 0.5
		var wz := float(int(t[1])) + 0.5
		if Vector3(wx - pos.x, wy - pos.y, wz - pos.z).length() <= r:
			out.append({"x": wx, "y": wy, "z": wz, "index": i})
	return out


## Tile/prop ray: marches the segment at LOS_STEP and reports any sample point strictly inside
## a solid box (tile slab or prop). Endpoints sit at bodies' centres, never inside solids.
func los(a: Vector3, b: Vector3) -> bool:
	var diff := b - a
	var seg := diff.length()
	if seg < 1e-9:
		return true
	var n := int(seg / LOS_STEP) + 1
	for i in range(1, n):
		var f := float(i) / float(n)
		var px: float = a.x + diff.x * f
		var py: float = a.y + diff.y * f
		var pz: float = a.z + diff.z * f
		if _point_solid(px, py, pz):
			return false
	return true


func target_feet_y(row: Dictionary) -> float:
	var near := nearest_player(Vector3(float(row["x"]), float(row["y"]), float(row["z"])))
	if near.is_empty():
		return float(row["y"])
	return float(near["y"])


## Straight-line approach over geometry and the void ("Floats"), SR-1: horizontal speed is the
## caller's already-multiplied-and-clamped value; feet ease toward the target's feet height at
## FLOATER_CLIMB u/s, NEVER multiplied (D-068). No collision: a floater crosses tiles and void.
func move_toward(row: Dictionary, tx: float, tz: float, h_speed: float, target_y: float) -> void:
	var dx := tx - float(row["x"])
	var dz := tz - float(row["z"])
	var d := sqrt(dx * dx + dz * dz)
	if d > 1e-9 and h_speed > 0.0:
		var step_len: float = minf(h_speed / TICKS_PER_SECOND, d)
		row["x"] = float(row["x"]) + dx / d * step_len
		row["z"] = float(row["z"]) + dz / d * step_len
	var ty := float(row["y"])
	var v: float = target_y - ty
	if absf(v) > 1e-9:
		var vs: float = minf(FLOATER_CLIMB / TICKS_PER_SECOND, absf(v))
		row["y"] = ty + v / absf(v) * vs


func _player_pos(i: int) -> Vector3:
	if i < controllers.size() and controllers[i] != null:
		return Vector3(float(controllers[i].x), float(controllers[i].y), float(controllers[i].z))
	if not level.get("spawns", []).is_empty():
		var s: Array = level["spawns"][0]
		return Vector3(float(int(s[0])) + 0.5, float(int(s[2])) * 0.5, float(int(s[1])) + 0.5)
	return Vector3(0.0, 0.0, 0.0)


func _spawn_positions() -> Array:
	var out: Array = []
	for e in enemies:
		out.append(Vector3(float(e["x"]), float(e["y"]), float(e["z"])))
	return out
