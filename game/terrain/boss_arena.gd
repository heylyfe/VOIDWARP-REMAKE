extends RefCounted
## The arena uses the ordinary packed tile format. Construction is pure and separate
## from voidgen so the generated terrain, parity fixtures and level seed stay intact.

const Terrain := preload("res://terrain/voidgen.gd")


static func build(level: Dictionary, config: Dictionary) -> Dictionary:
	var arena: Dictionary = config["arena"]
	var extent := int(arena["half_extent_tiles"])
	var height := int(arena["floor_height"])
	var result := level.duplicate(false)
	var tiles: Array = []
	for x in range(-extent, extent + 1):
		for z in range(-extent, extent + 1):
			tiles.append([x, z, height, 0, 0])
	result["tiles"] = tiles
	result["pieces"] = [{"id": 0, "kind": 0, "role": Terrain.ROLE_ROOM, "arch": "flat",
		"parent": -1, "depth": 0, "arm": -1, "y": height,
		"bbox": [-extent, -extent, extent, extent], "tiles": tiles.size(), "jumps": 0, "w": extent * 2 + 1}]
	for key in ["props", "pads", "gifts", "edges", "anchors", "arms"]:
		result[key] = []
	result["beacon"] = [0, int(arena["beacon_z"]), height]
	result["arena_spawn"] = [0, int(arena["spawn_z"]), height]
	result.erase("jump_pads")
	result["spawns"] = [result["arena_spawn"]]
	result["arena_boss"] = [0, int(arena["boss_z"]), height]
	return result
