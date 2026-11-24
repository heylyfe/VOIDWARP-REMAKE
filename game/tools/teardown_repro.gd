extends SceneTree
#
# teardown_repro.gd - the minimal headless reproduction for Terra's finding 5 (U4).
#
# Terra: running the suite prints, during world.teardown(),
#
#   ERROR: Parameter "material" is null.
#      at: material_get_instance_shader_parameters (servers/rendering/dummy/storage/material_storage.cpp:264)
#      [0] teardown (res://app/world.gd:1423)        <- for child in get_children(): child.free()
#
# This tool isolates WHICH child of the world triggers it: it builds one level, makes the
# views live, then frees the world's children ONE AT A TIME, printing each child's name and
# class immediately before the free. The child printed immediately above an ERROR line is
# the one that triggered it.
#
#   <godot> --headless --path game --script res://tools/teardown_repro.gd -- \
#       [--seed S] [--level N] [--ticks N] [--mode each|teardown]
#
#   --mode each      (default) free the children one by one with the attribution print.
#   --mode teardown  call world.teardown() exactly as the game does; used to count the
#                    error lines over one known-good command (the before/after proof).
#   --complete       drive the level to beacon completion first (all real gifts, then the
#                    beacon tile) - the state the suite is in when Terra's finding fires:
#                    the gold phase and the completion views exist at teardown time.
#   --transition     build level N, step, COMPLETE it, then build level N+1 with the same
#                    world - the app's real level transition, whose build() calls
#                    teardown() on the live level - then teardown() once more. This is the
#                    command the before/after error count is taken over.

const WorldScript := preload("res://app/world.gd")
const ContentApiScript := preload("res://core/content_api.gd")

const DT := 1.0 / 60.0

var _seed := 1
var _level := 1
var _ticks := 90
var _mode := "each"
var _complete := false
var _votes := false
var _transition := false
var _ran := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := str(args[i])
		match a:
			"--seed":
				i += 1
				_seed = int(args[i])
			"--level":
				i += 1
				_level = int(args[i])
			"--ticks":
				i += 1
				_ticks = int(args[i])
			"--mode":
				i += 1
				_mode = str(args[i])
			"--complete":
				_complete = true
			"--votes":
				_votes = true
			"--transition":
				_transition = true
		i += 1


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var world := WorldScript.new()
	# NOT added to the root: the suite's tests build their worlds out of tree, and the
	# finding reproduces in exactly that shape (an out-of-tree instance never enters a
	# scenario, so its RS update path differs from the in-tree game's).
	var ledger := {}
	if _votes:
		ledger = _all_votes_ledger()
	var ok := bool(world.build(_seed, _level, ledger))
	print("REPRO build seed=%d level=%d ok=%s mode=%s complete=%s votes=%s"
		% [_seed, _level, str(ok), _mode, str(_complete), str(_votes)])
	for t in _ticks:
		world.step(DT, {"move_x": 1, "move_z": 0, "buttons": 0, "app": 0})
	if _complete or _transition:
		_complete_level(world)
	if _transition:
		# The app's real transition: the next level's build() calls teardown() on the
		# live, completed level (the path Terra's finding backtraces show), then this
		# tool tears the second level down too.
		var ledger2 := _all_votes_ledger() if _votes else {}
		var ok2 := bool(world.build(_seed, _level + 1, ledger2))
		print("REPRO transition build seed=%d level=%d ok=%s" % [_seed, _level + 1, str(ok2)])
		for t in _ticks:
			world.step(DT, {"move_x": 1, "move_z": 0, "buttons": 0, "app": 0})
	var kids := world.get_children()
	print("REPRO children=%d" % kids.size())
	if _mode == "teardown":
		world.teardown()
		print("REPRO freed via teardown")
	else:
		for child in kids:
			if not is_instance_valid(child):
				continue
			print("REPRO free name=%s class=%s script=%s"
				% [child.name, child.get_class(), _script_of(child)])
			child.free()
		print("REPRO freed one by one")
	world.free()
	print("REPRO DONE")
	quit(0)


func _script_of(node: Node) -> String:
	var s: Script = node.get_script()
	if s == null:
		return "-"
	return str(s.resource_path).trim_prefix("res://")


## Every registry enemy id at 1 vote, the way the crash sweep's --vote-mode all does it,
## so the level carries the enemy views (billboards, clawds, Gin) the suite's failing tests
## build before they tear down.
func _all_votes_ledger() -> Dictionary:
	var out := {}
	var api: RefCounted = ContentApiScript.load()
	if api == null or not api.is_ok():
		return {}
	for id in api.enemy_ids():
		out[str(id)] = 1
	return {"class": "dasher", "votes": out, "curses": {}, "stacks": {},
		"purse": 300, "tithes": 0, "hunger": 0, "last_vote": ""}


## Drive the level to beacon completion, the way test_app_loop.gd's leg A does: teleport
## the controller onto every real gift (black -> gold phase) and then into the beacon, one
## world.step() per stop. The completion views (gold phase, beacon open) then exist, which
## is the state the suite tears down in when the finding fires.
func _complete_level(world: Node) -> void:
	var g = world.get("lstate").get("gifts")
	for i in g.slots.size():
		if not g.is_real(i):
			continue
		var pos: Vector3 = g.slot_pos(i)
		world.get("ctl").set("x", pos.x)
		world.get("ctl").set("y", pos.y - 1.0)
		world.get("ctl").set("z", pos.z)
		world.get("ctl").set("vy", 0.0)
		world.step(DT, {"move_x": 0, "move_z": 0, "buttons": 0, "app": 0})
	var bp: Array = world.get("lv")["beacon"]
	world.get("ctl").set("x", float(int(bp[0])) + 0.5)
	world.get("ctl").set("y", float(int(bp[2])) * 0.5)
	world.get("ctl").set("z", float(int(bp[1])) + 0.5)
	world.get("ctl").set("vy", 0.0)
	world.step(DT, {"move_x": 0, "move_z": 0, "buttons": 0, "app": 0})
	print("REPRO completed=%s gold_phase=%s"
		% [str(world.is_complete()), str(world.get("lstate").get("gifts").get("phase"))])
