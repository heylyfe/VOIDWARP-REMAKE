extends SceneTree
func _init() -> void:
	var name := OS.get_environment("ONE_TEST")
	var t = load("res://tests/%s.gd" % name).new()
	var fails: Array = t.run()
	print("FAILS %d" % fails.size())
	for x in fails:
		print("  - " + str(x))
	quit(0)
