extends Node
#
# The app orchestrator (ticket APP-FLOW): MENU -> LOADING -> WORLD, the seam the parallel
# MENU / LOADING tickets plug into. game/app/main.tscn (one Control running menu.gd) is
# superseded by res://app/app.tscn, which project.godot now names as run/main_scene.
#
# Flow:
#   _ready           -> show res://app/menu.gd (a Control), connect play_requested/quit_requested
#   play_requested   -> hide the menu, instantiate res://app/loading_screen.gd, start it
#                       (seed, -1.0, first_launch), THEN add it - add_child runs _ready, whose
#                       bootstrap start(0) would otherwise take a gag pick - connect
#                       loading_finished, build the world THIS frame (world.build(seed, 1)),
#                       then set_load_progress(1.0)
#   _process         -> the loading screen self-drives from its own _process; the app does NOT
#                       call advance() (D-APPFLOW-2, PARKED.md #20)
#   loading_finished -> free the loading screen, add the world, start stepping it
#   world.level_completed -> the app tears the world down (teardown(), then queue_free: the
#                            signal is emitted inside world.step()) and enters the
#                            Antechamber (STATE_LOBBY, view/lobby/lobby_scene.gd) with the
#                            level just completed, the run's purse and its carried ledger
#   lobby.exited          -> the player walked into the open Descent Gate: the lobby is
#                            queue_free'd and the next level is built with the lobby's
#                            ledger, so the run's votes / curses / purchases ride into
#                            world.build(seed, level + 1) exactly as the replay would
#                            (lobby n seeded mix(seed, 5000 + n), picks
#                            mix(mix(seed, 0xB07), n + 1) - tools/bot_run.gd's idiom)
#   world.run_over   -> death ends the run (DESIGN.md section 3). The app leaves WORLD so
#                       _process stops stepping the dead world, plays the HUD's 18-tick
#                       death black-out (view/hud/screen_fx.gd), then shows
#                       view/hud/run_over.gd with sim/death.gd's row on blackout_finished.
#                       Retry tears the world down and starts a NEW RUN pinned to the same seed
#                       (the same class falls out of the seeded level-1 replay), straight into
#                       the loading screen and the level - never back to the menu. Play starts
#                       the next run from there on a fresh seed (J1). BACK TO LOBBY
#                       (item 12) tears the dead run down and shows the menu.
#   quit_requested   -> get_tree().quit()
#   ESC / the pause binding -> mid-run (WORLD / LOBBY) the pause overlay: the run freezes,
#                       RESUME continues it, ABANDON ends it (the old ESC path: everything
#                       freed, back to MENU). In LOADING / RUN_OVER ESC still returns to
#                       MENU directly; in MENU it is a no-op.
#   PLAY -> the class altar (gap 2, DESIGN.md section 4) shows over the loading screen:
#                       the pick rebuilds the level with the chosen class and persists for
#                       the session; SKIP keeps the seeded replay's pick. The run WAITS for
#                       the altar: a loading clock that runs out first is held until the
#                       player confirms or skips - a timer never decides the class. The
#                       cursor is free while the altar is up and re-captured as play starts.
#
# The run seed (J1, supersedes D-APPFLOW-1's fixed DEFAULT_SEED 1): start_run(seed)'s argument
# when one was passed - that run reproduces exactly that level, since voidgen is a pure function
# of (seed, level, players, extra_mines) - else a fresh u32 drawn from the engine RNG per run, so
# level 1 differs every run. The explicit seed is used by the NEXT run only; the run after it
# draws a fresh one again. Every run prints "app: run seed=<seed> level=<n>" to the engine log
# (stdout and user://logs/godot.log) so a good level can be replayed with start_run(seed).
# The loading screen's own _process double-advances when this app also drives advance() -
# spec-literal reading of the ticket, flagged [CONTESTABLE] in D-APPFLOW-2.
#
# public API:
#   func start_run(seed_value: int) -> void   # pin the next run's seed; in MENU this also starts it
#   func run_seed() -> int                    # the seed of the current (or last) run
#   static func fresh_seed() -> int           # a new u32 run seed from the engine RNG
#   func state() -> String                    # "MENU" | "LOADING" | "WORLD" | "LOBBY" | "RUN_OVER"

const MenuScript := preload("res://app/menu.gd")
const LoadingScreenScript := preload("res://app/loading_screen.gd")
const WorldScript := preload("res://app/world.gd")
const InputCaptureScript := preload("res://app/input_capture.gd")
const RunOverScript := preload("res://view/hud/run_over.gd")
const LobbySceneScript := preload("res://view/lobby/lobby_scene.gd")
const RecordsScript := preload("res://core/records.gd")
const RunLogScript := preload("res://app/run_log.gd")
# Gap 1 + gap 2: the pause overlay (ESC mid-run freezes the run) and the class altar
# (the player picks the kit before the run starts).
const PauseOverlayScript := preload("res://app/pause_overlay.gd")
const ClassAltarScript := preload("res://app/class_altar.gd")
# The pre-run lobby's ledger hand-off: the app resolves lobby 0 with the PLAYER'S class
# the same way world.gd replays it, and hands the result to world.build as the ledger.
const ContentApiScript := preload("res://core/content_api.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const SettingsScript := preload("res://app/settings.gd")

const DT := 1.0 / 60.0   # fixed 60 Hz sim step (sim/ contract)
const FIRST_LEVEL := 1
const SEED_MASK := 0xFFFFFFFF   # a run seed is one u32 (TERRAIN_SPEC section 1)

const STATE_MENU := "MENU"
const STATE_LOADING := "LOADING"
const STATE_WORLD := "WORLD"
const STATE_LOBBY := "LOBBY"         # the Antechamber between two levels (J7)
const STATE_RUN_OVER := "RUN_OVER"   # dead: the black-out runs, then the run-over screen

var _state := STATE_MENU
var _seed := 0                # the current (or last) run's seed
var _pinned := false          # true when start_run(seed) chose the next run's seed
var _menu: Control = null
var _loading: Control = null
var _world: Node3D = null
var _lobby: Node3D = null     # the Antechamber (view/lobby/lobby_scene.gd)
var _run_over: Control = null
## The run-over screen's own canvas. The dead world's HUD is a CanvasLayer (layer 1) and its
## black-out is still up when the screen opens, so a Control parented straight to the app
## (layer 0) draws UNDER that black and the player sees nothing but black. Layer 2 puts the
## screen on top of the black-out, which is where it was always meant to be. Created lazily
## and kept: an empty CanvasLayer costs nothing, and the three places that free the screen
## only have to free the Control.
var _run_over_layer: CanvasLayer = null
var _death_info: Dictionary = {}   # sim/death.gd's row for the screen (world.run_over)
var _step_acc := 0.0
var _first_launch := true   # the two-duration law: 5 s on the session's first launch, 2.0 s after
var _pause_codes: Array[int] = []   # KEY_* codes bound to "pause" (data/bindings.json), else ESC
var _records: RefCounted = null
var records_path := ""            # tests point this at a scratch file (settings.gd's pattern)
var force_build_failure := false  # tests arm this to make level/lobby builds fail (the records_path pattern)
var _run_level_reached := FIRST_LEVEL
var _run_purse := 0
var _run_class := ""
var _run_recorded := false        # one records/telemetry write per run
var _ever_entered_world := false  # the run reached WORLD or LOBBY at least once
# gap 1: the pause overlay's state. The sim never sees a pause - the app just stops
# stepping the world / the hall while the overlay is open (the run's clock is the app's
# own fixed-step accumulator, so not stepping IS frozen time for the run).
var _paused := false
var _pause_prev_locked := false   # the mouse capture to restore on Resume
var _pause_overlay: Control = null
# gap 2: the player's class pick. "" = no pick yet - the seeded pre-run replay decides
# (the old behaviour). A pick persists across runs of the session until changed.
var _chosen_class := ""
var _class_altar: Control = null
# The loading clock ran out while the altar was still open: the run is held (state stays
# LOADING, the world stays out of the tree) until the player confirms or skips.
var _held_for_altar := false


func _ready() -> void:
	_records = RecordsScript.new()
	_records.load_from(records_path)
	_pause_codes = _load_pause_codes()
	_apply_saved_volume()
	_show_menu()


## The saved master volume reaches the audio bus at BOOT, not only when the settings screen
## is opened: a player who set 30 % last session hears 30 % from the menu's first cue. A
## missing or corrupt settings file reads as the default (settings.gd's contract), so this
## can never block boot.
func _apply_saved_volume() -> void:
	var sett := SettingsScript.new()
	sett.load_from()
	sett.apply_volume()


func _process(delta: float) -> void:
	# The loading screen drives its own clock from its own _process (T-024, D-T024-1), so the
	# app must NOT also call advance(): doing both accrues elapsed at 2x and the hold elapses
	# in half the wall time (D-APPFLOW-2, PARKED.md #20). The screen emits loading_finished
	# from inside its own advance(); _on_loading_finished frees it and moves us to WORLD.
	# gap 1: while the pause overlay is open the run is frozen - no world tick, no lobby
	# tick, and the accumulator is dropped so the resume never replays lost time.
	if _paused:
		_step_acc = 0.0
		return
	if _state == STATE_WORLD and _world != null:
		# Fixed 60 Hz sim accumulator (the sim's contract), decoupled from the render rate:
		# at 120+ Hz the world must not run 2x fast. Spiral-of-death clamp: 5 ticks/frame.
		_step_acc += delta
		var ticks := 0
		while _step_acc >= DT and ticks < 5:
			_world.step(DT)
			if _world == null:
				break   # the completion handler tore the world down mid-tick
			_step_acc -= DT
			ticks += 1
		if _world == null:
			_step_acc = 0.0
		elif ticks == 5:
			_step_acc = 0.0
	elif _state == STATE_LOBBY and _lobby != null:
		# The Antechamber walks on the same fixed step, so the hall's speed does not
		# depend on the render rate either. lobby.step() captures its own input.
		_step_acc += delta
		var lticks := 0
		while _step_acc >= DT and lticks < 5:
			_lobby.step(DT)
			if _lobby == null:
				break   # the exit handler tore the lobby down mid-tick
			_step_acc -= DT
			lticks += 1
		if _lobby == null or lticks == 5:
			_step_acc = 0.0


# ---- public API -----------------------------------------------------------------------------

## Pin the seed of the NEXT run: that run builds exactly the level voidgen gives for this seed
## (the bot and future multiplayer depend on it). In MENU this also starts the run (same path
## as the Play button); elsewhere it only pins the seed of the NEXT run. D-APPFLOW-3
## [CONTESTABLE]. The menu has to exist first: before _ready there is none, and a run started
## that early would be orphaned by _ready's _show_menu() (state back to MENU, a live loading
## screen left behind), so an early call degrades to "store the seed".
func start_run(seed_value: int) -> void:
	_seed = seed_value & SEED_MASK
	_pinned = true
	if _state == STATE_MENU and _menu != null:
		_begin_run()


func state() -> String:
	return _state


## The seed of the current run (or of the last one, back in the menu).
func run_seed() -> int:
	return _seed


## A fresh run seed: one u32 from a randomized engine RNG. App layer only - the generator never
## sees anything but the integer it is handed, so determinism per seed is untouched.
static func fresh_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return int(rng.randi()) & SEED_MASK


# ---- menu / loading / world transitions -------------------------------------------------------

func _show_menu() -> void:
	if _menu == null:
		_menu = MenuScript.new()
		add_child(_menu)
		_menu.play_requested.connect(_on_play_requested)
		_menu.quit_requested.connect(_on_quit_requested)
	else:
		_menu.show()
	# The menu reads the same records file the app writes (tests point records_path at a
	# scratch file), and a REUSED menu re-reads it: a run that just ended may have ratcheted
	# the bests, and the bests line must not show launch-time values for the session.
	_menu.records_path = records_path
	_menu.refresh_records()
	_state = STATE_MENU
	_step_acc = 0.0


func _on_play_requested() -> void:
	_begin_run()
	_open_class_altar()


## Hide the menu, show the loading screen, build the world THIS frame, report real progress.
func _begin_run() -> void:
	if _state != STATE_MENU:
		return
	if _menu != null:
		_menu.hide()
	# J1: an explicit start_run(seed) is used once; otherwise every run draws a fresh seed.
	if not _pinned:
		_seed = fresh_seed()
	_pinned = false
	_run_level_reached = FIRST_LEVEL
	_run_purse = 0
	_run_class = ""
	_run_recorded = false
	_ever_entered_world = false
	# gap 2: with a class picked, the run is born from the pre-run lobby resolved with
	# THAT class as a carried ledger - world.build then skips its own replay and uses it
	# (the same hand-off the Antechamber exit does). No pick: the old seeded replay.
	var ledger := {}
	if _chosen_class != "":
		ledger = _resolve_pre_run(_chosen_class)
	_loading = LoadingScreenScript.new()
	# start() BEFORE add_child: add_child runs _ready, whose bootstrap start(0) would take a gag
	# pick and overwrite the static _last_gag_id, so every restart would replay the same gag
	# (BUG-app-loop-2). start()'s _update_view() is documented safe before _ready.
	_loading.start(_seed, -1.0, _first_launch)
	_first_launch = false
	add_child(_loading)
	_loading.loading_finished.connect(_on_loading_finished)
	_state = STATE_LOADING
	# Build the world in the same frame the loading screen appears (the ticket's contract).
	if not _build_world(FIRST_LEVEL, ledger):
		# queue_free, not free: the screen is already in the tree and emits from inside its
		# own call stack (D-APPFLOW-7). A synchronous free here is the one shape that rule
		# exists to forbid, and the next refactor that routes this failure through a signal
		# would trip it.
		_loading.queue_free()
		_loading = null
		_show_menu()
		return
	_loading.set_load_progress(1.0)


## Creates the world for p_level with the run's carried ledger, wires its signals and
## builds it. Returns false (and leaves _world null) on a generator/content failure.
## The seed print lives here, so every level of a run announces itself the same way.
func _build_world(p_level: int, p_ledger: Dictionary) -> bool:
	var built := _build_world_node(p_level, p_ledger)
	_world = built
	if _world == null:
		return false
	# The class the run was born with: the carried pick, else the level-1 replay's own
	# CLASS-bay pick (world._resolve_run). The run telemetry (run_started) reads it.
	_run_class = str(_world.run_ledger().get("class", _run_class))
	return true


## Creates, wires and builds one world node - the call for the run's levels and for the
## class altar's rebuild alike. Returns the node, or null on a generator/content failure
## (nothing is assigned; the caller keeps whatever world it had).
func _build_world_node(p_level: int, p_ledger: Dictionary) -> Node:
	print("app: run seed=%d level=%d" % [_seed, p_level])
	_run_level_reached = maxi(_run_level_reached, p_level)
	if force_build_failure:
		push_warning("app: forced world build failure (test hook)")
		return null
	var fresh := WorldScript.new()
	fresh.level_completed.connect(_on_level_completed)
	fresh.run_over.connect(_on_run_over)
	_death_info = {}
	if not fresh.build(_seed, p_level, p_ledger):
		push_warning("app: world.build(%d, %d) failed; back to menu" % [_seed, p_level])
		fresh.free()
		return null
	return fresh


func _on_loading_finished() -> void:
	# gap 2: the altar holds the run. Before this guard the clock running out freed the
	# open altar and went live with the seeded replay's class - the owner's "it picks for me"
	# bug: 5 s on the first launch, 2 s on every later PLAY, and a player still reading
	# the cards lost the choice to the timer.
	if _class_altar != null and _class_altar.is_open():
		_held_for_altar = true
		return
	_go_live()


## The run goes live: the loading screen and the altar leave, the world enters the tree,
## and the world's own capture (a level begins CAPTURED, world.gd J5) is re-applied -
## the altar had released it so the cursor could reach the cards.
func _go_live() -> void:
	_held_for_altar = false
	if _loading != null:
		# queue_free, not free(): loading_finished is emitted from inside advance();
		# freeing the screen synchronously would pull the object from under its own
		# call stack. queue_free deletes at idle time, after advance() returns.
		_loading.queue_free()
		_loading = null
	# gap 2: the run is live - the pick window is over. The class itself (_chosen_class)
	# persists: the next PLAY carries it from the first build, no re-pick needed.
	if _class_altar != null:
		_class_altar.queue_free()
		_class_altar = null
	if _world != null:
		add_child(_world)
		_world._mouse_locked = true
		_world.apply_mouse_mode()
	_ever_entered_world = true   # the run is live: a later _end_run() records it
	_state = STATE_WORLD


func _on_quit_requested() -> void:
	_end_run()   # quitting mid-run ends it; a worse or partial run never lowers the records
	get_tree().quit()


## The world entered its beacon (APP-LOOP). The level is over: tear the world down and
## walk the player into the Antechamber (J7, DESIGN.md section 11). level_completed is
## emitted from inside world.step(), so the world is queue_free'd, never freed
## (D-APPFLOW-7); _world is nulled NOW, so the _process loop's re-check fires and stops
## stepping it. The run's carried ledger (class / votes / curses / purchases / purse) is
## read BEFORE the teardown, because teardown() drops it.
func _on_level_completed() -> void:
	if _world == null:
		return
	var completed: int = int(_world.level_number())
	var ledger: Dictionary = _world.run_ledger()
	_run_level_reached = maxi(_run_level_reached, completed)
	_run_purse = int(ledger.get("purse", _run_purse))
	_run_class = str(ledger.get("class", _run_class))
	_world.teardown()
	_world.queue_free()
	_world = null
	_enter_lobby(completed, ledger)


## The Antechamber for the level just completed. It is a real 3D place: the player walks
## it, F picks an altar, and the Descent Gate opens once every mandatory bay is resolved.
## A content failure falls back to the menu rather than trapping the player in a dead hall.
func _enter_lobby(p_completed: int, p_ledger: Dictionary) -> void:
	_lobby = LobbySceneScript.new()
	_lobby.exited.connect(_on_lobby_exited)
	add_child(_lobby)
	if force_build_failure or not _lobby.build(_seed, p_completed, p_ledger):
		push_warning("app: lobby.build(level_completed %d) failed; back to menu" % p_completed)
		_lobby.queue_free()
		_lobby = null
		_end_run()   # a run that ends in a build failure still records + logs
		_show_menu()
		return
	_ever_entered_world = true   # the run walked into the lobby: a later _end_run() records it
	_state = STATE_LOBBY
	_step_acc = 0.0
	print("app: lobby level_completed=%d purse=%d" % [p_completed, int(p_ledger.get("purse", 0))])


## The player walked into the open Descent Gate: build the next level with the lobby's
## ledger, so the run's votes / curses / purchases are the ones the player made and the
## level stays a pure function of (seed, level, ledger). exited is emitted from inside
## lobby.step(), so the lobby is queue_free'd, never freed (D-APPFLOW-7).
func _on_lobby_exited(p_ledger: Dictionary) -> void:
	if _lobby == null:
		return
	var next_level: int = int(_lobby.next_level())
	_run_purse = int(p_ledger.get("purse", _run_purse))
	_run_class = str(p_ledger.get("class", _run_class))
	_lobby.queue_free()
	_lobby = null
	_step_acc = 0.0
	if not _build_world(next_level, p_ledger):
		_end_run()   # a run that ends in a build failure still records + logs
		_show_menu()
		return
	add_child(_world)
	_state = STATE_WORLD


## The player died: DESIGN.md section 3, "Death ends the run". world.step() emitted this
## from inside its own tick, so nothing here frees the world (D-APPFLOW-7: queue_free, not
## free, on a signal emitted from inside the emitter - and the world is still needed).
## Leaving STATE_WORLD is what stops _process from stepping the dead run; the world stays
## in the tree for its own HUD's 18-tick death black-out, and the run-over screen opens on
## blackout_finished (one frame of black on black, seamless: screen_fx holds black).
func _on_run_over(info: Dictionary) -> void:
	if _world == null or _state != STATE_WORLD:
		return
	_death_info = info
	_run_level_reached = maxi(_run_level_reached, int(_world.level_number()))
	var ledger: Dictionary = _world.run_ledger()
	_run_purse = int(ledger.get("purse", _run_purse))
	_run_class = str(ledger.get("class", _run_class))
	_end_run()   # DESIGN.md section 9 + T-080: death ends the run, so record + log it here
	_state = STATE_RUN_OVER
	var hud = _world.hud
	if hud == null:
		_show_run_over()   # no HUD to play the black-out: the screen opens now
		return
	if not hud.blackout_finished.is_connected(_on_blackout_finished):
		hud.blackout_finished.connect(_on_blackout_finished)
	hud.death_blackout()


## The death black-out landed (view/hud/screen_fx.gd, section 2.4): show the run-over row.
func _on_blackout_finished() -> void:
	if _state != STATE_RUN_OVER:
		return
	_show_run_over()


func _show_run_over() -> void:
	if _run_over == null:
		_run_over = RunOverScript.new()
		_run_over.retried.connect(_on_retry_requested)
		_run_over.lobby_requested.connect(_on_back_to_lobby)
		if _run_over_layer == null:
			_run_over_layer = CanvasLayer.new()
			_run_over_layer.layer = 2   # above the dead world's HUD (layer 1) and its black-out
			add_child(_run_over_layer)
		_run_over_layer.add_child(_run_over)   # run_over.gd builds its own layout in _init
	_run_over.show_run_over(_death_info)


## Retry: restart the run with the same seed and the same class, straight into the level.
## The pinned seed reproduces level 1 exactly - the level-1 class is the seeded lobby-0
## replay's pick (world._resolve_run), a pure function of the seed, so the new run's class
## is the class the dead run was born with. The dead run's own teardown is the same one ESC
## does, but instead of showing the menu, the menu-hidden pin path (start_run, in MENU) runs
## the normal LOADING -> WORLD transition. The screen is queue_free'd, not freed: retried is
## emitted from inside its own Button.
func _on_retry_requested() -> void:
	if _state != STATE_RUN_OVER:
		return   # RETRY is not re-entrant: a double activation is a no-op
	var retry_seed := _seed
	if _run_over != null:
		_run_over.queue_free()
		_run_over = null
	_death_info = {}
	if _world != null:
		_world.teardown()
		_world.free()
		_world = null
	if _lobby != null:
		_lobby.teardown()
		_lobby.free()
		_lobby = null
	if _loading != null:
		# queue_free, not free(): a live loading screen may be mid-frame.
		_loading.queue_free()
		_loading = null
	_step_acc = 0.0
	# Land in MENU state (the menu stays hidden) so start_run takes the run path.
	_state = STATE_MENU
	if _menu == null:
		_show_menu()
	start_run(retry_seed)


## BACK TO LOBBY on the death screen: the run is over - free it and go back to the
## pre-run lobby (the menu; PLAY there opens the class altar for the next run). The
## same teardown ESC does on this screen; the screen is queue_free'd there (the signal
## is emitted from inside its own Button).
func _on_back_to_lobby() -> void:
	if _state != STATE_RUN_OVER:
		return
	_return_to_menu()


# ---- bests + run telemetry (DESIGN.md section 9 / T-080) ----------------------------------

## The locally recorded bests (DESIGN.md section 9), for the menu / run-over screens to
## display. One-line wiring for the lead (view files are not app-layer):
##   menu / run_over:  label.text = "Best level %d - best purse %d" % [app.best_level(), app.best_purse()]
func best_level() -> int:
	return _records.get_best_level() if _records != null else 0


func best_purse() -> int:
	return _records.get_best_purse() if _records != null else 0


## A run has ended (death, ESC back to menu, quit mid-run): ratchet the local records
## (DESIGN.md section 9 - only ever up) and write the run telemetry log (T-080). Guarded so
## death followed by ESC or retry does not write the file twice. The app has no per-tick
## event channel (world only signals level_completed / run_over), so the closed record set
## lands as run_start + run_end; feeding feed_tick needs a world-side event signal.
func _end_run() -> void:
	if _run_recorded:
		return
	if _state == STATE_MENU:
		return
	if not _ever_entered_world and _state != STATE_WORLD and _state != STATE_LOBBY \
			and _state != STATE_RUN_OVER:
		# ESC during LOADING (or a quit before the run went live): no level was ever
		# played, so there is nothing to ratchet and no run to log. An explicitly
		# WORLD/LOBBY/RUN_OVER state is a live run even if the flag was never set.
		return
	_run_recorded = true
	if _records == null:
		_records = RecordsScript.new()
		_records.load_from(records_path)
	_records.record_run(_run_level_reached, _run_purse)
	var log := RunLogScript.new()
	log.run_started(_seed, _run_class)
	log.run_finished(_run_level_reached, _run_purse)
	log.close()


# ---- pause (ESC / the pause binding) and the class altar -----------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if _pause_codes.has(int(key.keycode)):
			_pause_pressed()


## The pause binding, per state (gap 1): mid-run it opens the pause overlay - the run
## freezes - and open, it resumes. Anywhere else it keeps the old path (a run has not
## started in LOADING to freeze, and the run-over screen already ended the run), so ESC
## in LOADING / RUN_OVER still returns to the menu and ESC in MENU stays a no-op.
func _pause_pressed() -> void:
	if _pause_overlay != null and _pause_overlay.is_open():
		_resume_run()
	elif _state == STATE_WORLD or _state == STATE_LOBBY:
		_open_pause()
	else:
		_return_to_menu()


## Freeze the run and show the overlay. The capture state is remembered and restored on
## Resume (the world / the lobby hold their own _mouse_locked; read and written from the
## app the same way the death path in world.gd writes it - the sim is never involved).
func _open_pause() -> void:
	if _paused:
		return
	_paused = true
	_step_acc = 0.0
	var frozen = _world if _state == STATE_WORLD else _lobby
	_pause_prev_locked = frozen != null and bool(frozen._mouse_locked)
	if frozen != null:
		frozen._mouse_locked = false
	if _pause_overlay == null:
		_pause_overlay = PauseOverlayScript.new()
		_pause_overlay.resumed.connect(_resume_run)
		_pause_overlay.abandon_requested.connect(_return_to_menu)
		add_child(_pause_overlay)
	_pause_overlay.open(_pause_snapshot())
	if frozen != null:
		frozen.apply_mouse_mode()


## Resume: whatever the run was doing when it froze, it does again. The overlay closes,
## the frozen state keeps stepping from the tick it stopped on.
func _resume_run() -> void:
	if not _paused:
		return
	_paused = false
	if _pause_overlay != null:
		_pause_overlay.close()
	var frozen = _world if _state == STATE_WORLD else _lobby
	if frozen != null:
		frozen._mouse_locked = _pause_prev_locked
		frozen.apply_mouse_mode()


## The overlay's frozen-state line: the level the player is on and the whole-gold purse
## (the same number the HUD shows, via the world's economy; the lobby holds none yet).
func _pause_snapshot() -> String:
	var level := 0
	if _state == STATE_WORLD and _world != null:
		level = int(_world.level_number())
	elif _state == STATE_LOBBY and _lobby != null:
		level = int(_lobby.level_completed) + 1
	var line := "LEVEL %d" % maxi(level, 1)
	if _state == STATE_WORLD and _world != null and _world._economy != null:
		line = "%s - PURSE %d g" % [line, int(_world._economy.purse_gold())]
	return line


## ESC / the pause binding outside a live run: free the world (and any loading screen or
## lobby), show the menu - the Abandon path and the old ESC behaviour in one.
func _return_to_menu() -> void:
	if _state == STATE_MENU:
		return
	# A pause is impossible once the run is gone (nothing left to freeze); an open overlay
	# or altar follows the run out. queue_free: Abandon is emitted from the overlay's own
	# Button, and loading_finished from the loading screen's advance().
	_paused = false
	if _pause_overlay != null:
		_pause_overlay.queue_free()
		_pause_overlay = null
	if _class_altar != null:
		_class_altar.queue_free()
		_class_altar = null
	_held_for_altar = false
	_end_run()   # ESC abandons the run in progress; the records only ratchet up
	# queue_free: retried is emitted from inside the run-over screen's own Button.
	if _run_over != null:
		_run_over.queue_free()
		_run_over = null
	_death_info = {}
	if _world != null:
		_world.teardown()
		_world.free()
		_world = null
	if _lobby != null:
		_lobby.teardown()
		_lobby.free()
		_lobby = null
	if _loading != null:
		_loading.free()
		_loading = null
	_step_acc = 0.0
	_show_menu()


func _load_pause_codes() -> Array[int]:
	var codes: Array[int] = [KEY_ESCAPE]
	var res := InputCaptureScript.load_bindings("res://data/bindings.json")
	if (res.get("errors", []) as Array).is_empty():
		var kb: Dictionary = res.get("key_bindings", {})
		var bound: Array = kb.get("pause", [])
		var out: Array[int] = []
		for code in bound:
			var c := int(code)
			if not out.has(c):
				out.append(c)
		if not out.is_empty():
			return out
	return codes

# ---- the class altar (gap 2, DESIGN.md section 4) -------------------------------------------

## The altar shows over the loading screen, before the run starts. A confirmed pick
## rebuilds the not-yet-in-tree world with the chosen class; SKIP leaves the seeded
## replay's pick. The run waits for one of the two (_on_loading_finished holds it).
## world.build() captured the mouse when the world was built a moment ago (a level
## begins CAPTURED) - with the cursor hidden and locked to the window centre no click
## could reach a card, so the altar releases it through the world's own
## apply_mouse_mode() (the single Input.mouse_mode writer). start_run() never
## shows the altar: a pinned seed must reproduce the run it pins (the bot, Retry), and
## Retry reruns the dead run's own class (the pick persists in _chosen_class).
func _open_class_altar() -> void:
	if _state != STATE_LOADING:
		return
	if _class_altar != null:
		_class_altar.queue_free()
		_class_altar = null
	_held_for_altar = false
	_class_altar = ClassAltarScript.new()
	_class_altar.class_chosen.connect(_on_class_chosen)
	_class_altar.skipped.connect(_on_class_skipped)
	add_child(_class_altar)   # after the loading screen: the altar draws on top
	_class_altar.open(_chosen_class)
	_release_cursor_for_altar()


## The cursor is free while the altar is up: the not-yet-live world holds the capture
## state, so release it there (a rebuild after a pick captures again - call again).
func _release_cursor_for_altar() -> void:
	if _world != null:
		_world._mouse_locked = false
		_world.apply_mouse_mode()


## SKIP: the seeded replay's class stands. If the clock already ran out, go live now.
func _on_class_skipped() -> void:
	if _state == STATE_LOADING and _held_for_altar:
		_go_live()


## One pick at the altar: remember it for every later run of the session, and in LOADING
## rebuild the level-1 world around the screen with the chosen class. The world is not in
## the tree until loading_finished, so the swap happens in one frame, invisible; on a
## build failure the run keeps the world it was born with (a warning, never a crash).
func _on_class_chosen(class_id: String) -> void:
	_chosen_class = str(class_id)
	if _state != STATE_LOADING or _world == null:
		return
	var ledger := _resolve_pre_run(_chosen_class)
	var fresh := _build_world_node(FIRST_LEVEL, ledger)
	if fresh != null:
		_world.teardown()
		_world.free()
		_world = fresh
		_run_class = str(_world.run_ledger().get("class", _run_class))
	_release_cursor_for_altar()
	if _held_for_altar:
		_go_live()   # the clock already ran out: the confirmed pick starts the run now


## The pre-run lobby (level_completed 0) resolved with the PLAYER'S class: the CLASS bay's
## pick is the altar the player chose; the starter E bay is resolved by the bot's own
## uniform pick over the run's pick stream (world.gd _resolve_run's exact idiom and
## seeding). Returns the carried ledger world.build() takes - it has "votes", so world
## skips its own replay and uses exactly this state - or {} when the content api is down
## or the class id is not on the table (the run then falls back to world's own replay).
func _resolve_pre_run(class_id: String) -> Dictionary:
	var api := ContentApiScript.load()
	if api == null or not api.is_ok():
		push_warning("app: no content api - the seeded replay picks the class")
		return {}
	var lb: RefCounted = IntermissionScript.create(api, 0, 0,
			VoidRngScript.mix(_seed, 5000), {}, {}, {}, class_id, 0, 0, "", {},
			WorldScript.max_stacks_bonus_for({}, class_id))
	var rng: RefCounted = VoidRngScript.new(VoidRngScript.mix(
			VoidRngScript.mix(_seed, 0xB07), 1))
	for _i in range(80):
		if bool(lb.gate_open()):
			break
		var table: Array = lb.altar_table()
		var class_pick := -1
		var picks: Array[int] = []
		var tithe_picks: Array[int] = []
		for i in table.size():
			var entry: Dictionary = table[i]
			var bay: Dictionary = lb.bays[int(entry["bay_index"])]
			var kind := str(entry["kind"])
			var bay_kind := str(entry["bay"])
			if bay_kind == "CLASS":
				# the CLASS bay never resolves as a bay while class_chosen rides the state
				# (intermission.gd's gate_open); the pick IS the player's class
				if str(lb.class_chosen) == "" and _altar_id_matches(bay,
						int(entry["altar"]), class_id):
					class_pick = i
			elif bool(bay.get("resolved", false)):
				continue
			elif kind == "offer" and (bay_kind == "E" or bay_kind == "C"):
				picks.append(i)
			elif kind == "tithe" and bay_kind == "C":
				tithe_picks.append(i)
		var ev: Array = []
		if class_pick >= 0:
			lb.apply_select(0, class_pick, ev)
		elif not picks.is_empty():
			lb.apply_select(0, picks[rng.urange(picks.size())], ev)
		elif not tithe_picks.is_empty():
			if not bool(lb.apply_select(0, tithe_picks[0], ev)):
				break
		else:
			break
	if not bool(lb.gate_open()):
		push_warning("app: the pre-run lobby did not resolve for class '%s'" % class_id)
		return {}
	return {
		"class": class_id,
		"votes": (lb.votes as Dictionary).duplicate(),
		"curses": (lb.curses_held as Dictionary).duplicate(),
		"stacks": (lb.upgrade_stacks as Dictionary).duplicate(),
		"purse": int(lb.purse),
		"tithes": int(lb.tithes),
		"hunger": int(lb.hunger),
		"last_vote": str(lb.last_vote),
	}


## True when p_bay's altar p_altar is the class altar for class_id.
static func _altar_id_matches(p_bay: Dictionary, p_altar: int, class_id: String) -> bool:
	var altars: Array = p_bay.get("altars", [])
	if p_altar < 0 or p_altar >= altars.size():
		return false
	return str((altars[p_altar] as Dictionary).get("id", "")) == class_id
