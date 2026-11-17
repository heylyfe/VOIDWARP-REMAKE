extends RefCounted
#
# Altar panel counter-play text test (DESIGN.md section 11; ticket T-076).
#
# Proves every line the enemy altar panel renders for an enemy is VERBATIM from DESIGN.md:
#   - the enemy.json top-level "tell" and "counter_play" strings (the lines altar_details()
#     appends to every enemy panel) are substrings of DESIGN.md once both are normalised
#     (markdown emphasis markers ** and ` stripped, all whitespace collapsed);
#   - altar_details() itself renders exactly those strings (a hostile panel cannot pass
#     by shipping different text than the data the check reads);
#   - data/tips.json carries >= 18 tips (owner spec), >= 8 tagged hazard_tell, unique ids,
#     and the five named T-076 tips (tip_hurdle, tip_seal_bark, tip_ben_launch,
#     tip_void_dive, tip_last_light_dim).
#
# Headless, outside the scene tree, like the other lobby tests: a real Antechamber with a
# stubbed lobby (only the members altar_details() reads) is enough to get the panel lines.

const ContentApiScript := preload("res://core/content_api.gd")
const Antechamber := preload("res://view/lobby/antechamber.gd")

const ENEMY_IDS := ["kiwi_cat", "coil", "thicc_ben", "isagi", "nuke", "you",
		"gift_larper", "toucher", "seal", "address_me", "claude", "gin"]


class StubLobby extends RefCounted:
	var bays: Array = []
	var content: RefCounted = null
	var tithes: int = 0
	var stamp: int = 1


func run() -> Array[String]:
	var f: Array[String] = []
	var design := _design_text()
	if design == "":
		f.append("DESIGN.md not found at the repo root (res://../DESIGN.md)")
		return f
	var norm_design := _norm(design)
	var api: RefCounted = ContentApiScript.load()
	if not bool(api.call("is_ok")):
		f.append("content api boot failed: %s" % " / ".join(api.call("boot_errors")))
		return f
	for eid in ENEMY_IDS:
		_enemy_lines(f, api, eid, norm_design)
	_tips_pool(f)
	return f


# ---- the per-enemy panel lines, verbatim against DESIGN.md ----------------------
func _enemy_lines(f: Array[String], api: RefCounted, eid: String,
		norm_design: String) -> void:
	var path := "res://content/enemies/%s/enemy.json" % eid
	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		f.append("%s: cannot read %s" % [eid, path])
		return
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		f.append("%s: enemy.json does not parse" % eid)
		return
	var doc: Dictionary = parsed
	var tell := str(doc.get("tell", ""))
	var answer := str(doc.get("counter_play", ""))
	if tell.strip_edges() == "":
		f.append("%s: top-level tell is missing or empty (the panel renders a blank tell line)" % eid)
	if answer.strip_edges() == "":
		f.append("%s: top-level counter_play is missing or empty (the panel renders a blank answer line)" % eid)
	if tell.strip_edges() != "" and not norm_design.contains(_norm(tell)):
		f.append("%s: tell is not verbatim from DESIGN.md: '%s'" % [eid, tell])
	if answer.strip_edges() != "" and not norm_design.contains(_norm(answer)):
		f.append("%s: counter_play is not verbatim from DESIGN.md: '%s'" % [eid, answer])
	# the panel itself renders exactly those strings
	var stub := StubLobby.new()
	stub.content = api
	stub.bays = [{
		"kind": "E",
		"altars": [{"id": eid, "votes": 1, "name": str(doc.get("name", eid))}],
	}]
	var hall := Antechamber.new()
	hall.lobby = stub
	var lines: Array = hall.altar_details(stub, 0, 0, "E")
	if not lines.has(tell):
		f.append("%s: altar_details() does not render the tell line verbatim: %s" % [eid, str(lines)])
	if not lines.has(answer):
		f.append("%s: altar_details() does not render the counter_play line verbatim: %s" % [eid, str(lines)])
	hall.free()


# ---- the tip pool ---------------------------------------------------------------
func _tips_pool(f: Array[String]) -> void:
	var path := "res://data/tips.json"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		f.append("tips: data/tips.json does not parse")
		return
	var tips: Array = (parsed as Dictionary).get("tips", [])
	if tips.size() < 18:
		f.append("tips: data/tips.json has %d tips, want >= 18 (owner spec)" % tips.size())
	var hazard := 0
	var seen := {}
	for tip in tips:
		var t: Dictionary = tip
		for key in ["id", "text", "tags", "source"]:
			if not t.has(key):
				f.append("tips: tip %s has no '%s'" % [str(t.get("id", "?")), key])
		var id := str(t.get("id", ""))
		if seen.has(id):
			f.append("tips: duplicate tip id '%s'" % id)
		seen[id] = true
		if (t.get("tags", []) as Array).has("hazard_tell"):
			hazard += 1
	if hazard < 8:
		f.append("tips: only %d hazard_tell tips, want >= 8 (owner spec)" % hazard)
	for named in ["tip_hurdle", "tip_seal_bark", "tip_ben_launch", "tip_void_dive", "tip_last_light_dim"]:
		if not seen.has(named):
			f.append("tips: the named T-076 tip '%s' is missing" % named)


# ---- normalisation: strip markdown emphasis markers, collapse whitespace --------
func _norm(s: String) -> String:
	var t := s.replace("**", "").replace("`", "")
	var re := RegEx.new()
	re.compile("\\s+")
	t = re.sub(t, " ", true)
	return t.strip_edges()


func _design_text() -> String:
	var game_dir := ProjectSettings.globalize_path("res://")
	var path := game_dir.path_join("..").simplify_path().path_join("DESIGN.md")
	return FileAccess.get_file_as_string(path)
