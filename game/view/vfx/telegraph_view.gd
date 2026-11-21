extends Node3D
#
# Generic enemy telegraph view (DESIGN.md section 5: "every attack is telegraphed").
#
# View layer only: reads the runtime's LIVE telegraph rows (sim/enemy_runtime.gd
# live_telegraphs(): {"kind","shape","ticks","total","source","tick"}) and draws each one
# by its collision.gd footprint, never by enemy id:
#   circle r > 0    a flat translucent red patch with a brighter inner disc that grows
#                   from the centre to the rim over the telegraph's lifetime (the fill
#                   says WHEN it lands) + a rim ring so the edge reads at a glance
#   ring r0..r1     a flat red torus band
#   box x0..x1      a flat red slab
#   "line"/"dash_line" [x0,y0,z0,x1,y1,z1]  a thin red beam along the warned line
#   "fx"/"fy"/"fz"  (an aim from a muzzle) a red sight line from the muzzle to the
#                   aim target the caller passes (the player the shooter locks)
# r == 0 circles with no line are sound-only tells (meow / bark): nothing is drawn.
# Kinds that already have a bespoke view in the scene (coil's landing ring) are skipped
# through `skip_kinds`.
#
# Audio: on_events() reads the step's raw events and plays the cue for each new
# telegraph (TELL_CUES, kind -> cue file name), each sim "audio"/"coil_land" event's own
# cue, and the projectile launch cue. Cue files are looked up by name under
# res://assets/audio/enemies/*/ (indexed once); a telegraph whose kind has no file
# plays a synthesized warning beep, so no telegraph is ever silent. Every cue played
# is logged in `cue_log` (headless tests read it; the player only starts in the tree).
#
# The threat cue layer (view/audio/threat_cues.gd, PARKED.md rows 12-15) rides the same
# two calls: on_events() hands it the step's telegraphs (the data-driven offsets from
# every enemy.json's audio_cue_timing - gin's shing at mark + 120, the nuke roar, the
# strings sweep...), sync() hands it the live rows (Claude's one-beat-early pre-hits,
# address me's appearance) and plays whatever comes due. The rows are read from
# `rt_source` when set, else from the parent's `rt` (app/world.gd) - read only.
# cue_log rows carry the step tick ("tick") and the gain.
#
# Unshaded, additive, fog-exempt, no depth test on lines - the tell must read across
# the level (the straggler-beam / danger-text rule: fog never eats the answer).

const ThreatCuesScript := preload("res://view/audio/threat_cues.gd")
const AUDIO_ROOT := "res://assets/audio/enemies"
const TELL_COLOR := Color(1.0, 0.1647, 0.1647)   # #FF2A2A, the danger red
const PATCH_ALPHA := 0.22
const FILL_ALPHA := 0.40
const RIM_ALPHA := 0.85
const RIM_TUBE := 0.07
const LINE_W := 0.12
const LIFT := 0.05          # u above the footprint plane (no z-fight with the slab top)
const CUE_LOG_MAX := 64
const BEEP_HZ := 880.0
const BEEP_S := 0.18

# telegraph kind -> cue file name (the sound the tell carries). Kinds missing here play
# the synthesized beep. ground_ring's solid (locked) variant is LOCKED_CUE.
const TELL_CUES := {
	"drum_ring": "ui_chime",
	"strings_line": "keystroke_tick",
	"mark": "crack_rumble",
	"aim": "isagi_voice_direct_shot",
	"meow": "meow",
	"ground_ring": "lock_on_beep",
	"dash_line": "flipper_flap",
	"bark": "bark",
	"teleport": "thicc_ben_chime",
	"toucher_pulse": "prowl",
	"you_rumble": "you_corrupted_rumble",
	"coil_ring": "",            # coil carries its own boing as a sim "audio" event
}
const LOCKED_CUE := "locked"
const PROJECTILE_CUE := "isagi_gunshot"

var skip_kinds: Array = ["coil_ring"]
var cue_log: Array = []      # [{"cue", "x", "y", "z", "tick", "gain"}], newest last, capped
var threat_cues = ThreatCuesScript.new()   # the scheduled half of the cue layer
var rt_source = null         # an EnemyRuntime to read rows from (else the parent's rt)
var _step := -1              # the step tick of the latest events / sync
var _nodes := {}             # telegraph key -> {"root": Node3D, "fill": MeshInstance3D|null, "r": float}
var _cue_paths := {}         # cue name -> res:// path
var _beep: AudioStreamWAV = null


func _ready() -> void:
	if _cue_paths.is_empty():
		index_audio()


## Index every cue file under AUDIO_ROOT by its base name. Exported builds list the
## .import remap beside the (stripped) source, so both spellings resolve.
func index_audio() -> void:
	_cue_paths = {}
	var root := DirAccess.open(AUDIO_ROOT)
	if root == null:
		return
	for d in root.get_directories():
		var sub := DirAccess.open("%s/%s" % [AUDIO_ROOT, d])
		if sub == null:
			continue
		for fn in sub.get_files():
			var name := str(fn)
			if name.ends_with(".import"):
				name = name.trim_suffix(".import")
			if not name.ends_with(".wav"):
				continue
			_cue_paths[name.trim_suffix(".wav")] = "%s/%s/%s" % [AUDIO_ROOT, d, name]


func has_cue(cue: String) -> bool:
	if _cue_paths.is_empty():
		index_audio()
	return _cue_paths.has(cue)


## Stable identity of one telegraph row (rows are appended once and never mutated).
static func key_of(t: Dictionary) -> String:
	var s: Dictionary = t.get("shape", {})
	return "%s|%s|%d|%s|%s" % [str(t.get("source", "")), str(t.get("kind", "")),
			int(t.get("tick", -1)), str(s.get("cx", s.get("x0", 0.0))),
			str(s.get("cz", s.get("z0", 0.0)))]


## 0..1 progress of a telegraph at runtime tick `now`.
static func progress(t: Dictionary, now: int) -> float:
	var total := maxi(int(t.get("total", t.get("ticks", 1))), 1)
	return clampf(float(now - int(t.get("tick", now))) / float(total), 0.0, 1.0)


## The drawn element count (one per live drawable telegraph).
func shown_count() -> int:
	return _nodes.size()


func shown_keys() -> Array:
	return _nodes.keys()


## One view tick. live: rt.live_telegraphs() (read, never written); now: rt.tick;
## fallback_y: the plane for a footprint that carries no y0 (the caller passes the
## player's feet - every y-less tell is aimed at the player); aim_to: where an aim
## sight line ends (the player's centre).
func sync(live: Array, now: int, fallback_y: float, aim_to: Vector3) -> void:
	var wanted := {}
	for t in live:
		var kind := str(t.get("kind", ""))
		if skip_kinds.has(kind):
			continue
		var shape: Dictionary = t.get("shape", {})
		if not _drawable(shape):
			continue
		var k := key_of(t)
		wanted[k] = true
		if not _nodes.has(k):
			_nodes[k] = _build(shape, fallback_y, aim_to)
		var n: Dictionary = _nodes[k]
		var fill = n.get("fill", null)
		if fill != null:
			var p := maxf(progress(t, now), 0.02)
			(fill as MeshInstance3D).scale = Vector3(p, 1.0, p)
		if n.get("aim", false):
			_place_line(n["root"], n["from"], aim_to)
	for k in _nodes.keys():
		if not wanted.has(k):
			var root: Node3D = _nodes[k]["root"]
			remove_child(root)
			root.queue_free()
			_nodes.erase(k)
	_cue_pass(now - 1)   # sync runs after rt.step: the step that just ran is now - 1


## The scheduled cues: the live rows (beat clock, appearances) + every pending cue due by
## step tick `step`.
func _cue_pass(step: int) -> void:
	if threat_cues == null:
		return
	_step = maxi(_step, step)
	var src = rt_source
	if src == null and get_parent() != null:
		src = get_parent().get("rt")
	var due: Array = []
	if src != null and src.get("enemies") is Array:
		due = threat_cues.watch_rows(src.enemies, step)
	else:
		due = threat_cues.due(step)
	for p in due:
		play(str(p["cue"]), Vector3(float(p["x"]), float(p["y"]), float(p["z"])),
				float(p["gain"]), int(p["at"]))


static func _drawable(shape: Dictionary) -> bool:
	if shape.has("line") or shape.has("dash_line"):
		return true
	if shape.has("fx") and shape.has("fz"):
		return true
	match str(shape.get("shape", "")):
		"circle":
			return float(shape.get("r", 0.0)) > 0.0
		"ring":
			return float(shape.get("r1", 0.0)) > 0.0
		"box":
			return true
	return false


func _build(shape: Dictionary, fallback_y: float, aim_to: Vector3) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var out := {"root": root, "fill": null}
	var y := float(shape.get("y0", fallback_y)) + LIFT
	var line: Array = shape.get("line", shape.get("dash_line", []))
	if line.size() >= 6:
		_place_line(root, Vector3(float(line[0]), float(line[1]), float(line[2])),
				Vector3(float(line[3]), float(line[4]), float(line[5])))
		return out
	if shape.has("fx") and shape.has("fz"):
		var from := Vector3(float(shape["fx"]), float(shape.get("fy", y)), float(shape["fz"]))
		out["aim"] = true
		out["from"] = from
		_place_line(root, from, aim_to)
		return out
	match str(shape.get("shape", "")):
		"circle":
			var r := float(shape.get("r", 0.0))
			root.position = Vector3(float(shape.get("cx", 0.0)), y, float(shape.get("cz", 0.0)))
			root.add_child(_disc(r, PATCH_ALPHA))
			root.add_child(_rim(r))
			var fill := _disc(r, FILL_ALPHA)
			fill.scale = Vector3(0.02, 1.0, 0.02)
			root.add_child(fill)
			out["fill"] = fill
		"ring":
			var r0 := float(shape.get("r0", 0.0))
			var r1 := float(shape.get("r1", 0.0))
			root.position = Vector3(float(shape.get("cx", 0.0)), y, float(shape.get("cz", 0.0)))
			var mi := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = maxf(r0, 0.01)
			tor.outer_radius = maxf(r1, r0 + 0.02)
			tor.rings = 48
			mi.mesh = tor
			mi.scale = Vector3(1.0, 0.05, 1.0)
			mi.material_override = _material(PATCH_ALPHA * 1.6, false)
			root.add_child(mi)
		"box":
			var x0 := float(shape.get("x0", 0.0))
			var x1 := float(shape.get("x1", 0.0))
			var z0 := float(shape.get("z0", 0.0))
			var z1 := float(shape.get("z1", 0.0))
			root.position = Vector3((x0 + x1) * 0.5, y, (z0 + z1) * 0.5)
			var bi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(maxf(absf(x1 - x0), 0.05), 0.04, maxf(absf(z1 - z0), 0.05))
			bi.mesh = bm
			bi.material_override = _material(PATCH_ALPHA * 1.6, false)
			root.add_child(bi)
	return out


## Lays (or re-lays) a root's single beam child between two points.
func _place_line(root: Node3D, a: Vector3, b: Vector3) -> void:
	var mi: MeshInstance3D = null
	if root.get_child_count() > 0:
		mi = root.get_child(0) as MeshInstance3D
	if mi == null:
		mi = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(LINE_W, LINE_W, 1.0)
		mi.mesh = bm
		mi.material_override = _material(RIM_ALPHA, true)
		root.add_child(mi)
	var d := b - a
	var len := maxf(d.length(), 0.01)
	root.position = Vector3.ZERO
	mi.position = (a + b) * 0.5
	mi.basis = Basis()
	if len > 0.011:
		var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		mi.basis = Basis.looking_at(d.normalized(), up)
	mi.scale = Vector3(1.0, 1.0, len)


static func _disc(r: float, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.03
	c.radial_segments = 48
	c.rings = 1
	mi.mesh = c
	mi.material_override = _material(alpha, false)
	return mi


static func _rim(r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = maxf(r - RIM_TUBE, 0.01)
	tor.outer_radius = r + RIM_TUBE
	tor.rings = 64
	tor.ring_segments = 6
	mi.mesh = tor
	mi.material_override = _material(RIM_ALPHA, false)
	return mi


static func _material(alpha: float, no_depth: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(TELL_COLOR.r, TELL_COLOR.g, TELL_COLOR.b, alpha)
	m.disable_fog = true
	m.disable_receive_shadows = true
	m.no_depth_test = no_depth
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# ---- audio ------------------------------------------------------------------------------

## The step's raw events (rt.step's list): one cue per new telegraph, per sim audio
## event and per projectile launch; then the threat cue layer schedules the telegraphs'
## data-driven cues and every one due on this step plays now.
func on_events(events: Array) -> void:
	var played: Array = []
	for e in events:
		if e.has("tick"):
			_step = maxi(_step, int(e["tick"]))
	for e in events:
		var kind := str(e.get("e", ""))
		var at := int(e.get("tick", _step))
		if kind == "telegraph":
			var tk := str(e.get("kind", ""))
			var shape: Dictionary = e.get("shape", {})
			var cue := ""
			if TELL_CUES.has(tk):
				cue = str(TELL_CUES[tk])
				if cue == "":
					played.append("kind:" + tk)   # the scheduler leaves its offset-0 cue too
					continue   # the tell's sound rides its own sim audio event
			if tk == "ground_ring" and bool(shape.get("solid", false)):
				cue = LOCKED_CUE
			played.append(cue)
			play(cue, Vector3(float(shape.get("cx", shape.get("fx", 0.0))),
					float(shape.get("y0", shape.get("fy", 0.0))),
					float(shape.get("cz", shape.get("fz", 0.0)))), 1.0, at)
		elif e.has("cue"):
			# any sim event that carries its own cue (coil's boing, the coil landing twang,
			# toucher's squelch, and whatever a later behavior raises): the event names the
			# file, so a new cue needs no change here
			var c := str(e.get("cue", ""))
			if c != "":
				played.append(c)
				play(c, Vector3(float(e.get("x", 0.0)), float(e.get("y", 0.0)),
						float(e.get("z", 0.0))), 1.0, at)
		elif kind == "projectile_spawn":
			played.append(PROJECTILE_CUE)
			play(PROJECTILE_CUE, Vector3(float(e.get("x", 0.0)), float(e.get("y", 0.0)),
					float(e.get("z", 0.0))), 1.0, at)
	if threat_cues == null:
		return
	var step: int = threat_cues.schedule(events, played)
	if step < 0:
		return
	for p in threat_cues.due(step):
		play(str(p["cue"]), Vector3(float(p["x"]), float(p["y"]), float(p["z"])),
				float(p["gain"]), int(p["at"]))


## Plays a cue at a world position. "" or a cue with no file plays the synthesized beep
## (logged as "beep"). gain in (0, 1] (the pre-hits are quieter); tick is the step tick
## the cue belongs to (-1: the latest seen). Logged always; heard only inside the tree.
func play(cue: String, pos: Vector3, gain: float = 1.0, tick: int = -1) -> void:
	var stream: AudioStream = null
	var logged := cue
	if cue != "" and has_cue(cue):
		stream = load(str(_cue_paths[cue])) as AudioStream
	if stream == null:
		stream = _beep_stream()
		logged = "beep"
	cue_log.append({"cue": logged, "x": pos.x, "y": pos.y, "z": pos.z,
			"tick": tick if tick >= 0 else _step, "gain": gain})
	if cue_log.size() > CUE_LOG_MAX:
		cue_log.pop_front()
	if not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.position = pos
	p.unit_size = 12.0
	p.volume_db = linear_to_db(clampf(gain, 0.001, 1.0))
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _beep_stream() -> AudioStreamWAV:
	if _beep != null:
		return _beep
	var rate := 22050
	var n := int(BEEP_S * float(rate))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var env := minf(1.0, t * 80.0) * (1.0 - float(i) / float(n))
		data.encode_s16(i * 2, int(sin(TAU * BEEP_HZ * t) * env * 0.45 * 32767.0))
	_beep = AudioStreamWAV.new()
	_beep.format = AudioStreamWAV.FORMAT_16_BITS
	_beep.mix_rate = rate
	_beep.stereo = false
	_beep.data = data
	return _beep
