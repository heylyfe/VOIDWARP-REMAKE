extends SceneTree

# Headless terrain hash tool:
#   tools\godot\godot.exe --headless --path game --script res://tools/terrain_hash.gd -- <seed> <level> [players] [extra_mines]
# Prints exactly one line: HASH <seed> <level> <hash>

const VoidGenScript := preload("res://terrain/voidgen.gd")


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("HASH 0 0 USAGE: seed level [players] [extra_mines]")
		quit(1)
		return
	var sd: int = int(args[0])
	var lv: int = int(args[1])
	var players: int = int(args[2]) if args.size() > 2 else 1
	var extra: int = int(args[3]) if args.size() > 3 else 0
	var L: Dictionary = VoidGenScript.generate(sd, lv, players, extra)
	if L.is_empty():
		print("HASH %d %d GEN_FAILED" % [sd, lv])
		quit(1)
		return
	print("HASH %d %d %s" % [sd, lv, VoidGenScript.level_hash(L)])
	quit(0)
