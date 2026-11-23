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

const WorldScript := preload("res://app/world.gd")

const DT := 1.0 / 60.0

var _seed := 1
var _level := 1
var _ticks := 90
var _mode := "each"
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
		i += 1


func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var world := WorldScript.new()
	get_root().add_child(world)
	var ok := bool(world.build(_seed, _level, {}))
	print("REPRO build seed=%d level=%d ok=%s mode=%s" % [_seed, _level, str(ok), _mode])
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
