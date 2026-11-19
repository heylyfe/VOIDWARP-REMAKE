extends RefCounted
#
# ANTECHAMBER ENEMY EXHIBITS test (headless).
#
# The lobby builds one exhibit per enemy it can show, and every exhibit parses that
# enemy's sprites.json and scales the body to ENEMY_BODY_H. The T-016 schema stores
# `world_height` as JSON null where DESIGN.md section 5 gives the enemy no body row
# (nuke and gift_larper are the two), and Dictionary.get() only falls back to its
# default when the key is ABSENT - so `float(doc.get("world_height", 1.0))` threw
# "Invalid call. Nonexistent 'float' constructor" and aborted the exhibit function
# on every lobby build. The exhibit still appeared (the billboard is added before
# the throw) but its name came back empty and the scale was never applied.
#
# This leg builds the exhibit for EVERY registered enemy and asserts a non-empty
# name comes back. With the unguarded float() the nuke exhibit returns "" and this
# fails; with the type-checked read it returns "nuke". That is the negative control.

const ContentApiScript := preload("res://core/content_api.gd")
const AntechamberScript := preload("res://view/lobby/antechamber.gd")
const IntermissionScript := preload("res://sim/intermission.gd")
const BillboardScript := preload("res://view/billboard.gd")


func run() -> Array[String]:
	var f: Array[String] = []
	var api: RefCounted = ContentApiScript.load()
	if not bool(api.call("is_ok")):
		f.append("exhibits: content boot failed: %s" % " / ".join(api.call("boot_errors")))
		return f
	var ids: Array = api.call("enemy_ids")
	if ids.is_empty():
		f.append("exhibits: no enemies registered - the leg proves nothing")
		return f
	var hall = AntechamberScript.new()
	hall.lobby = IntermissionScript.create(api, 0, 0, 99)
	var built := 0
	for id in ids:
		var anchor := Node3D.new()
		var shown: String = hall._exhibit_enemy(anchor, {"id": str(id), "name": str(id), "votes": 0})
		if shown.strip_edges() == "":
			f.append("exhibits: enemy '%s' returned an empty exhibit name - the exhibit function aborted (a null world_height reaching float()?)" % str(id))
		if anchor.get_child_count() != 1:
			f.append("exhibits: enemy '%s' put %d children on the anchor, want 1 (the billboard)" % [str(id), anchor.get_child_count()])
		elif not (anchor.get_child(0) is BillboardScript):
			f.append("exhibits: enemy '%s' exhibit child is %s, want the billboarded PNG sprite" % [str(id), anchor.get_child(0).get_class()])
		built += 1
		anchor.free()
	if built != ids.size():
		f.append("exhibits: built %d of %d exhibits" % [built, ids.size()])
	# The specific case that used to throw: a sheet whose world_height is JSON null.
	# Read sprites.json directly - _enemy_doc returns enemy.json, which has no
	# world_height key at all.
	var null_ids: Array[String] = []
	for id in ids:
		var sheet := "res://content/enemies/%s/sprites.json" % str(id)
		if not FileAccess.file_exists(sheet):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sheet))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var doc: Dictionary = parsed
		if doc.has("world_height") and doc["world_height"] == null:
			null_ids.append(str(id))
	if null_ids.is_empty():
		f.append("exhibits: no enemy declares a null world_height - the regression this leg guards is no longer reachable, so the leg proves nothing")
	else:
		for id in null_ids:
			var anchor2 := Node3D.new()
			var shown2: String = hall._exhibit_enemy(anchor2, {"id": id, "name": id, "votes": 0})
			if shown2.strip_edges() == "":
				f.append("exhibits: the null-world_height enemy '%s' returned an empty name" % id)
			anchor2.free()
	hall.free()
	return f
