extends Node3D
## EffectsManager：爆発・ビーム・火花・閃光・破片。すべてプールで使い回す（Web 書き出しでも軽く）

const BEAM_SHADER := preload("res://shaders/beam.gdshader")

var tex_soft: Texture2D
var tex_ring: Texture2D
var mat_fire: StandardMaterial3D
var mat_spark: StandardMaterial3D
var mat_smoke: StandardMaterial3D

var fire_pool: Array = []
var spark_pool: Array = []
var smoke_pool: Array = []
var fire_i := 0
var spark_i := 0
var smoke_i := 0

var flash_free: Array = []
var flashes: Array = []     # {mi, mat, t, life, s0, s1, col, ring}
var beam_free: Array = []
var beams: Array = []       # {mi, mat, t, life, from, to, w, col, travel, node, lfrom, lto, fade}
var lights: Array = []
var light_i := 0
var chunk_free: Array = []
var chunks: Array = []      # {mi, v, av, t, life}
var timers: Array = []      # [残り秒, Callable]


func _ready() -> void:
	Game.fx = self
	tex_soft = _radial([[0.0, Color(1, 1, 1, 1)], [0.25, Color(1, 1, 1, 0.75)], [0.6, Color(1, 1, 1, 0.18)], [1.0, Color(1, 1, 1, 0)]])
	tex_ring = _radial([[0.0, Color(1, 1, 1, 0)], [0.7, Color(1, 1, 1, 0)], [0.86, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	mat_fire = _pmat(tex_soft, true)
	mat_spark = _pmat(tex_soft, true)
	mat_smoke = _pmat(tex_soft, false)
	for i in 28:
		fire_pool.append(_mk_particles(mat_fire, 20, _fire_ramp(), true))
	for i in 28:
		spark_pool.append(_mk_particles(mat_spark, 24, _spark_ramp(), false))
	for i in 14:
		smoke_pool.append(_mk_particles(mat_smoke, 12, _smoke_ramp(), true))
	for i in 40:
		flash_free.append(_mk_flash())
	for i in 140:
		beam_free.append(_mk_beam())
	for i in 4:
		var l := OmniLight3D.new()
		l.visible = false
		l.shadow_enabled = false
		l.omni_attenuation = 1.4
		add_child(l)
		lights.append({"l": l, "t": 0.0, "life": 0.1, "e": 0.0})
	for i in 60:
		var mi := MeshInstance3D.new()
		mi.mesh = Models.get_mesh("chunk")
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		chunk_free.append(mi)


func _radial(stops: Array) -> Texture2D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _pmat(tex: Texture2D, add: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = tex
	m.albedo_color = Color(2.2, 2.2, 2.2, 1) if add else Color(1, 1, 1, 1)
	m.disable_fog = add
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


func _fire_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.85, 1.0))
	g.set_color(1, Color(0.0, 0.0, 0.0, 0.0))
	g.add_point(0.12, Color(1.0, 0.72, 0.3, 1.0))
	g.add_point(0.4, Color(0.9, 0.3, 0.08, 0.8))
	g.add_point(0.72, Color(0.35, 0.08, 0.04, 0.35))
	return g


func _spark_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 1.0, 0.9, 1.0))
	g.set_color(1, Color(1.0, 0.3, 0.05, 0.0))
	g.add_point(0.3, Color(1.0, 0.75, 0.35, 1.0))
	return g


func _smoke_ramp() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(0.25, 0.22, 0.2, 0.0))
	g.set_color(1, Color(0.08, 0.08, 0.09, 0.0))
	g.add_point(0.15, Color(0.22, 0.2, 0.19, 0.55))
	g.add_point(0.6, Color(0.12, 0.12, 0.13, 0.3))
	return g


func _mk_particles(m: Material, amount: int, ramp: Gradient, grow: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = amount
	p.local_coords = false
	var q := QuadMesh.new()
	q.material = m
	p.mesh = q
	p.direction = Vector3(0, 0, -1)
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.0
	p.color_ramp = ramp
	var c := Curve.new()
	if grow:
		c.add_point(Vector2(0, 0.35))
		c.add_point(Vector2(0.25, 0.9))
		c.add_point(Vector2(1, 1.25))
	else:
		c.add_point(Vector2(0, 1))
		c.add_point(Vector2(1, 0.1))
	p.scale_amount_curve = c
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _mk_flash() -> Dictionary:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = tex_soft
	m.disable_fog = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mi.material_override = m
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return {"mi": mi, "mat": m}


func _mk_beam() -> Dictionary:
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = BEAM_SHADER
	mi.material_override = m
	mi.visible = false
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1, -1, -1.2), Vector3(2, 2, 1.4))
	add_child(mi)
	return {"mi": mi, "mat": m}


# ------------------------------------------------------------------ 公開
## 爆発。size はおおよその半径
func explosion(pos: Vector3, size: float, sound := true, smoke := true) -> void:
	var p: CPUParticles3D = fire_pool[fire_i]
	fire_i = (fire_i + 1) % fire_pool.size()
	p.global_position = pos
	p.emission_sphere_radius = size * 0.35
	p.initial_velocity_min = size * 0.6
	p.initial_velocity_max = size * 1.6
	p.scale_amount_min = size * 0.9
	p.scale_amount_max = size * 1.9
	p.lifetime = clampf(0.5 + size * 0.03, 0.6, 2.4)
	p.restart()
	sparks(pos, size, Vector3.ZERO, 1.0)
	flash(pos, size * 5.0, Color(1.0, 0.8, 0.55), 0.22 + size * 0.004)
	if size >= 14.0:
		ring(pos, size * 7.0, Color(1.0, 0.6, 0.35), 0.7 + size * 0.006)
	if smoke and size >= 6.0:
		var s: CPUParticles3D = smoke_pool[smoke_i]
		smoke_i = (smoke_i + 1) % smoke_pool.size()
		s.global_position = pos
		s.emission_sphere_radius = size * 0.4
		s.initial_velocity_min = size * 0.2
		s.initial_velocity_max = size * 0.6
		s.scale_amount_min = size * 1.2
		s.scale_amount_max = size * 2.4
		s.lifetime = clampf(1.2 + size * 0.05, 1.5, 4.0)
		s.restart()
	var cam := _cam_pos()
	var dist := cam.distance_to(pos)
	if dist < size * 30.0 + 150.0:
		_light(pos, Color(1.0, 0.6, 0.3), size * 6.0, 6.0 + size * 0.1)
	if size >= 4.0:
		debris(pos, int(clampf(size * 0.5, 2, 10)), size)
	if sound and Game.audio:
		var key := "explo_s"
		if size >= 30.0:
			key = "explo_l"
		elif size >= 12.0:
			key = "explo_m"
		if dist > 2500.0:
			key = "far_boom"
		Game.audio.play_at(key, pos, 0.0, randf_range(0.9, 1.1), 40.0 + size * 4.0)


## 大きな連鎖爆発（大型目標の撃破）
func big_explosion(pos: Vector3, size: float, spread: float, count: int, duration: float) -> void:
	explosion(pos, size)
	for i in count:
		var dt := randf() * duration
		var off := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread
		later(dt, explosion.bind(pos + off, size * randf_range(0.4, 0.8), i % 3 == 0))


func sparks(pos: Vector3, size: float, dir := Vector3.ZERO, amount := 1.0) -> void:
	var p: CPUParticles3D = spark_pool[spark_i]
	spark_i = (spark_i + 1) % spark_pool.size()
	p.global_position = pos
	p.emission_sphere_radius = size * 0.1
	p.initial_velocity_min = size * 3.0
	p.initial_velocity_max = size * 9.0
	p.scale_amount_min = maxf(size * 0.08, 0.15)
	p.scale_amount_max = maxf(size * 0.22, 0.35)
	p.lifetime = 0.45 + size * 0.01
	if dir != Vector3.ZERO:
		p.direction = dir.normalized()
		p.spread = 55.0
	else:
		p.direction = Vector3(0, 0, -1)
		p.spread = 180.0
	p.amount = int(clampf(8 + size * amount, 8, 48))
	p.restart()


## 着弾の光と火花
func impact(pos: Vector3, normal: Vector3, col: Color, strong := false) -> void:
	var s := 1.4 if strong else 0.7
	sparks(pos, 2.5 * s, normal, 2.0)
	flash(pos, 7.0 * s, col.lerp(Color.WHITE, 0.5), 0.12)


func flash(pos: Vector3, size: float, col: Color, life := 0.2) -> void:
	_flash(pos, size * 0.4, size, col, life, false)


func ring(pos: Vector3, size: float, col: Color, life := 0.8) -> void:
	_flash(pos, size * 0.1, size, col, life, true)


func _flash(pos: Vector3, s0: float, s1: float, col: Color, life: float, is_ring: bool) -> void:
	var f: Dictionary
	if flash_free.is_empty():
		f = flashes.pop_front()
	else:
		f = flash_free.pop_back()
	var mi: MeshInstance3D = f["mi"]
	mi.global_position = pos
	mi.visible = true
	(f["mat"] as StandardMaterial3D).albedo_texture = tex_ring if is_ring else tex_soft
	f["t"] = 0.0
	f["life"] = life
	f["s0"] = s0
	f["s1"] = s1
	f["col"] = col
	f["ring"] = is_ring
	flashes.append(f)


## 静的なビーム（背景の艦隊戦・大型砲）
func beam(from: Vector3, to: Vector3, col: Color, width: float, life: float, intensity := 2.5) -> Dictionary:
	return _beam(from, to, col, width, life, 0.0, intensity)


## 飛んでいく光弾（自弾・敵弾）。travel 秒で to に届く
func bolt(from: Vector3, to: Vector3, col: Color, width: float, travel: float, seg_len := 40.0, intensity := 3.0) -> Dictionary:
	var b := _beam(from, to, col, width, travel + 0.08, travel, intensity)
	b["seg"] = seg_len
	return b


func _beam(from: Vector3, to: Vector3, col: Color, width: float, life: float, travel: float, intensity: float) -> Dictionary:
	var b: Dictionary
	if beam_free.is_empty():
		b = beams.pop_front()
	else:
		b = beam_free.pop_back()
	b["t"] = 0.0
	b["life"] = life
	b["from"] = from
	b["to"] = to
	b["w"] = width
	b["travel"] = travel
	b["seg"] = 0.0
	var m: ShaderMaterial = b["mat"]
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("alpha", 1.0)
	m.set_shader_parameter("flow", 0.0)
	m.set_shader_parameter("tail", 1.0 if travel > 0.0 else 0.0)
	(b["mi"] as MeshInstance3D).visible = true
	_place_beam(b["mi"], from, to, width)
	beams.append(b)
	return b


func _place_beam(mi: MeshInstance3D, from: Vector3, to: Vector3, width: float) -> void:
	var dv := to - from
	var l := dv.length()
	if l < 0.01:
		mi.visible = false
		return
	mi.visible = true
	var z := -dv / l
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	mi.global_transform = Transform3D(Basis(x * width, y * width, z * l), from)


## 大型レーザーなど、外から動かし続ける太いビーム
func make_big_beam(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	var m := ShaderMaterial.new()
	m.shader = BEAM_SHADER
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("intensity", 4.0)
	m.set_shader_parameter("flow", 1.0)
	m.set_shader_parameter("core", 0.45)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1, -1, -1.2), Vector3(2, 2, 1.4))
	mi.visible = false
	add_child(mi)
	return mi


func place_big_beam(mi: MeshInstance3D, from: Vector3, to: Vector3, width: float) -> void:
	_place_beam(mi, from, to, width)


func debris(pos: Vector3, n: int, size: float) -> void:
	for i in n:
		var mi: MeshInstance3D
		if chunk_free.is_empty():
			var c: Dictionary = chunks.pop_front()
			mi = c["mi"]
		else:
			mi = chunk_free.pop_back()
		mi.visible = true
		mi.global_position = pos
		var sc := size * randf_range(0.05, 0.16)
		mi.scale = Vector3.ONE * sc
		var v := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * size * randf_range(1.5, 5.0)
		chunks.append({"mi": mi, "v": v, "av": Vector3(randf(), randf(), randf()) * 6.0, "t": 0.0, "life": randf_range(1.5, 3.5), "sc": sc})


## 燃え続ける損傷箇所（大型目標の部位・味方艦）
func attach_fire(parent: Node3D, local_pos: Vector3, size: float) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = local_pos
	var f := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.material = mat_fire
	f.mesh = q
	f.amount = 14
	f.lifetime = 0.7
	f.local_coords = false
	f.direction = Vector3.UP
	f.spread = 30.0
	f.gravity = Vector3.ZERO
	f.initial_velocity_min = size * 1.0
	f.initial_velocity_max = size * 2.5
	f.scale_amount_min = size * 0.5
	f.scale_amount_max = size * 1.1
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = size * 0.3
	f.color_ramp = _fire_ramp()
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(f)
	var s := CPUParticles3D.new()
	var q2 := QuadMesh.new()
	q2.material = mat_smoke
	s.mesh = q2
	s.amount = 10
	s.lifetime = 2.2
	s.local_coords = false
	s.direction = Vector3.UP
	s.spread = 25.0
	s.gravity = Vector3.ZERO
	s.initial_velocity_min = size * 1.2
	s.initial_velocity_max = size * 2.2
	s.scale_amount_min = size * 1.0
	s.scale_amount_max = size * 2.0
	s.color_ramp = _smoke_ramp()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.6))
	s.scale_amount_curve = c
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(s)
	return root


## 火花が散り続ける損傷箇所
func attach_sparks(parent: Node3D, local_pos: Vector3, size: float) -> Node3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.material = mat_spark
	p.mesh = q
	p.amount = 10
	p.lifetime = 0.5
	p.explosiveness = 0.6
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = size * 3.0
	p.initial_velocity_max = size * 7.0
	p.scale_amount_min = size * 0.1
	p.scale_amount_max = size * 0.25
	p.color_ramp = _spark_ramp()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.position = local_pos
	return p


func later(delay: float, c: Callable) -> void:
	timers.append([delay, c])


func _light(pos: Vector3, col: Color, rng: float, energy: float) -> void:
	var L: Dictionary = lights[light_i]
	light_i = (light_i + 1) % lights.size()
	var l: OmniLight3D = L["l"]
	l.global_position = pos
	l.light_color = col
	l.omni_range = rng
	l.light_energy = energy
	l.visible = true
	L["t"] = 0.0
	L["life"] = 0.35
	L["e"] = energy


func _cam_pos() -> Vector3:
	var vp := get_viewport()
	if vp and vp.get_camera_3d():
		return vp.get_camera_3d().global_position
	return Vector3.ZERO


func tick(dt: float) -> void:
	var i := 0
	while i < timers.size():
		timers[i][0] -= dt
		if timers[i][0] <= 0.0:
			var c: Callable = timers[i][1]
			timers.remove_at(i)
			if c.is_valid():
				c.call()
		else:
			i += 1
	i = 0
	while i < flashes.size():
		var f: Dictionary = flashes[i]
		f["t"] += dt
		var k: float = f["t"] / f["life"]
		var mi: MeshInstance3D = f["mi"]
		if k >= 1.0:
			mi.visible = false
			flashes.remove_at(i)
			flash_free.append(f)
			continue
		var s: float = lerpf(f["s0"], f["s1"], 1.0 - pow(1.0 - k, 3.0))
		mi.scale = Vector3.ONE * s
		var c: Color = f["col"]
		var e2: float = 1.2 if f.get("ring", false) else 2.5
		(f["mat"] as StandardMaterial3D).albedo_color = Color(c.r * e2, c.g * e2, c.b * e2, (1.0 - k) * (1.0 - k))
		i += 1
	i = 0
	while i < beams.size():
		var b: Dictionary = beams[i]
		b["t"] += dt
		var mi2: MeshInstance3D = b["mi"]
		var life: float = b["life"]
		if b["t"] >= life:
			mi2.visible = false
			beams.remove_at(i)
			beam_free.append(b)
			continue
		var m: ShaderMaterial = b["mat"]
		var travel: float = b["travel"]
		if travel > 0.0:
			var from: Vector3 = b["from"]
			var to: Vector3 = b["to"]
			var L := from.distance_to(to)
			var s := clampf(b["t"] / travel, 0.0, 1.0)
			var seg: float = b["seg"]
			var s0 := maxf(0.0, s - seg / maxf(L, 1.0))
			if b["t"] > travel:
				s0 = minf(1.0, s0 + (b["t"] - travel) / 0.08)
			_place_beam(mi2, from.lerp(to, s0), from.lerp(to, s), b["w"])
		else:
			m.set_shader_parameter("alpha", 1.0 - b["t"] / life)
		i += 1
	for L2 in lights:
		var l: OmniLight3D = L2["l"]
		if l.visible:
			L2["t"] += dt
			var k2: float = L2["t"] / L2["life"]
			if k2 >= 1.0:
				l.visible = false
			else:
				l.light_energy = L2["e"] * (1.0 - k2)
	i = 0
	while i < chunks.size():
		var c2: Dictionary = chunks[i]
		c2["t"] += dt
		var mi3: MeshInstance3D = c2["mi"]
		if c2["t"] >= c2["life"]:
			mi3.visible = false
			chunks.remove_at(i)
			chunk_free.append(mi3)
			continue
		mi3.global_position += (c2["v"] as Vector3) * dt
		mi3.rotate_x(c2["av"].x * dt)
		mi3.rotate_y(c2["av"].y * dt)
		var fade: float = 1.0 - maxf(0.0, (c2["t"] - c2["life"] + 0.5) / 0.5)
		mi3.scale = Vector3.ONE * float(c2["sc"]) * maxf(fade, 0.01)
		i += 1
