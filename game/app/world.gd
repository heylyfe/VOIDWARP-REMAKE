extends Node3D
#
# Reusable playable level (ticket APP-FLOW): the assembled sim + view of one level as a
# Node3D the app orchestrator can add to the tree. Adapted from game/tools/perf_probe.gd's
# working _build_scene() assembly: voidgen.generate -> collision.make_world ->
# level_mesher.build (one MeshInstance3D per mesh) -> fog_env WorldEnvironment configured
# for the level's biome -> controller -> camera_rig -> enemy_runtime -> one billboard per
# enemy, PLUS view/hud/hud.gd (the probe has no HUD; this is the real game scene).
#
# Differences from the probe, by ticket:
#   - the enemy plan is the run's OWN seeded plan, not the probe's hardcoded VOTE_LIST:
#     the pre-run/intermission votes for this level are resolved by replaying the
#     intermissions the run would have seen (level_completed 0..level-1) with the sim's
#     own Intermission/Offers systems, seeded from the run seed, and the resulting votes
#     dict IS the plan (bot_run.gd's resolving idiom; "votes ARE inputs", DESIGN.md
#     section 13 rule 2). U / REST bays are never touched (no purchase policy is
#     invented); an empty mandatory C draw is tithe-passed when affordable, exactly the
#     bot's rule. For level 1 this replays the pre-run lobby (CLASS + the one starter
#     E bay). Class comes from the CLASS bay the same way; "dasher" when unset.
#   - the HUD is a CanvasLayer child (a Control cannot render under a Node3D).
#   - the LevelState owner decision landed (APP-LOOP): step() now builds and owns
#     the sim LevelState (gifts / mines / beacon) exactly the way tools/bot_run.gd
#     ticks it - controller -> player-row sync -> lv.tick++ -> GiftsScript.tick ->
#     MinesScript.tick -> beacon try_enter -> enemy_runtime. The economy (chain /
#     purse) is ticked on the same pass: beacon open begins the gold phase,
#     tick_gold(dt) advances the window, gold gift pickups pay collect_gold_gift,
#     chain_reset events break the chain, beacon entry pays the stipend. A signal
#     (level_completed) reports the completion so app.gd can advance.
#   - the run's owned upgrade stacks and held curses reach the live run through
#     core/content_api.gd's apply_modifiers (DESIGN.md section 12): the economy reads the
#     gold-phase stats (gold_value / chain_window / chain_cap / overtime_period /
#     stipend_flat) and the controller reads its six (run_speed / glitch_slow_mul /
#     respawn_delay / respawn_invuln / void_charges_max / void_fall_charge_cost). A stat
#     with no consumer in either file is NOT applied here - see the ticket report; the
#     enemy runtime, the mines, the gifts and the view keep their own knobs.
#
# The run seed reaches the controller and the camera unchanged; the ENEMY runtime gets the
# same run seed (spawn stream), the intermissions are seeded mix(seed, 5000 + lobby) /
# mix(mix(seed, 0xB07), lobby + 1) exactly as the bot seeds them, so the whole level is a
# pure function of (seed, level).
#
# public API:
#   func build(seed_value: int, level: int) -> bool  # false on generator/content failure, never crash
#   func step(dt: float) -> void                     # one sim tick + view pass
#   func teardown() -> void
#   func level_number() -> int
#   func is_complete() -> bool                       # true once the beacon was entered (APP-LOOP)
#
# signal level_completed()  - emitted exactly once, at the end of the tick in which
# the beacon is entered (the sim's level_complete event fires on the same tick).
# (The APP-LOOP tick order lives in step()'s own doc comment below.)
#
# signal run_over(info)  - emitted exactly once, at the end of the tick in which the
# controller reports dead: a third void fall, an enemy contact or a tripmine - every
# kill path lands on ctl.dead. DESIGN.md section 3: "Death ends the run." info is
# sim/death.gd's screen_data() row (code / killer / level / purse) plus the charges
# held at death, i.e. the keys view/hud/run_over.gd reads. A dead run never ticks
# again: step() returns before the sim once the latch is set, so the app owns the
# frame from there on (death black-out -> run-over screen).

const VoidGenScript := preload("res://terrain/voidgen.gd")
const CollisionScript := preload("res://sim/collision.gd")
const MesherScript := preload("res://view/level_mesher.gd")
const CollapseScript := preload("res://sim/collapse.gd")          # platform collapse schedule
const CollapseViewScript := preload("res://view/collapse_view.gd")  # its cracks + drop
const GliderViewScript := preload("res://view/glider_view.gd")      # the glide wing on the figure
const ControllerScript := preload("res://sim/controller.gd")
const CameraRigScript := preload("res://app/camera_rig.gd")
const EnemyRuntimeScript := preload("res://sim/enemy_runtime.gd")
const StatsScript := preload("res://core/stats.gd")
const BillboardScript := preload("res://view/billboard.gd")
const FogEnvScript := preload("res://view/fog_env.gd")
const SkyDomeScript := preload("res://view/sky_dome.gd")   # D-ATMO-1
const DebrisScript := preload("res://view/debris.gd")      # D-ATMO-2
const HudScript := preload("res://view/hud/hud.gd")
# The core-loop views (DESIGN.md section 3): the black/gold gifts, the tripmine tell and
# the beacon with its progress ring + light column. Nothing under app/ drew them.
const GiftsViewScript := preload("res://view/gifts_view.gd")
const TripmineViewScript := preload("res://view/tripmine_view.gd")
const BeaconViewScript := preload("res://view/beacon_view.gd")
# The glitched-floor decal layer. The body is one of the `boards` billboards; the decals are
# a separate world-origin node in floor-only mode, because the sim's glitched entries carry
# absolute tile coordinates and the body node moves.
const ToucherViewScript := preload("res://view/toucher_view.gd")
const ContentApiScript := preload("res://core/content_api.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")
const SettingsScript := preload("res://app/settings.gd")
# The T-015 player figure. Without it the third-person rig frames empty space and the game
# reads first-person: the camera sits 7 u behind a body that was never drawn.
const PLAYER_MODEL := "res://assets/models/player_figure.glb"
# APP-LOOP: the sim LevelState (gifts / mines / beacon), the gift + mine ticks and the
# gold-phase economy - the same pieces tools/bot_run.gd ticks on the reference surface.
const LevelStateScript := preload("res://sim/level_state.gd")
const GiftsScript := preload("res://sim/gifts.gd")
const MinesScript := preload("res://sim/mines.gd")
const EconomyScript := preload("res://sim/economy.gd")
const InputScript := preload("res://sim/input.gd")
const DeathScript := preload("res://sim/death.gd")
# The enemy presentation layer (the VFX wiring wave): every view below existed and was
# tested in isolation, but nothing fed it, so attacks arrived with no ring, no line, no
# sound, and projectiles were invisible. build() creates them, step() feeds them.
const TelegraphViewScript := preload("res://view/vfx/telegraph_view.gd")
const CoilTelegraphScript := preload("res://view/vfx/coil_telegraph.gd")
const ProjectileViewScript := preload("res://view/vfx/projectile_view.gd")
const StragglerBeamScript := preload("res://view/straggler_beam.gd")
const DangerTextScript := preload("res://view/hud/danger_text.gd")
const ScreenBlurScript := preload("res://view/hud/screen_blur.gd")
const RespawnViewScript := preload("res://view/respawn_view.gd")
# The player's and the world's own cues (the "too quiet" pass): footsteps, landing, dash,
# the glide bed, the gift pickup, the level-complete and death stings, the collapse crack
# and fall. Every file is synthesized by game/tools/audio/synth_cues.gd; a missing file is
# silent, never an error (view/audio/cue_audio.gd's house shape).
const PlayerAudioScript := preload("res://view/audio/player_audio.gd")
const WorldAudioScript := preload("res://view/audio/world_audio.gd")
# The enemy cues that ride a row state edge (the blast frame, the ring release): their
# enemy.json rows name sim events the sim never raises, so the edge is the hook. The
# id/state table lives in view/audio/enemy_cue.gd - app/ names no content id.
const EnemyCueScript := preload("res://view/audio/enemy_cue.gd")
# The curse hook dispatcher (W9-A): every held SCRIPT curse's module hooks (on_level_start /
# on_tick / on_beacon_open / on_void_fall) and its build-time queries run through it. The
# declarative "modifiers" half of a curse still goes through _run_modifiers below.
const CurseRuntimeScript := preload("res://sim/curse_runtime.gd")
# The upgrade hook dispatcher (W13-A): every owned SCRIPT upgrade's module hooks
# (on_gift_collected / on_beacon_enter / on_void_fall / on_mine_defused /
# on_barrier_absorbed) run through it, event-driven, before the economy pass; its
# on_curse_draw entry runs over the lobby's curse bays. Before it existed four upgrades
# declared hooks nothing called, and the shop took the gold for nothing.
const UpgradeRuntimeScript := preload("res://sim/upgrade_runtime.gd")
# The owned scripted upgrades' sim ROLES (D-T053-1): the one id -> role table. The world
# built the LevelState without them, so lstate.upgrades stayed null and every role-gated
# feature (the radars, the footprint map, the 90% quota, the beacon channel) was dead.
const UpgradeRolesScript := preload("res://content/upgrades/t053_roles.gd")
# The scripted-upgrades engine itself (T-053): the radar queries and the footprint-map
# memory the HUD feed reads. Roles and ranges come from the engine's own constants;
# no upgrade id is named here (the id-to-role table lives in content).
const UpgradesScript := preload("res://sim/upgrades.gd")
# The bespoke per-enemy views (W11-A): nine view files existed, complete and tested, and
# nothing instantiated them, so every enemy rendered as the generic billboard. The host
# owns the per-view signatures (view/ may name content ids; this file may not) and is
# fed through one uniform call set. A row whose id has no bespoke view keeps the billboard.
const EnemyViewHostScript := preload("res://view/enemies/enemy_view_host.gd")

signal level_completed()
signal run_over(info: Dictionary)

const DT := 1.0 / 60.0
const FALLBACK_CLASS := "dasher"   # D-APPFLOW-6 when the CLASS bay somehow resolved to ""

var lv: Dictionary = {}
var w: Dictionary = {}
var ctl = null
var rt = null
var rig: Node3D = null
var camera: Camera3D = null
var fog: WorldEnvironment = null
# Atmosphere (D-ATMO-1/2): the sky dome + floating rocks. View-only; false skips both
# (test_atmosphere.gd hashes the sim with it on and off). Found by name: SkyDome / Debris.
var atmosphere := true
var hud: Control = null
# The core-loop views: built in build(), driven from step(), freed by teardown().
var gifts_view: Node3D = null
var tripmine_view: Node3D = null
var beacon_view: Node3D = null
var toucher_floor: Node3D = null   # the glitched-floor decals (floor-only mode)
# The enemy presentation layer (see the preloads): telegraphs + their cues, Coil's own
# landing ring/shockwave, projectiles, the straggler beam, the diegetic danger text,
# thicc ben's screen blur and the respawn invulnerability visual.
var telegraph_view: Node3D = null
var coil_view: Node3D = null
var projectile_view: Node3D = null
var straggler_beam: Node3D = null
var danger_text: Node3D = null
var screen_blur: Control = null
var respawn_view: Node3D = null
var boards: Array = []          # EnemyRuntime enemies index -> billboard node (or null)
# EnemyRuntime enemies index -> the row's bespoke view host (or null; a row has a host OR
# a billboard, never both, so nothing is drawn twice). Index-aligned with boards.
var enemy_views: Array = []
# Off = every row falls back to the generic billboard (the wiring test's negative
# control). Not reset by teardown(): it is a setting, not per-level state.
var bespoke_enemy_views := true
# M1: the HUD feed switch. true (the default) feeds the radar and the footprint map
# exactly as shipped; false empties both feeds, so the radar wiring test can run its
# negative control through this one field instead of asserting nothing. Owned by the
# feed-off path only; the sim's own memory is untouched either way.
var radar_feed := true
var lstate: RefCounted = null   # the sim LevelState (gifts / mines / beacon); bot_run.gd's lv
var player_model: Node3D = null # the T-015 player figure, feet on the controller's position
var _player_yaw := 0.0          # facing yaw, follows the camera's forward while captured
var _player_light: OmniLight3D = null   # palette.json player_fill_light, rides the figure
var glider_view: Node3D = null   # view/glider_view.gd, child of player_model; shown while gliding

# The player's own cue state (view/audio/player_audio.gd): the step clock and its variant
# counter, and the glide bed the glide engagement owns. Tick-driven, never wall clock, so
# two identical runs step on the same ticks.
const STEP_PERIOD := 0.34        # s between footsteps at a run
const STEP_MIN_SPEED := 1.0      # u/s: below this the player is standing, not walking
var _step_clock := STEP_PERIOD   # armed: the first moving tick lands a step
var _step_variant := 0
var _glide_player: AudioStreamPlayer = null
# enemy index -> the anim_state last seen, for the state-edge cues (view/audio/enemy_cue.gd)
var _row_anim_state := {}

# --- J5: mouse-lock and the procedural figure pose (view side; sim is never touched) -----
# MOUSE-LOOK (J5, supersedes D-T082-4's "no turn"): Ctrl toggles capture. Captured, the
# cursor is hidden and every mouse-motion delta turns the rig through apply_mouse() at the
# settings' sensitivity; released, the cursor shows and the motion handler is a no-op.
# The state machine is camera_rig.next_mouse_locked (pure); the mode applier is
# camera_rig.mouse_mode_for. Release paths: the APP_PAUSE edge, the death latch and
# teardown() (menu) - all four transitions live here in world.gd.
var _mouse_locked := false       # start captured when a level begins (build() sets it)
var _prev_mouse_toggle := false  # last tick's APP_MOUSE_TOGGLE, for the edge detect
var _prev_app_pause := false     # last tick's APP_PAUSE, for the edge detect
var _mouse_sens := CameraRigScript.MOUSE_SENS_DEFAULT  # settings.mouse_sensitivity

# The fixed tick captures controller samples. The render pass owns all pose clocks and
# contacts, and applies them to the articulated figure only.
const Locomotion := preload("res://view/player_locomotion.gd")
const LIMB_NAMES := ["Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]
const POSE_KEYS := ["torso", "head", "arm_l", "arm_r", "leg_l", "leg_r"]  # same order
const ANIM_BLEND_TIME := 0.08    # s, pose blend constant (1 - e^(-dt/tau) toward target)
const POSE_EXTRAS := ["arm_spread", "elbow_l", "elbow_r", "twist", "body_y", "knee_l", "knee_r"]
const ANIM_RISE_TIME := 0.085   # s, body height catch-up to the sim feet (stairs)
const LAND_TIME := 0.30          # s, the touchdown knee-dip
## Field Dressing (DESIGN.md section 8, D-086): the controller's free-fall budget. It has no
## module for the upgrade dispatcher to call, so the app grants the budget itself at level
## start (controller apply_field_dressing). No content id is named here (test_boundaries.gd): the upgrade is
## found by its data signature - on_void_fall as its ONLY hook, no stat modifiers, and no
## content module of its own (a hook with a module is that module's job, not this grant).
const FREE_FALL_HOOK := "on_void_fall"
const ANIM_PHASE_IDLE := 1.6     # rad/s idle sway rate
var _limbs: Array = []           # LIMB_NAMES order -> limb nodes of player_model (or null)
var _limb_rest: Array[Vector3] = []
var _limb_mounts: Array[Vector3] = []
var _pose := {}                  # currently blended pose, _pose_run()'s shape
var _anim_phase := 0.0           # gait/sway phase (view-side clock, view-legal)
var _breath_phase := 0.0
var _leg_rig: Locomotion
var _anim_prev := {}
var _anim_next := {}
var _anim_ticks := 0
var _anim_remainder := 0.0
var _anim_height := INF
var _contact_weight := 0.0
var _climb_weight := 0.0
var _descent_weight := 0.0
var _fold_lift := 0.0            # u, hips raised for a high step (see _step_up)
var _rise_rate := 0.0            # u/s, low-passed vertical speed of the grounded samples
var _side_weight := 0.0
var _land_clock := -1.0          # s since touchdown while < LAND_TIME, else -1
var _was_airborne := false
var _feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _run_speed := 9.0            # data/player.json shared_kit.run_speed (read in build())

var _economy: RefCounted = null   # the gold-phase economy (purse / chain / upgrade stats)
# The run's stats, from core/content_api.gd apply_modifiers over the owned upgrade stacks
# and held curses: _stats_black is the always-on set, _stats_gold adds the `when:
# gold_phase` modifiers (Weighed Down) on top. The controller swaps between them on the
# gold-phase edges; the economy is built from _stats_gold, whose numbers ARE the gold phase.
var _stats_black: Dictionary = {}
var _stats_gold: Dictionary = {}
var _gold_began := false          # beacon open -> begin_gold_phase + rt.on_beacon_open fire once
var _completed_emitted := false   # level_completed fires once
var _run_over_emitted := false    # run_over fires once; a dead run stops ticking

var _hud_layer: CanvasLayer = null
var _mesh_instances: Array = []
var _prebuilt_views: Dictionary = {}   # eid -> Array of ready host nodes; the spawn tick pops them
var _warm_refs: Array = []   # billboard-path art pins; freed in teardown()
var _warm_pinned: Dictionary = {}   # eid -> true, one pin per id
var _level_number: int = 0
var _roster: Array = []          # [{id, name, count}] built from the resolved votes
var _bindings: Dictionary = {}
var _api: RefCounted = null
var _ledger: Dictionary = {}     # the run's carried state (class / votes / curses / purse)
var _gift_radar_range := UpgradesScript.GIFT_RADAR_RANGE   # this run's gift radar reach (40/80 u)
var _facing := -PI / 2.0         # the footprint map's drawn heading (persists at rest)
var _map_colours: Dictionary = {}     # the footprint map palette, resolved lazily, once per level
var _curses: RefCounted = null   # sim/curse_runtime.gd, built per level in build()
var _upgrades: RefCounted = null # sim/upgrade_runtime.gd, built per level in build()
var _boost_on := false           # an upgrade run-speed boost touched the controller last tick
# The tile-schedule curses (W10-C): a held module that declares step_on(state, key) arms
# a tile when the player's feet settle on it, and its on_tick returns tile_fell /
# tile_returned events that this file applies to w["removed"]. No content id is named:
# the modules are found by the step_on signature. _tile_step_keys is the set of tile keys
# the rule applies to (edge_lane_keys below: the outer lane of a walkway), computed once per level from the level's
# STATIC geometry; _tiles_dropped is the set of keys THIS applicator removed, so a return
# never restores a tile some other writer removed.
const TILE_STEP_QUERY := "step_on"
const TILE_FELL := "tile_fell"
const TILE_RETURNED := "tile_returned"
var _tile_step_mods: Array = []
var _tile_step_keys: Dictionary = {}
var _tiles_dropped: Dictionary = {}
# Platform collapse (sim/collapse.gd, D-B10-1): after the beacon opens the non-hub pieces fall
# zone by zone from the outside in (crack, fall 5 s later, 10 s gap, the next zone inward;
# numbers in data/collapse.json); the hub never does. platform_collapse is a
# setting (not reset by teardown) - false is the feature's negative control.
var platform_collapse := true
var _collapse: Dictionary = {}
var collapse_view: Node3D = null
var last_events: Array = []   # the last step's event list (read-only, for tests/probes)


func _ready() -> void:
	if _bindings.is_empty():
		_load_bindings()


func _load_bindings() -> void:
	_bindings = InputCaptureScript.load_bindings()
	if not (_bindings.get("errors", []) as Array).is_empty():
		push_warning("world: bindings unreadable, keyboard input disabled: %s"
				% str(_bindings["errors"]))


## Build the level. Returns false on generator/content failure; never crashes.
## p_ledger is the run's carried state from the last lobby (app.gd hands over
## view/lobby/lobby_scene.gd's ledger()). Empty = resolve the run by replaying the
## intermissions before this level, which is what the bot and the first level do.
func build(seed_value: int, level: int, p_ledger: Dictionary = {}) -> bool:
	teardown()
	if _bindings.is_empty():
		_load_bindings()
	# The run's own seeded plan for this level: replay the lobbies before it.
	_api = ContentApiScript.load()
	if _api == null or not _api.is_ok():
		push_warning("world: content registry failed to boot; cannot vote the level plan")
		teardown()
		return false
	var plan := _resolve_run(seed_value, level, p_ledger)
	if plan.is_empty():
		teardown()
		return false
	_ledger = plan.duplicate(true)

	# Gap 9 (FULL_GAME_PLAN.md): the collected votes land as extra tripmines on
	# the NEXT level. The count -> weight arithmetic (per-vote constant, vote
	# cap) is each roster module's own static (content/enemies/<entry>/enemy.gd,
	# DESIGN.md section 5.7); sim keeps the ledger only (sim/gifts.gd's
	# run_votes / run_votes_for, counts keyed by the lobby's own ids). App reads
	# both here and hands the sum to terrain's generate() as its extra_mines
	# argument (TERRAIN_SPEC section 6.8 clamps the applied count). Rows whose
	# module declares no extra_mines() weigh nothing, so a run that voted for
	# neither keeps the canon base roll (extra_mines 0).
	var plan_votes: Dictionary = plan.get("votes", {}) as Dictionary
	var extra_mines := 0
	for id in plan_votes.keys():
		var entry_id := str(id)
		var n := maxi(0, int(plan_votes.get(id, 0)))
		if n <= 0:
			continue
		var K = load("res://content/enemies/%s/enemy.gd" % entry_id)
		if K == null or not K.has_method("extra_mines"):
			continue
		extra_mines += maxi(0, int(K.call("extra_mines", n)))
	# A held curse's build-time mine query (total_extra_mines(state, roster_extra)) folds
	# the roster's number - the dispatcher probes the modules, no curse id is named here.
	extra_mines = CurseRuntimeScript.extra_mines(plan.get("curses", {}) as Dictionary,
			extra_mines, Callable(self, "_curse_module"))
	lv = VoidGenScript.generate(seed_value, level, 1, extra_mines)
	if lv.is_empty():
		push_warning("world: voidgen.generate(%d, %d) returned {}" % [seed_value, level])
		teardown()
		return false
	# The spawn is the level's own spawn tile (the collision default, spawns[0] - the same
	# assembly feel_probe.gd and perf_probe.gd use). The bot_run override {"dais": beacon}
	# plants the spawn inside the beacon monument, which encloses the 1.8 u figure and
	# buries the third-person view's subject.
	w = CollisionScript.make_world(lv["tiles"], lv["props"], lv["pads"])
	# The sim LevelState: one level's slice of the state tree (players + gifts + mines +
	# beacon). Built from the same Level dict; the run seed feeds the Defuse Kit roll.
	# The owned upgrades' sim roles ride in (D-T053-1): {} when none is owned, which keeps
	# lstate.upgrades null exactly as before for an un-upgraded run.
	lstate = LevelStateScript.build(lv, level, 1, seed_value,
			UpgradeRolesScript.roles_for(plan.get("stacks", {}) as Dictionary))
	_gift_radar_range = _gift_radar_range_for(plan.get("stacks", {}) as Dictionary)
	_facing = -PI / 2.0
	_map_colours = {}
	var kit := str(plan.get("class", ""))
	if kit == "":
		kit = FALLBACK_CLASS   # D-APPFLOW-6
	ctl = ControllerScript.new()
	ctl.setup(kit, ControllerScript.load_constants())
	ctl.place(w)

	# The run's owned upgrade stacks and held curses -> the closed stat list (DESIGN.md
	# section 12) through core/content_api.gd's apply_modifiers. This is the only place the
	# shipped game runs the modifier math, so a bought upgrade and a held curse change the
	# live run. Two contexts, because `when: gold_phase` is live only while the gold phase
	# is on: _stats_black is the always-on set, _stats_gold adds the gold-phase modifiers.
	var mods := _run_modifiers(plan, kit)
	var base: Dictionary = ctl.base_stats()
	_stats_black = ContentApiScript.apply_modifiers(base, mods, {"phase": "", "class": kit})
	_stats_gold = ContentApiScript.apply_modifiers(base, mods,
			{"phase": "gold_phase", "class": kit})
	ctl.apply_stats(_stats_black)
	# Field Dressing's per-level budget: once per level per owned stack (the shop lives in
	# the lobby, so level start is the only grant point - no mid-level purchase exists).
	ctl.apply_field_dressing(_free_fall_stacks(plan))
	# The stack knobs the controller exposes but cannot compute itself (it never reads a
	# ledger). Each owning upgrade's module declares them (static knobs(stacks, kit)), so this
	# file names no upgrade id - the boundary scan forbids a content id in app/ - and each
	# number stays next to the rule sentence that states it. A knob left at its default
	# reproduces the canon body exactly, so an un-upgraded run is byte-identical to before.
	var knobs := _upgrade_knobs(plan, kit)
	ctl.push_mul = float(knobs.get("push_mul", 1.0))
	ctl.coyote_add = float(knobs.get("coyote_add", 0.0))
	ctl.cooldown_mul = float(knobs.get("cooldown_mul", 1.0))
	ctl.feather_fall = bool(knobs.get("feather_fall", false))
	var glide_bonus := float(knobs.get("glide_energy_bonus", 0.0))
	ctl.glide_energy_bonus = glide_bonus
	if glide_bonus > 0.0:
		# The bonus is owned from the first frame of the level, not the first refill:
		# the refill math only lands on the next _glide_max() call, so the live pool is
		# raised here (minf() against base + bonus reproduces the refill math exactly).
		ctl.glide_energy = minf(ctl.glide_energy + glide_bonus,
				float(ctl.C.get("glide_energy", 3.0)) + glide_bonus)

	# The gold-phase economy: the gold phase's own stats (gold_value / chain_window /
	# chain_cap / overtime_period / stipend_flat), tuned by data/economy.json through the
	# content api. A stat no modifier touches keeps the data file's value.
	_economy = EconomyScript.create(_stats_gold, _api)
	# The purse the run carries in from the last lobby (whole gold -> centi).
	_economy.purse_centi = int(plan.get("purse", 0)) * EconomyScript.CENTI
	# The stack consumers the modules cannot self-apply (the economy and gifts and the
	# controller expose no ledger of their own). The world names no upgrade id: each
	# consumer is matched to the owned stacks by the registry row's signature
	# (_signature_stacks, the same idiom the free-fall budget uses).
	_apply_stack_consumers(plan)

	rt = EnemyRuntimeScript.new()
	rt.setup(lv, w, [ctl], seed_value, {})
	for id in (plan["votes"] as Dictionary).keys():
		var n := int(plan["votes"][id])
		if n <= 0:
			continue
		var eid := str(id)
		var entry: Dictionary = _api.enemy(eid)
		var beh = _behavior_for(eid)
		var cfg := _cfg_for(entry, eid, level, n, beh)
		if beh == null or cfg.is_empty():
			push_warning("world: enemy plan row unreadable: %s" % eid)
			teardown()
			return false
		rt.plan(eid, str(cfg.get("name", eid)), beh, cfg, n)
		_roster.append({"id": eid, "name": str(cfg.get("name", eid)), "count": n})

	# Level geometry. Built always (not only windowed, unlike the probe): this IS the
	# playable scene; the headless gate builds it too (test_mesh.gd meshes headless).
	# With the collapse on, the hub is meshed on its own and every collapse zone is meshed
	# as its own part under the collapse view (one drop root per zone); off, the level is
	# one build. The state rides on lstate so sim/state_hash.gd dumps it (COLLAPSE line).
	_collapse = CollapseScript.create(lv)
	_collapse["enabled"] = platform_collapse
	lstate.collapse = _collapse
	var mesher: Dictionary = MesherScript.build(lv, {},
			MesherScript.PART_HUB if platform_collapse else "")
	for mn in mesher["meshes"]:
		var mi := MeshInstance3D.new()
		mi.mesh = mesher["meshes"][mn]
		add_child(mi)
		_mesh_instances.append(mi)
	if platform_collapse:
		collapse_view = CollapseViewScript.new()
		add_child(collapse_view)
		var zone_meshes: Array = []
		for zi in CollapseScript.zone_count(_collapse):
			zone_meshes.append(MesherScript.build(lv, {}, MesherScript.PART_ZONE,
					_collapse["zones"][zi]["pieces"])["meshes"])
		collapse_view.setup(lv, zone_meshes, _collapse)
		_mesh_instances.append_array(collapse_view.mesh_instances())

	# Fog / environment for the level's biome (act table; 31+ cycles, D-T014c-1).
	fog = FogEnvScript.new()
	fog.configure(FogEnvScript.biome_id_for_level(level), level)
	add_child(fog)
	if atmosphere:   # D-ATMO-1/2: cloud dome + contour rocks, placed from (seed, level)
		var dome := SkyDomeScript.new()
		dome.configure()
		add_child(dome)
		var rocks := DebrisScript.new()
		rocks.configure(hash([seed_value, level]))
		add_child(rocks)

	# The void's own glow: one soft overhead light, shadows OFF (palette.json ambient's
	# "no sun, no directional shadows" still holds - this casts nothing). Without it the
	# only light was the near-black ambient plus the player's 18 u fill, so everything past
	# the player's feet rendered black and the slab detail could not be seen at all.
	var key := DirectionalLight3D.new()
	key.name = "VoidGlow"
	key.light_color = Color(str(FogEnvScript.load_palette().get("roles", {})
			.get("void_glow", {}).get("hex", "#8FE8E0")))
	key.light_energy = float(FogEnvScript.load_palette().get("roles", {})
			.get("void_glow", {}).get("energy", 0.55))
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-62.0, 34.0, 0.0)
	add_child(key)

	# Third-person camera rig (app/camera_rig.gd defaults - the "normal third-person" view).
	rig = CameraRigScript.new()   # the rig's defaults are its D-T082-1 values
	rig.yaw_deg = 0.0
	var cam := Camera3D.new()
	rig.add_child(cam)
	add_child(rig)
	# dt=1.0 snaps the height spring onto the feet (a dt=0 call is a documented no-op).
	rig.update_rig(Vector3(float(ctl.x), float(ctl.y), float(ctl.z)), 1.0)
	cam.fov = CameraRigScript.FOV_DEFAULT
	cam.current = true
	camera = cam

	# The player figure (T-015): feet on the controller's position, yawed to the motion.
	# Without it the third-person rig frames empty space and the game reads first-person.
	var ps: PackedScene = load(PLAYER_MODEL)
	if ps != null:
		player_model = ps.instantiate()
		_apply_player_body_material(player_model)
		player_model.position = Vector3(float(ctl.x), float(ctl.y), float(ctl.z))
		player_model.rotation.y = _player_yaw
		add_child(player_model)
		# The hang glider (owner request 2026-11-20): built once, parented to the figure so
		# it follows for free, hidden until ctl.gliding (glider_view.sync in _player_pass).
		glider_view = GliderViewScript.new()
		if glider_view.build():
			player_model.add_child(glider_view)
		else:
			glider_view.free()
			glider_view = null
	# The player fill light (palette.json roles.player_fill_light: omni #BFFFF8, range 18,
	# energy 1.2). Nothing ever created it, so ALBEDO rendered near-black and only the light
	# squares' emission showed - the reason the slabs read as untextured. Parented to the
	# figure so it follows the player; held 2.0 u behind the shoulder, because an omni parked
	# at the body's centre lights almost nothing (the falloff kills the close-range term).
	_player_light = OmniLight3D.new()
	var fill: Dictionary = FogEnvScript.load_palette().get("roles", {}).get("player_fill_light", {})
	_player_light.light_color = Color(str(fill.get("hex", "#BFFFF8")))
	_player_light.omni_range = float(fill.get("range", 18.0))
	_player_light.light_energy = float(fill.get("energy", 1.2))
	_player_light.position = Vector3(0.0, 1.3, 2.0)
	if player_model != null:
		player_model.add_child(_player_light)
	else:
		_player_light.position = Vector3(float(ctl.x), float(ctl.y) + 1.3, float(ctl.z) + 2.0)
		add_child(_player_light)

	# J5 mouse-lock: a level begins CAPTURED (hidden cursor; Ctrl releases/toggles). The
	# sensitivity comes from the settings store's clamped value (default 0.12 deg/px).
	# Headless (the tests and the bot) the mode set is a harmless no-op.
	var sett := SettingsScript.new()
	sett.load_from()
	_mouse_sens = sett.mouse_sensitivity
	_prev_mouse_toggle = false
	_prev_app_pause = false
	_mouse_locked = true
	Input.mouse_mode = CameraRigScript.mouse_mode_for(true)

	# J5 procedural pose: cache the limb nodes (part names from the .glb, see
	# assets_src/blender/player_figure.py) and the run speed the gait rate normalises to.
	_cache_player_limbs(player_model)
	_pose = {}
	_anim_phase = 0.0
	var pstats: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/player.json"))
	if pstats is Dictionary and (pstats as Dictionary).has("shared_kit"):
		_run_speed = float((pstats["shared_kit"] as Dictionary).get("run_speed", 9.0))

	# HUD (CanvasLayer: a Control child of a Node3D never reaches the canvas).
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)
	# thicc ben's screen blur sits UNDER the HUD (the wash is a lens on the world, the
	# counters stay readable). Stepped from step() on the sim clock, never _process.
	screen_blur = ScreenBlurScript.new()
	screen_blur.set_process(false)
	_hud_layer.add_child(screen_blur)
	hud = HudScript.new()
	_hud_layer.add_child(hud)
	_sync_hud()

	# The core-loop views, placed from the LevelState step() ticks: a black + a gold
	# model per REAL gift slot (the gold ones hidden until the flip), one mine per mine
	# slot, the beacon on its dais tile. Without them the run is played blind.
	gifts_view = GiftsViewScript.new()
	add_child(gifts_view)
	gifts_view.setup(lv, lstate.gifts)
	tripmine_view = TripmineViewScript.new()
	add_child(tripmine_view)
	tripmine_view.setup(lv, lstate.mines)
	beacon_view = BeaconViewScript.new()
	add_child(beacon_view)
	beacon_view.setup(lv)

	# The glitched floor, at the world origin: the sim's glitched entries carry
	# absolute tile coordinates, so this node must not move. Floor-only mode builds just the
	# decal layer - the body is already one of the boards above.
	toucher_floor = ToucherViewScript.new()
	add_child(toucher_floor)
	toucher_floor.setup(ToucherViewScript.SHEET_REL, ToucherViewScript.FOLDER_REL, true)

	# The enemy presentation layer, all at the world origin (every feed is in absolute
	# world coordinates): the generic telegraph view (rings / lines / patches + their
	# cues), Coil's bespoke landing ring + shockwave, the projectiles, the straggler beam
	# over the last 20% of REAL gifts, the diegetic danger text and the respawn view.
	telegraph_view = TelegraphViewScript.new()
	add_child(telegraph_view)
	coil_view = CoilTelegraphScript.new()
	add_child(coil_view)
	projectile_view = ProjectileViewScript.new()
	add_child(projectile_view)
	straggler_beam = StragglerBeamScript.new()
	add_child(straggler_beam)
	straggler_beam.setup(lstate.gifts)
	danger_text = DangerTextScript.new()
	danger_text.driven = true
	add_child(danger_text)
	respawn_view = RespawnViewScript.new()
	add_child(respawn_view)

	# Every other stat consumer (mines / gifts / enemy runtime / fog / fill light) takes the
	# same always-on dict the controller just did; _apply_phase_stats re-feeds them on both
	# gold-phase edges.
	_feed_run_stats(_stats_black)

	_level_number = level
	# The curse hooks: last, so every piece a module touches (the runtime's spawn delay,
	# the controller's kit numbers, the economy's purse) already holds its final build value
	# and nothing later in build() overwrites a curse's change.
	_curses = CurseRuntimeScript.new()
	_curses.setup(plan.get("curses", {}) as Dictionary, Callable(self, "_curse_module"), {
		"rt": rt, "players": [ctl], "economy": _economy, "beacon": lstate.beacon,
		"spawn_plan": _roster.duplicate(true), "enemy_factory": Callable(self, "_curse_enemy"),
		"seed": seed_value, "level": level, "tick": int(lstate.tick),
	})
	_curses.level_start(int(lstate.tick))
	# The mines ask the held curses for their blast radius, their chain targets and their
	# tell distance. Nothing handed them the dispatcher before, so those queries could never
	# be reached - the same gap this wave exists to close.
	lstate.mines.curses = _curses
	_tile_step_setup()
	# The upgrade hooks: the owned upgrades' modules, dispatched from this tick's event
	# list in step() (see _upgrade_module for the loader; no upgrade id is named here).
	_upgrades = UpgradeRuntimeScript.new()
	_upgrades.setup(plan.get("stacks", {}) as Dictionary, Callable(self, "_upgrade_module"), {
		"players": [ctl], "economy": _economy, "beacon": lstate.beacon,
		"level": level, "tick": int(lstate.tick),
	})
	_boost_on = false
	# The first spawn tick would otherwise pay two one-time costs inside a single 60 Hz
	# step: the enemy runtime's spawn round-trip set (built on first use, cached per
	# level) and the first bespoke enemy view build per roster id (frame textures via
	# ResourceLoader). Both are pure functions of the level dict and the roster plan,
	# so they are pre-paid here, before the first step is ever taken.
	if rt != null:
		rt._round_trip_cached()
	_prebuild_enemy_views()
	return true


## One sim tick plus the view pass. dt is the fixed 60 Hz step; headless callers drive it
## directly. The sim half mirrors tools/bot_run.gd's per-tick order exactly:
##   controller -> player-row sync -> lv.tick++ -> gifts -> mines -> beacon ->
##   (beacon open: rt.on_beacon_open + the gold phase) -> enemy runtime.
## Mines carry defuse stacks [0], but _feed_run_stats has applied the run's defuse_chance, which
## overrides the stacks argument (sim/mines.gd apply_stats); the last-light/respawn path
## rides ctl.step itself. The completion
## signal fires at the end of the tick that entered the beacon; the death signal fires at
## the end of the tick the player died on, and every later call is a no-op.
func step(dt: float) -> void:
	if ctl == null or rt == null or lstate == null:
		return
	if _run_over_emitted:
		return   # the run is over: a dead run never ticks again (DESIGN.md section 3)
	var a_in: Dictionary = _capture_input()
	_mouse_lock_pass(int(a_in.get("app", 0)))
	# The respawn safe-tile search reads w["hazards"] (controller.gd valid_safe_tile). Nothing
	# published that list before, so a void-fall could put the player back down inside a mine.
	# Built from the live mine set plus the runtime's LIVE telegraph rows - the same one-tick
	# staleness the w["enemies"] / w["projectiles"] mirrors already accept.
	w["hazards"] = LevelStateScript.hazard_footprints(lstate.mines, rt.live_telegraphs())
	_upgrade_speed_pass()
	var ev: Array = ctl.step(dt, a_in, w)
	# on_void_fall: one dispatch per void_fall event the controller reported this tick
	# (free falls included - the fall happened; what it costs is the module's call).
	if _curses != null:
		var falls: Array = []
		for e in ev:
			if str(e.get("e", "")) == "void_fall":
				falls.append(e)
		for e in falls:
			_curses.void_fall(int(lstate.tick), ev, e)
	# The LevelState's player row mirrors the controller (gifts/mines read lv.players).
	var p0: Dictionary = lstate.players[0]
	var prev_buttons := int(p0.get("prev_buttons", 0))
	p0["x"] = ctl.x
	p0["y"] = ctl.y
	p0["z"] = ctl.z
	p0["vx"] = ctl.vx
	p0["vy"] = ctl.vy
	p0["vz"] = ctl.vz
	p0["grounded"] = ctl.grounded
	p0["prev_buttons"] = int(a_in.get("buttons", 0))
	# The scripted-upgrade pass (footprint memory and the beacon channel). Runs in the
	# same slot sim.gd gives it - after the movement step, before the gifts read the
	# row - and unlike the sim path it must write a channel teleport back into the
	# controller, because the controller owns the position out here.
	if lstate.upgrades != null:
		var inp: RefCounted = InputScript.new(int(a_in.get("move_x", 0)),
				int(a_in.get("move_z", 0)), int(a_in.get("buttons", 0)))
		lstate.upgrades.step_player(lstate, 0, inp, prev_buttons, ev)
		for e in ev:
			if str(e.get("e", "")) == "beacon_teleport" and int(e.get("player", -1)) == 0:
				ctl.x = float(p0["x"])
				ctl.y = float(p0["y"])
				ctl.z = float(p0["z"])
				ctl.vx = 0.0
				ctl.vy = 0.0
				ctl.vz = 0.0
				ctl.grounded = true
				ctl.cur_key = "" # re-tracked on the next grounded tick
				ctl.sync_body()
				break
	lstate.tick += 1
	GiftsScript.tick(lstate, 0, ev)
	var minev: Array = []
	MinesScript.tick(lstate, [ctl], w, [0], lstate.tick, minev)
	for e in minev:
		ev.append(e)
	# The curse entry gate (a crowded dais, an unserved dwell): a refused player simply
	# does not enter this tick; the beacon stays open and the next tick asks again.
	if _curses == null or bool(_curses.entry_allowed(0)):
		lstate.beacon.try_enter(ctl, lstate.tick, 0, ev)
	if lstate.beacon.is_open() and not _gold_began:
		_gold_began = true
		rt.on_beacon_open()
		if _curses != null:
			_curses.beacon_open(int(lstate.tick), ev)
		if _economy != null:
			_economy.begin_gold_phase()
		_apply_phase_stats()   # `when: gold_phase` modifiers go live with the phase
		var cev: Dictionary = CollapseScript.start(_collapse, int(lstate.tick))
		if not cev.is_empty():
			ev.append(cev)
	# The collapse schedule: on each zone's fall tick its tiles leave collision (the next
	# zone inward cracks after the gap). A key it removes is
	# no longer this file's tile-schedule drop, so a later tile_returned cannot restore it.
	var fell: Array = CollapseScript.tick(_collapse, int(lstate.tick), w, ev)
	for ck in fell:
		_tiles_dropped.erase(ck)
	# ...and everything that was standing on those tiles goes with them.
	_collapse_sweep(fell)
	if _economy != null and bool(_economy.gold_phase):
		_economy.tick_gold(dt)
	for e in rt.step(dt):
		ev.append(e)
		# the cleanse wave is a view event, not an economy one: the decal layer plays the
		# 18-tick outward ring from the tile the player cleaned
		if toucher_floor != null and str(e.get("e", "")) == "glitched_cleanse":
			toucher_floor.on_cleanse(e)
	# on_tick runs AFTER rt.step: the modules read rows the behaviors already moved this
	# tick (a landing, a telegraph start, a teleport) instead of last tick's, and BEFORE
	# the economy and fx passes so a kill / drop / tier jump a curse makes is paid and drawn
	# on the same tick.
	if _curses != null:
		var ev0 := ev.size()
		_curses.tick(int(lstate.tick), ev)
		# The tile applicator: a fell / returned event a module raised THIS tick changes
		# collision now, so the next tick's controller and enemy moves see it.
		_apply_tile_events(ev, ev0)
		# A curse can raise the economy's overtime tier (the beacon-open tier jump), but the
		# enemy runtime keeps its own tier and that is the one that drives enemy speed and
		# cooldowns. Push the difference across, and only upward: the runtime's own clock
		# raises its tier independently, so a lower economy tier must never pull it back.
		if _economy != null and rt != null:
			var tier_gap: int = int(_economy.overtime_tier) - int(rt.overtime_tier)
			if tier_gap > 0:
				rt.add_overtime_tier(tier_gap)
	# The upgrade hooks, one pass over the whole tick's list (gift pickups, the beacon
	# entry, void falls, the mine ladder's defuse / shield): BEFORE the economy pass, so
	# interest a hook pays is on the purse the player carried in (the stipend is paid after)
	# and a chain_reset a hook saves is skipped by the economy on this same tick.
	if _upgrades != null:
		_upgrades.dispatch_events(int(lstate.tick), ev)
	_economy_pass(ev)
	last_events = ev
	_fx_events(ev)
	if rig != null:
		rig.update_rig(Vector3(float(ctl.x), float(ctl.y), float(ctl.z)), dt)
	_player_pass()
	_player_audio_pass()
	_billboard_pass(dt, ev)
	_view_pass()
	_sync_hud()
	# Death ends the run (DESIGN.md section 3). The row is sim/death.gd's own screen_data()
	# plus the charges held at death - the controller's death event carries the same pair.
	# Death is checked first: a dead player cannot enter the beacon (try_enter refuses a
	# dead controller), so the two signals never both fire on one tick.
	if not _run_over_emitted and bool(ctl.dead):
		_run_over_emitted = true
		_mouse_locked = false
		Input.mouse_mode = CameraRigScript.mouse_mode_for(false)   # death screen: release
		var purse := -1
		if _economy != null:
			purse = int(_economy.purse_centi)   # centi, the same integer the HUD shows
		var info: Dictionary = DeathScript.screen_data(ctl, _level_number, purse)
		info["charges"] = int(ctl.charges)
		WorldAudioScript.play_death(self)
		run_over.emit(info)
		return
	if not _completed_emitted and lstate.beacon != null and bool(lstate.beacon.completed):
		_completed_emitted = true
		WorldAudioScript.play_level_complete(self)
		level_completed.emit()


## Read sim -> economy mapping over this tick's event list (both event shapes: sim events
## key on "type", controller/mine/enemy raw dicts on "e"). Data-driven: no upgrade or
## curse id is named here. The chain_reset -> break reason map covers the two mine-ladder
## reasons (economy's whitelist calls that one reason "defused_or_shielded_tripmine");
## whatever else arrives is handed to break_chain verbatim, which refuses strings that are
## not on the canon whitelist (thicc ben's eject rides through unchanged).
func _economy_pass(ev: Array) -> void:
	if _economy == null:
		return
	for e in ev:
		var kind := str(e.get("e", e.get("type", "")))
		if kind == "gift_collected":
			if str(e.get("phase", "")) == "gold":
				_economy.collect_gold_gift(_final_band_now())
		elif kind == "chain_reset":
			if bool(e.get("saved", false)):
				continue   # an upgrade hook spent its chain save on this break
			var why := str(e.get("why", ""))
			if why == "defused_mine" or why == "shielded_mine":
				why = "defused_or_shielded_tripmine"
			_economy.break_chain(why)
		elif kind == "beacon_enter":
			_economy.enter_beacon(_level_number)
			_apply_phase_stats()   # the gold phase ended: the gold-phase modifiers come off


## The controller's stats follow the phase: a `when: gold_phase` modifier (Weighed Down)
## is live only while the gold phase is on. Called at build and on both phase edges.
func _apply_phase_stats() -> void:
	if ctl == null:
		return
	var gold := _economy != null and bool(_economy.gold_phase)
	var stats: Dictionary = _stats_gold if gold else _stats_black
	ctl.apply_stats(stats)
	_feed_run_stats(stats)


## An upgrade hook's run-speed boost (a gift-pickup sprint): the controller's run_speed
## multiplier becomes the phase stat x the boost for each controller step the boost covers,
## and goes back to the phase stat on the first step after it ends. A run with no boost
## running never has the multiplier touched here (it stays apply_stats' own value).
func _upgrade_speed_pass() -> void:
	if ctl == null or _upgrades == null:
		return
	var mul := float(_upgrades.speed_step())
	var boosting := not is_equal_approx(mul, 1.0)
	if not boosting and not _boost_on:
		return
	var gold := _economy != null and bool(_economy.gold_phase)
	var stats: Dictionary = _stats_gold if gold else _stats_black
	ctl.run_speed_mul = float(stats.get("run_speed", 1.0)) * mul
	_boost_on = boosting


## The controller knobs every owned upgrade module declares (static knobs(stacks, kit)).
## A module that declares none, or an upgrade with no module, contributes nothing - so an
## un-upgraded run reads every knob at its canon default. Later modules win on a shared key,
## which is the same last-writer rule the stat pipeline uses.
func _upgrade_knobs(plan: Dictionary, kit: String) -> Dictionary:
	var out := {}
	var stacks: Dictionary = plan.get("stacks", {})
	for id in stacks.keys():
		if int(stacks[id]) <= 0:
			continue
		var path := "res://content/upgrades/%s.gd" % str(id)
		if not ResourceLoader.exists(path):
			continue
		var mod: Script = load(path)
		if mod == null or not mod.has_method("knobs"):
			continue
		var d = mod.knobs(stacks, kit)
		if d is Dictionary:
			out.merge(d, true)
	return out


## The owned stacks of every upgrade carrying the free-fall signature (FREE_FALL_HOOK).
func _free_fall_stacks(plan: Dictionary) -> int:
	var total := 0
	var stacks: Dictionary = plan.get("stacks", {})
	for id in stacks.keys():
		var u: Dictionary = _api.upgrade(str(id))
		var hooks: Array = u.get("hooks", [])
		if hooks.size() != 1 or str(hooks[0]) != FREE_FALL_HOOK:
			continue
		if not (u.get("modifiers", []) as Array).is_empty():
			continue
		if ResourceLoader.exists("res://content/upgrades/%s.gd" % str(id)):
			continue
		total += maxi(0, int(stacks[id]))
	return total


## The stack consumers the app owes a call: the registry-row signature decides which
## owned stacks belong to which consumer (the world never names an upgrade id - the
## boundary scan forbids it here). Hooks must match exactly, modifiers must be empty,
## class_boost must be empty unless p_boost says otherwise ("*" = any), class_only must
## equal p_class_only ("" = empty), and a module file must exist iff p_module. A row
## that stopped matching would silently keep its consumer dark, so the wiring test
## covers every one of these through world.build()/world.step().
func _signature_stacks(plan: Dictionary, p_hooks: Array, p_boost: String,
		p_class_only: String, p_module: bool) -> int:
	var total := 0
	var stacks: Dictionary = plan.get("stacks", {})
	var want: Array = p_hooks.duplicate()
	want.sort()
	for id in stacks.keys():
		var n := maxi(0, int(stacks[id]))
		if n <= 0:
			continue
		var u: Dictionary = _api.upgrade(str(id))
		if u.is_empty():
			continue
		var hooks: Array = (u.get("hooks", []) as Array).duplicate()
		hooks.sort()
		if hooks != want:
			continue
		if not (u.get("modifiers", []) as Array).is_empty():
			continue
		var boost: Array = u.get("class_boost", [])
		if p_boost == "":
			if not boost.is_empty():
				continue
		elif p_boost != "*":
			if not boost.has(p_boost):
				continue
		var only: Variant = u.get("class_only")
		if str(only if only != null else "") != p_class_only:
			continue
		var has_module := ResourceLoader.exists("res://content/upgrades/%s.gd" % str(id))
		if has_module != p_module:
			continue
		total += n
	return total


## The build-time call sites for the stack consumers (see _signature_stacks). Every
## branch is unconditional on ownership - a run that owns nothing pays nothing and
## every consumer sees its canon default.
func _apply_stack_consumers(plan: Dictionary) -> void:
	if lstate != null and lstate.gifts != null:
		lstate.gifts.apply_straggler_band(_signature_stacks(plan, [], "", "", false))
	if ctl != null:
		ctl.apply_double_jump_stacks(_signature_stacks(plan, [], "athletic", "", false))
		if _signature_stacks(plan, [], "*", "dasher", true) > 0:
			ctl.apply_twin_dash()
		if _signature_stacks(plan, [], "*", "glider", true) > 0:
			ctl.apply_updraft()
	if _economy != null:
		_economy.apply_gift_yield(_signature_stacks(plan, ["on_gift_collected"], "", "", false))


## True when the gold gift about to be collected sits inside the final band: every
## stacked module declaring the band predicate is asked (the content layer owns the
## numbers; no id is named here). False with no such module owned or an empty band.
func _final_band_now() -> bool:
	if _economy == null:
		return false
	var total := 0
	if lstate != null and lstate.gifts != null:
		total = int(lstate.gifts.total_real)
	var collected := int(_economy.gold_gifts_collected)
	var stacks: Dictionary = _ledger.get("stacks", {})
	for id in stacks.keys():
		if int(stacks[id]) <= 0:
			continue
		var path := "res://content/upgrades/%s.gd" % str(id)
		if not ResourceLoader.exists(path):
			continue
		var mod: Script = load(path)
		if mod == null or not mod.has_method("is_final_band"):
			continue
		if bool(mod.call("is_final_band", collected, total)):
			return true
	return false


## The non-controller stat consumers, fed the same dict ctl.apply_stats takes:
##   lstate.mines  defuse_chance   (Defuse Kit; switches MinesScript.tick off its stacks arg)
##   lstate.gifts  pickup_radius   (Long Reach)
##   rt            enemy_speed_mul / telegraph_mul (Rush Hour, Early Warning / Hasty)
##   fog           fog_density     (Thick Fog; applied as the delta over the biome's base)
##   fill light    fill_light_range (Lights Out; op=set, so the stat IS the range - only a
##                 value off the canon base overrides the palette's own range)
## Consumer logic lives in each consumer; this is the call site only.
func _feed_run_stats(stats: Dictionary) -> void:
	if lstate != null:
		if lstate.mines != null:
			lstate.mines.apply_stats(stats)
		if lstate.gifts != null:
			lstate.gifts.apply_stats(stats)
	if rt != null:
		rt.apply_stats(stats)
	if fog != null:
		fog.apply_stats(stats)
	if _player_light != null and stats.has("fill_light_range"):
		var r := float(stats["fill_light_range"])
		if not is_equal_approx(r, float(StatsScript.DEFAULTS.get("fill_light_range", r))):
			_player_light.omni_range = maxf(0.0, r)


## Every modifier the run owns: each held curse's and each owned upgrade's modifiers,
## repeated once per stack (DESIGN.md sections 7 and 8), plus whatever a script upgrade's
## own module declares through static stat_mods(kit) (D-B5A-1) - so a script upgrade can add
## to a stat the same way a JSON modifier does. Data-driven - no content id is named here -
## and sorted by id so the `set`-wins tie-break in apply_modifiers is deterministic whatever
## order the ledger's dictionaries happen to hold.
func _run_modifiers(plan: Dictionary, kit: String) -> Array:
	var out: Array = []
	var curses: Dictionary = plan.get("curses", {})
	var curse_ids: Array = curses.keys()
	curse_ids.sort()
	for id in curse_ids:
		var c: Dictionary = _api.curse(str(id))
		out.append_array(ContentApiScript.mods_for_stacks(c.get("modifiers", []),
				int(curses[id])))
	var stacks: Dictionary = plan.get("stacks", {})
	var upgrade_ids: Array = stacks.keys()
	upgrade_ids.sort()
	for id in upgrade_ids:
		var u: Dictionary = _api.upgrade(str(id))
		out.append_array(ContentApiScript.mods_for_stacks(u.get("modifiers", []),
				int(stacks[id])))
		# A script upgrade may also declare a stat contribution of its own (D-B5A-1): its
		# module's static stat_mods(kit) returns ONE stack's modifier dicts, repeated here
		# per owned stack exactly like the JSON half above. The module names itself and
		# decides which classes it applies to; this file names no upgrade id.
		out.append_array(ContentApiScript.mods_for_stacks(_upgrade_stat_mods(str(id), kit),
				int(stacks[id])))
	return out


## One owned script upgrade's declared stat contribution (static stat_mods(kit)): the
## modifier dicts ONE stack makes, in the same shape a JSON "modifiers" row has. A module
## that declares none, or an upgrade with no module, contributes nothing - so an un-upgraded
## run's modifier list is exactly what it was before this existed.
func _upgrade_stat_mods(id: String, kit: String) -> Array:
	var path := "res://content/upgrades/%s.gd" % id
	if not ResourceLoader.exists(path):
		return []
	var mod: Script = load(path)
	if mod == null or not mod.has_method("stat_mods"):
		return []
	var d = mod.stat_mods(kit)
	if d is Array:
		return d
	return []


## True once the beacon has been entered (the level is complete). Convenience for
## callers that poll; the level_completed signal is the push channel.
func is_complete() -> bool:
	return lstate != null and lstate.beacon != null and bool(lstate.beacon.completed)


## Free everything build() created and reset the sim references. Safe to call twice; the
## app calls it before queue_free-ing the node.
func teardown() -> void:
	for child in get_children():
		child.free()
	_mesh_instances.clear()
	boards.clear()
	enemy_views.clear()
	_roster.clear()
	for eid in _prebuilt_views.keys():
		for host in _prebuilt_views[eid]:
			if is_instance_valid(host):
				host.free()
	_prebuilt_views.clear()
	_warm_pinned.clear()
	for wr in _warm_refs:
		if is_instance_valid(wr):
			wr.free()
	_warm_refs.clear()
	ctl = null
	rt = null
	rig = null
	camera = null
	fog = null
	hud = null
	_hud_layer = null
	gifts_view = null
	tripmine_view = null
	beacon_view = null
	collapse_view = null
	_collapse = {}
	last_events = []
	toucher_floor = null
	telegraph_view = null
	coil_view = null
	projectile_view = null
	straggler_beam = null
	danger_text = null
	screen_blur = null
	respawn_view = null
	player_model = null
	glider_view = null   # freed with player_model
	_player_light = null
	_player_yaw = 0.0
	# the glide bed is a long-lived player: stop it with the level it belongs to
	PlayerAudioScript.stop_glide(_glide_player)
	_glide_player = null
	_step_clock = STEP_PERIOD
	_step_variant = 0
	_row_anim_state.clear()
	# J5: back to the menu = release the mouse, drop the pose/lock state.
	_mouse_locked = false
	_prev_mouse_toggle = false
	_prev_app_pause = false
	Input.mouse_mode = CameraRigScript.mouse_mode_for(false)
	_limbs = []
	_limb_rest.clear()
	_limb_mounts.clear()
	_pose = {}
	_anim_phase = 0.0
	lstate = null
	if _curses != null:
		_curses.clear()   # drops the modules and their per-level curse_st scratch
	_curses = null
	if _upgrades != null:
		_upgrades.clear()   # drops the modules, the per-level upgrade_st and any boost
	_upgrades = null
	_boost_on = false
	_tile_step_mods = []
	_tile_step_keys = {}
	_tiles_dropped = {}
	_economy = null
	_stats_black = {}
	_stats_gold = {}
	_gold_began = false
	_completed_emitted = false
	_run_over_emitted = false
	lv = {}
	w = {}
	_level_number = 0
	_ledger = {}
	_gift_radar_range = UpgradesScript.GIFT_RADAR_RANGE
	_facing = -PI / 2.0
	_map_colours = {}


func level_number() -> int:
	return _level_number


## The curse dispatcher's module loader: a curse's script module, or null for a curse that
## is declarative only (its modifiers already ran in _run_modifiers).
func _curse_module(id: String) -> Variant:
	var path := "res://content/curses/%s.gd" % id
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## The upgrade dispatcher's module loader: an upgrade's script module, or null for a
## declarative upgrade (its modifiers already ran in _run_modifiers). Static so the lobby
## (view/lobby/lobby_scene.gd) can hand the same loader to UpgradeRuntime.curse_draw().
static func upgrade_module(id: String) -> Variant:
	var path := "res://content/upgrades/%s.gd" % id
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## The shop's max-stacks bonus, aggregated from the owned modules at call time: every
## stacked module declaring the bonus predicate contributes its dict (the pairing lives
## in content; this file names no upgrade id). Static so the lobby and the pre-run
## resolve can aggregate the same way this file's replay does.
static func max_stacks_bonus_for(stacks: Dictionary, p_class: String) -> Dictionary:
	var out := {}
	for id in stacks.keys():
		if int(stacks[id]) <= 0:
			continue
		var path := "res://content/upgrades/%s.gd" % str(id)
		if not ResourceLoader.exists(path):
			continue
		var mod: Script = load(path)
		if mod == null or not mod.has_method("max_bonus"):
			continue
		var d = mod.call("max_bonus", p_class, stacks)
		if d is Dictionary:
			for k in d:
				out[str(k)] = int(out.get(k, 0)) + int(d[k])
	return out


func _upgrade_module(id: String) -> Variant:
	return upgrade_module(id)


## Tile-schedule curses (W10-C): find every held module declaring step_on, compute the
## level's walkway-edge set once, and subscribe to the controller's tile-step hook. With no such
## module held nothing is subscribed - the un-cursed run pays nothing.
func _tile_step_setup() -> void:
	_tile_step_mods = []
	_tile_step_keys = {}
	_tiles_dropped = {}
	if _curses == null or ctl == null:
		return
	for m in _curses.modules:
		if (m["argc"] as Dictionary).has(TILE_STEP_QUERY):
			_tile_step_mods.append(m["mod"])
	if _tile_step_mods.is_empty():
		return
	tile_step_rescan()
	ctl.tile_step_hook = Callable(self, "_on_tile_step")


## Recompute the walkway-edge set from w's static geometry. build() calls it once; a caller that
## edits the level's geometry after build (a test fixture) calls it again.
func tile_step_rescan() -> void:
	_tile_step_keys = edge_lane_keys(w) if not w.is_empty() else {}


## The walkway-edge predicate ("1-wide walkway tiles fall ...", the curse's rule).
## DECISION (lead, W10, DECISIONS.md): "1-wide walkway tiles" is read as THE OUTER LANE OF
## A WALKWAY. voidgen tags no piece as 1-wide and GEN_VERSION 4 (owner override, J1)
## builds every walkway WALK_W = 3 cells wide, so the literal reading matched zero tiles in
## every shipped level and the brutal curse could never fire. The edge reading keeps the
## owner's geometry, keeps the rule's intent (the ground a player would fall off crumbles
## underfoot) and makes the counter-play ("keep moving; they regrow") true. The rule:
##   A neighbour column is FLOOR when it holds a prop, or a tile whose top is within
##   SIDE_BAND_HU (4 HU = 2.0 u) of this tile's - a ledge, a stair tread or a wall the
##   player stands beside. Anything farther is open void.
##   A tile (not under a prop) is an EDGE when, along one axis, one neighbour is void and
##   the opposite one is floor - the outer lane, with ground on its inner side.
##   A true 1-wide strip (void on BOTH sides along one axis, floor along the other) still
##   qualifies: it is edge on both sides, and the literal reading must never be narrower
##   than the reinterpretation.
##   An isolated pad (void on all four sides) never qualifies: a stepping stone, not a
##   walkway edge.
## Why void and not walkable-connectivity: reading "walkable" as the 1 HU auto-step makes
## every 2 HU stair tread look like an edge; the side test asks whether there is any ground
## beside the tile at all.
## Static geometry only (w["cols"] / w["prop_cols"]; w["removed"] is ignored), so a fallen
## tile never turns its neighbours into edges. Returns {tile key "x,z,y_hu": true}.
const SIDE_BAND_HU := 4


static func edge_lane_keys(wd: Dictionary) -> Dictionary:
	var out := {}
	var cols: Dictionary = wd.get("cols", {})
	var props: Dictionary = wd.get("prop_cols", {})
	for ck in cols.keys():
		if props.has(ck):
			continue
		var parts: PackedStringArray = str(ck).split(",")
		var x := int(parts[0])
		var z := int(parts[1])
		for t in cols[ck]:
			var y := int(t["y"])
			var px := _floor_beside(cols, props, x + 1, z, y)
			var nx := _floor_beside(cols, props, x - 1, z, y)
			var pz := _floor_beside(cols, props, x, z + 1, y)
			var nz := _floor_beside(cols, props, x, z - 1, y)
			var edge := (px != nx) or (pz != nz)
			var strip := (not pz and not nz and (px or nx)) or (not px and not nx and (pz or nz))
			if edge or strip:
				out[CollisionScript.tile_key(x, z, y)] = true
	return out


static func _floor_beside(cols: Dictionary, props: Dictionary, x: int, z: int, y: int) -> bool:
	var k := "%d,%d" % [x, z]
	if props.has(k):
		return true
	for t in cols.get(k, []):
		if absi(int(t["y"]) - y) <= SIDE_BAND_HU:
			return true
	return false


## The controller's tile-step hook: a walkway-edge tile the feet just settled on is armed in
## every held tile-schedule module. The module reads the clock from state["tick"], set
## here to the LevelState tick this controller step runs on.
func _on_tile_step(key: String) -> void:
	if _curses == null or not _tile_step_keys.has(key):
		return
	_curses.state["tick"] = int(lstate.tick) if lstate != null else 0
	for mod in _tile_step_mods:
		mod.call(TILE_STEP_QUERY, _curses.state, key)


## Everything that was standing on a tile the collapse just removed goes with it. The
## collapse itself (sim/collapse.gd) only edits collision; this is the one place that knows
## what was resting on those tiles, because it is the one place that holds the gift state,
## the mine state and the enemy runtime at the same time.
##   gift    - lost (gifts.lose): gone with the platform, never collected, never paid, never
##             rendered. Safe for the quota: the collapse starts on the beacon-open tick, so
##             the black quota is already met and no gift loss can make a level unwinnable.
##   tripmine- dropped (mines.drop): the same bitset a defused mine uses, so the view hides
##             it and contact_at can never return it - it cannot kill from the void.
##   enemy   - NOT handled here: enemy_runtime's own support rule (resting_key/_support_pass)
##             makes a body whose tile left collision fall, and retires it past the kill
##             plane. It runs inside rt.step, so it also covers a tile a curse removes.
## The player is deliberately untouched: a body left without support drops through the
## controller's own kill plane and the existing void-fall rule runs (sim/controller.gd).
func _collapse_sweep(keys: Array) -> void:
	if keys.is_empty() or lstate == null:
		return
	var gone := {}
	for k in keys:
		gone[str(k)] = true
	if lstate.gifts != null:
		var g: RefCounted = lstate.gifts
		for i in g.slots.size():
			if not g.present(i):
				continue
			var s: Dictionary = g.slots[i]
			if gone.has(CollisionScript.tile_key(int(s["x"]), int(s["z"]), int(s["y"]))):
				g.lose(i)
	if lstate.mines != null:
		var m: RefCounted = lstate.mines
		for slot_id in m.ids:
			if m.is_consumed(slot_id):
				continue
			var s: Dictionary = m.slots[slot_id]
			if gone.has(CollisionScript.tile_key(int(s["x"]), int(s["z"]), int(s["y"]))):
				m.drop(slot_id)


## Apply the tile events raised at index >= from: fell erases the tile from collision
## (into w["removed"]), returned restores it - only a tile this applicator dropped.
func _apply_tile_events(ev: Array, from: int) -> void:
	if w.is_empty():
		return
	for k in range(from, ev.size()):
		var e: Variant = ev[k]
		if not (e is Dictionary):
			continue
		var kind := str((e as Dictionary).get("e", ""))
		var key := str((e as Dictionary).get("key", ""))
		if key == "":
			continue
		if kind == TILE_FELL:
			if not w["removed"].has(key):
				w["removed"][key] = true
				_tiles_dropped[key] = true
		elif kind == TILE_RETURNED:
			if _tiles_dropped.has(key):
				_tiles_dropped.erase(key)
				w["removed"].erase(key)


## The curse dispatcher's enemy factory (api.spawn_enemy): the same behavior + cfg
## construction the level plan uses, scaled for this level and the id's own vote count
## (1 when the id was not voted - a curse may add an enemy the run never voted for).
func _curse_enemy(id: String) -> Dictionary:
	if _api == null:
		return {}
	var entry: Dictionary = _api.enemy(id)
	var beh = _behavior_for(id)
	if entry.is_empty() or beh == null:
		return {}
	var n := maxi(1, int((_ledger.get("votes", {}) as Dictionary).get(id, 1)))
	var cfg := _cfg_for(entry, id, _level_number, n, beh)
	if cfg.is_empty():
		return {}
	return {"behavior": beh, "cfg": cfg, "name": str(cfg.get("name", id))}


# ---- the run's own seeded plan (replay the lobbies before this level) -----------------------

## Resolve the intermissions the run would have seen (level_completed 0..level-1) with the
## sim's own Intermission state machine, seeded exactly the way tools/bot_run.gd seeds its
## bot: lobby n from mix(seed, 5000 + n), pick stream mix(mix(seed, 0xB07), n + 1), uniform
## random among the unresolved mandatory bays (CLASS / E / C), U and REST untouched, an
## empty mandatory C draw tithe-passed when affordable. Returns
## {"class": String, "votes": Dictionary, "curses": Dictionary, "stacks": Dictionary,
##  "purse": int, "tithes": int, "hunger": int, "last_vote": String} or {} on failure.
##
## A CARRIED ledger (p_ledger, the app's own lobby picks) IS the run's state and is
## returned as-is: replaying the lobbies again would overwrite the player's votes with the
## bot's. The replay stays the only source for a run the player has not voted in yet.
func _resolve_run(seed_value: int, level: int, p_ledger: Dictionary = {}) -> Dictionary:
	if not p_ledger.is_empty() and p_ledger.has("votes"):
		return {
			"class": str(p_ledger.get("class", "")),
			"votes": (p_ledger.get("votes", {}) as Dictionary).duplicate(),
			"curses": (p_ledger.get("curses", {}) as Dictionary).duplicate(),
			"stacks": (p_ledger.get("stacks", {}) as Dictionary).duplicate(),
			"purse": int(p_ledger.get("purse", 0)),
			"tithes": int(p_ledger.get("tithes", 0)),
			"hunger": int(p_ledger.get("hunger", 0)),
			"last_vote": str(p_ledger.get("last_vote", "")),
		}
	var votes := {}
	var curses := {}
	var stacks := {}
	var purse := 0
	var tithes := 0
	var hunger := 0
	var last_vote := ""
	var class_chosen := ""
	for completed in range(0, level):
		var lb: RefCounted = IntermissionScript.create(_api, completed, purse,
				VoidRngScript.mix(seed_value, 5000 + completed), votes, curses, stacks,
				class_chosen, tithes, hunger, last_vote, {},
				max_stacks_bonus_for(stacks, class_chosen))
		var rng: RefCounted = VoidRngScript.new(VoidRngScript.mix(
				VoidRngScript.mix(seed_value, 0xB07), completed + 1))
		for _i in range(80):
			if bool(lb.gate_open()):
				break
			# on_curse_draw over the curse bays as drawn (or redrawn): idempotent per bay,
			# so asking every pass is exact; with no hook module owned it is a no-op.
			UpgradeRuntimeScript.curse_draw(lb.bays, lb.upgrade_stacks,
					Callable(self, "_upgrade_module"), completed)
			var table: Array = lb.altar_table()
			var picks: Array[int] = []
			var tithe_picks: Array[int] = []
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
					tithe_picks.append(i)
			var ev: Array = []
			if not picks.is_empty():
				lb.apply_select(0, picks[rng.urange(picks.size())], ev)
			elif not tithe_picks.is_empty():
				if not bool(lb.apply_select(0, tithe_picks[0], ev)):
					break
			else:
				break
		if not bool(lb.gate_open()):
			push_warning("world: lobby %d did not resolve its mandatory bays" % completed)
			return {}
		votes = lb.votes
		curses = lb.curses_held
		stacks = lb.upgrade_stacks
		purse = int(lb.purse)
		tithes = int(lb.tithes)
		hunger = int(lb.hunger)
		last_vote = str(lb.last_vote)
		class_chosen = str(lb.class_chosen)
	return {"class": class_chosen, "votes": votes, "curses": curses, "stacks": stacks,
			"purse": purse, "tithes": tithes, "hunger": hunger, "last_vote": last_vote}


## The run's carried state after this level: what the lobby needs (view/lobby/lobby_scene.gd
## build()) and what the next level's build() takes. The purse is the economy's live
## whole-gold balance, so gold earned in the gold phase reaches the shop.
func run_ledger() -> Dictionary:
	var out := _ledger.duplicate(true)
	if _economy != null:
		out["purse"] = int(_economy.purse_gold())
	# The run's always-on stats, so the lobby prices its shop (shop_price_mul) and lights
	# its hall (fill_light_range) from the world-computed dict. _resolve_run ignores the key
	# on the way back in: the next build recomputes the stats from curses + stacks.
	out["stats"] = _stats_black.duplicate()
	return out


# Per-id behavior construction, content-derived: the enemy module's factory shape is
# probed in a fixed order (no content id is named here):
#   1. a module-level behavior() / new_behavior() static factory;
#   2. an inner class whose name ends in "Behavior" (each module declares exactly one);
#   3. the module script itself as the behavior.
func _behavior_for(id: String):
	var K = load("res://content/enemies/%s/enemy.gd" % id)
	if K == null:
		return null
	if K.has_method("behavior"):
		return K.behavior()
	if K.has_method("new_behavior"):
		return K.new_behavior()
	var inner := _behavior_inner(K)
	if inner != null:
		return inner.new()
	return K.new()   # the file-as-behavior module


## The module's inner behavior class: a script constant whose value is a Script whose
## name ends in "Behavior". Deterministic (lowest name) when several qualify; null when none.
static func _behavior_inner(K: Script) -> GDScript:
	var cmap: Dictionary = K.get_script_constant_map()
	var names: Array[String] = []
	for cname in cmap:
		var v: Variant = cmap[cname]
		if v is GDScript and str(cname).to_lower().ends_with("behavior"):
			names.append(str(cname))
	names.sort()
	if names.is_empty():
		return null
	return cmap[names[0]] as GDScript


## The runtime cfg for one planned enemy: the enemy.json stats block with the top-level
## contact_kill / preferred_kind / arbiter keys the runtime reads, stamped with name /
## votes / level_number (bot_run.gd's shape). A behavior module that wants its raw stats
## nested under a cfg key declares that key as a `cfg_stats` constant on its script; the
## nesting follows the declaration, never an id match.
func _cfg_for(entry: Dictionary, id: String, level: int, votes: int, beh = null) -> Dictionary:
	if entry.is_empty():
		return {}
	var stats: Dictionary = (entry.get("stats", {}) as Dictionary).duplicate(true)
	for key in ["contact_kill", "preferred_kind", "arbiter"]:
		if entry.has(key) and not stats.has(key):
			stats[key] = entry[key]
	stats["id"] = id
	stats["name"] = str(entry.get("name", id))
	stats["votes"] = votes
	stats["level_number"] = level
	if beh != null:
		var bscript: Script = beh.get_script()
		if bscript != null:
			var cmap: Dictionary = bscript.get_script_constant_map()
			var key := str(cmap.get("cfg_stats", ""))
			if key != "":
				stats[key] = (entry.get("stats", {}) as Dictionary).duplicate(true)
	return stats


# ---- per-frame view passes ------------------------------------------------------------------

## Keyboard/gamepad -> PlayerInput, pre-rotated by the camera yaw and quantized to int8
## (D-T010-2), through the real app/input_capture.gd path against data/bindings.json.
func _capture_input():
	var kb: Dictionary = _bindings.get("key_bindings", {})
	var keys: Array = []
	var seen := {}
	for action in kb.keys():
		for code in kb[action]:
			var c := int(code)
			if seen.has(c):
				continue
			seen[c] = true
			if Input.is_key_pressed(c):
				keys.append(c)
	var joy: Array = []
	var jb: Dictionary = _bindings.get("joy_bindings", {})
	var stick_x := 0.0
	var stick_y := 0.0
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var device: int = int(pads[0])
		for action in jb.keys():
			var idx := int(jb[action])
			if Input.is_joy_button_pressed(device, idx):
				joy.append(idx)
		stick_x = Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		stick_y = Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	var yaw := 0.0
	if rig != null:
		yaw = float(rig.yaw_deg)
	var res: Dictionary = InputCaptureScript.capture(keys, joy, stick_x, stick_y, yaw, _bindings,
			Input.is_key_pressed(InputCaptureScript.KEY_MOUSE_LOCK))
	var pi: RefCounted = res["input"]
	# PlayerInput -> the Dictionary the controller reads (buttons/move_x/move_z/aim_*).
	# Aim follows the move stick/keys (no separate aim device exists yet).
	# The APP_* flags ride along (the controller ignores unknown keys); world.step()
	# edge-detects them for the mouse-lock toggle and the pause release.
	var mx := int(pi.move_x)
	var mz := int(pi.move_z)
	var aim_x := 0.0
	var aim_z := 1.0
	if mx != 0 or mz != 0:
		var l := sqrt(float(mx * mx + mz * mz))
		aim_x = float(mx) / l
		aim_z = float(mz) / l
	return {"move_x": mx, "move_z": mz, "buttons": int(pi.buttons),
			"aim_x": aim_x, "aim_z": aim_z,
			"app": int(res.get("app", 0))}


## The mouse-capture state machine (J5): Ctrl toggles, the APP_PAUSE edge and the death /
## menu latches force a release. a_flags is this tick's APP_* bitmask from capture().
## All four transitions live here: build() captures, teardown() releases (menu), the death
## latch below releases (death screen), and this pass handles pause + Ctrl.
func _mouse_lock_pass(a_flags: int) -> void:
	var toggled := (a_flags & InputCaptureScript.APP_MOUSE_TOGGLE) != 0
	var paused := (a_flags & InputCaptureScript.APP_PAUSE) != 0
	_mouse_locked = CameraRigScript.next_mouse_locked(
			_mouse_locked, toggled and not _prev_mouse_toggle,
			paused and not _prev_app_pause)
	_prev_mouse_toggle = toggled
	_prev_app_pause = paused
	Input.mouse_mode = CameraRigScript.mouse_mode_for(_mouse_locked)


## Apply the current lock state to the engine. This is the ONLY Input.mouse_mode write in
## app/ (test_input.gd enforces the single-writer rule): the pause overlay releases and
## restores the mouse by setting _mouse_locked and calling this, never by writing the mode
## itself. A frozen state does not step, so _mouse_lock_pass cannot run while paused.
func apply_mouse_mode() -> void:
	Input.mouse_mode = CameraRigScript.mouse_mode_for(_mouse_locked)


## Mouse motion -> the rig (J5). The ONLY mouse path in app/: nothing runs unless the
## mouse is captured; released, this returns after the first check and the camera never
## turns. The toggle itself is NOT an event path - Ctrl is polled per tick in
## _capture_input / _mouse_lock_pass, so the toggle remains the only capture transition.
func _unhandled_input(event: InputEvent) -> void:
	if not _mouse_locked or rig == null:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var np := CameraRigScript.apply_mouse(rig.yaw_deg, rig.pitch_deg,
				float(mm.relative.x), float(mm.relative.y), _mouse_sens)
		rig.yaw_deg = (np as Vector2).x
		rig.pitch_deg = (np as Vector2).y


## The player figure pass: stand at the controller's feet, then animate.
func _player_pass() -> void:
	if player_model == null:
		return
	player_model.position = Vector3(float(ctl.x), float(ctl.y), float(ctl.z))
	_player_yaw = deg_to_rad(float(rig.yaw_deg)) if rig != null else 0.0
	player_model.rotation.y = _player_yaw
	_anim_pass()
	if glider_view != null:
		# velocity in the figure's frame (x right, y up, z back): the bank reads x, the pitch y
		var v_local := Vector3(float(ctl.vx), float(ctl.vy), float(ctl.vz)).rotated(
				Vector3.UP, -_player_yaw)
		glider_view.sync(bool(ctl.gliding), v_local)


## The player's own cues, once per sim tick: the glide bed follows ctl.gliding (started on
## the engage edge, stopped when the glide ends) and a footstep lands every STEP_PERIOD
## while the player is grounded and actually moving. Read-only on the controller; the step
## clock is tick-driven, so the cadence is identical on every run of the same seed.
func _player_audio_pass() -> void:
	if ctl == null:
		return
	if bool(ctl.gliding):
		if _glide_player == null:
			_glide_player = PlayerAudioScript.start_glide(self)
	elif _glide_player != null:
		PlayerAudioScript.stop_glide(_glide_player)
		_glide_player = null
	var speed := sqrt(float(ctl.vx) * float(ctl.vx) + float(ctl.vz) * float(ctl.vz))
	if bool(ctl.grounded) and speed > STEP_MIN_SPEED:
		_step_clock += DT
		if _step_clock >= STEP_PERIOD:
			_step_clock = 0.0
			PlayerAudioScript.play_footstep(self, _step_variant)
			_step_variant += 1
	else:
		_step_clock = STEP_PERIOD   # the next step lands on the first moving tick


## The figure's yaw follows the captured camera's forward (D-T082-4's character/camera
## coupling kept; the MOUSE-LOOK part of D-T082-4 is superseded by J5, see the header of
## this file and camera_rig.gd): the character always faces away from the viewer and strafes instead
## of rotating to face its velocity. The camera now turns - through world.gd's
## _unhandled_input, which applies deltas only while the mouse is captured.
##
## Why the camera does not instead trail the character's facing (unchanged since D-T082-4):
## input_capture.capture() rotates the stick by the rig yaw, so a camera that chases the
## facing closes a feedback loop (yaw -> input -> velocity -> facing -> yaw). Locking the
## character's yaw to the camera's is the stable reading of the request.


## The player figure's base pass (J11): the T-015 .glb carries no material by design
## (export_materials="NONE"; the palette rides the vertex colours), so without a base
## override every surface renders Godot's default WHITE and the authored palette is never
## seen (the J11 defect - the fill light made the white figure visible, which is why it
## went unnoticed). Unshaded with vertex colours as albedo, the exact base pass
## gifts_view.gd uses for the gifts: this world has no sun and a teal ambient that renders
## a LIT vertex-colour body near-black (J3/J8 measured), and the palette intent is the
## authored hex, not a lighting result. A surface override material does not touch the
## limb nodes' transforms, so the J5 pose layer is unaffected.
static func _player_body_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 1.0, 1.0)
	return m


## Adds the base material to every mesh surface under the figure (the glb carries no
## material of its own - see _player_body_material).
static func _apply_player_body_material(p_root: Node3D) -> void:
	var mat := _player_body_material()
	var stack: Array = [p_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, mat)


## Pose values are local pitch in radians, except head roll and the optional extras.
## The base run pose sets the lean. The articulated gait derives counter-swing and
## hip and knee angles from the foot contacts.
static func _pose_run(phase: float, amp: float) -> Dictionary:
	var swing := sin(phase) * 0.9 * amp
	var counter := -swing * 0.85
	return {
		"torso": -0.28 * amp,
		"head": 0.0,
		"arm_l": counter * (1.0 - 0.4 * (1.0 - amp)),
		"arm_r": -counter * (1.0 - 0.4 * (1.0 - amp)),
		"leg_l": swing,
		"leg_r": -swing,
	}


## Idle: a slow phase-driven sway, the head drifting a little, arms loose at the sides.
static func _pose_idle(phase: float) -> Dictionary:
	return {
		"torso": -0.02 + sin(phase) * 0.014,
		"head": sin(phase) * 0.023,
		"arm_l": sin(phase) * 0.035,
		"arm_r": -sin(phase) * 0.035,
		"leg_l": 0.0,
		"leg_r": 0.0,
		"body_y": -0.03 + sin(phase) * 0.006,
	}


## Jump (rising): both legs tucked back, arms swung back-up, torso leaning into the rise.
static func _pose_jump() -> Dictionary:
	return {
		"torso": -0.22,
		"head": 0.0,
		"arm_l": 0.95,
		"arm_r": 0.95,
		"leg_l": 0.65,
		"leg_r": 0.65,
		"knee_l": 1.35,
		"knee_r": 1.35,
	}


## Fall (sinking): flail - arms up over the head, legs trailing, one knee higher.
static func _pose_fall() -> Dictionary:
	return {
		"torso": 0.10,
		"head": 0.0,
		"arm_l": 2.55,
		"arm_r": 2.35,
		"leg_l": -0.20,
		"leg_r": 0.30,
		"knee_l": 0.85,
		"knee_r": 1.20,
	}


static func _pose_dash() -> Dictionary:
	return {"torso": -0.67, "head": 0.0, "arm_l": -1.25, "arm_r": -1.25,
			"leg_l": -0.45, "leg_r": 0.60, "knee_l": 0.35, "knee_r": 1.25}


static func _pose_glide() -> Dictionary:
	return {"torso": -0.36, "head": 0.0, "arm_l": -0.38, "arm_r": -0.38,
			"leg_l": -0.28, "leg_r": -0.10, "arm_spread": 1.20, "knee_l": 0.35, "knee_r": 0.75}


## Capture one sample per fixed tick. Detached tools can still drive the view manually.
func _anim_pass() -> void:
	if _limbs.is_empty() or ctl == null:
		return
	_anim_prev = _anim_next
	_anim_next = _anim_sample()
	if _anim_prev.is_empty():
		_anim_prev = _anim_next
	var movement: Vector3 = _anim_next.position - _anim_prev.position
	if movement.length() > maxf(0.8, (_anim_next.velocity as Vector3).length() * DT * 2.0):
		_anim_prev = _anim_next
		_anim_height = INF
		_leg_rig.reset_contacts()
	if is_inside_tree():
		_anim_ticks += 1
	else:
		_render_animation(DT, 1.0)


func _anim_sample() -> Dictionary:
	return {
		"position": Vector3(ctl.x, ctl.y, ctl.z),
		"velocity": Vector3(ctl.vx, ctl.vy, ctl.vz),
		"grounded": bool(ctl.grounded),
		"dash": ctl.dash_ticks > 0,
		"glide": bool(ctl.gliding),
		"yaw": _player_yaw,
	}


func _process(delta: float) -> void:
	if player_model == null or ctl == null or _run_over_emitted:
		return
	# App owns pause and drops its fixed-step remainder on a five-tick catch-up.
	if get_parent().get("_paused") == true:
		_anim_remainder = 0.0
		_anim_ticks = 0
		return
	_anim_remainder = 0.0 if _anim_ticks >= 5 else clampf(
			_anim_remainder + delta - _anim_ticks * DT, 0.0, DT)
	_anim_ticks = 0
	_render_animation(delta, _anim_remainder / DT)


func _render_animation(delta: float, alpha: float) -> void:
	if _anim_next.is_empty():
		_anim_next = _anim_sample()
		_anim_prev = _anim_next
	var root_pos := (_anim_prev.position as Vector3).lerp(_anim_next.position, alpha)
	var velocity := (_anim_prev.velocity as Vector3).lerp(_anim_next.velocity, alpha)
	var dash: bool = _anim_next.dash
	var glide: bool = _anim_next.glide
	var on_ground: bool = _anim_next.grounded and not dash and not glide
	if _anim_height == INF:
		_anim_height = root_pos.y
	# Spread the vertical displacement of a stair riser over several render frames.
	# Soles remain in world space while the body catches up to the new tread.
	# (A 0.5 u riser over ~0.09 s: fast enough to read as a step, slow enough that the hips
	# never yank the legs through a big angle in one frame.)
	# Feed the sim's own vertical speed forward, so a steady climb up a ramp has no lag
	# (only the discrete stair snaps are smoothed).
	# The controller snaps its feet onto slopes and treads (vy stays 0 on the ground), so
	# the climb rate is read from the ground itself: the rise across one unit of course
	# centred on the body, times the ground speed. A ramp and a flight of 1 HU stairs both
	# give a steady rate, which is fed forward so the hips climb WITH the feet instead of
	# lagging a whole step below them (only an isolated step is smoothed).
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var climb_rate := 0.0
	if on_ground and flat.length() > Locomotion.MIN_SPEED:
		var dir := flat.normalized()
		var ahead := Locomotion.tile_height(w, root_pos + dir * 0.5, root_pos.y + 0.55)
		var behind := Locomotion.tile_height(w, root_pos - dir * 0.5, root_pos.y + 0.05)
		if ahead != -INF and behind != -INF:
			climb_rate = clampf(ahead - behind, -0.6, 0.6) * flat.length()
	_rise_rate = lerpf(_rise_rate, climb_rate, 1.0 - exp(-delta / 0.10))
	var feed := _rise_rate * ANIM_RISE_TIME if on_ground else 0.0
	_anim_height = lerpf(_anim_height, root_pos.y + feed, 1.0 - exp(-delta / ANIM_RISE_TIME))
	if not on_ground and not _anim_prev.grounded:
		_anim_height = move_toward(_anim_height, root_pos.y, absf(velocity.y) * delta)
	player_model.position = Vector3(root_pos.x, _anim_height, root_pos.z)
	player_model.rotation.y = lerp_angle(_anim_prev.yaw, _anim_next.yaw, alpha)
	var k := 1.0 - exp(-delta / ANIM_BLEND_TIME)
	var contact := 1.0 if on_ground else 0.0
	_contact_weight = contact if _pose.is_empty() else lerpf(_contact_weight, contact, k)
	if absf(_contact_weight - contact) < 0.001:
		_contact_weight = contact

	if on_ground and _was_airborne:
		_land_clock = 0.0
	elif _land_clock >= 0.0:
		_land_clock = _land_clock + delta if on_ground and _land_clock < LAND_TIME else -1.0
	_was_airborne = not on_ground
	var target: Dictionary
	if dash:
		target = _pose_dash()
	elif glide:
		target = _pose_glide()
	elif not on_ground:
		target = _pose_jump() if velocity.y >= -0.4 else _pose_fall()
	else:
		target = _pose_locomotion(root_pos, velocity, delta, k)
	if not on_ground:
		_leg_rig.reset_contacts()
	if _pose.is_empty():
		k = 1.0
	elif _contact_weight == 1.0:
		k = 1.0 - exp(-delta / 0.025)
	for key in POSE_KEYS + POSE_EXTRAS:
		_pose[key] = lerpf(float(_pose.get(key, 0.0)), float(target.get(key, 0.0)), k)
	if _contact_weight == 1.0:
		_pose["body_y"] = target.body_y
	_apply_pose()


## Ground locomotion. The figure keeps its facing (the camera yaw); the feet step along the
## ACTUAL horizontal velocity, so backpedalling and strafing step backward/sideways with
## the knees still forward. Speed sets cadence and stride (walk -> run blend), the torso
## leans into forward running only, and the bob peaks at mid-stance.
func _pose_locomotion(root_pos: Vector3, velocity: Vector3, delta: float, blend: float) -> Dictionary:
	velocity.y = 0.0
	var speed := velocity.length()
	var moving := smoothstep(Locomotion.MIN_SPEED, 1.0, speed)
	var direction := velocity.normalized()
	var yaw := player_model.rotation.y
	var local_dir := direction.rotated(Vector3.UP, -yaw)   # -z ahead, +x right
	# Grounded here, so the sim's vy is the slope, not a jump: grade() reads the ground only.
	var rise := Locomotion.grade(w, root_pos, direction, 0.0)
	_climb_weight = lerpf(_climb_weight, rise, blend)
	_descent_weight = lerpf(_descent_weight, Locomotion.descent(w, root_pos, direction), blend)
	_side_weight = lerpf(_side_weight, absf(local_dir.x) if speed >= Locomotion.MIN_SPEED else 0.0, blend)
	var gait := Locomotion.profile(speed, _run_speed, _climb_weight, _side_weight, _descent_weight)
	if speed < Locomotion.MIN_SPEED:
		gait.x = 0.0
		velocity = Vector3.ZERO
		_anim_phase = 0.0            # a start always lifts the right foot first
	_anim_phase = fposmod(_anim_phase + gait.x * TAU * delta, TAU)
	_breath_phase = fposmod(_breath_phase + ANIM_PHASE_IDLE * delta, TAU)
	var target := _pose_idle(_breath_phase)
	var run_pose := _pose_run(_anim_phase, gait.z)
	var ahead := clampf(-local_dir.z, -0.35, 1.0) if speed >= Locomotion.MIN_SPEED else 0.0
	target["torso"] = lerpf(target.torso, (float(run_pose.torso) - 0.06) * ahead
			- 0.04 * _climb_weight + 0.05 * _descent_weight, moving)
	target["twist"] = sin(_anim_phase) * lerpf(0.11, 0.19, gait.z) * moving * (1.0 - 0.7 * _side_weight)
	target["head"] = float(target.head) * (1.0 - moving)
	if _leg_rig.boots.size() != 2:
		return target
	# Knees turn a little toward a sideways step (never past POLE_YAW, never backward).
	var pole := clampf(-local_dir.x, -1.0, 1.0) * Locomotion.POLE_YAW * moving
	_leg_rig.pole_yaw = lerpf(_leg_rig.pole_yaw, pole, blend)
	var forward := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var bob := 0.0
	var fold_lift := 0.0
	var lift := float(_pose.get("body_y", target.body_y))
	for side in 2:
		var phase := fposmod(_anim_phase / TAU + side * 0.5, 1.0)
		var hip_local := _limb_rest[side + 4] + _limb_mounts[side + 4]
		var rest := Locomotion.neutral(side, root_pos, yaw, hip_local, _side_weight)
		var hip := player_model.position + (hip_local + Vector3.UP * (Locomotion.HIP_RISE + lift)).rotated(
				Vector3.UP, yaw)
		var sole: Vector3 = _leg_rig.place_foot(side, rest, velocity, phase, gait, _climb_weight,
				yaw, w, delta, hip, root_pos, _descent_weight)
		_feet[side] = (sole - player_model.position).rotated(Vector3.UP, -yaw)
		if _leg_rig.stance[side]:
			# A planted sole the lagging hips have caught up on (a fresh tread): the body
			# rises so the knee never folds past its limit onto that tread.
			fold_lift = maxf(fold_lift, Locomotion.fold_height(sole, hip))
		else:
			# A swinging sole headed for a tread near hip height: the body steps up with
			# it, so the thigh never comes up past level into the chest.
			fold_lift = maxf(fold_lift, _leg_rig.swing_floor(side) + Locomotion.SOLE_HEIGHT
					+ Locomotion.SWING_DROP - hip.y)
		var key := "arm_l" if side == 0 else "arm_r"
		var travel := (sole - rest).dot(forward)
		var counter := clampf(-travel / 0.34, -1.0, 1.0) * lerpf(0.30, 0.79, gait.z)
		target[key] = lerpf(float(target[key]), counter, moving)
		target["elbow_l" if side == 0 else "elbow_r"] = 0.10 + moving * (
				lerpf(0.12, 0.42, gait.z) + 0.16 * maxf(0.0, counter))
		if phase < gait.y:
			bob = maxf(bob, pow(sin(PI * phase / gait.y), 2.0))
	bob *= lerpf(0.024, 0.064, gait.z) * (1.0 - 0.90 * _climb_weight)
	# Slopes and stairs: the hips sit lower so both soles stay inside the leg's reach.
	var crouch := (0.10 * _climb_weight + 0.06 * _descent_weight) * moving
	# A run sits lower than a walk: the hips drop with the run blend so the bob's peak
	# (mid-stance, sole under the hip) still leaves the stance leg inside its reach.
	target["body_y"] = lerpf(float(target.body_y), -0.065 - 0.05 * gait.z + bob, moving) 			- crouch - _land_dip() + _step_up(fold_lift, delta)
	return target


## The body's step-up: follows a demanded rise at a bounded rate, settles back slowly.
func _step_up(demand: float, delta: float) -> float:
	if demand > _fold_lift:
		_fold_lift = minf(demand, _fold_lift + 5.0 * delta)
	else:
		_fold_lift = lerpf(_fold_lift, demand, 1.0 - exp(-delta / 0.12))
	return _fold_lift


## The touchdown dip: the hips sink and recover over LAND_TIME (knees bend, the IK keeps
## the soles planted).
func _land_dip() -> float:
	if _land_clock < 0.0:
		return 0.0
	return 0.11 * sin(PI * clampf(_land_clock / LAND_TIME, 0.0, 1.0))


func _cache_player_limbs(figure: Node3D) -> void:
	_limbs.clear()
	_limb_rest.clear()
	_limb_mounts.clear()
	_anim_prev.clear()
	_anim_next.clear()
	_anim_ticks = 0
	_anim_remainder = 0.0
	_anim_height = INF
	_climb_weight = 0.0
	_descent_weight = 0.0
	_rise_rate = 0.0
	_fold_lift = 0.0
	_side_weight = 0.0
	_land_clock = -1.0
	_was_airborne = false
	_contact_weight = 0.0
	_breath_phase = 0.0
	for i in LIMB_NAMES.size():
		var node := figure.find_child(LIMB_NAMES[i], true, false) as MeshInstance3D if figure != null else null
		_limbs.append(node)
		_limb_rest.append(node.position if node != null else Vector3.ZERO)
		var mount := Vector3.ZERO
		if node != null and i != 1:
			var bounds := node.get_aabb()
			mount = bounds.get_center()
			mount.y = bounds.position.y if i == 0 else bounds.end.y
		_limb_mounts.append(mount)
	_leg_rig = Locomotion.new()
	_leg_rig.build(_limbs, _limb_mounts)


func _apply_pose() -> void:
	var body := Basis.from_euler(Vector3(_pose.torso, _pose.twist, 0.0))
	var waist := _limb_rest[0] + _limb_mounts[0]
	var offset := Vector3.UP * float(_pose.body_y)
	# The floor under the figure, in its own frame: an airborne/dash leg pose never
	# swings a boot through the ground the body is skimming.
	var ground := -INF
	if w != null and player_model != null:
		var under := Locomotion.tile_height(w, player_model.position, player_model.position.y + 0.3)
		if under != -INF:
			ground = under - player_model.position.y
	for i in LIMB_NAMES.size():
		var node = _limbs[i]
		if node == null or not _pose.has(POSE_KEYS[i]):
			continue
		var angle := float(_pose[POSE_KEYS[i]])
		var rotation := Basis(Vector3.RIGHT, angle)
		if i == 1:
			# Keep the gaze steady as the neck is carried by the chest.
			var stabilize := _contact_weight * 0.87
			rotation = body.inverse().slerp(Basis.IDENTITY, 1.0 - stabilize) * Basis(Vector3.BACK, angle)
		elif i == 2 or i == 3:
			var spread := float(_pose.get("arm_spread", 0.0))
			rotation = Basis.from_euler(Vector3(angle, 0.0, -spread if i == 2 else spread))
		# Carry the upper body with the torso and keep the visible mesh mounts
		# together as the compact figure moves around its imported rest origins.
		var mount := _limb_mounts[i]
		var joint := _limb_rest[i] + mount
		if i > 0 and i < 4:
			joint = waist + body * (joint - waist)
			rotation = body * rotation
		elif i == 0:
			rotation = body
		elif _leg_rig.shins.size() == 2:
			joint.y += Locomotion.HIP_RISE
		joint += offset
		node.transform = Transform3D(rotation, joint - rotation * mount)
		if (i == 2 or i == 3) and _leg_rig.forearms.size() == 2:
			var bend: float = _pose.elbow_l if i == 2 else _pose.elbow_r
			_leg_rig.pose_arm(i - 2, node, mount, bend)
		elif i >= 4 and _leg_rig.shins.size() == 2:
			_leg_rig.pose_leg(i - 4, node, joint, mount, _feet[i - 4],
					player_model.rotation.y, _contact_weight, angle,
					float(_pose.get("knee_l" if i == 4 else "knee_r", 0.0)), ground)


## The enemy body pass: every live runtime row gets ONE body - its bespoke view host when
## its id has one (and the switch is on), else the generic billboard. A new row is the
## spawn: rows are append-only and a row appears on its enemy_spawn tick, so the host's
## on_spawn fires right at creation. Then this tick's telegraph / screen_blur events are
## routed to the row that raised them (the host decides which copy owns an event), and
## every host is stepped once. No content id is named here.
func _billboard_pass(dt: float, ev: Array = []) -> void:
	# outside the tree, global transforms error: the rig is a direct child of this node and
	# this node is its own world, so the local position carries the same information
	var cam_pos: Vector3 = rig.global_position if (rig != null and rig.is_inside_tree()) \
			else (rig.position if rig != null else Vector3.ZERO)
	while boards.size() < rt.enemies.size():
		var row: Dictionary = rt.enemies[boards.size()]
		var host = _make_enemy_view(row)
		enemy_views.append(host)
		boards.append(null if host != null else _make_board(row))
		if host != null:
			host.on_spawn()
	var feet := Vector3(float(ctl.x), float(ctl.y), float(ctl.z)) if ctl != null \
			else Vector3.ZERO
	for e in ev:
		var idx: int = EnemyViewHostScript.route(rt.enemies, e, feet)
		if idx >= 0 and idx < enemy_views.size() and enemy_views[idx] != null:
			enemy_views[idx].on_event(e, rt.enemies[idx])
	var ctx := {
		"dt": dt, "cam": cam_pos,
		"player": {"x": feet.x, "y": feet.y, "z": feet.z},
		"curses": _curses.state if _curses != null else {},
	}
	for i in rt.enemies.size():
		var e: Dictionary = rt.enemies[i]
		# A body that fell with its platform (sim/enemy_runtime.gd _support_pass) is drawn
		# while it falls and hidden once it is past the kill plane. The row stays in
		# rt.enemies so every index here keeps pointing at it, but nothing should keep
		# animating 40 u below the level.
		var gone: bool = bool(e.get("gone", false))
		if not gone:
			_state_cue_pass(i, e)
		if enemy_views[i] != null:
			enemy_views[i].set_shown(not gone)
			if not gone:
				enemy_views[i].sync(e, ctx)
		var bd = boards[i]
		if bd == null:
			continue
		bd.visible = not gone
		if gone:
			continue
		bd.position = Vector3(float(e["x"]), float(e["y"]), float(e["z"]))
		bd.set_animation(str(e.get("anim_state", "")))
		bd.advance_animation(dt)
		bd.face_camera(cam_pos)


## The state-edge cues: a row entering an anim_state that carries a cue (view/audio/
## enemy_cue.gd's table) plays it once, on the edge.
## Read-only on the row; the last state per index is view state, never sim state.
func _state_cue_pass(i: int, e: Dictionary) -> void:
	var state := str(e.get("anim_state", ""))
	if str(_row_anim_state.get(i, "")) == state:
		return
	_row_anim_state[i] = state
	EnemyCueScript.play_state(self, str(e.get("id", "")), state,
			Vector3(float(e.get("x", 0.0)), float(e.get("y", 0.0)), float(e.get("z", 0.0))))


## The row's bespoke view host, added as a child of this node, or null (no bespoke view
## for the id, the switch is off, or the view failed to build - the billboard then draws).
func _make_enemy_view(e: Dictionary):
	var eid := str(e.get("id", ""))
	if not bespoke_enemy_views or not EnemyViewHostScript.supports(eid):
		return null
	# built at build time (see _prebuild_enemy_views); pop one ready host
	var stack: Array = _prebuilt_views.get(eid, [])
	if not stack.is_empty():
		var prebuilt = stack.pop_back()
		add_child(prebuilt)
		return prebuilt
	var host = EnemyViewHostScript.new()
	add_child(host)
	if not host.setup(eid, "res://content/enemies/%s" % eid):
		push_warning("world: bespoke view for %s failed to build; billboard used" % eid)
		host.free()
		return null
	return host


func _make_board(e: Dictionary):
	var folder := "res://content/enemies/%s" % str(e["id"])
	var doc: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(folder + "/sprites.json"))
	if not (doc is Dictionary):
		push_warning("world: sprites.json unreadable for %s; billboard skipped" % str(e["id"]))
		return null
	var bd = BillboardScript.new()
	bd.setup_from_sheet(doc, folder)
	add_child(bd)
	return bd


## Build-time pre-build: the whole enemy plan spawns on one tick (the spawn delay), and
## building each bespoke view there cost ~150 ms inside one 60 Hz step. The roster is the
## whole plan, known now, so build the hosts here instead - one per planned copy - and
## _make_enemy_view pops them off this stack when the rows appear. Unused pops and leftovers
## are freed in teardown(). Ids with no bespoke view take the billboard path instead: one
## pin per id here keeps their frame art in the loader's (weak) cache, so the real board
## build on the spawn tick is cache hits. Pure presentation; the sim never sees any of this.
func _prebuild_enemy_views() -> void:
	for r in _roster:
		var eid := str(r.get("id", ""))
		var copies := int(r.get("count", 0))
		if eid == "" or copies <= 0:
			continue
		var folder := "res://content/enemies/%s" % eid
		if bespoke_enemy_views and EnemyViewHostScript.supports(eid):
			if not _prebuilt_views.has(eid):
				_prebuilt_views[eid] = []
			var stack: Array = _prebuilt_views[eid]
			for i in copies:
				var host = EnemyViewHostScript.new()
				if host.setup(eid, folder):
					stack.append(host)
				else:
					push_warning("world: build-time view pre-build failed for %s; spawn tick will build it" % eid)
					host.free()
			continue
		if _warm_pinned.get(eid, false):
			continue
		_warm_pinned[eid] = true
		var doc: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(folder + "/sprites.json"))
		if doc is Dictionary:
			var bd = BillboardScript.new()
			bd.setup_from_sheet(doc, folder)
			_warm_refs.append(bd)


## The core-loop view pass: the three views read the same LevelState step() ticks, so
## what the player sees is what the sim holds - the black gifts go out one by one (gold
## models at the same slots once the phase flips), a consumed mine leaves, and the beacon
## column ramps from the tick it opened on.
func _view_pass() -> void:
	if lstate == null:
		return
	# The removed-tile set (collision.gd's w["removed"]) is fed to both slot views before
	# they sync: a gift or a mine standing on a tile a tile-schedule curse just removed
	# renders hidden for the 5 s the hole lasts and comes back with the tile (D-B7-1).
	# View-side only - the sim state is untouched, so the gift stays collectible and the
	# mine stays live. The collapse path needs nothing from this: a gift that fell with its
	# platform is `lost` and a mine is `consumed`, so both are already hidden.
	var removed: Dictionary = w["removed"] if not w.is_empty() else {}
	if gifts_view != null:
		gifts_view.set_removed(removed)
		gifts_view.sync(lstate.gifts)
	if tripmine_view != null and lstate.mines != null:
		tripmine_view.set_removed(removed)
		# the view owns no clock: sim seconds in, one turn per TURN_PERIOD (4 s)
		tripmine_view.set_time(float(lstate.tick) * DT)
		tripmine_view.sync(_eye_pos())
	if beacon_view != null and lstate.beacon != null:
		beacon_view.sync_from(lstate.beacon, lstate.gifts, lstate.tick)
	if toucher_floor != null and rt != null:
		toucher_floor.sync_floor_rows(rt.enemies)
	if collapse_view != null:
		collapse_view.sync(_collapse, int(lstate.tick))
	_fx_pass()


## The step's event list -> the one-shot presentation: every new telegraph's cue and the
## sim's own audio events (telegraph_view), Coil's landing shockwave, the danger line at
## each spawn, thicc ben's blur and the respawn reappear. Read only; nothing is fed back.
func _fx_events(ev: Array) -> void:
	if telegraph_view != null:
		telegraph_view.on_events(ev)
	for e in ev:
		var kind := str(e.get("e", e.get("type", "")))
		match kind:
			"land":
				PlayerAudioScript.play_land(self)
			"dash_start":
				PlayerAudioScript.play_dash(self)
			"gift_collected":
				# the slot id picks the variant, so a chain of gifts never repeats one
				WorldAudioScript.play_gift_pickup(self, int(e.get("slot", 0)))
			"platforms_cracked":
				WorldAudioScript.play_collapse_crack(self)
			"platforms_fell":
				WorldAudioScript.play_collapse_fall(self)
			"coil_land":
				if coil_view != null:
					coil_view.impact(Vector3(float(e.get("x", 0.0)), float(e.get("y", 0.0)),
							float(e.get("z", 0.0))))
			"enemy_spawn":
				if danger_text != null:
					danger_text.on_enemy_spawn(e)
			"screen_blur":
				# the eject's blur is the ejected player's own (player index 0 is this client)
				if screen_blur != null and int(e.get("player", 0)) == 0:
					screen_blur.trigger(int(e.get("ticks", ScreenBlurScript.TOTAL_TICKS_DEFAULT)))
			"void_fall":
				# Field Dressing's free fall: the HUD's pip flash (no charge was spent).
				# A paid fall flashes the screen edge in the void colour - screen_fx's
				# contract is "once per spend", so the free fall keeps only its pip flash.
				if hud != null:
					if bool(e.get("free", false)):
						if hud.void_pips != null:
							hud.void_pips.pip_free_fall()
					elif hud.screen_fx != null:
						hud.screen_fx.void_flash()
			"last_light_save":
				# controller.try_kill's save: the full-screen white bloom and the Last
				# Light icon's shatter on the pips row (T-086)
				if hud != null:
					if hud.screen_fx != null:
						hud.screen_fx.white_bloom()
					if hud.void_pips != null:
						hud.void_pips.last_light_trigger()
			"respawn":
				if respawn_view != null and ctl != null:
					respawn_view.on_respawn(lstate.tick if lstate != null else 0,
							Vector3(float(ctl.x), float(ctl.y), float(ctl.z)))


## The per-tick presentation sync: live telegraphs, projectiles, the straggler beam, the
## danger text clock, the blur clock and the invulnerability rim + blink.
func _fx_pass() -> void:
	if rt == null or ctl == null:
		return
	var feet := Vector3(float(ctl.x), float(ctl.y), float(ctl.z))
	var live: Array = rt.live_telegraphs()
	if telegraph_view != null:
		telegraph_view.sync(live, int(rt.tick), feet.y, feet + Vector3(0.0, 0.9, 0.0))
	if coil_view != null:
		coil_view.sync(live, 1)
	if projectile_view != null:
		projectile_view.sync(ProjectileViewScript.gather(rt))
	if straggler_beam != null and lstate != null:
		straggler_beam.sync(lstate.gifts)
	if danger_text != null:
		danger_text.advance(DT)
	if screen_blur != null:
		screen_blur.advance(1.0)
	if respawn_view != null and lstate != null:
		var left := int(ceil(maxf(float(ctl.invuln), 0.0) * 60.0))
		respawn_view.sync_tick(lstate.tick, left, feet)
		# the player model's own 8 Hz blink while the respawn invulnerability runs
		if player_model != null:
			var rtick: int = int(respawn_view.respawn_tick())
			if left > 0 and rtick >= 0:
				player_model.visible = RespawnViewScript.blink_on(float(lstate.tick - rtick))
			else:
				player_model.visible = true


## The eye the distance-driven view ramps measure from: the rig IS the camera holder, so
## its position is the camera. Local, not global - the mine roots the tripmine view syncs
## are positioned in this node's own space, and the distance must not mix the two spaces.
func _eye_pos() -> Vector3:
	if rig == null:
		return Vector3.ZERO
	return rig.position


## The gift radar's reach for this run, resolved opaquely: iterate the ledger's stacks
## and keep scripts whose declared role is the gift-radar role, so no upgrade id is
## named here. 1 stack within the engine's base range, 2 stacks the wider one.
func _gift_radar_range_for(stacks: Dictionary) -> float:
	var best := 0
	for id in stacks.keys():
		var p := "res://content/upgrades/%s.gd" % str(id)
		if not ResourceLoader.exists(p):
			continue
		var K = load(p)
		if K == null:
			continue
		if str(K.get("ROLE")) == UpgradesScript.ROLE_GIFT_RADAR:
			best = maxi(best, int(stacks[id]))
	if best >= 2:
		return UpgradesScript.GIFT_RADAR_RANGE_AT_2
	return UpgradesScript.GIFT_RADAR_RANGE


## The radar arrows' entry list: one row per target source this run owns a radar for,
## from the engine's own queries. Angles are world-space atan2(dz, dx) straight onto
## the screen (+x right, +z down) - the widget's documented contract. Empty when no
## radar role is owned (the map is not built, nothing is drawn, nothing is paid).
func _radar_entries() -> Array:
	var out: Array = []
	if not radar_feed:
		return out
	if lstate == null or ctl == null:
		return out
	var upg = lstate.upgrades
	if upg == null:
		return out
	var px := float(ctl.x)
	var pz := float(ctl.z)
	if bool(upg.has(UpgradesScript.ROLE_MINE_RADAR)) and lstate.mines != null:
		for slot in UpgradesScript.mine_outline_ids(lstate.mines, px, pz):
			var c: Vector3 = lstate.mines.point(slot)
			out.append(_radar_row(c.x - px, c.z - pz))
	if bool(upg.has(UpgradesScript.ROLE_GIFT_RADAR)) and lstate.gifts != null:
		var gift: Dictionary = UpgradesScript.nearest_real_gift(lstate, px, pz, _gift_radar_range)
		if not gift.is_empty():
			out.append(_radar_row(float(gift["x"]) - px, float(gift["z"]) - pz))
	if bool(upg.has(UpgradesScript.ROLE_THREAT_RADAR)):
		for marker in UpgradesScript.threat_markers(w.get("enemies", []), px, pz):
			out.append(_radar_row(float(marker["x"]) - px, float(marker["z"]) - pz))
	if bool(upg.has(UpgradesScript.ROLE_BEACON_COMPASS)):
		var b: Dictionary = UpgradesScript.beacon_compass(lstate, px, pz)
		if not b.is_empty():
			out.append(_radar_row(float(b["dx"]), float(b["dz"])))
	return out


static func _radar_row(dx: float, dz: float) -> Dictionary:
	return {"angle": atan2(dz, dx), "dist": sqrt(dx * dx + dz * dz)}


## The footprint map's snapshot field. A run not owning the footprint role gets {}
## (the map stays hidden and free); otherwise this tick's tile is noted before the
## widget reveals, so the map sees the current position too. Colours ride the current
## biome's resolved palette, cached here once per level (the map itself draws plain
## Colors and loads no content).
func _footprint_feed() -> Dictionary:
	if not radar_feed:
		return {}
	if lstate == null or ctl == null:
		return {}
	var upg = lstate.upgrades
	if upg == null or not bool(upg.has(UpgradesScript.ROLE_CARTOGRAPHER)):
		return {}
	var px := float(ctl.x)
	var pz := float(ctl.z)
	upg.note_footprint(0, px, pz)
	var vx := float(ctl.vx)
	var vz := float(ctl.vz)
	if vx * vx + vz * vz > 0.01:
		_facing = atan2(vz, vx)
	if _map_colours.is_empty():
		_map_colours = _resolve_map_colours()
	return {"visible": true, "lv": lstate, "p_index": 0, "scale_px": 2.75,
			"colours": _map_colours, "facing": _facing}


func _resolve_map_colours() -> Dictionary:
	var pal: Dictionary = FogEnvScript.resolve_palette(
			FogEnvScript.biome_id_for_level(_level_number), _level_number)
	var roles: Dictionary = pal.get("roles", {})
	return {
		"platform": _role_hex(roles, "platform_light", "#2FB7B0"),
		"walkway": _role_hex(roles, "walkway_light", "#3A74FF"),
		"gift": _role_hex(roles, "black_gift_rim", "#7CFFF4"),
		"mine": _role_hex(roles, "tripmine_particles", "#FF4FD8"),
		"beacon": _role_hex(roles, "beacon_open", "#E8FFFF"),
	}


static func _role_hex(roles: Dictionary, role: String, fallback: String) -> Color:
	var entry = roles.get(role, {})
	if entry is Dictionary:
		return Color(str((entry as Dictionary).get("hex", fallback)))
	return Color(fallback)


## HUD snapshot. gifts / purse / chain come from the LevelState and the economy this
## node owns; the roster is the resolved vote plan (static for the level).
## gifts_collected counts the real slots that were actually COLLECTED, not
## total_real - remaining(): since the platform collapse (sim/gifts.gd lose()) a gift can
## leave the level without being collected, and the subtraction would count it as taken.
func _sync_hud() -> void:
	# D-GUI-1: the gold counter's numbers come from its own pure reader (the gold_taken
	# bitset over REAL slots, total_real, the phase); the hint reads the real lock flag.
	const GoldCounterScript := preload("res://view/hud/gold_counter.gd")
	if hud == null or ctl == null or rt == null:
		return
	var total := 0
	var collected := 0
	var gold: Dictionary = {}
	if lstate != null and lstate.gifts != null:
		var g: RefCounted = lstate.gifts
		total = int(g.total_real)
		for i in g.slots.size():
			if g.is_real(i) and g.collected(i):
				collected += 1
		gold = GoldCounterScript.read(g)
	var purse := 0
	var chain := 1.0
	if _economy != null:
		purse = int(_economy.purse_centi)
		chain = float(_economy.chain_display())
	hud.sync({
		"gifts_collected": collected,
		"gifts_total": total,
		"purse_centi": purse,
		"chain": chain,
		"charges": int(ctl.charges),
		"charge_cap": int(ctl.charge_cap),
		"last_light": str(ctl.hud_last_light()),
		"kit": str(ctl.kit),
		"roster": _roster,
		"ability_remaining": _ability_remaining(),
		"ability_total": _ability_total(),
		"curses": _icon_items(_ledger.get("curses", {})),
		"upgrades": _icon_items(_ledger.get("stacks", {})),
		"radar_entries": _radar_entries(),
		"footprint_map": _footprint_feed(),
		"collapse": _collapse_feed(),
		"gold": gold,
		"mouse_locked": _mouse_locked,
	})


## D-B12-1: the collapse countdown the HUD shows (view/hud/collapse_warning.gd). Empty until
## the beacon opens, so the warning stays hidden through the whole black phase. Read-only on
## sim state: the schedule itself lives in sim/collapse.gd.
func _collapse_feed() -> Dictionary:
	if _collapse == null or _collapse.is_empty() or lstate == null:
		return {}
	var ph := CollapseScript.phase(_collapse)
	if ph == CollapseScript.PHASE_IDLE:
		return {}
	var left := CollapseScript.zone_count(_collapse) - int(_collapse.get("fallen_n", 0))
	var secs := 0.0
	if ph == CollapseScript.PHASE_CRACKING:
		secs = float(int(_collapse["fall_tick"]) - int(lstate.tick)) / 60.0
	elif ph == CollapseScript.PHASE_WAITING:
		secs = float(int(_collapse["crack_tick"]) - int(lstate.tick)) / 60.0
	return {
		"active": true,
		"cracking": ph == CollapseScript.PHASE_CRACKING,
		"seconds": maxf(secs, 0.0),
		"zones_left": maxi(left, 0),
	}


## The class ability's live number for the cooldown HUD: the Dasher's dash cooldown
## seconds left, the Glider's glide energy left (ability_cooldown.gd reads the glider as
## energy, the dasher as cooldown). The Athletic has none (the element hides itself).
func _ability_remaining() -> float:
	if ctl == null:
		return 0.0
	if str(ctl.kit) == "glider":
		return float(ctl.glide_energy)
	return maxf(float(ctl.dash_cd), 0.0)


func _ability_total() -> float:
	if ctl == null:
		return 3.0
	var c: Dictionary = ctl.C
	if str(ctl.kit) == "glider":
		return float(c.get("glide_energy", 3.0))
	return float(c.get("dash_regen", 3.0))


## {id: stacks} -> the icon rows' [{id, stacks}], sorted by id so the row order is stable.
static func _icon_items(held: Variant) -> Array:
	var out: Array = []
	if not (held is Dictionary):
		return out
	var ids: Array = (held as Dictionary).keys()
	ids.sort()
	for id in ids:
		var n := int(held[id])
		if n > 0:
			out.append({"id": str(id), "stacks": n})
	return out
