extends RefCounted
#
# Curse requires_enemy proof (FIX-A14; D-FIX-A14-3).
#
# Every curse's requires_enemy is either null (general pool) or the id of a real enemy in
# the content tree - so the enemy-linked pool can never name an id that cannot be offered,
# whatever the curse schema allows (the schema pattern-checks the shape; the registry and
# this test check the referent). Also asserts the boot itself is clean: a curse whose
# requires_enemy does not resolve would have refused the boot, which is the load-time half
# of the same rule.

const ContentApiScript := preload("res://core/content_api.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	var api: RefCounted = ContentApiScript.load()
	if not bool(api.call("is_ok")):
		for line in api.call("boot_errors"):
			failures.append("boot refused: %s" % str(line))
		return failures
	var enemy_ids: Array = api.call("enemy_ids")
	for raw in api.call("curse_ids"):
		var id := str(raw)
		var c: Dictionary = api.call("curse", id)
		var req: Variant = c.get("requires_enemy")
		if req == null:
			continue
		var req_id := str(req)
		if not enemy_ids.has(req_id):
			failures.append("%s: requires_enemy '%s' names no enemy id in content/enemies/ (the curse can never be offered)" % [id, req_id])
	return failures
