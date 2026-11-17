extends RefCounted
#
# gin ichimaru placeholder audio (ticket T-041; ENEMIES.md "New sound", verbatim:
# "sword 'shing' (unsheath) + whoosh when the spears launch, deep cracking rumble
# before a platform breaks" + the void zone cues). Hooks named per the section 3
# brief: crack_rumble (the 120-tick mark), shing (the launch, tick 120), whoosh
# (the 18-tick spear flight), zone_open (the tiles vanish), zone_close (the tiles
# fade back).
#
# Pure synthesis on the view layer - NO recorded or downloaded audio, nothing
# copied from any existing recording. Deterministic: same cue, same bytes. The
# cue NAMES are the stable contract; T-055 swaps in file-backed cues.

const SAMPLE_RATE := 22050

const CUES := {
	"crack_rumble": "gin_crack_rumble",
	"shing": "gin_shing",
	"whoosh": "gin_whoosh",
	"zone_open": "gin_zone_open",
	"zone_close": "gin_zone_close",
}


static func cue_names() -> Array:
	var out: Array = []
	for k in CUES.keys():
		out.append(str(k))
	out.sort()
	return out


static func file_name_for(cue: String) -> String:
	return str(CUES.get(cue, ""))


## Plays the cue on `host` (a Node in the tree - the view passes itself). Returns
## the created player (already playing), or null when the host is unusable.
static func play_cue(host: Object, cue: String) -> AudioStreamPlayer:
	if not CUES.has(cue):
		push_warning("gin_audio: unknown cue '%s'" % cue)
		return null
	if not (host is Node):
		return null
	var parent := host as Node
	if not parent.is_inside_tree():
		return null
	var p := AudioStreamPlayer.new()
	p.stream = stream_for(cue)
	p.name = "gin_%s" % cue
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p


## The synthesized placeholder stream for a cue. Deterministic: same cue, same
## bytes (a fixed LCG, no Math.random anywhere).
static func stream_for(cue: String) -> AudioStreamWAV:
	match cue:
		"crack_rumble":
			# the 120-tick mark: a 50 Hz drone with random-ish noise clicks rising
			# 4 -> 20 Hz over 2.0 s
			return _render(50.0, 2.0, 0.55, 0.45)
		"shing":
			# the launch: a bright metallic sweep, sine 2000 -> 6000 Hz, 0.3 s
			return _render(4000.0, 0.3, 0.7, 0.2, 2000.0, 6000.0)
		"whoosh":
			# the 18-tick spear flight: band-passed noise sweeping down, 0.3 s
			return _render(900.0, 0.3, 0.5, 900.0, 300.0)
		"zone_open":
			# the tiles vanish: a hollow drop
			return _render(220.0, 0.4, 0.6, 220.0, 90.0)
		"zone_close":
			# the tiles fade back: the drop's reverse
			return _render(90.0, 0.4, 0.6, 220.0)
	return null
