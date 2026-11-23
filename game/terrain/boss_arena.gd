extends RefCounted
## The arena uses the ordinary packed tile format. Construction is pure and separate
## from voidgen so the generated terrain, parity fixtures and level seed stay intact.

static func build(level: Dictionary, config: Dictionary) -> Dictionary:
	var arena: Dictionary = config["arena"]
	var extent := int(arena["half_extent_tiles"])
	var height := int(arena["floor_height"])
	var result := level.duplicate(false)
	var tiles: Array = []
	for x in range(-extent, extent + 1):
		for z in range(-extent, extent + 1):
			tiles.append([x, z, height, 0, 0, 0])
	result["tiles"] = tiles
	result["pieces"] = [{"id": 0, "kind": 0, "role": 0, "arch": "flat",
		"bbox": [-extent, -extent, extent, extent], "tiles": tiles.size(), "jumps": 0, "w": extent * 2 + 1}]
	for key in ["props", "pads", "jump_pads", "gifts", "cut_edges", "links"]:
		result[key] = []
	result["beacon"] = [0, int(arena["beacon_z"]), height]
	result["arena_spawn"] = [0, int(arena["spawn_z"]), height]
	result["arena_boss"] = [0, int(arena["boss_z"]), height]
	return result
