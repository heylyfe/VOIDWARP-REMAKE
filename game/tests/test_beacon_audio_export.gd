extends SceneTree
# Export Windows Desktop, then copy this script to probe.gd in an empty project
# (a directory containing a project.godot with config_version=5). Run:
# godot --headless --path <empty-project> --script res://probe.gd -- <absolute-export-path>
# Isolation prevents source files masking the pack; the argument may be an exe or PCK.

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures := 0
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not ProjectSettings.load_resource_pack(args[0]):
		print("FAIL: could not mount exported pack")
		quit(1)
		return
	var path := "res://assets/audio/world/beacon_open.mp3"
	if FileAccess.file_exists(path) or not ResourceLoader.exists(path):
		print("FAIL: fixture must expose the imported resource without its raw file")
		failures += 1
	var audio = load("res://view/audio/beacon_audio.gd")
	if audio == null:
		print("FAIL: beacon audio script missing from export")
		quit(failures + 1)
		return
	var host := Node.new()
	root.add_child(host)
	var player: AudioStreamPlayer = audio.play_open(host)
	if player == null or not player.playing:
		print("FAIL: packed beacon cue did not start")
		failures += 1
	if audio._play_path(host, "res://missing_beacon_cue.mp3") != null:
		print("FAIL: missing cue unexpectedly started")
		failures += 1
	host.free()
	print("EXPORT BEACON failures=", failures)
	quit(failures)
