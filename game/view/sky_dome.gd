extends MeshInstance3D
#
# Procedural cloud dome (DECISIONS D-ATMO-1). A large sphere seen from the inside, carrying a
# spatial shader: horizon -> zenith gradient, three fbm value-noise layers (5 octaves each)
# shaped by narrow smoothsteps into hard-edged billows, a broad dark mass in the lower sky and a
# stretched horizontal streak band. No textures - fully procedural.
#
# Draw contract: unshaded, cull_front (inside faces), depth_draw_never, fog_disabled,
# render_priority = RENDER_PRIORITY_MIN, no shadows, never frustum-culled. The node follows the
# active camera every frame, so the dome never clips and always surrounds the view.
#
# Colours, radius and drift speed come from data/palette.json "sky" (no colour lives here).
# View-only: nothing here touches the sim, the collision world or the state hash.
#
# public API:
#   static func load_config() -> Dictionary   # palette.json "sky" block ({} if absent)
#   func configure(cfg: Dictionary = {}) -> void   # builds the mesh + material
#   var shader_material: ShaderMaterial

const PALETTE_PATH := "res://data/palette.json"
const RINGS := 24
const SEGMENTS := 48

const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec4 zenith : source_color;
uniform vec4 horizon : source_color;
uniform vec4 cloud : source_color;
uniform vec4 cloud_dark : source_color;
uniform float t = 0.0;

varying vec3 dir;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x);
	float b = mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x);
	float c = mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x);
	float d = mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		s += amp * vnoise(p);
		p = p * 2.02 + vec3(11.3, 7.7, 5.1);
		amp *= 0.5;
	}
	return s;
}

void vertex() {
	// the dome is centred on its own origin, so the model-space vertex IS the view direction
	dir = VERTEX;
}

void fragment() {
	vec3 d = normalize(dir);
	float h = smoothstep(-0.15, 0.85, d.y);
	vec3 col = mix(horizon.rgb, zenith.rgb, h);
	col = mix(col, zenith.rgb, smoothstep(0.45, 1.0, d.y) * 0.35);
	// hard-edged billows: a narrow band turns the fbm into crisp silhouettes
	float billow = fbm(d * 3.0 + vec3(t * 0.01, 0.0, t * 0.006));
	col = mix(col, cloud.rgb, smoothstep(0.42, 0.62, billow) * 0.85);
	// broad low-frequency dark masses in the lower sky
	float mass = fbm(d * 0.85 + vec3(t * 0.003, 0.0, t * 0.002));
	float lower = 1.0 - smoothstep(-0.05, 0.75, d.y);
	col = mix(col, cloud_dark.rgb, smoothstep(0.38, 0.72, mass) * lower * 0.75);
	// storm wall: noise stretched along the horizontal so it reads as long streaks
	float streak = fbm(vec3(d.x * 0.6, d.y * 6.0, d.z * 0.6) + vec3(t * 0.02, 0.0, 0.0));
	float band = 1.0 - smoothstep(0.0, 0.55, abs(d.y - 0.12));
	col = mix(col, cloud_dark.rgb, smoothstep(0.45, 0.75, streak) * band * 0.35);
	ALBEDO = col;
}
"""

var shader_material: ShaderMaterial = null
var drift_speed := 1.0
var radius := 450.0
var _t := 0.0


static func load_config() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PALETTE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("sky_dome: cannot parse %s" % PALETTE_PATH)
		return {}
	return (parsed as Dictionary).get("sky", {})


func configure(cfg: Dictionary = {}) -> void:
	if cfg.is_empty():
		cfg = load_config()
	name = "SkyDome"
	radius = float(cfg.get("radius", 450.0))
	drift_speed = float(cfg.get("drift_speed", 1.0))
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = SEGMENTS
	sphere.rings = RINGS
	var sh := Shader.new()
	sh.code = SKY_SHADER
	shader_material = ShaderMaterial.new()
	shader_material.shader = sh
	shader_material.render_priority = Material.RENDER_PRIORITY_MIN
	for key in ["zenith", "horizon", "cloud", "cloud_dark"]:
		shader_material.set_shader_parameter(key, Color(str(cfg.get(key, "#000000"))))
	shader_material.set_shader_parameter("t", 0.0)
	sphere.material = shader_material
	mesh = sphere
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# never culled: the camera always sits inside it
	extra_cull_margin = 16384.0


func _ready() -> void:
	if mesh == null:
		configure()


func _process(delta: float) -> void:
	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	if cam != null:
		global_position = cam.global_position
	_t += delta * drift_speed
	if shader_material != null:
		shader_material.set_shader_parameter("t", _t)
