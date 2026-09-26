extends Node3D
## World：宇宙背景（星・星雲・惑星）・恒星光・宇宙塵・漂う残骸

const SKY_SHADER := preload("res://shaders/sky.gdshader")
const DUST_SHADER := preload("res://shaders/dust.gdshader")
const DEBRIS_SHADER := preload("res://shaders/debris.gdshader")

const SUN_DIR := Vector3(-0.45, 0.55, 0.7)
const PLANET_DIR := Vector3(0.55, -0.32, -0.77)

var env: Environment
var sky_mat: ShaderMaterial
var leg := -1
## 跳躍で移る三つの宙域の空（惑星の位置・大きさ・色、星雲の色）
const LEGS := [
	{"dir": Vector3(0.55, -0.32, -0.77), "size": 0.3, "a": Color(0.42, 0.33, 0.26), "b": Color(0.72, 0.6, 0.46), "c": Color(0.3, 0.36, 0.44),
		"na": Color(0.11, 0.045, 0.16), "nb": Color(0.02, 0.07, 0.11), "bands": 7.0},
	{"dir": Vector3(-0.75, 0.3, -0.6), "size": 0.13, "a": Color(0.5, 0.62, 0.7), "b": Color(0.82, 0.9, 0.95), "c": Color(0.3, 0.45, 0.6),
		"na": Color(0.02, 0.1, 0.11), "nb": Color(0.05, 0.12, 0.06), "bands": 3.0},
	{"dir": Vector3(0.78, 0.12, 0.62), "size": 0.46, "a": Color(0.55, 0.2, 0.12), "b": Color(0.85, 0.5, 0.28), "c": Color(0.35, 0.12, 0.1),
		"na": Color(0.16, 0.04, 0.05), "nb": Color(0.09, 0.03, 0.12), "bands": 11.0},
]
var sun: DirectionalLight3D
var dust_mat: ShaderMaterial
var web := false


func _ready() -> void:
	Game.world = self
	web = OS.has_feature("web")
	_environment()
	_dust()
	_debris()


func _environment() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("sun_dir", SUN_DIR.normalized())
	if web:
		sky_mat.set_shader_parameter("gain", 2.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.23, 0.32)
	env.ambient_light_energy = 0.95
	env.ambient_light_sky_contribution = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.6)
	env.set_glow_level(5, 0.4)
	# 奥行きの手がかりとして、遠い艦ほどわずかに青く霞ませる
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.08, 0.14)
	env.fog_density = 0.00005
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 900.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.shadow_bias = 0.08
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -SUN_DIR, Vector3.UP)
	# 惑星からの照り返し。恒星の反対側（夜の側）も真っ黒にしない
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.75, 0.62, 0.5)
	fill.light_energy = 0.55
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, -PLANET_DIR, Vector3.UP)


func _dust() -> void:
	dust_mat = ShaderMaterial.new()
	dust_mat.shader = DUST_SHADER
	var q := QuadMesh.new()
	q.material = dust_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = 380 if web else 700
	var box := 360.0
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(randf(), randf(), randf()) * box))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _debris() -> void:
	var m := ShaderMaterial.new()
	m.shader = DEBRIS_SHADER
	var mesh: ArrayMesh = Models.get_mesh("chunk").duplicate()
	mesh.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 90 if web else 160
	var box := 1400.0
	for i in mm.instance_count:
		var b := Basis(Vector3(randf(), randf(), randf()).normalized(), randf() * TAU)
		var s := randf_range(0.5, 3.0) if randf() < 0.85 else randf_range(4.0, 7.0)
		b = b.scaled(Vector3(s, s * randf_range(0.4, 1.0), s * randf_range(0.6, 2.0)))
		mm.set_instance_transform(i, Transform3D(b, Vector3(randf(), randf(), randf()) * box))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	add_child(mmi)


func set_leg(i: int) -> void:
	if i == leg:
		return
	leg = i
	var L: Dictionary = LEGS[i]
	sky_mat.set_shader_parameter("planet_dir", (L["dir"] as Vector3).normalized())
	sky_mat.set_shader_parameter("planet_size", L["size"])
	sky_mat.set_shader_parameter("planet_a", L["a"])
	sky_mat.set_shader_parameter("planet_b", L["b"])
	sky_mat.set_shader_parameter("planet_c", L["c"])
	sky_mat.set_shader_parameter("nebula_a", L["na"])
	sky_mat.set_shader_parameter("nebula_b", L["nb"])
	sky_mat.set_shader_parameter("bands", L["bands"])


## 跳躍の演出：k = 0〜1 で宇宙塵が光の筋に伸びる
func set_jump(k: float) -> void:
	dust_mat.set_shader_parameter("streak", 0.06 + k * k * 2.5)
	dust_mat.set_shader_parameter("size", 0.35 + k * 0.5)


func tick(_dt: float) -> void:
	if Game.rail:
		dust_mat.set_shader_parameter("vel", -Game.rail.vel)
