extends SceneTree
#
# game/tools/audio/synth_cues.gd - the synthesized cue set for the player, the UI, the
# world and the ambience bed (the owner's "the game is too quiet" pass).
#
#   "<godot>" --headless --path game --script res://tools/audio/synth_cues.gd
#
# Every cue is generated from code - no sampled, recorded or downloaded audio ships here.
# The module follows the game/tools/art/*.gd convention: one SceneTree script, deterministic
# (a fixed LCG seed per cue, a fixed sample rate, no wall clock), writes its output under
# game/assets/audio/ and prints one line per file. Re-running it reproduces the whole set
# byte for byte, so the entire sound pass is one command.
#
# Output: game/assets/audio/<group>/<name>.wav - 44.1 kHz mono 16-bit, the same format the
# T-055 enemy cues already use, so one loader reads both. Peak-normalised to 0.89 (never
# clips). Looping cues (glide, the lobby bed, the music bed) are generated 30 ms long and
# crossfaded down to their declared length, so the loop point is seamless.
#
# The cue NAMES are the contract the view layer plays (view/audio/*.gd); the recipes below
# are the sound design and may be rewritten without renaming a cue.

const RATE := 44100
const PEAK := 0.89
const OUT_REL := "assets/audio"
const TAU_F := 6.283185307179586
const LOOP_FADE_S := 0.03

# group, name, seconds, LCG seed. The seed is the cue's identity: same seed, same bytes.
const CUES := [
	["player", "footstep_01", 0.10, 11],
	["player", "footstep_02", 0.10, 12],
	["player", "footstep_03", 0.10, 13],
	["player", "footstep_04", 0.10, 14],
	["player", "land", 0.24, 21],
	["player", "dash", 0.30, 22],
	["player", "glide", 1.50, 23],
	["player", "jump_pad", 0.55, 24],
	["world", "gift_pickup_01", 0.22, 31],
	["world", "gift_pickup_02", 0.22, 32],
	["world", "gift_pickup_03", 0.22, 33],
	["world", "level_complete", 1.80, 34],
	["world", "death", 1.60, 35],
	["world", "collapse_crack", 0.60, 36],
	["world", "collapse_fall", 1.00, 37],
	["ui", "menu_hover", 0.07, 41],
	["ui", "menu_click", 0.14, 42],
	["ambience", "lobby_ambience", 4.00, 51],
	["ambience", "music_bed", 8.00, 52],
]

# cues that must loop seamlessly (generated long, crossfaded back to their declared length)
const LOOPING := ["glide", "lobby_ambience", "music_bed"]


# Deterministic pseudo-noise (LCG, Numerical Recipes constants) - the same generator
# tools/synth_audio.py uses, so a rebuild is byte-stable.
class Lcg:
	var state: int

	func _init(seed_value: int) -> void:
		state = seed_value & 0x7FFFFFFF

	func next() -> float:
		state = (1103515245 * state + 12345) & 0x7FFFFFFF
		return float(state) / 1073741823.5 - 1.0


func _init() -> void:
	var game_dir := ProjectSettings.globalize_path("res://")
	if game_dir.ends_with("/"):
		game_dir = game_dir.substr(0, game_dir.length() - 1)
	var out_root := game_dir + "/" + OUT_REL
	var fade := int(round(LOOP_FADE_S * float(RATE)))
	var made := 0
	for row in CUES:
		var group := str(row[0])
		var cue := str(row[1])
		var secs := float(row[2])
		var n := int(round(secs * float(RATE)))
		var gen := n + fade if LOOPING.has(cue) else n
		var buf := _render(cue, gen, Lcg.new(int(row[3])))
		if LOOPING.has(cue):
			buf = _loopify(buf, fade)
		_normalize(buf)
		var dir := out_root + "/" + group
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir + "/" + cue + ".wav"
		if not _write_wav(path, buf):
			print("SYNTH FAILED: cannot write %s" % path)
			quit(1)
			return
		made += 1
		print("  %-9s %-16s %5.2f s  %6d frames" % [group, cue, secs, buf.size()])
	print("SYNTH OK: %d cue(s) written under %s" % [made, out_root])
	quit(0)
# ---- dispatch -------------------------------------------------------------------

func _render(cue: String, n: int, rng: Lcg) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	if cue.begins_with("footstep_"):
		_footstep(buf, n, rng, int(cue.substr(9)) - 1)
	elif cue.begins_with("gift_pickup_"):
		_gift_pickup(buf, n, rng, int(cue.substr(12)) - 1)
	else:
		match cue:
			"land": _land(buf, n, rng)
			"dash": _dash(buf, n, rng)
			"glide": _glide(buf, n, rng)
			"jump_pad": _jump_pad(buf, n, rng)
			"level_complete": _level_complete(buf, n, rng)
			"death": _death(buf, n, rng)
			"collapse_crack": _collapse_crack(buf, n, rng)
			"collapse_fall": _collapse_fall(buf, n, rng)
			"menu_hover": _menu_hover(buf, n, rng)
			"menu_click": _menu_click(buf, n, rng)
			"lobby_ambience": _lobby_ambience(buf, n, rng)
			"music_bed": _music_bed(buf, n, rng)
			_: pass   # an unknown name stays silent rather than failing the whole run
	return buf


# ---- voices ---------------------------------------------------------------------

# Jump pad (D-JUMPPAD-5): a springy rising boing. A sine whose pitch sweeps up (140 -> ~620 Hz,
# exponential approach) with a vibrato that starts fast and wide and settles - the spring's
# wobble - over a short low thump (the pad compressing) and a breath of filtered noise.
func _jump_pad(buf: PackedFloat32Array, n: int, rng: Lcg) -> void:
	var a := _lp_coef(1800.0)
	var lp := 0.0
	var phase := 0.0
	var phase2 := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var sweep := 140.0 + 480.0 * (1.0 - exp(-7.0 * t))
		var wob := 1.0 + 0.10 * exp(-9.0 * t) * sin(TAU_F * 26.0 * t)
		var hz := sweep * wob
		phase += TAU_F * hz / float(RATE)
		phase2 += TAU_F * hz * 2.0 / float(RATE)
		var env := minf(1.0, t / 0.008) * exp(-4.2 * t)
		var tone := sin(phase) * 0.8 + sin(phase2) * 0.18
		var thump := sin(TAU_F * 70.0 * t) * exp(-30.0 * t)
		lp += a * (rng.next() - lp)
		buf[i] = tone * env + thump * 0.6 + lp * exp(-25.0 * t) * 0.25

# One-pole lowpass coefficient for a cutoff in Hz (the filter state is the caller's).
static func _lp_coef(cutoff: float) -> float:
	return 1.0 - exp(-TAU_F * maxf(cutoff, 1.0) / float(RATE))


# A footstep: a low thump plus a short filtered-noise scuff. The four variants differ in
# thump pitch and scuff brightness, so a run does not machine-gun one sample.
func _footstep(buf: PackedFloat32Array, n: int, rng: Lcg, variant: int) -> void:
	var thump_hz := 84.0 + 14.0 * float(variant)
	var a := _lp_coef(900.0 + 220.0 * float(variant))
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		lp += a * (rng.next() - lp)
		var thump := sin(TAU_F * thump_hz * t) * exp(-38.0 * t)
		var scuff := lp * exp(-70.0 * t)
		buf[i] = thump * 0.75 + scuff * 0.55


# Landing: a body thud whose pitch drops as it settles, with a dust tail.
func _land(buf: PackedFloat32Array, n: int, rng: Lcg) -> void:
	var a := _lp_coef(520.0)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var hz := 96.0 * exp(-6.0 * t) + 42.0
		phase += TAU_F * hz / float(RATE)
		lp += a * (rng.next() - lp)
		buf[i] = sin(phase) * exp(-11.0 * t) * 0.85 + lp * exp(-16.0 * t) * 0.5


# Dash: a noise band whose cutoff sweeps up under a rising tone - the air being cut.
func _dash(buf: PackedFloat32Array, n: int, rng: Lcg) -> void:
	var lp := 0.0
	var low := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var p := float(i) / float(n)
		var x := rng.next()
		lp += _lp_coef(380.0 + 3600.0 * p * p) * (x - lp)
		low += _lp_coef(180.0) * (lp - low)
		var band := lp - low
		var env := minf(1.0, t * 60.0) * exp(-3.2 * t)
		phase += TAU_F * (180.0 + 620.0 * p) / float(RATE)
		buf[i] = band * env * 1.1 + sin(phase) * env * 0.18


# Glide: wind under the wing - a band of noise with a 2 Hz swell (3 whole cycles over the
# 1.5 s cue, so the loop point is continuous) and a faint low body.
func _glide(buf: PackedFloat32Array, n: int, rng: Lcg) -> void:
	var a_low := _lp_coef(760.0)
	var a_high := _lp_coef(2400.0)
	var lp := 0.0
	var hp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var x := rng.next()
		lp += a_low * (x - lp)
		hp += a_high * (x - hp)
		var air := hp - lp
		var swell := 0.72 + 0.28 * sin(TAU_F * 2.0 * t)
		buf[i] = (air * 0.9 + sin(TAU_F * 196.0 * t) * 0.10) * swell
# Gift pickup: a bright bell with a fifth and an octave over it, plus a tiny click. The
# three variants sit a whole tone apart (A5, B5, D6) so repeats do not grate.
func _gift_pickup(buf: PackedFloat32Array, n: int, rng: Lcg, variant: int) -> void:
	var base: float = [880.0, 987.77, 1174.66][clampi(variant, 0, 2)]
	var a := _lp_coef(6000.0)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var env := minf(1.0, t * 400.0) * exp(-9.0 * t)
		var tone := sin(TAU_F * base * t) + 0.45 * sin(TAU_F * base * 1.5 * t) \
				+ 0.22 * sin(TAU_F * base * 2.0 * t)
		lp += a * (rng.next() - lp)
		buf[i] = tone * env * 0.5 + lp * exp(-160.0 * t) * 0.5


# Level complete: a rising major arpeggio (C5 E5 G5 C6) over a soft pad.
func _level_complete(buf: PackedFloat32Array, n: int, rng: Lcg) -> void:
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var step := 0.30
	var a := _lp_coef(4000.0)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var v := 0.0
		for k in notes.size():
			var t0 := step * float(k)
			if t < t0:
				continue
			var dt := t - t0
			var env := minf(1.0, dt * 300.0) * exp(-3.4 * dt)
			v += (sin(TAU_F * float(notes[k]) * dt)
					+ 0.3 * sin(TAU_F * float(notes[k]) * 2.0 * dt)) * env
		var pad := (sin(TAU_F * 130.81 * t) + sin(TAU_F * 196.0 * t)) * 0.10 \
				* minf(1.0, t * 3.0) * exp(-0.9 * t)
		lp += a * (rng.next() - lp)
		buf[i] = v * 0.30 + pad + lp * 0.02


# Death: a tone falling a two-octave minor third, a breath of noise and a sub rumble.
func _death(buf: PackedFloat32Array, n: int, rng: Lcg) -> void:
	var a := _lp_coef(700.0)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var p := clampf(t / 1.2, 0.0, 1.0)
		phase += TAU_F * (392.0 * pow(0.25, p)) / float(RATE)
		lp += a * (rng.next() - lp)
		var tone := sin(phase) * minf(1.0, t * 40.0) * exp(-1.5 * t)
		var air := lp * minf(1.0, t * 6.0) * exp(-2.2 * t)
		var sub := sin(TAU_F * 49.0 * t) * exp(-1.1 * t) * 0.5
		buf[i] = tone * 0.55 + air * 0.45 + sub


# Collapse crack: sparse impulses (a noise sample past a high threshold re-arms the
# crackle) over a low crack thump.
func _collapse_crack(buf: PackedFloat32Array, n: int, rng: Lcg) -> void:
	var a_high := _lp_coef(3200.0)
	var a_low := _lp_coef(300.0)
	var hp := 0.0
	var lp := 0.0
	var burst := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var x := rng.next()
		hp += a_high * (x - hp)
		lp += a_low * (x - lp)
		if absf(x) > 0.86:
			burst = 1.0
		burst *= 0.90
		var crackle := (hp - lp) * burst * exp(-4.0 * t)
		buf[i] = crackle * 1.4 + sin(TAU_F * 70.0 * t) * exp(-22.0 * t) * 0.6


# Collapse fall: a rumble whose cutoff and pitch both sink as the slab drops away.
func _collapse_fall(buf: PackedFloat32Array, n: int, rng: Lcg) -> void:
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var p := clampf(t / 0.9, 0.0, 1.0)
		lp += _lp_coef(900.0 * pow(0.18, p)) * (rng.next() - lp)
		phase += TAU_F * (58.0 * pow(0.6, p)) / float(RATE)
		var env := minf(1.0, t * 25.0) * exp(-1.6 * t)
		buf[i] = lp * env * 1.2 + sin(phase) * env * 0.5


# Menu hover: one soft high tick, gone in 70 ms.
func _menu_hover(buf: PackedFloat32Array, n: int, _rng: Lcg) -> void:
	for i in n:
		var t := float(i) / float(RATE)
		buf[i] = sin(TAU_F * 1320.0 * t) * minf(1.0, t * 900.0) * exp(-70.0 * t) * 0.5


# Menu click: two tones a fifth apart, the second answering the first.
func _menu_click(buf: PackedFloat32Array, n: int, _rng: Lcg) -> void:
	var split := 0.055
	for i in n:
		var t := float(i) / float(RATE)
		var v := 0.0
		if t < split:
			v = sin(TAU_F * 880.0 * t) * minf(1.0, t * 900.0) * exp(-45.0 * t)
		else:
			var dt := t - split
			v = sin(TAU_F * 1320.0 * dt) * minf(1.0, dt * 900.0) * exp(-38.0 * dt)
		buf[i] = v * 0.6


# Lobby ambience: a low drone (55 / 82.5 / 110 Hz) breathing at 0.25 Hz - one whole cycle
# over the 4 s cue - under a band of airy noise.
func _lobby_ambience(buf: PackedFloat32Array, n: int, rng: Lcg) -> void:
	var a := _lp_coef(420.0)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var drone := sin(TAU_F * 55.0 * t) * 0.5 + sin(TAU_F * 82.5 * t) * 0.28 \
				+ sin(TAU_F * 110.0 * t) * 0.16
		var breath := 0.85 + 0.15 * sin(TAU_F * 0.25 * t)
		lp += a * (rng.next() - lp)
		buf[i] = drone * breath * 0.55 + lp * 0.5


# Music bed: four two-second chords (Am - F - C - G) with a detuned shimmer, each swelling
# in and out so the chord changes and the loop point are both continuous.
func _music_bed(buf: PackedFloat32Array, n: int, rng: Lcg) -> void:
	var chords := [
		[220.0, 261.63, 329.63],
		[174.61, 220.0, 261.63],
		[261.63, 329.63, 392.0],
		[196.0, 246.94, 293.66],
	]
	var seg := 2.0
	var lp := 0.0
	for i in n:
		var t := float(i) / float(RATE)
		var idx := int(t / seg) % chords.size()
		var local := fmod(t, seg)
		var env := minf(1.0, local / 0.35) * minf(1.0, (seg - local) / 0.5)
		var v := 0.0
		for hz in chords[idx]:
			v += sin(TAU_F * float(hz) * t) * 0.33
			v += sin(TAU_F * float(hz) * 1.005 * t) * 0.12
		lp += _lp_coef(1800.0) * (rng.next() - lp)
		buf[i] = v * env * 0.5 + lp * 0.03
# ---- buffer plumbing --------------------------------------------------------------

# Folds the tail into the head and returns the buffer cut back to its declared length, so
# the last sample runs into the first one with no step. `fade` samples of the tail are
# mixed into the head with an equal-gain ramp.
static func _loopify(buf: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := buf.size()
	if fade <= 0 or fade * 2 >= n:
		return buf
	var out := PackedFloat32Array()
	out.resize(n - fade)
	for i in n - fade:
		out[i] = buf[i]
	for i in fade:
		var w := float(i) / float(fade)
		out[i] = buf[i] * w + buf[n - fade + i] * (1.0 - w)
	return out


static func _normalize(buf: PackedFloat32Array) -> void:
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	if peak <= 1e-6:
		return
	var g := PEAK / peak
	for i in buf.size():
		buf[i] = buf[i] * g


# ---- RIFF/WAVE writer (44.1 kHz mono 16-bit, little-endian by hand) -----------------

static func _write_wav(path: String, buf: PackedFloat32Array) -> bool:
	var n := buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(round(clampf(buf[i], -1.0, 1.0) * 32767.0)))
	var hdr := PackedByteArray()
	hdr.resize(44)
	_put_ascii(hdr, 0, "RIFF")
	_put_u32(hdr, 4, 36 + n * 2)
	_put_ascii(hdr, 8, "WAVE")
	_put_ascii(hdr, 12, "fmt ")
	_put_u32(hdr, 16, 16)
	_put_u16(hdr, 20, 1)              # PCM
	_put_u16(hdr, 22, 1)              # mono
	_put_u32(hdr, 24, RATE)
	_put_u32(hdr, 28, RATE * 2)       # byte rate
	_put_u16(hdr, 32, 2)              # block align
	_put_u16(hdr, 34, 16)             # bits per sample
	_put_ascii(hdr, 36, "data")
	_put_u32(hdr, 40, n * 2)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(hdr)
	f.store_buffer(data)
	f.close()
	return true


static func _put_ascii(b: PackedByteArray, at: int, s: String) -> void:
	var raw := s.to_ascii_buffer()
	for i in raw.size():
		b[at + i] = raw[i]


static func _put_u16(b: PackedByteArray, at: int, v: int) -> void:
	b[at] = v & 0xFF
	b[at + 1] = (v >> 8) & 0xFF


static func _put_u32(b: PackedByteArray, at: int, v: int) -> void:
	b[at] = v & 0xFF
	b[at + 1] = (v >> 8) & 0xFF
	b[at + 2] = (v >> 16) & 0xFF
	b[at + 3] = (v >> 24) & 0xFF
