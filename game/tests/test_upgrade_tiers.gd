extends RefCounted
#
# Upgrade tiers vs levels vs prices (cycle 4 item 15, the owner's balance complaint: "no
# end-game upgrade at level 2"). DESIGN.md section 8's price-tier table is the bar; its one
# machine-readable copy is data/upgrade_pools.json "tiers" (D-C4-15-1). Proves:
#   1. the data tier table equals DESIGN.md section 8 (bands + pool-from levels), the bands
#      are disjoint and ascending, and pool-from levels ascend - loosening the data to fit
#      an upgrade fails here first;
#   2. every upgrade's list price sits inside its tier's band;
#   3. no bracket in the data lists an id whose tier has not entered the pool at the
#      bracket's min_level (a raw-data check: shop_pool() would hide the defect);
#   4. shop_pool(level) never holds an id before its tier's pool-from level, levels 0..60;
#   5. draw_shop() - the real shop - never OFFERS one: every level 0..32, every class,
#      purses from broke to rich, several seeds (the affordability fill included);
#   6. README.md's upgrade table equals tools/upgrade_table.gd's output, byte for byte.

const ContentApiScript := preload("res://core/content_api.gd")
const OffersScript := preload("res://sim/offers.gd")
const VoidRngScript := preload("res://terrain/void_rng.gd")
const TableScript := preload("res://tools/upgrade_table.gd")

# DESIGN.md section 8 "Price tiers and when they enter the pool" [CANON]: [pool_from, min, max].
const CANON_TIERS := {
	"T1": [1, 40, 80], "T2": [4, 120, 200], "T3": [10, 280, 400],
	"T4": [18, 550, 800], "T5": [26, 1100, 1500],
}
const TIER_ORDER: Array[String] = ["T1", "T2", "T3", "T4", "T5"]


func run() -> Array[String]:
	var f: Array[String] = []
	var api: RefCounted = ContentApiScript.load()
	if not api.is_ok():
		f.append("content api boot failed: %s" % " / ".join(api.boot_errors()))
		return f
	_tier_table(f, api)
	_price_bands(f, api)
	_raw_brackets(f, api)
	_shop_pool_gate(f, api)
	_draw_shop_gate(f, api)
	_readme_table(f, api)
	return f


func _tier_table(f: Array[String], api: RefCounted) -> void:
	var tiers: Dictionary = api.tiers()
	for t in TIER_ORDER:
		var row: Dictionary = tiers.get(t, {})
		var want: Array = CANON_TIERS[t]
		var got := [int(row.get("pool_from", -1)), int(row.get("price_min", -1)), int(row.get("price_max", -1))]
		if got != want:
			f.append("tiers.%s = [pool_from, min, max] %s, DESIGN.md section 8 says %s" % [t, str(got), str(want)])
		if int(api.TIER_FROM.get(t, -1)) != int(want[0]):
			f.append("api.TIER_FROM[%s] = %s, the data says %d" % [t, str(api.TIER_FROM.get(t)), int(want[0])])
	for i in range(1, TIER_ORDER.size()):
		var lo: Dictionary = tiers.get(TIER_ORDER[i - 1], {})
		var hi: Dictionary = tiers.get(TIER_ORDER[i], {})
		if int(lo.get("price_max", 0)) >= int(hi.get("price_min", 0)):
			f.append("tier bands overlap: %s max %d >= %s min %d" % [TIER_ORDER[i - 1],
					int(lo.get("price_max", 0)), TIER_ORDER[i], int(hi.get("price_min", 0))])
		if int(lo.get("pool_from", 0)) >= int(hi.get("pool_from", 0)):
			f.append("tier pool-from not ascending: %s %d >= %s %d" % [TIER_ORDER[i - 1],
					int(lo.get("pool_from", 0)), TIER_ORDER[i], int(hi.get("pool_from", 0))])


func _price_bands(f: Array[String], api: RefCounted) -> void:
	var tiers: Dictionary = api.tiers()
	var n := 0
	for id in api.upgrade_ids():
		var u: Dictionary = api.upgrade(id)
		var t := str(u.get("tier", ""))
		var row: Dictionary = tiers.get(t, {})
		var p := int(u.get("price", -1))
		n += 1
		if row.is_empty():
			f.append("%s: tier %s has no row in data/upgrade_pools.json tiers" % [id, t])
		elif p < int(row["price_min"]) or p > int(row["price_max"]):
			f.append("%s: price %d g is outside the %s band %d-%d g" % [id, p, t,
					int(row["price_min"]), int(row["price_max"])])
	if n != 36:
		f.append("price bands checked %d upgrades, expected the 36 of DESIGN.md section 8" % n)


func _raw_brackets(f: Array[String], api: RefCounted) -> void:
	var tf: Dictionary = api.TIER_FROM
	for b in api.data("upgrade_pools").get("brackets", []):
		var br: Dictionary = b
		var lo := int(br.get("min_level", 0))
		for raw in br.get("ids", []):
			var id := str(raw)
			var t := str(api.upgrade(id).get("tier", ""))
			if int(tf.get(t, 99999)) > lo:
				f.append("bracket %s (from level %d) lists %s, a %s upgrade that enters the pool at %s" % [
						str(br.get("bracket", "?")), lo, id, t, str(tf.get(t, "never"))])


func _shop_pool_gate(f: Array[String], api: RefCounted) -> void:
	var tf: Dictionary = api.TIER_FROM
	for lv in range(0, 61):
		for id in api.shop_pool(lv):
			var t := str(api.upgrade(id).get("tier", ""))
			if int(tf.get(t, 99999)) > lv:
				f.append("shop_pool(%d) holds %s (%s, pool from %s)" % [lv, id, t, str(tf.get(t))])


func _draw_shop_gate(f: Array[String], api: RefCounted) -> void:
	var tf: Dictionary = api.TIER_FROM
	var draws := 0
	var offers := 0
	for lv in range(0, 33):
		for cls in ["", "dasher", "glider", "athletic"]:
			for purse in [0, 60, 250, 1000, 100000]:
				for s in range(4):
					var rng: RefCounted = VoidRngScript.new(VoidRngScript.mix(15015 + lv, s * 7 + purse))
					var shop: Dictionary = OffersScript.draw_shop(api, lv, purse, {}, str(cls), rng)
					draws += 1
					for o in shop["offers"]:
						offers += 1
						var id := str((o as Dictionary)["id"])
						var t := str(api.upgrade(id).get("tier", ""))
						if int(tf.get(t, 99999)) > lv:
							f.append("draw_shop(level %d, %s, purse %d, seed %d) offered %s (%s, pool from %s)" % [
									lv, cls, purse, s, id, t, str(tf.get(t))])
	# the sweep must actually see offers (an empty shop everywhere would pass vacuously)
	if offers < draws * 2:
		f.append("draw_shop sweep saw only %d offers in %d draws" % [offers, draws])


func _readme_table(f: Array[String], api: RefCounted) -> void:
	var text := FileAccess.get_file_as_string(TableScript.readme_path())
	var a := text.find(TableScript.BEGIN)
	var b := text.find(TableScript.END)
	if a < 0 or b < a:
		f.append("README.md has no upgrade-table markers (run tools/upgrade_table.gd -- --write)")
		return
	var have := text.substr(a, b + TableScript.END.length() - a) + "\n"
	var want: String = TableScript.table_markdown(api)
	if have != want:
		f.append("README.md upgrade table differs from the data - regenerate with tools/upgrade_table.gd -- --write")
