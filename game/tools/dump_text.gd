extends SceneTree

# Dumps the canonical to_text output for (seed, level, players, extra_mines) to a file so it
# can be diffed against `python terrain_ref/voidgen.py --seed S --level L --players P [--extra-mines E] --text file`.
#   tools\godot\godot.exe --headless --path game --script res://tools/dump_text.gd -- <seed> <level> <out_path> [players] [extra_mines]

const VoidGenScript := preload("res://terrain/voidgen.gd")


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var nums: Array = []
	var out_path: String = ""
	for a in args:
		if a.is_valid_int():
			nums.append(int(a))
		else:
			out_path = a
	if out_path == "" or nums.size() < 2:
		print("USAGE: dump_text.gd -- <seed> <level> <out_path> [players] [extra_mines]")
		quit(1)
		return
	var sd: int = nums[0]
	var lv: int = nums[1]
	var players: int = nums[2] if nums.size() > 2 else 1
	var extra: int = nums[3] if nums.size() > 3 else 0
	var L: Dictionary = VoidGenScript.generate(sd, lv, players, extra)
	if L.is_empty():
		print("GEN_FAILED seed=%d level=%d" % [sd, lv])
		quit(1)
		return
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		print("CANNOT_OPEN %s" % out_path)
		quit(1)
		return
	f.store_string(VoidGenScript.to_text(L))
	f.close()
	print("WROTE %s hash=%s" % [out_path, VoidGenScript.level_hash(L)])
	quit(0)
