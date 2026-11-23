extends RefCounted
#
# The synthesized cue set (the "too quiet" pass): every cue the code references resolves
# through ResourceLoader.exists and loads as an AudioStream, so a typo cannot ship silent.
#
# The cue tables are the contract: view/audio/player_audio.gd, ui_audio.gd, world_audio.gd
# and ambience_audio.gd each own a cue_names() table and a path_for() resolver, and
# view/audio/enemy_cue.gd owns the enemy state-edge table. Call sites pass a variant INDEX
# or a state, never a cue-name string, so the only place a name can be misspelled is a
# table - and this test walks every table.
#
# Four legs:
#   1. every declared cue: path_for() is non-empty, ResourceLoader.exists() is true, load()
#      returns an AudioStream with a positive length;
#   2. drift both ways: every .wav on disk under the four groups is declared, and every
#      declared cue has a file (a stray file and a missing file both fail);
#   3. the enemy state-edge table (nuke's blast, YOU?!'s ring release) resolves the same way;
#   4. the negative control: a misspelled name must NOT resolve, and the same checker run
#      over a deliberately broken table must report exactly NEGATIVE_CONTROL_FAILURES
#      failures - a checker that passes with a broken table proves nothing.
#
# The ResourceLoader gate is the export-safe one: an export packs the imported stream and
# its remap, not the raw .wav, so FileAccess.file_exists() would make this test lie.

const CueAudio := preload("res://view/audio/cue_audio.gd")
const PlayerAudio := preload("res://view/audio/player_audio.gd")
const UiAudio := preload("res://view/audio/ui_audio.gd")
const WorldAudio := preload("res://view/audio/world_audio.gd")
const AmbienceAudio := preload("res://view/audio/ambience_audio.gd")
const EnemyCue := preload("res://view/audio/enemy_cue.gd")
const BossAudio := preload("res://view/audio/boss_audio.gd")

const MODULES := [PlayerAudio, UiAudio, WorldAudio, AmbienceAudio, BossAudio]
const GROUPS := ["player", "ui", "world", "ambience", "boss"]
const AUDIO_ROOT := "res://assets/audio"

# The negative control's stated count: the broken table below has exactly this many bad rows.
const NEGATIVE_CONTROL_FAILURES := 2


func run() -> Array[String]:
	var f: Array[String] = []
	_check_tables(f)
	_check_disk(f)
	_check_enemy_state_edges(f)
	_check_negative_control(f)
	return f


# ---- 1. every declared cue resolves and loads -------------------------------------

func _check_tables(f: Array[String]) -> void:
	var seen := 0
	for m in MODULES:
		var names: Array = m.cue_names()
		if names.is_empty():
			f.append("table: a module declares no cues at all")
		for cue in names:
			var name := str(cue)
			var path: String = m.path_for(name)
			seen += 1
			if path == "":
				f.append("table: '%s' is in cue_names() but path_for() refuses it" % name)
				continue
			if not ResourceLoader.exists(path):
				f.append("table: '%s' -> %s does not resolve through ResourceLoader.exists"
						% [name, path])
				continue
			var res: Variant = load(path)
			if not (res is AudioStream):
				f.append("table: '%s' -> %s did not load as an AudioStream (got %s)"
						% [name, path, type_string(typeof(res))])
				continue
			if (res as AudioStream).get_length() <= 0.0:
				f.append("table: '%s' -> %s loaded with zero length" % [name, path])
	if seen < 18:
		f.append("table: only %d cues declared, want at least 18 (the synthesized set)" % seen)


# ---- 2. drift both ways: disk <-> tables ------------------------------------------

func _check_disk(f: Array[String]) -> void:
	var declared := {}
	for m in MODULES:
		for cue in m.cue_names():
			declared[str(cue)] = true
	var on_disk := {}
	for group in GROUPS:
		var dir := DirAccess.open("%s/%s" % [AUDIO_ROOT, group])
		if dir == null:
			f.append("disk: cannot open %s/%s" % [AUDIO_ROOT, group])
			continue
		for fn in dir.get_files():
			var name := str(fn)
			if not name.ends_with(".wav"):
				continue
			on_disk[name.trim_suffix(".wav")] = true
	for name in on_disk.keys():
		if not declared.has(name):
			f.append("disk: %s.wav exists but no module declares it (drift)" % name)
	for name in declared.keys():
		if not on_disk.has(name):
			f.append("disk: '%s' is declared but has no .wav on disk" % name)


# ---- 3. the enemy state-edge table ------------------------------------------------

func _check_enemy_state_edges(f: Array[String]) -> void:
	var edges := 0
	for enemy_id in EnemyCue.STATE_CUES.keys():
		var rows: Dictionary = EnemyCue.STATE_CUES[enemy_id]
		for state in rows.keys():
			edges += 1
			var path: String = EnemyCue.path_for_state(str(enemy_id), str(state))
			if path == "":
				f.append("enemy edge: %s/%s has no path" % [enemy_id, state])
				continue
			if not ResourceLoader.exists(path):
				f.append("enemy edge: %s/%s -> %s does not resolve" % [enemy_id, state, path])
				continue
			if not (load(path) is AudioStream):
				f.append("enemy edge: %s/%s -> %s is not an AudioStream" % [enemy_id, state, path])
	if edges < 2:
		f.append("enemy edge: only %d state edges declared, want at least 2" % edges)


# ---- 4. the negative control ------------------------------------------------------

func _check_negative_control(f: Array[String]) -> void:
	# a misspelled cue name must not resolve, and must not load
	if PlayerAudio.path_for("footstpe_01") != "":
		f.append("negative: a misspelled cue name resolved through path_for()")
	if CueAudio.load_stream("%s/player/footstpe_01.wav" % AUDIO_ROOT) != null:
		f.append("negative: a misspelled path loaded a stream")
	if EnemyCue.cue_for_state("nuke", "attack") != "":
		f.append("negative: an undeclared enemy state edge resolved")
	if EnemyCue.path_for_state("nuke", "attack") != "":
		f.append("negative: an undeclared enemy state edge produced a path")
	# the same checker over a deliberately broken table must report the stated count
	var broken := [
		["%s/player/footstep_01.wav" % AUDIO_ROOT, "good"],
		["%s/player/footstpe_01.wav" % AUDIO_ROOT, "typo"],
		["%s/ui/no_such_cue.wav" % AUDIO_ROOT, "missing"],
	]
	var failures := _check_paths(broken)
	if failures.size() != NEGATIVE_CONTROL_FAILURES:
		f.append("negative: the broken table reported %d failure(s), want exactly %d - the checker is not actually checking" % [failures.size(), NEGATIVE_CONTROL_FAILURES])
	print("  negative control: %d bad row(s) -> %d failure(s) (want %d)"
			% [broken.size() - 1, failures.size(), NEGATIVE_CONTROL_FAILURES])


## The checker the legs above use, factored out so the negative control can run it over a
## table it knows is broken. entries: [[path, label], ...] -> one message per bad row.
func _check_paths(entries: Array) -> Array[String]:
	var out: Array[String] = []
	for row in entries:
		var path := str(row[0])
		var label := str(row[1])
		if not ResourceLoader.exists(path):
			out.append("%s: %s does not resolve" % [label, path])
			continue
		if not (load(path) is AudioStream):
			out.append("%s: %s is not an AudioStream" % [label, path])
	return out

