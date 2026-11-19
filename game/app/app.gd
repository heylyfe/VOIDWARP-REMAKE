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
#                       Retry (like ESC) tears the world down and returns to MENU; Play
#                       starts the next run from there on a fresh seed (J1).
#   quit_requested   -> get_tree().quit()
#   ESC / the pause binding -> back to MENU from LOADING, WORLD or LOBBY (freed)
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
var _death_info: Dictionary = {}   # sim/death.gd's row for the screen (world.run_over)
var _step_acc := 0.0
var _first_launch := true   # the two-duration law: 5 s on the session's first launch, 2.0 s after
var _pause_codes: Array[int] = []   # KEY_* codes bound to "pause" (data/bindings.json), else ESC


func _ready() -> void:
	_pause_codes = _load_pause_codes()
	_show_menu()


func _process(delta: float) -> void:
	# The loading screen drives its own clock from its own _process (T-024, D-T024-1), so the
	# app must NOT also call advance(): doing both accrues elapsed at 2x and the hold elapses
	# in half the wall time (D-APPFLOW-2, PARKED.md #20). The screen emits loading_finished
	# from inside its own advance(); _on_loading_finished frees it and moves us to WORLD.
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
	_state = STATE_MENU
	_step_acc = 0.0


func _on_play_requested() -> void:
	_begin_run()


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
	if not _build_world(FIRST_LEVEL, {}):
		_loading.free()
		_loading = null
		_show_menu()
		return
	_loading.set_load_progress(1.0)


## Creates the world for p_level with the run's carried ledger, wires its signals and
## builds it. Returns false (and leaves _world null) on a generator/content failure.
## The seed print lives here, so every level of a run announces itself the same way.
func _build_world(p_level: int, p_ledger: Dictionary) -> bool:
	print("app: run seed=%d level=%d" % [_seed, p_level])
	_world = WorldScript.new()
	_world.level_completed.connect(_on_level_completed)
	_world.run_over.connect(_on_run_over)
	_death_info = {}
	if not _world.build(_seed, p_level, p_ledger):
		push_warning("app: world.build(%d, %d) failed; back to menu" % [_seed, p_level])
		_world.free()
		_world = null
		return false
	return true


func _on_loading_finished() -> void:
	if _loading != null:
		# queue_free, not free(): loading_finished is emitted from inside advance();
		# freeing the screen synchronously would pull the object from under its own
		# call stack. queue_free deletes at idle time, after advance() returns.
		_loading.queue_free()
		_loading = null
	if _world != null:
		add_child(_world)
	_state = STATE_WORLD


func _on_quit_requested() -> void:
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
	if not _lobby.build(_seed, p_completed, p_ledger):
		push_warning("app: lobby.build(level_completed %d) failed; back to menu" % p_completed)
		_lobby.queue_free()
		_lobby = null
		_show_menu()
		return
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
	_lobby.queue_free()
	_lobby = null
	_step_acc = 0.0
	if not _build_world(next_level, p_ledger):
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
		add_child(_run_over)   # run_over.gd builds its own layout in _init
	_run_over.show_run_over(_death_info)


## Retry a new run: the same teardown as ESC, then the menu - Play starts the next run on
## the same seed (there is no intermission lobby yet). The screen is queue_free'd, not
## freed: retried is emitted from inside its own Button.
func _on_retry_requested() -> void:
	_return_to_menu()


# ---- pause (ESC / the pause binding) -----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if _pause_codes.has(int(key.keycode)):
			_return_to_menu()


## ESC / the pause binding: free the world (and any loading screen or lobby), show the menu.
func _return_to_menu() -> void:
	if _state == STATE_MENU:
		return
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