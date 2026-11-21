extends RefCounted
#
# Level mesher (ticket T-011; TERRAIN_SPEC.md sections 4, 8, 12; DESIGN.md section 10).
#
# Builds the level visuals from the generator's Level dict (section 8.1) into one ArrayMesh per
# material. World units: 1 cell = 1 u, the top surface of tile [x, z, y] sits at y * 0.5 u, slabs
# are 1 u thick, ramps rise 1 HU over 1 u (26.57 deg). Coplanar same-material tiles are
# greedy-merged into rectangles; checker, grain, the slab surface (seam, bevel, noise) and the
# hub sigil are computed in the shaders from world position, so merging has no UV seams.
#
# Meshes (one ArrayMesh per material):
#   platform_top / walkway_top / deadend_top / hub_top  tile tops, light square = (x+z)&1 == 0
#   slab_side     1 u faces with the 0.125 u trim band (UV.y < trim rule) + slab bottoms
#   prop / prop_crate  prop boxes on their tile (kind 2 = crate), trimmed sides
#   spike         inverted stepped spike under small platforms (section 12.4), never the hub
#   pad           launch pad plate, emission pulsing 0.5..1.5 at 1 Hz
#   Ramp wedges join their piece's top material (sloped top quad) and slab_side (side walls).
#
# Determinism: a pure function of the Level dict. Section 12.4 allows mix(seed, piece id) for
# dressing randomness; none is used - the spike step profile is fixed.
# All vertices are in world space: instance the result at the origin.

const VoidRngScript := preload("res://terrain/void_rng.gd")
const FogEnvScript := preload("res://view/fog_env.gd")

const HU := 0.5             # world u per height unit (section 4)
const SLAB := 1.0           # visual slab thickness (u) = collision
const TRIM := 0.125         # trim band height (u) at the top of faces (UV.y < TRIM rule)
const TEXEL := 8.0          # px per u, nearest filtering (section 12.2)
const SPIKE_MAX_BBOX := 7   # spike only under platforms with bbox <= 7x7 cells (section 12.4)
const HUB_CLEAR_HU := 12    # HU: section 4 distance at which two pieces read as one (section 12.4)
# Inverted stepped spike profile: [width fraction of the 1x1 cell, height in u] top to tip,
# totalling 8 HU = 4 u (section 12.4). Fixed - section 12.4's mix(seed, piece id) allowance
# stays unused, so the dressing adds no RNG.
const SPIKE_STEPS := [[1.0, 2.0], [0.5, 1.5], [0.25, 0.5]]

const DX := [1, 0, -1, 0]   # section 4: 0 = +x, 1 = +z, 2 = -x, 3 = -z
const DZ := [0, 1, 0, -1]

const ROLES_HUB := 0
const ROLES_ROOM := 1
const ROLES_DEADEND := 2
const ROLES_LINK := 3
const ROLES_LOOP := 4
const ROLES_DROP := 5

const GRAIN_LO := 0.94      # per-texel lightness multiplier range [0.94, 1.06] (section 12.2)
const GRAIN_AMP := 0.12

# ---- materials --------------------------------------------------------------------------------

# Tile tops: world-space checker (light when (x + z) & 1 == 0) at 8 px/u, nearest. The slab look is
# computed from world position so greedy merging has no UV seams: a 1-texel seam gap on the +x/+z
# rims, an outer 3-texel bevel (light on the -x/-z edges, dark on +x/+z), slab-to-slab tone shift,
# the section 12.2 per-texel grain, a 3-octave value noise light modulation (+/-12%), a sparse dark
# speckle, a noise-derived normal perturbation (NORMAL) and noise-varied roughness/specular.
# umix/ufmix below mirror terrain_rng mix/fmix exactly (32-bit unsigned wrap). Static - no TIME.
const TOP_SHADER := "
shader_type spatial;
render_mode cull_back;

uniform vec3 color_light : source_color = vec3(0.184, 0.718, 0.690);
uniform vec3 color_dark : source_color = vec3(0.039, 0.180, 0.188);
uniform float emission_light : hint_range(0.0, 8.0) = 1.35;   // TOTAL factor: albedo + 0.35 x albedo

uint um32(uint a, uint b) {
	return (a & 0xFFFFu) * b + ((((a >> 16u) * b) & 0xFFFFu) << 16u);
}

uint ufmix(uint x) {
	uint z = x;
	z ^= z >> 16u;
	z = um32(z, 0x85EBCA6Bu);
	z ^= z >> 13u;
	z = um32(z, 0xC2B2AE35u);
	z ^= z >> 16u;
	return z;
}

uint umix(uint a, uint b) {
	return ufmix((a ^ um32(b + 0x9E3779B9u, 0x01000193u)));
}

float hash01(uint h) {
	return float(h & 1023u) / 1023.0;
}

// Deterministic smooth value noise on the world grid (smoothstep-bilinear hash lattice).
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash01(umix(uint(int(i.x)), uint(int(i.y))));
	float b = hash01(umix(uint(int(i.x + 1.0)), uint(int(i.y))));
	float c = hash01(umix(uint(int(i.x)), uint(int(i.y + 1.0))));
	float d = hash01(umix(uint(int(i.x + 1.0)), uint(int(i.y + 1.0))));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 3 octaves, wavelengths 0.5 / 0.25 / 0.125 u (4 / 2 / 1 px at 8 px/u), amplitudes sum to 1.
float fbm(vec2 p) {
	float v = 0.55 * vnoise(p * 2.0);
	v += 0.30 * vnoise(p * 4.0 + vec2(13.7, 7.3));
	v += 0.15 * vnoise(p * 8.0 + vec2(41.3, 27.9));
	return v;
}

varying vec3 v_world;
varying mat3 v_modelview;
varying mat3 v_modelview_t;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_modelview = mat3(MODELVIEW_MATRIX);
	v_modelview_t = transpose(mat3(MODELVIEW_MATRIX));
}

void fragment() {
	vec2 wp = v_world.xz;
	float checker = mod(floor(wp.x) + floor(wp.y), 2.0);
	vec3 albedo = mix(color_dark, color_light, 1.0 - checker);
	vec2 texel = floor(wp * 8.0);
	vec2 tile = floor(wp);
	vec2 ti = floor(fract(wp) * 8.0);    // 0..7 texel index inside the 8x8 square

	// section 12.2 per-texel grain, static
	uint grain_h = umix(uint(int(texel.x)), uint(int(texel.y)));
	float grain = 0.94 + 0.12 * float(grain_h & 255u) / 255.0;

	// slab-to-slab tone shift: each square sits at its own lightness
	float tile_h = hash01(umix(uint(int(tile.x)) + 0x51B1u, uint(int(tile.y)) + 0x0E7Fu));
	float tile_tint = 0.955 + 0.09 * tile_h;

	// 1-texel seam gap on the +x/+z rim of each square (every grid line drawn once)
	float seam = 1.0;
	if (ti.x > 6.5 || ti.y > 6.5) {
		seam = 0.58;
	}

	// bevel: outer 3 texels, top/left (-x/-z) raised light, bottom/right (+x/+z) dropped dark
	float bevel = 1.0;
	bevel *= 1.0 + 0.15 * max(0.0, 1.0 - ti.x / 3.0);
	bevel *= 1.0 + 0.15 * max(0.0, 1.0 - ti.y / 3.0);
	bevel *= 1.0 - 0.22 * max(0.0, 1.0 - (7.0 - ti.x) / 3.0);
	bevel *= 1.0 - 0.22 * max(0.0, 1.0 - (7.0 - ti.y) / 3.0);

	// 3-octave value-noise lightness, +/-12%
	float n = fbm(wp);
	float light_mod = 0.88 + 0.24 * n;

	// sparse dark speckle, ~5% of texels
	uint sp = umix(uint(int(texel.x)) + 0x9E37u, uint(int(texel.y)) + 0x7F4Au);
	float speckle = ((sp & 255u) < 14u) ? 0.72 : 1.0;

	float detail = tile_tint * grain * seam * bevel * light_mod * speckle;
	// light squares gain back the detail deficit: their average luminance holds at ~1.03x
	float gain = mix(1.0, 1.2, 1.0 - checker);
	ALBEDO = albedo * detail * gain;
	if (checker == 0.0) {
		// mean factor ~1.16 vs the pure palette emission: detail stays visible in the dark,
		// light squares' average luminance is raised slightly, never darkened
		EMISSION = color_light * (emission_light - 1.0) * clamp(detail * 1.35, 0.0, 2.0);
	}

	// relief: world-space gradient of the same noise, added to the geometric normal
	float e = 0.05;
	float hx = fbm(wp + vec2(e, 0.0)) - fbm(wp - vec2(e, 0.0));
	float hz = fbm(wp + vec2(0.0, e)) - fbm(wp - vec2(0.0, e));
	vec3 base_world = v_modelview_t * NORMAL;
	vec3 n_world = base_world + vec3(-hx * 1.1, 0.0, -hz * 1.1);
	NORMAL = normalize(v_modelview * normalize(n_world));

	// roughness/specular vary with the noise so the fill light glints unevenly
	ROUGHNESS = clamp(0.92 - 0.50 * n, 0.42, 0.95);
	SPECULAR = clamp(0.30 + 0.45 * n, 0.15, 0.75);
}
"
# Sides carry a subtle world-space noise break-up (lightness + speckle + roughness) so they are
# never dead flat once a light is present; the trim band rule is unchanged (UV.y < trim_height).
const SIDE_SHADER := "
shader_type spatial;
render_mode cull_back;

uniform vec3 color : source_color = vec3(0.06, 0.25, 0.26);
uniform vec3 trim_color : source_color = vec3(0.11, 0.43, 0.44);
uniform float trim_height : hint_range(0.0, 2.0) = 0.125;

uint um32(uint a, uint b) {
	return (a & 0xFFFFu) * b + ((((a >> 16u) * b) & 0xFFFFu) << 16u);
}

uint ufmix(uint x) {
	uint z = x;
	z ^= z >> 16u;
	z = um32(z, 0x85EBCA6Bu);
	z ^= z >> 13u;
	z = um32(z, 0xC2B2AE35u);
	z ^= z >> 16u;
	return z;
}

uint umix(uint a, uint b) {
	return ufmix((a ^ um32(b + 0x9E3779B9u, 0x01000193u)));
}

float hash01(uint h) {
	return float(h & 1023u) / 1023.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash01(umix(uint(int(i.x)), uint(int(i.y))));
	float b = hash01(umix(uint(int(i.x + 1.0)), uint(int(i.y))));
	float c = hash01(umix(uint(int(i.x)), uint(int(i.y + 1.0))));
	float d = hash01(umix(uint(int(i.x + 1.0)), uint(int(i.y + 1.0))));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	return 0.6 * vnoise(p * 2.0) + 0.4 * vnoise(p * 5.0 + vec2(13.7, 7.3));
}

varying vec3 v_world;
varying vec3 v_nw;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nw = mat3(MODEL_MATRIX) * NORMAL;
}

void fragment() {
	vec3 albedo;
	if (UV.y < trim_height) {
		albedo = trim_color;
	} else {
		albedo = color;
	}
	// sample the face plane (z,y) for x-facing walls, (x,y) for z-facing walls
	vec2 sp = (abs(v_nw.x) > 0.5) ? v_world.zy : v_world.xy;
	float n = fbm(sp);
	albedo *= 0.91 + 0.18 * n;
	vec2 texel = floor(sp * 8.0);
	uint hs = umix(uint(int(texel.x)) + 0x9E37u, uint(int(texel.y)) + 0x7F4Au);
	if ((hs & 255u) < 12u) {
		albedo *= 0.75;
	}
	ALBEDO = albedo;
	ROUGHNESS = clamp(0.90 - 0.35 * n, 0.5, 1.0);
	SPECULAR = clamp(0.25 + 0.40 * n, 0.15, 0.65);
}
"

# Hub dais: solid colour with the 12-point star sigil (section 12.2: #1C6E70 dais, #031A1B
# sigil, 12-point star on the 5x5 dais centred on the beacon tile (0, 0)). The star radius test
# runs on the nearest texel centre (8 px/u), so the decal is as crisp as a texture.
const HUB_SHADER := "
shader_type spatial;
render_mode cull_back;

uniform vec3 color : source_color = vec3(0.11, 0.43, 0.44);
uniform vec3 sigil_color : source_color = vec3(0.01, 0.1, 0.11);
uniform vec2 star_centre = vec2(0.5, 0.5);
uniform float star_r_out = 2.4;
uniform float star_r_in = 1.0;

uint um32(uint a, uint b) {
	return (a & 0xFFFFu) * b + ((((a >> 16u) * b) & 0xFFFFu) << 16u);
}

uint ufmix(uint x) {
	uint z = x;
	z ^= z >> 16u;
	z = um32(z, 0x85EBCA6Bu);
	z ^= z >> 13u;
	z = um32(z, 0xC2B2AE35u);
	z ^= z >> 16u;
	return z;
}

uint umix(uint a, uint b) {
	return ufmix((a ^ um32(b + 0x9E3779B9u, 0x01000193u)));
}

float hash01(uint h) {
	return float(h & 1023u) / 1023.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash01(umix(uint(int(i.x)), uint(int(i.y))));
	float b = hash01(umix(uint(int(i.x + 1.0)), uint(int(i.y))));
	float c = hash01(umix(uint(int(i.x)), uint(int(i.y + 1.0))));
	float d = hash01(umix(uint(int(i.x + 1.0)), uint(int(i.y + 1.0))));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.55 * vnoise(p * 2.0);
	v += 0.30 * vnoise(p * 4.0 + vec2(13.7, 7.3));
	v += 0.15 * vnoise(p * 8.0 + vec2(41.3, 27.9));
	return v;
}

varying vec3 v_world;
varying mat3 v_modelview;
varying mat3 v_modelview_t;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_modelview = mat3(MODELVIEW_MATRIX);
	v_modelview_t = transpose(mat3(MODELVIEW_MATRIX));
}

void fragment() {
	vec2 wp = v_world.xz;
	float checker = mod(floor(wp.x) + floor(wp.y), 2.0);
	vec3 albedo = mix(color * 0.52, color, 1.0 - checker);
	vec2 texel = floor(wp * 8.0);
	vec2 tile = floor(wp);
	vec2 ti = floor(fract(wp) * 8.0);

	uint grain_h = umix(uint(int(texel.x)), uint(int(texel.y)));
	float grain = 0.94 + 0.12 * float(grain_h & 255u) / 255.0;

	float tile_h = hash01(umix(uint(int(tile.x)) + 0x51B1u, uint(int(tile.y)) + 0x0E7Fu));
	float tile_tint = 0.955 + 0.09 * tile_h;

	float seam = 1.0;
	if (ti.x > 6.5 || ti.y > 6.5) {
		seam = 0.58;
	}

	float bevel = 1.0;
	bevel *= 1.0 + 0.15 * max(0.0, 1.0 - ti.x / 3.0);
	bevel *= 1.0 + 0.15 * max(0.0, 1.0 - ti.y / 3.0);
	bevel *= 1.0 - 0.22 * max(0.0, 1.0 - (7.0 - ti.x) / 3.0);
	bevel *= 1.0 - 0.22 * max(0.0, 1.0 - (7.0 - ti.y) / 3.0);

	float n = fbm(wp);
	float light_mod = 0.88 + 0.24 * n;

	uint sp = umix(uint(int(texel.x)) + 0x9E37u, uint(int(texel.y)) + 0x7F4Au);
	float speckle = ((sp & 255u) < 14u) ? 0.72 : 1.0;

	float detail = tile_tint * grain * seam * bevel * light_mod * speckle;
	ALBEDO = albedo * detail;

	// the dais sigil, drawn on the nearest texel centre so it stays crisp
	vec2 tex = (texel + 0.5) / 8.0;
	vec2 d = tex - star_centre;
	float r = length(d);
	float x12 = (atan(d.y, d.x) * 12.0) / 6.2831853;
	float wave = abs(fract(x12) - 0.5) * 2.0;    // 1 at a star tip, 0 halfway to the next tip
	float r_max = mix(star_r_in, star_r_out, wave);
	if (r <= r_max) {
		ALBEDO = sigil_color * detail;
	}

	float e = 0.05;
	float hx = fbm(wp + vec2(e, 0.0)) - fbm(wp - vec2(e, 0.0));
	float hz = fbm(wp + vec2(0.0, e)) - fbm(wp - vec2(0.0, e));
	vec3 base_world = v_modelview_t * NORMAL;
	vec3 n_world = base_world + vec3(-hx * 1.1, 0.0, -hz * 1.1);
	NORMAL = normalize(v_modelview * normalize(n_world));

	ROUGHNESS = clamp(0.92 - 0.50 * n, 0.42, 0.95);
	SPECULAR = clamp(0.30 + 0.45 * n, 0.15, 0.75);
}
"

const PAD_SHADER := "
shader_type spatial;
render_mode cull_back;

uniform vec3 color : source_color = vec3(0.16, 0.36, 1.0);
uniform float pulse_lo : hint_range(0.0, 8.0) = 0.5;
uniform float pulse_hi : hint_range(0.0, 8.0) = 1.5;

void fragment() {
	float e = mix(pulse_lo, pulse_hi, 0.5 + 0.5 * sin(TIME * 6.2831853));
	ALBEDO = color;
	EMISSION = color * e;
}
"

# ---- mesh assembly ---------------------------------------------------------------------------

class Surf:
	var pos: PackedVector3Array = PackedVector3Array()
	var nor: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var idx: PackedInt32Array = PackedInt32Array()

	func quad(pts: Array, uvs_in: Array, n: Vector3) -> void:
		var b := pos.size()
		for i in range(4):
			pos.append(pts[i])
			nor.append(n)
			uvs.append(uvs_in[i])
		idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))

# ---- material factory ------------------------------------------------------------------------

static var _shader_cache := {}


static func _shader(code: String) -> Shader:
	if not _shader_cache.has(code):
		var sh := Shader.new()
		sh.code = code
		_shader_cache[code] = sh
	return _shader_cache[code]


## Merged role table: role name -> { "hex": "#RRGGBB", "emission": float }.
static func _roles_of(biome: Dictionary) -> Dictionary:
	var bd: Dictionary = biome
	if bd.is_empty():
		bd = FogEnvScript.resolve_palette("")
	return bd["roles"]


## One ShaderMaterial per mesh name (TERRAIN_SPEC section 12.2):
## platform/walkway/deadend/hub tops (checker + grain + sigil), slab side with trim band,
## prop boxes with side trim, spikes, launch pad plate.
static func make_materials(biome: Dictionary = {}) -> Dictionary:
	var R: Dictionary = _roles_of(biome)
	var trim: Color = Color(R["slab_trim"]["hex"])
	var mats := {}
	# TOP_SHADER emission_light = the TOTAL light-square factor: 1.35 = albedo + 0.35 x albedo.
	mats["platform_top"] = _top_mat(Color(R["platform_light"]["hex"]), Color(R["platform_dark"]["hex"]), 1.0 + float(R["platform_light"].get("emission", 0.0)))
	mats["walkway_top"] = _top_mat(Color(R["walkway_light"]["hex"]), Color(R["walkway_dark"]["hex"]), 1.0 + float(R["walkway_light"].get("emission", 0.0)))
	# Section 12.2 states no emission for the dead-end light role - it ships without.
	mats["deadend_top"] = _top_mat(Color(R["dead_end_light"]["hex"]), Color(R["platform_dark"]["hex"]), 1.0)
	var hub := ShaderMaterial.new()
	hub.shader = _shader(HUB_SHADER)
	hub.set_shader_parameter("color", Color(R["hub_dais"]["hex"]))
	hub.set_shader_parameter("sigil_color", Color(R["hub_dais"]["sigil_hex"]))
	mats["hub_top"] = hub
	mats["slab_side"] = _side_mat(Color(R["slab_side"]["hex"]), trim, TRIM)
	mats["prop"] = _side_mat(Color(R["prop_block"]["hex"]), Color(R["prop_block"].get("trim_hex", R["slab_trim"]["hex"])), TRIM)
	mats["prop_crate"] = _side_mat(Color(R["prop_crate"]["hex"]), trim, TRIM)
	mats["spike"] = _side_mat(Color(R["support_spike"]["hex"]), Color(R["support_spike"]["hex"]), 0.0)
	mats["pad"] = _pad_mat(Color(R["launch_pad"]["hex"]))
	return mats

const TOP_MATS := ["platform_top", "walkway_top", "deadend_top", "hub_top"]
const ALL_MATS := ["platform_top", "walkway_top", "deadend_top", "hub_top", "slab_side", "prop", "prop_crate", "spike", "pad"]


static func _top_mat(light_col: Color, dark_col: Color, emission_total: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(TOP_SHADER)
	mat.set_shader_parameter("color_light", light_col)
	mat.set_shader_parameter("color_dark", dark_col)
	mat.set_shader_parameter("emission_light", emission_total)
	return mat


static func _side_mat(col: Color, trim_col: Color, trim_h: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(SIDE_SHADER)
	mat.set_shader_parameter("color", col)
	mat.set_shader_parameter("trim_color", trim_col)
	mat.set_shader_parameter("trim_height", trim_h)
	return mat


static func _pad_mat(col: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(PAD_SHADER)
	mat.set_shader_parameter("color", col)
	return mat


## CPU reference for the section 12.2 grain rule - the same rule TOP_SHADER runs per fragment.
## Inputs are the global texel indices (tile * 8 + px); negative tile coordinates normalize into
## the unsigned 32-bit domain first (the shader uint() cast wraps the same way), and the hash is
## VoidRngScript.mix exactly as the brief states. Static - never animated.
static func grain_factor(texel_x: int, texel_z: int) -> float:
	var h: int = VoidRngScript.mix(texel_x & 0xFFFFFFFF, texel_z & 0xFFFFFFFF) & 0xFF
	return 0.94 + GRAIN_AMP * float(h) / 255.0



static func _top_mat_name(role: int) -> String:
	match role:
		ROLES_HUB:
			return "hub_top"
		ROLES_DEADEND:
			return "deadend_top"
		ROLES_LINK, ROLES_LOOP, ROLES_DROP:
			return "walkway_top"
	return "platform_top"


## Face factory: winding-verified axis faces (outward normals, CCW from outside).
static func _face_x(s: Surf, x: float, y0: float, y1: float, z0: float, z1: float, dir_i: int, top_ref: float) -> void:
	_side(s, dir_i, x, y0, z0, x, y1, z1, top_ref)


static func _face_z(s: Surf, z: float, x0: float, x1: float, y0: float, y1: float, dir_i: int, top_ref: float) -> void:
	_side(s, dir_i, x0, y0, z, x1, y1, z, top_ref)


static func _face_y(s: Surf, y: float, x0: float, x1: float, z0: float, z1: float, up: bool) -> void:
	# uv.y = 1: away from the trim band (top shaders ignore uv entirely).
	var uv := Vector2(0.0, 1.0)
	if up:
		s.quad([Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)],
			[uv, uv, uv, uv], Vector3(0, 1, 0))
	else:
		s.quad([Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(x1, y, z0)],
			[uv, uv, uv, uv], Vector3(0, -1, 0))


## Vertical quad on one plane with the outward normal of dir_i. uv.y = top_ref - world y (the
## side shader reads the trim band from it: trim where uv.y < trim_height); uv.x unused.
static func _side(s: Surf, dir_i: int, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float, top_ref: float) -> void:
	var pts: Array
	match dir_i:
		0:
			pts = [Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1)]
		2:
			pts = [Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x0, y0, z0)]
		1:
			pts = [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0)]
		_:
			pts = [Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0)]
	var n := Vector3(DX[dir_i], 0, DZ[dir_i])
	var uvs: Array = []
	for p in pts:
		uvs.append(Vector2(0.0, top_ref - p.y))
	s.quad(pts, uvs, n)

## Vertical face on the boundary side dir_i of cell box x0..x1 z0..z1 (dir 2 -> x0, dir 0 -> x1,
## dir 3 -> z0, dir 1 -> z1 plane).
static func _side_rect(s: Surf, dir_i: int, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, top_ref: float) -> void:
	if dir_i == 0 or dir_i == 2:
		_face_x(s, x0 if dir_i == 2 else x1, y0, y1, z0, z1, dir_i, top_ref)
	else:
		_face_z(s, z0 if dir_i == 3 else z1, x0, x1, y0, y1, dir_i, top_ref)


## True when the side face of tile (x, z) with top edge y (HU) toward dir_i is fully hidden: the
## neighbour column holds a tile whose edge on the shared boundary has the same HU height (its
## 1 u slab then covers this face's whole span). A neighbour ramp's HIGH edge counts as y + 1.
static func _edge_covered(cols: Dictionary, x: int, z: int, y: int, dir_i: int) -> bool:
	var ncol: Dictionary = cols.get("%d,%d" % [x + int(DX[dir_i]), z + int(DZ[dir_i])], {})
	var from_n := (dir_i + 2) % 4     # my direction as seen from the neighbour
	for y2 in ncol:
		var facing: int = int(y2)
		if int(ncol[y2]) > ROLES_HUB and int(ncol[y2]) - 1 == from_n:
			facing += 1
		if facing == y:
			return true
	return false


## Face plane coordinate (cell boundary) for a tile side toward dir_i.
static func _side_plane(x: int, z: int, dir_i: int) -> int:
	match dir_i:
		0:
			return x + 1
		2:
			return x
		1:
			return z + 1
	return z


## Greedy 1D runs over { int coord: true } -> [[start, count], ...], ascending.
static func _runs(coords: Dictionary) -> Array:
	var keys: Array = coords.keys()
	keys.sort()
	var out: Array = []
	var i := 0
	while i < keys.size():
		var start: int = keys[i]
		var n := 1
		while i + n < keys.size() and int(keys[i + n]) == start + n:
			n += 1
		out.append([start, n])
		i += n
	return out

## Classic greedy 2D merge over one coplanar layer {"x,z": true} -> [[x, z, w, d], ...].
static func _merge_layer(cells: Dictionary) -> Array:
	var used := {}
	var rects: Array = []
	var keys: Array = cells.keys()
	keys.sort()
	for key in keys:
		if used.has(key):
			continue
		var parts: PackedStringArray = (key as String).split(",")
		var x: int = int(parts[0])
		var z: int = int(parts[1])
		var w := 1
		while cells.has("%d,%d" % [x + w, z]) and not used.has("%d,%d" % [x + w, z]):
			w += 1
		var d := 1
		var growing := true
		while growing:
			growing = false
			var full := true
			for i in range(w):
				var k := "%d,%d" % [x + i, z + d]
				if not cells.has(k) or used.has(k):
					full = false
					break
			if full:
				d += 1
				growing = true
		for i in range(w):
			for j in range(d):
				used["%d,%d" % [x + i, z + j]] = true
		rects.append([x, z, w, d])
	return rects
# ---- ramp wedges ------------------------------------------------------------------------------

## (a, l) -> world: a = ramp axis offset, l = lateral offset, h = world y.
static func _wpt(fx: float, fz: float, ax: float, az: float, lx: float, lz: float, a: float, l: float, h: float) -> Vector3:
	return Vector3(fx + a * ax + l * lx, h, fz + a * az + l * lz)

## One ramp tile [x, z, y, asc]: kind 1+d, LOW edge at y HU, high edge y+1 HU, ascending toward
## direction d (section 4; slope 0.5 u per 1 u = 26.57 deg). The sloped top joins the piece's
## top material (checker/grain continue seamlessly); the two lateral walls are parallelograms
## in slab_side with the trim band hugging the surface; the high-edge and low-edge vertical
## faces are skipped exactly when a neighbour slab covers them.
static func _wedge(s_top: Surf, s_side: Surf, x: int, z: int, y: int, d: int, cols: Dictionary) -> void:
	var ax: float = DX[d]
	var az: float = DZ[d]
	var lx: float = DX[(d + 1) % 4]
	var lz: float = DZ[(d + 1) % 4]
	var fx := float(x)
	var fz := float(z)
	var ry := float(y) * HU
	var rh := float(y + 1) * HU
	var zero := Vector2.ZERO


	# sloped top; normal opposes the rise direction. Winding: low edge first, then the high
	# edge in the same lateral order - the reverse of that order is back-facing from above
	# (the same defect _face_y had, which culled every tile top).
	s_top.quad([_wpt(fx, fz, ax, az, lx, lz, 0.0, 0.0, ry), _wpt(fx, fz, ax, az, lx, lz, 1.0, 0.0, rh), _wpt(fx, fz, ax, az, lx, lz, 1.0, 1.0, rh), _wpt(fx, fz, ax, az, lx, lz, 0.0, 1.0, ry)],
		[zero, zero, zero, zero], Vector3(-0.5 * ax, 1.0, -0.5 * az).normalized())

	# high edge face (top edge = rh): covered by a tile at y+1 exactly
	if not _edge_covered(cols, x, z, y + 1, d):
		_side_rect(s_side, d, fx, fx + 1.0, rh - SLAB, rh, fz, fz + 1.0, rh)
	# low edge face (top edge = ry)
	var back := (d + 2) % 4
	if not _edge_covered(cols, x, z, y, back):
		_side_rect(s_side, back, fx, fx + 1.0, ry - SLAB, ry, fz, fz + 1.0, ry)

	# lateral walls: (a, y) corners of the side plane, trim band hugging the surface line
	var u_lo := Vector2(0.0, 1.0)
	var u_hi := Vector2(0.0, 0.0)
	for lat_side in [[(d + 1) % 4, 1.0, true], [(d + 3) % 4, 0.0, false]]:
		var sdir: int = lat_side[0]
		var lo: float = lat_side[1]
		var nl := Vector3(DX[sdir], 0, DZ[sdir])
		var c0 := _wpt(fx, fz, ax, az, lx, lz, 0.0, lo, ry - 1.0)
		var c1 := _wpt(fx, fz, ax, az, lx, lz, 1.0, lo, rh - 1.0)
		var c2 := _wpt(fx, fz, ax, az, lx, lz, 1.0, lo, rh)
		var c3 := _wpt(fx, fz, ax, az, lx, lz, 0.0, lo, ry)
		if lat_side[2]:
			s_side.quad([c0, c1, c2, c3], [u_lo, u_lo, u_hi, u_hi], nl)
		else:
			s_side.quad([c0, c3, c2, c1], [u_lo, u_hi, u_hi, u_lo], nl)


# ---- build -----------------------------------------------------------------------------------

## Build the level's visual meshes from a Level dict (TERRAIN_SPEC section 8.1).
## biome: optional merged palette (FogEnvScript.resolve_palette(biome_id, level)); default is
## the level's own biome. Returns:
##   meshes:     { material name -> ArrayMesh } (only materials with geometry)
##   materials:  { material name -> ShaderMaterial } (every material, empty or not)
##   triangles:  total triangle count over every mesh
##   ms:         meshing wall time (Time.get_ticks_usec based, this call only)
##   tiles_top / tiles_flat / ramps / spikes / props / pads: counts for tests
## part: "" (default) meshes the whole level exactly as before. PART_HUB meshes only the hub
## piece (tiles, props and pads on it); PART_REST meshes everything else (the platform
## collapse drops that set as one node). In a split build each part's hidden-face test sees
## only its own tiles, so a seam face between the hub and a neighbour is kept on both sides
## and neither part shows a hole once the other is gone.
## PART_ZONE meshes only the pieces whose ids are keys of `zone_pieces` (one collapse zone,
## sim/collapse.gd; D-B10-1): the sequential collapse drops each zone on its own, so each zone
## is its own part. The hub is never in a zone set. The same per-part hidden-face rule holds.
const PART_HUB := "hub"
const PART_REST := "rest"
const PART_ZONE := "zone"


static func build(L: Dictionary, biome: Dictionary = {}, part: String = "",
		zone_pieces: Dictionary = {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var split_hub := -1
	for p in L.get("pieces", []):
		if int(p["role"]) == ROLES_HUB:
			split_hub = int(p["id"])
			break
	var want_hub := part == PART_HUB
	var split := part == PART_HUB or part == PART_REST
	var zoned := part == PART_ZONE
	var lvl := int(L.get("level", 1))
	var bd: Dictionary = biome
	if bd.is_empty():
		bd = FogEnvScript.resolve_palette(FogEnvScript.biome_id_for_level(lvl), lvl)
	var mats := make_materials(bd)
	var surf := {}
	for mn in ALL_MATS:
		surf[mn] = Surf.new()

	# Classification pass. cols: "x,z" -> { y(HU): tile kind }; piece_min_y: for the 12.4 rule.
	var cols := {}
	var cols_e := {}    # the part's own columns (== cols when part is ""): hidden-face test
	var tile_piece := {}   # "x,z,y" -> piece id, to place pads in a split build
	var role_of := {}
	var piece_y := {}
	var tops := {}      # top mat -> { y(HU) -> {"x,z": true} }
	var ramps := {}     # top mat -> [[x, z, y, asc]]
	for mat in TOP_MATS:
		tops[mat] = {}
		ramps[mat] = []
	var n_flat := 0
	for p in L.get("pieces", []):
		role_of[int(p["id"])] = int(p["role"])
	for t in L.get("tiles", []):
		var x: int = int(t[0])
		var z: int = int(t[1])
		var y: int = int(t[2])
		var kind: int = int(t[3])
		var pid: int = int(t[4])
		var kz := "%d,%d" % [x, z]
		if not cols.has(kz):
			cols[kz] = {}
		(cols[kz] as Dictionary)[y] = kind
		if not piece_y.has(pid) or y < int(piece_y[pid]):
			piece_y[pid] = y
		tile_piece["%d,%d,%d" % [x, z, y]] = pid
		if split and ((pid == split_hub) != want_hub):
			continue
		if zoned and not zone_pieces.has(pid):
			continue
		if not cols_e.has(kz):
			cols_e[kz] = {}
		(cols_e[kz] as Dictionary)[y] = kind
		var mat: String = _top_mat_name(int(role_of.get(pid, ROLES_ROOM)))
		if kind == 0:
			n_flat += 1
			var layer: Dictionary = tops[mat]
			if not layer.has(y):
				layer[y] = {}
			(layer[y] as Dictionary)["%d,%d" % [x, z]] = true
		else:
			ramps[mat].append([x, z, y, kind - 1])

	# Tile tops + slab bottoms, greedy per material per HU layer.
	var top_tiles := 0
	for mat in TOP_MATS:
		for y in tops[mat]:
			var wy: float = float(y) * HU
			for rect in _merge_layer(tops[mat][y]):
				var x0: float = float(rect[0])
				var z0: float = float(rect[1])
				var x1: float = float(rect[0] + rect[2])
				var z1: float = float(rect[1] + rect[3])
				_face_y(surf[mat], wy, x0, x1, z0, z1, true)
				_face_y(surf["slab_side"], wy - SLAB, x0, x1, z0, z1, false)
				top_tiles += rect[2] * rect[3]

	# Vertical faces: hidden-face test, then 1D run merge per (top edge HU, dir, plane).
	var side_faces := {}
	for t in L.get("tiles", []):
		if int(t[3]) != 0:
			continue
		if split and ((int(t[4]) == split_hub) != want_hub):
			continue
		if zoned and not zone_pieces.has(int(t[4])):
			continue
		var x: int = int(t[0])
		var z: int = int(t[1])
		var y: int = int(t[2])
		for d in range(4):
			if _edge_covered(cols_e, x, z, y, d):
				continue
			var key := "%d|%d|%d" % [y, d, _side_plane(x, z, d)]
			if not side_faces.has(key):
				side_faces[key] = {}
			(side_faces[key] as Dictionary)[z if d == 0 or d == 2 else x] = true
	for key in side_faces:
		var parts: PackedStringArray = (key as String).split("|")
		var yhu: int = int(parts[0])
		var dir_i: int = int(parts[1])
		var plane: float = float(int(parts[2]))
		var top: float = float(yhu) * HU
		for run in _runs(side_faces[key]):
			var a0: float = float(run[0])
			var a1: float = float(run[0] + run[1])
			if dir_i == 0 or dir_i == 2:
				_face_x(surf["slab_side"], plane, top - SLAB, top, a0, a1, dir_i, top)
			else:
				_face_z(surf["slab_side"], plane, a0, a1, top - SLAB, top, dir_i, top)


	# Ramp wedges (rare: ramps are at most 10% of path rows in every archetype table).
	var n_ramps := 0
	for mat in TOP_MATS:
		for wr in ramps[mat]:
			_wedge(surf[mat], surf["slab_side"], int(wr[0]), int(wr[1]), int(wr[2]), int(wr[3]), cols_e)
			n_ramps += 1

	# Props: boxes standing on their tile, top + 4 sides, side trim like slabs (kind 2 crate).
	var props_meshed := 0
	for p in L.get("props", []):
		if split and ((int(p[5]) == split_hub) != want_hub):
			continue
		if zoned and not zone_pieces.has(int(p[5])):
			continue
		var px: float = float(p[0])
		var pz: float = float(p[1])
		var pbase: float = float(p[2]) * HU
		var ph: float = float(p[3]) * HU
		var ptop: float = pbase + ph
		var s: Surf = surf["prop_crate"] if int(p[4]) == 2 else surf["prop"]
		_face_y(s, ptop, px, px + 1.0, pz, pz + 1.0, true)
		_side_rect(s, 0, px, px + 1.0, pbase, ptop, pz, pz + 1.0, ptop)
		_side_rect(s, 2, px, px + 1.0, pbase, ptop, pz, pz + 1.0, ptop)
		_side_rect(s, 1, px, px + 1.0, pbase, ptop, pz, pz + 1.0, ptop)
		_side_rect(s, 3, px, px + 1.0, pbase, ptop, pz, pz + 1.0, ptop)
		props_meshed += 1

	# Launch pads: 0.125 u plate on the tile top (section 12.2: pulsing emission 0.5-1.5 at 1 Hz).
	var pads_meshed := 0
	for p in L.get("pads", []):
		var pad_pid: int = int(tile_piece.get("%d,%d,%d" % [int(p[0]), int(p[1]), int(p[2])], -2))
		if split and ((pad_pid == split_hub) != want_hub):
			continue
		if zoned and not zone_pieces.has(pad_pid):
			continue
		var px: float = float(p[0])
		var pz: float = float(p[1])
		var pbase: float = float(p[2]) * HU
		var ptop: float = pbase + TRIM
		var s: Surf = surf["pad"]
		_face_y(s, ptop, px, px + 1.0, pz, pz + 1.0, true)
		_side_rect(s, 0, px, px + 1.0, pbase, ptop, pz, pz + 1.0, ptop)
		_side_rect(s, 2, px, px + 1.0, pbase, ptop, pz, pz + 1.0, ptop)
		_side_rect(s, 1, px, px + 1.0, pbase, ptop, pz, pz + 1.0, ptop)
		_side_rect(s, 3, px, px + 1.0, pbase, ptop, pz, pz + 1.0, ptop)
		pads_meshed += 1

	# "Anything that reads as part of the hub" (section 12.4, "Under the HUB: nothing"). The role
	# filter alone keeps the hub piece spike-free, but a spike under ANOTHER piece can still hang
	# on the hub: centre inside the hub footprint and vertical span within HUB_CLEAR_HU of the hub
	# slab reads as attached to it. Suppress it there, whatever the supporting piece is; a span a
	# full layer away is a different floor and stays legal. This mirrors test_mesh.gd's hub rule
	# (spike span from the platform's lowest tile, slab 2 HU, spike 8 HU) so the mesher and the test
	# agree on what hangs on the hub.
	var hub_bb: Array = []
	var hub_pid := -1
	for p in L.get("pieces", []):
		if int(p["role"]) == ROLES_HUB:
			hub_bb = p["bbox"]
			hub_pid = int(p["id"])
			break
	var hub_ymin := 1 << 30
	var hub_ymax := -(1 << 30)
	if hub_pid >= 0:
		for t in L.get("tiles", []):
			if int(t[4]) == hub_pid:
				var hty: int = int(t[2])
				if hty < hub_ymin:
					hub_ymin = hty
				if hty > hub_ymax:
					hub_ymax = hty
	var spike_len_hu := 0
	for seg in SPIKE_STEPS:
		spike_len_hu += roundi(float(seg[1]) / HU)
	var slab_hu: int = roundi(SLAB / HU)

	# Support spikes (section 12.4): under each role-1/2 piece with bbox <= 7x7 cells, an
	# inverted stepped spike below the bbox centre, 1x1 cell, 8 HU total. Skipped entirely when
	# any of the 9 columns around the centre column holds a tile below the platform. Never
	# under the hub, and never on anything that reads as part of the hub (see above).
	var spike_cells: Array = []    # [cx, cz] centre cell of each spike, for tests
	for p in (L.get("pieces", []) if not want_hub else []):
		var srole: int = int(p["role"])
		if srole != ROLES_ROOM and srole != ROLES_DEADEND:
			continue
		var bb: Array = p["bbox"]
		var bbw: int = int(bb[2]) - int(bb[0]) + 1
		var bbd: int = int(bb[3]) - int(bb[1]) + 1
		if bbw > SPIKE_MAX_BBOX or bbd > SPIKE_MAX_BBOX:
			continue
		var pid: int = int(p["id"])
		if zoned and not zone_pieces.has(pid):
			continue
		@warning_ignore("integer_division")
		var cxi: int = (int(bb[0]) + int(bb[2])) / 2
		@warning_ignore("integer_division")
		var czi: int = (int(bb[1]) + int(bb[3])) / 2
		var below := false
		for ddx in range(-1, 2):
			for ddz in range(-1, 2):
				var ncol: Dictionary = cols.get("%d,%d" % [cxi + ddx, czi + ddz], {})
				for y2 in ncol:
					if int(y2) < int(piece_y[pid]):
						below = true
		if below:
			continue
		if hub_pid >= 0 and _spike_hangs_on_hub(hub_bb, hub_ymin, hub_ymax, cxi, czi, int(piece_y[pid]), slab_hu, spike_len_hu):
			continue
		var stem: Surf = surf["spike"]
		var bottom: float = float(int(piece_y[pid])) * HU - SLAB
		var wx: float = (float(bb[0]) + float(bb[2]) + 1.0) * 0.5
		var wz: float = (float(bb[1]) + float(bb[3]) + 1.0) * 0.5
		var cum := 0.0
		for si in range(SPIKE_STEPS.size()):
			var seg: Array = SPIKE_STEPS[si]
			var seg_top: float = bottom - cum
			cum += float(seg[1])
			var seg_bot: float = bottom - cum
			var half: float = 0.5 * float(seg[0])
			_face_x(stem, wx - half, seg_bot, seg_top, wz - half, wz + half, 2, seg_top)
			_face_x(stem, wx + half, seg_bot, seg_top, wz - half, wz + half, 0, seg_top)
			_face_z(stem, wz - half, wx - half, wx + half, seg_bot, seg_top, 3, seg_top)
			_face_z(stem, wz + half, wx - half, wx + half, seg_bot, seg_top, 1, seg_top)
			if si > 0:
				_face_y(stem, seg_top, wx - half, wx + half, wz - half, wz + half, true)
			if si == SPIKE_STEPS.size() - 1:
				_face_y(stem, seg_bot, wx - half, wx + half, wz - half, wz + half, false)
		spike_cells.append([cxi, czi])

	# Commit one ArrayMesh per material; materials with no geometry are omitted.
	var meshes := {}
	var triangles := 0
	for mn in ALL_MATS:
		var s: Surf = surf[mn]
		if s.idx.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.pos
		arrays[Mesh.ARRAY_NORMAL] = s.nor
		arrays[Mesh.ARRAY_TEX_UV] = s.uvs
		arrays[Mesh.ARRAY_INDEX] = s.idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		m.surface_set_material(0, mats[mn])
		meshes[mn] = m
		@warning_ignore("integer_division")
		triangles += s.idx.size() / 3
	return {
		"meshes": meshes,
		"materials": mats,
		"triangles": triangles,
		"ms": (Time.get_ticks_usec() - t0) / 1000,
		"tiles_top": top_tiles,
		"tiles_flat": n_flat,
		"ramps": n_ramps,
		"props": props_meshed,
		"pads": pads_meshed,
		"spikes": spike_cells,
	}


## True when a spike at centre cell (cx, cz), hung from a platform whose lowest tile is at
## plat_min_y (HU), reads as part of the hub: its centre sits inside the hub bbox AND its vertical
## span (slab bottom down the spike's full length) comes within HUB_CLEAR_HU of the hub slab.
## hub_ymin / hub_ymax are the hub tiles' y range in HU. Same predicate as test_mesh.gd's
## _spike_hangs_on_hub, so the mesher and the test agree on what hangs on the hub.
static func _spike_hangs_on_hub(hub_bb: Array, hub_ymin: int, hub_ymax: int, cx: int, cz: int, plat_min_y: int, slab_hu: int, spike_hu: int) -> bool:
	if cx < int(hub_bb[0]) or cx > int(hub_bb[2]) or cz < int(hub_bb[1]) or cz > int(hub_bb[3]):
		return false
	var s_top: int = plat_min_y - slab_hu
	var s_bot: int = s_top - spike_hu
	var h_top: int = hub_ymax
	var h_bot: int = hub_ymin - slab_hu
	var gap := 0
	if s_bot > h_top:
		gap = s_bot - h_top
	elif s_top < h_bot:
		gap = h_bot - s_top
	return gap < HUB_CLEAR_HU
