extends RefCounted
#
# APP-DEATH test (headless): death ends the run. The bug hunt found the app reading
# nothing about death - no controller "death" event, no ctl.dead, no caller of
# view/hud/hud.gd's death_blackout() or view/hud/run_over.gd's show_run_over() - so on
# the third void fall (or any enemy / tripmine kill) the world kept ticking and the run
# simply stopped. DESIGN.md section 3: "Death ends the run"; README: "the third fall is
# the end of the run".
#
#   leg A (level 1, seed 1): three void falls through the real controller path inside
#   world.step() - two cost a charge, the third has none left - and world.gd's run_over
#   signal fires exactly once on that tick, carrying sim/death.gd's row (the D-VOID code,
#   the void as killer, the level number, the live purse, the charges held at death). The
#   dead world then stops advancing (lstate.tick frozen, no second emission) and
#   teardown() clears the latch. The same row, fed to the real run-over screen, prints the
#   purse and the charges it was given (the screen used to read a key sim/death.gd never
#   wrote and printed "PURSE 0.00 g" / "CHARGES HELD: 0" instead).
#   leg B (level 5, seed 0): a killing blow through the controller's own try_kill (the
#   tripmine ladder's entry point) ends the run the same way, one emission, code D-MINE.
#   leg C (the shipped app, seed 1 level 1): the same death drives app.gd out of WORLD into
#   RUN_OVER (its _process stops stepping the dead world), the HUD's 18-tick death
#   black-out runs, and the run-over screen opens on blackout_finished with the dead run's
#   row; Retry tears the dead run down and restarts the SAME seed straight into
#   LOADING -> WORLD, with the menu never shown (gap 22).
#
# The test fails if step() stops detecting a dead controller, if the signal re-fires, if a
# dead world keeps ticking, or if the app freezes with the run-over screen unreachable.

const WorldScript := preload("res://app/world.gd")
const AppScript := preload("res://app/app.gd")
const DeathScript := preload("res://sim/death.gd")
const RunOverScript := preload("res://view/hud/run_over.gd")
const ScreenFxScript := preload("res://view/hud/screen_fx.gd")

const SEED_A := 1
const LEVEL_A := 1
const SEED_B := 0
const LEVEL_B := 5   # mine occupancy (TERRAIN_SPEC 6.8), the same level test_app_loop uses
const DT := 1.0 / 60.0


func run() -> Array[String]:
	var f: Array[String] = []
	_leg_a(f)
	_leg_b(f)
	_leg_c_app(f)
	return f


## Leg A: two falls that cost a charge, the third that ends the run.
func _leg_a(f: Array[String]) -> void:
	var world = WorldScript.new()
	var hits: Array = []
	world.run_over.connect(func(info: Dictionary) -> void: hits.append(info))
	if not world.build(SEED_A, LEVEL_A):
		f.append("leg A: world failed to build level %d seed %d" % [LEVEL_A, SEED_A])
		world.free()
		return
	var ctl = world.ctl
	if int(ctl.charges) != 2:
		f.append("leg A: spawn charges %d, want 2 (DESIGN 3.1: two falls, the third kills)"
				% int(ctl.charges))
	for i in range(2):
		_fall_over_the_void(world)
		if bool(ctl.dead):
			f.append("leg A: void fall %d killed the player; only the third fall may" % (i + 1))
			break
		if int(ctl.charges) != 1 - i:
			f.append("leg A: after fall %d the charges are %d, want %d"
					% [i + 1, int(ctl.charges), 1 - i])
	if hits.size() != 0:
		f.append("leg A: run_over fired %d times before the last charge was spent" % hits.size())
	if not bool(ctl.dead):
		_fall_over_the_void(world)
	if not bool(ctl.dead):
		f.append("leg A: the third void fall did not kill the player (charges %d, dead %s)"
				% [int(ctl.charges), str(ctl.dead)])
	if hits.size() != 1:
		f.append("leg A: run_over fired %d times on the death tick, want exactly 1" % hits.size())
	else:
		# the payload: exactly the keys view/hud/run_over.gd reads
		var info: Dictionary = hits[0]
		var code := str(info.get("code", ""))
		if code != DeathScript.VOID_CODE:
			f.append("leg A: the payload's code is '%s', want '%s'" % [code, DeathScript.VOID_CODE])
		var killer := str(info.get("killer", ""))
		if killer != DeathScript.VOID_NAME:
			f.append("leg A: the payload's killer is '%s', want '%s'"
					% [killer, DeathScript.VOID_NAME])
		if int(info.get("level", 0)) != LEVEL_A:
			f.append("leg A: the payload's level is %d, want %d"
					% [int(info.get("level", 0)), LEVEL_A])
		if int(info.get("purse", -2)) != int(world._economy.purse_centi):
			f.append("leg A: the payload's purse is %d, want the live purse %d"
					% [int(info.get("purse", -2)), int(world._economy.purse_centi)])
		if int(info.get("charges", -1)) != int(ctl.charges):
			f.append("leg A: the payload's charges are %d, want %d"
					% [int(info.get("charges", -1)), int(ctl.charges)])

	# a dead run stops advancing: no sim step, no second signal
	var tick_at_death: int = int(world.lstate.tick)
	for i in range(3):
		world.step(DT)
	if int(world.lstate.tick) != tick_at_death:
		f.append("leg A: the dead world kept ticking (%d -> %d)"
				% [tick_at_death, int(world.lstate.tick)])
	if hits.size() != 1:
		f.append("leg A: run_over re-fired after the death tick (%d times)" % hits.size())

	_screen_leg(f, world)

	# teardown clears the latch, and step() after it stays the null-guard no-op
	world.teardown()
	if bool(world._run_over_emitted):
		f.append("leg A: teardown() left the run-over latch set")
	world.step(DT)
	if hits.size() != 1:
		f.append("leg A: run_over re-fired after teardown (%d times)" % hits.size())
	world.free()


## Leg B: the controller's own kill API (an enemy hit or the tripmine ladder's entry).
func _leg_b(f: Array[String]) -> void:
	var world = WorldScript.new()
	var hits: Array = []
	world.run_over.connect(func(info: Dictionary) -> void: hits.append(info))
	if not world.build(SEED_B, LEVEL_B):
		f.append("leg B: world failed to build level %d seed %d" % [LEVEL_B, SEED_B])
		world.free()
		return
	var ctl = world.ctl
	# nothing to save it: no charge left and Last Light already spent
	ctl.charges = 0
	ctl.last_light_spent = true
	ctl.try_kill("D-MINE", "gift_larper", world.w)
	if not bool(ctl.dead):
		f.append("leg B: try_kill with no charge left did not kill the player")
	if not hits.is_empty():
		f.append("leg B: run_over fired outside step() (%d times)" % hits.size())
	world.step(DT)
	if hits.size() != 1:
		f.append("leg B: run_over fired %d times on the death tick, want exactly 1" % hits.size())
	else:
		var info: Dictionary = hits[0]
		var code := str(info.get("code", ""))
		if code != "D-MINE":
			f.append("leg B: the payload's code is '%s', want 'D-MINE'" % code)
		var want_killer := DeathScript.killer_for("D-MINE")
		var killer := str(info.get("killer", ""))
		if killer != want_killer:
			f.append("leg B: the payload's killer is '%s', want '%s'" % [killer, want_killer])
	_drop(world)


## The producer's row is the screen's row: purse, charges and the killer name must land.
## screen_data() writes "purse"; the screen renders centi and used to read "purse_centi"
## only, so a wired run printed PURSE 0.00 g whatever the player held.
func _screen_leg(f: Array[String], world) -> void:
	var ro = RunOverScript.new()
	ro.show_run_over(DeathScript.screen_data(world.ctl, 7, 14900))
	if int(ro.purse_centi) != 14900:
		f.append("screen: purse_centi is %d from screen_data's row, want 14900"
				% int(ro.purse_centi))
	if str(ro._purse_label.text) != "PURSE 149.00 g":
		f.append("screen: the purse line reads '%s', want 'PURSE 149.00 g'"
				% str(ro._purse_label.text))
	if str(ro._code_label.text) != DeathScript.VOID_CODE:
		f.append("screen: the code line reads '%s', want '%s'"
				% [str(ro._code_label.text), DeathScript.VOID_CODE])
	if str(ro.killer_text) != RunOverScript.VOID_DISPLAY:
		f.append("screen: a void death reads '%s' as the killer, want '%s'"
				% [str(ro.killer_text), RunOverScript.VOID_DISPLAY])
	# an untracked purse (screen_data's -1 default) renders as 0.00, never as a negative
	ro.show_run_over(DeathScript.screen_data(world.ctl, 7))
	if int(ro.purse_centi) != 0:
		f.append("screen: an untracked purse rendered as %d, want 0" % int(ro.purse_centi))
	ro.free()


## Leg C: the shipped app's own wiring, MENU -> LOADING -> WORLD -> RUN_OVER -> MENU.
func _leg_c_app(f: Array[String]) -> void:
	var app = AppScript.new()
	# I4: a test must never ratchet the player's real user://records.json. Point the store at a
	# scratch file before _ready loads it.
	app.records_path = "user://test_app_death_scratch.json"
	# J1: Play draws a fresh seed per run; pin seed 1 (this leg's documented input) so the suite
	# is deterministic. Before _ready there is no menu, so start_run only stores the seed and the
	# run below still goes through the real play_requested path.
	app.start_run(SEED_A)
	app._ready()   # the tree is unavailable under --headless --script (test_app_flow)
	if app._menu == null:
		f.append("leg C: the app created no menu")
		app.free()
		return
	app._menu.play_requested.emit()
	if app.run_seed() != SEED_A:
		f.append("leg C: the run used seed %d, want the pinned %d" % [app.run_seed(), SEED_A])
	var loading = app._loading
	var guard := 0
	while app.state() == "LOADING" and loading != null and guard < 400:
		loading.advance(0.25)
		guard += 1
	if app.state() != "WORLD":
		f.append("leg C: the app never reached WORLD (state=%s after %d advances)"
				% [app.state(), guard])
		app.free()
		return
	var world = app._world
	if world == null:
		f.append("leg C: the app has no world in WORLD")
		app.free()
		return
	# the kill: a void fall with no charge left, through world.step() as the app would
	world.ctl.charges = 0
	_fall_over_the_void(world)
	if not bool(world.ctl.dead):
		f.append("leg C: the void fall with no charge left did not kill the player")
	if app.state() != "RUN_OVER":
		f.append("leg C: the app is in %s after the death tick, want RUN_OVER" % app.state())
	# the dead run is not stepped any more even where a frame is offered
	var tick_at_death: int = int(world.lstate.tick)
	app._process(DT)
	if int(world.lstate.tick) != tick_at_death:
		f.append("leg C: the app kept stepping the dead world (%d -> %d)"
				% [tick_at_death, int(world.lstate.tick)])
	# the HUD black-out starts on the death tick, the screen opens when it lands
	if not world.hud.screen_fx.blackout_active():
		f.append("leg C: the HUD death black-out never started")
	world.hud.screen_fx.advance(ScreenFxScript.BLACKOUT_TICKS)
	if app._run_over == null:
		f.append("leg C: no run-over screen after the black-out (blackout_finished unhandled)")
	else:
		if not bool(app._run_over.visible):
			f.append("leg C: the run-over screen is not visible")
		if str(app._run_over.code) != DeathScript.VOID_CODE:
			f.append("leg C: the screen's code is '%s', want '%s'"
					% [str(app._run_over.code), DeathScript.VOID_CODE])
		if str(app._run_over.killer_text) != RunOverScript.VOID_DISPLAY:
			f.append("leg C: the screen's killer is '%s', want '%s'"
					% [str(app._run_over.killer_text), RunOverScript.VOID_DISPLAY])
		var purse_at_death: int = int(world._economy.purse_centi)
		if int(app._run_over.purse_centi) != purse_at_death:
			f.append("leg C: the screen's purse is %d, want the dead run's %d"
					% [int(app._run_over.purse_centi), purse_at_death])
		# retry: the dead run is torn down and the SAME seed starts again, straight into
		# LOADING -> WORLD. The menu is never shown - gap 22: Retry must retry, not bounce
		# the player back to the title screen and make them press PLAY again.
		app._run_over.retried.emit()
		if app.state() != "LOADING" and app.state() != "WORLD":
			f.append("leg C: retry left the app in %s, want LOADING or WORLD" % app.state())
		if is_instance_valid(world):
			f.append("leg C: retry did not release the dead world")
		if app._run_over != null:
			f.append("leg C: retry did not release the run-over screen")
		if app._menu != null and app._menu.visible:
			f.append("leg C: retry showed the menu; it must go straight back into the run")
		if app.run_seed() != SEED_A:
			f.append("leg C: retry used seed %d, want the same seed %d"
					% [app.run_seed(), SEED_A])
	app.free()


## Drop the player over the void, past the kill plane: the controller's own fall path
## (y < kill_plane_y inside step()). One step is one fall; the respawn wait is cleared so
## the next call lands a second time instead of riding the pending respawn.
func _fall_over_the_void(world) -> void:
	var ctl = world.ctl
	ctl.respawn_t = -1.0
	ctl.invuln = 0.0
	ctl.x = -500.0   # over the void: no column underfoot
	ctl.y = -41.0    # already past the kill plane (-40.0)
	ctl.z = 0.0
	ctl.vy = -1.0
	ctl.grounded = false
	world.step(DT)


func _drop(world) -> void:
	world.teardown()
	world.free()
