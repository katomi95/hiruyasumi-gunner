class_name SetPieces
extends RefCounted
## 大型の舞台装置：敵巡洋艦（SCENE 2）・敵戦艦（SCENE 4）・敵要塞と大型レーザー砲台（SCENE 5）・質量兵器（SCENE 6）。
## 巨大なものは近づくと画面からはみ出す大きさで作り、表面の細部（装甲板・砲塔・アンテナ・灯火）を多く置く

const MB = Models.MB


static func _mi(parent: Node3D, mesh: Mesh, pos := Vector3.ZERO, b := Basis(), shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.basis = b
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _unit_box(mat_key: String) -> ArrayMesh:
	var m := MB.new()
	m.box(Vector3.ZERO, Vector3.ONE, Color(1, 1, 1))
	return m.commit(Models.mat(mat_key), Models.mat("glow"))


static func _unit_glow() -> ArrayMesh:
	var m := MB.new()
	m.box(Vector3.ZERO, Vector3.ONE, Color(1, 1, 1), true)
	return m.commit(Models.mat("enemy"), Models.mat("glow_hot"))


## 表面の細かい構造物（MultiMesh）。faces: [{c: 面の中心, n: 法線, u: 面の横, v: 面の縦, su, sv}]
static func _greebles(parent: Node3D, faces: Array, count: int, mat_key: String, size_min: float, size_max: float,
		lights := 0, light_cols: Array = []) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _unit_box(mat_key)
	mm.instance_count = count
	for i in count:
		var f: Dictionary = faces[randi() % faces.size()]
		var n: Vector3 = f["n"]
		var u: Vector3 = f["u"]
		var v: Vector3 = f["v"]
		var p: Vector3 = f["c"] + u * randf_range(-0.5, 0.5) * float(f["su"]) + v * randf_range(-0.5, 0.5) * float(f["sv"])
		var h := randf_range(size_min, size_max) * (0.3 if randf() < 0.6 else 0.8)
		var a := randf_range(size_min, size_max) * randf_range(0.8, 3.0)
		var b := randf_range(size_min, size_max) * randf_range(0.6, 1.5)
		var bas := Basis(u * a, n * h, v * b)
		if absf(n.dot(Vector3.UP)) < 0.5:
			bas = Basis(u * b, n * h, v * a)
		mm.set_instance_transform(i, Transform3D(bas, p + n * h * 0.5))
		var g := randf_range(0.7, 1.15)
		mm.set_instance_color(i, Color(g, g * randf_range(0.95, 1.0), g * randf_range(0.93, 1.0), 1.0 if randf() < 0.3 else 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)
	if lights > 0:
		var lm := MultiMesh.new()
		lm.transform_format = MultiMesh.TRANSFORM_3D
		lm.use_colors = true
		lm.mesh = _unit_glow()
		lm.instance_count = lights
		for i in lights:
			var f2: Dictionary = faces[randi() % faces.size()]
			var p2: Vector3 = f2["c"] + (f2["u"] as Vector3) * randf_range(-0.5, 0.5) * float(f2["su"]) + (f2["v"] as Vector3) * randf_range(-0.5, 0.5) * float(f2["sv"])
			var s := randf_range(1.2, 3.0)
			lm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s * randf_range(1.0, 4.0))), p2 + (f2["n"] as Vector3) * 0.8))
			lm.set_instance_color(i, light_cols[randi() % light_cols.size()])
		var lmi := MultiMeshInstance3D.new()
		lmi.multimesh = lm
		lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(lmi)


static func _face(c: Vector3, n: Vector3, u: Vector3, su: float, sv: float) -> Dictionary:
	return {"c": c, "n": n, "u": u, "v": u.cross(n).normalized(), "su": su, "sv": sv}


# ------------------------------------------------------------------ SCENE 2：敵巡洋艦
static func enemy_cruiser(root: Node3D, pos: Vector3) -> Node3D:
	var E = Game.enemies
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = pos
	n.global_basis = Basis(Vector3.UP, PI)
	var mi := _mi(n, Models.get_mesh("enemy_cruiser"))
	mi.scale = Vector3.ONE * 3.2
	E.add_armor(n, AABB(Vector3(-45, -22, -110), Vector3(90, 44, 275)))
	E.add_armor(n, AABB(Vector3(-50, -16, -270), Vector3(100, 26, 170)))
	for z in [-60.0, 30.0, 110.0]:
		E.turret(n, Vector3(24, 21, z), Vector3.UP, {"label": "砲台", "group": "s2", "rate": 3.4, "range": 1600.0, "hp": 18.0})
	var l: Target = E.part(n, Vector3(-10, 22, 60), Basis(), "launcher", {"hp": 26.0, "radius": 20.0, "label": "ミサイル発射機",
		"group": "s2", "score": 600, "hit_off": Vector3(0, 6, 0), "d": {"launch": {"rate": 12.0, "cd": 6.0, "n": 1, "range": 1800.0}}})
	l.scale = Vector3.ONE * 0.9
	return n


# ------------------------------------------------------------------ SCENE 4：敵戦艦
## 艦首がワールド +Z を向くように 180° 回して置く。プレイヤーから見える舷側はローカル +X
static func dreadnought(root: Node3D, pos: Vector3, web: bool) -> Node3D:
	var E = Game.enemies
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = pos
	n.global_basis = Basis(Vector3.UP, PI)
	var m := MB.new()
	var H := Color(1, 1, 1)
	var D := Color(0.72, 0.66, 0.66)
	var DK := Color(0.52, 0.47, 0.47)
	m.loft([m.sec(1100, 280, 150, 0, -60), m.sec(700, 300, 170, 0, -60), m.sec(-600, 300, 170, 0, -60),
		m.sec(-950, 220, 130, 0, -70), m.sec(-1120, 50, 40, 0, -95)], H)
	m.loft([m.sec(1000, 230, 90, 0, 60), m.sec(-700, 230, 90, 0, 60), m.sec(-880, 130, 50, 0, 40)], D)
	m.loft([m.sec(820, 130, 90, 0, 150), m.sec(100, 120, 80, 0, 145), m.sec(-160, 60, 36, 0, 122)], H)
	m.box(Vector3(0, 250, 450), Vector3(70, 110, 110), D)
	m.box(Vector3(0, 312, 470), Vector3(90, 14, 60), DK)
	m.loft([m.sec(900, 60, 60, 0, -170), m.sec(-700, 40, 40, 0, -160)], DK)
	for s in [-1.0, 1.0]:
		for z in [-950.0, -800.0, -650.0, -500.0, -200.0, 100.0, 400.0, 700.0]:
			m.box(Vector3(s * 170, -30, z), Vector3(40, 34, 80), D)
		m.box(Vector3(s * 153, 20, 100), Vector3(8, 10, 1800), DK)
		m.box(Vector3(s * 118, 108, 150), Vector3(6, 6, 1600), DK)
		for k in 14:
			var z2 := -850.0 + k * 135.0
			m.box(Vector3(s * 150.6, -100, z2), Vector3(1.2, 3, 50), Models.C_RED, true)
			m.box(Vector3(s * 115.6, 80, z2 + 40), Vector3(1.2, 2.5, 30), Color(1.0, 0.6, 0.4), true)
	m.box(Vector3(0, -40, 1130), Vector3(240, 140, 60), DK)
	for x in [-80.0, 0.0, 80.0]:
		m.cyl(Vector3(x, -40, 1160), Vector3(x, -40, 1185), 34, 40, 16, DK)
		m.cyl(Vector3(x, -40, 1186), Vector3(x, -40, 1188), 30, 30, 16, Models.C_ORG, true)
	# 艦橋の窓
	m.box(Vector3(0, 280, 394.6), Vector3(60, 5, 1), Color(1.0, 0.55, 0.3), true)
	m.box(Vector3(35.4, 260, 450), Vector3(1, 4, 90), Color(1.0, 0.55, 0.3), true)
	_mi(n, m.commit(Models.mat("enemy_big"), Models.mat("glow")))
	# 反対舷の飾りの主砲
	for z in [-350.0, -150.0]:
		_mi(n, Models.get_mesh("mturret_base"), Vector3(-60, 108, z))
		_mi(n, Models.get_mesh("mturret_head"), Vector3(-60, 108, z), Basis(Vector3.UP, 0.4))
	# 表面の構造物
	var faces := [
		_face(Vector3(150, -60, 75), Vector3.RIGHT, Vector3.BACK, 2000, 150),
		_face(Vector3(115, 60, 150), Vector3.RIGHT, Vector3.BACK, 1650, 80),
		_face(Vector3(0, 105, 150), Vector3.UP, Vector3.BACK, 1650, 220),
		_face(Vector3(65, 150, 460), Vector3.RIGHT, Vector3.BACK, 700, 80),
		_face(Vector3(0, 192, 460), Vector3.UP, Vector3.BACK, 700, 120),
		_face(Vector3(-150, -60, 75), Vector3.LEFT, Vector3.BACK, 2000, 150),
		_face(Vector3(0, -145, 100), Vector3.DOWN, Vector3.BACK, 1900, 260),
	]
	_greebles(n, faces, 700 if web else 1400, "enemy", 3.0, 16.0, 150 if web else 320,
		[Color(1.0, 0.3, 0.15), Color(1.0, 0.6, 0.35), Color(1.0, 0.9, 0.8)])
	# アンテナ
	var am := MB.new()
	for i in 26:
		var x := randf_range(-55, 55)
		var z3 := randf_range(120, 800)
		var h := randf_range(20, 70)
		am.box(Vector3(x, 192 + h * 0.5, z3), Vector3(1.2, h, 1.2), DK)
		am.box(Vector3(x, 192 + h * 0.8, z3), Vector3(14, 1, 1), DK)
	for i in 8:
		var hh := randf_range(40, 90)
		am.box(Vector3(randf_range(-30, 30), 319 + hh * 0.5, randf_range(430, 500)), Vector3(1.5, hh, 1.5), DK)
	_mi(n, am.commit(Models.mat("enemy"), Models.mat("glow")))
	# 当たり判定（装甲）
	E.add_armor(n, AABB(Vector3(-150, -145, -1120), Vector3(300, 170, 2220)))
	E.add_armor(n, AABB(Vector3(-115, 15, -880), Vector3(230, 90, 1880)))
	E.add_armor(n, AABB(Vector3(-65, 105, -160), Vector3(130, 90, 980)))
	E.add_armor(n, AABB(Vector3(-35, 195, 395), Vector3(70, 124, 110)))
	E.add_armor(n, AABB(Vector3(150, -47, -990), Vector3(40, 34, 1730)))
	# 撃てる部位
	for z in [-950.0, -800.0, -650.0, -500.0]:
		E.turret(n, Vector3(170, -11, z), Vector3.UP, {"label": "砲台", "group": "s4t", "rate": 3.8, "range": 1300.0, "hp": 18.0})
	var mains: Array = []
	for z in [-350.0, -150.0]:
		mains.append(E.turret(n, Vector3(60, 108, z), Vector3.UP, {"big": true, "label": "主砲", "group": "s4m",
			"mode": "allies", "rate": 12.0, "hp": 55.0, "score": 1500}))
	for z in [150.0, 330.0]:
		E.part(n, Vector3(92, 105, z), Basis(), "launcher", {"hp": 30.0, "radius": 22.0, "label": "ミサイル発射機",
			"group": "s4l", "score": 800, "hit_off": Vector3(0, 6, 0), "d": {"launch": {"rate": 11.0, "cd": 3.0, "n": 2, "range": 1300.0}}})
	E.part(n, Vector3(0, 319, 470), Basis(), "sensor", {"hp": 40.0, "radius": 30.0, "label": "センサー", "group": "s4s",
		"score": 1200, "hit_off": Vector3(0, 60, 0), "boom": 30.0})
	for y in [-40.0, 60.0]:
		E.part(n, Vector3(185, y, 930), Basis(), "engine_pod", {"hp": 45.0, "radius": 38.0, "label": "推進器", "group": "s4e",
			"score": 1200, "boom": 36.0})
	return n


# ------------------------------------------------------------------ SCENE 5：敵要塞と大型レーザー砲台
## ローカル -Z が射線。戻り値：{node, tip, capacitors, sweep_emitter}
static func fortress(root: Node3D, pos: Vector3, aim_at: Vector3, toward_player: Vector3, web: bool) -> Dictionary:
	var E = Game.enemies
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = pos
	n.global_basis = Basis.looking_at(aim_at - pos, Vector3.UP)
	var m := MB.new()
	var H := Color(1, 1, 1)
	var D := Color(0.72, 0.68, 0.7)
	var DK := Color(0.5, 0.47, 0.5)
	var LZ := Color(1.0, 0.5, 0.3)
	m.box(Vector3(0, 0, 150), Vector3(520, 420, 460), H)
	m.box(Vector3(0, 0, 480), Vector3(380, 300, 240), D)
	m.box(Vector3(0, 330, 200), Vector3(220, 260, 220), D)
	m.cyl(Vector3(0, 460, 200), Vector3(0, 760, 200), 34, 4, 8, DK)
	m.cyl(Vector3(0, -210, 150), Vector3(0, -640, 150), 130, 12, 8, D)
	for k in 20:
		var a := TAU * k / 20.0
		m.obox(Vector3(cos(a) * 580, sin(a) * 580, 200), Vector3(56, 190, 80), Basis(Vector3.BACK, a), D)
	for k in 4:
		var a2 := TAU * k / 4.0 + PI / 4.0
		m.obox(Vector3(cos(a2) * 400, sin(a2) * 400, 200), Vector3(30, 300, 40), Basis(Vector3.BACK, a2 - PI / 2.0), DK)
	m.cyl(Vector3(0, 0, -200), Vector3(0, 0, -1150), 82, 62, 18, D)
	for z in [-420.0, -640.0, -860.0, -1060.0]:
		m.cyl(Vector3(0, 0, z), Vector3(0, 0, z - 44), 108, 108, 18, DK)
		m.cyl(Vector3(0, 0, z - 16), Vector3(0, 0, z - 28), 110, 110, 18, LZ, true)
	# 壁面の灯火
	for k in 30:
		m.box(Vector3(randf_range(-240, 240), randf_range(-190, 190), -80.5), Vector3(randf_range(4, 18), 2, 1), Color(1.0, 0.45, 0.25), true)
	_mi(n, m.commit(Models.mat("fort"), Models.mat("glow")))
	var faces := [
		_face(Vector3(0, 0, -80), Vector3.FORWARD, Vector3.RIGHT, 500, 400),
		_face(Vector3(260, 0, 150), Vector3.RIGHT, Vector3.BACK, 440, 400),
		_face(Vector3(-260, 0, 150), Vector3.LEFT, Vector3.BACK, 440, 400),
		_face(Vector3(0, 210, 150), Vector3.UP, Vector3.BACK, 440, 500),
		_face(Vector3(0, -210, 150), Vector3.DOWN, Vector3.BACK, 440, 500),
	]
	_greebles(n, faces, 400 if web else 900, "enemy", 5.0, 26.0, 120 if web else 260,
		[Color(1.0, 0.35, 0.2), Color(1.0, 0.7, 0.4), Color(0.9, 0.6, 1.0)])
	# 砲口（充填で明るく大きくなる）
	var tip := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 60
	sm.height = 120
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(3.0, 1.4, 0.8)
	sm.material = tm
	tip.mesh = sm
	tip.position = Vector3(0, 0, -1170)
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tip.scale = Vector3.ONE * 0.2
	n.add_child(tip)
	E.add_armor(n, AABB(Vector3(-260, -210, -80), Vector3(520, 420, 460)))
	E.add_armor(n, AABB(Vector3(-190, -150, 360), Vector3(380, 300, 240)))
	E.add_armor(n, AABB(Vector3(-110, 200, 90), Vector3(220, 260, 220)))
	E.add_armor(n, AABB(Vector3(-78, -78, -1150), Vector3(156, 156, 950)))
	# 集束器（三基）。プレイヤー側の半面に並べる
	var inv := n.global_basis.inverse()
	var tw := inv * toward_player
	tw.z = 0.0
	tw = tw.normalized()
	var up := Vector3.UP
	var dirs := [tw, (tw * 0.7 + up * 0.7).normalized(), (tw * 0.7 - up * 0.7).normalized()]
	var caps: Array = []
	for k in 3:
		var dv: Vector3 = dirs[k]
		var bz := Vector3(0, 0, 1)
		var bx := dv.cross(bz).normalized()
		var b := Basis(bx, dv, bx.cross(dv))
		var c: Target = E.part(n, Vector3(0, 0, -900 - k * 70) + dv * 150.0, b, "capacitor", {"hp": 32.0, "radius": 44.0,
			"label": "集束器", "group": "cap", "score": 1500, "boom": 34.0, "d": {"keep": false}})
		caps.append(c)
	# 防御砲台
	for k in 4:
		var p := Vector3(0, -130 + (k % 2) * 200, 30 + (k / 2) * 220) + tw * 262.0
		E.turret(n, p, tw, {"label": "防御砲台", "group": "s5t", "rate": 6.0, "range": 1700.0, "hp": 18.0, "objective": false, "hit": 0.15})
	# 副砲（掃射用）
	var sweep := Node3D.new()
	n.add_child(sweep)
	sweep.position = Vector3(0, -330, -40) + tw * 120.0
	var sg := MeshInstance3D.new()
	var sm2 := SphereMesh.new()
	sm2.radius = 30
	sm2.height = 60
	var sgm := StandardMaterial3D.new()
	sgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sgm.albedo_color = Color(3.0, 1.3, 0.7)
	sm2.material = sgm
	sg.mesh = sm2
	sg.scale = Vector3.ONE * 0.3
	sweep.add_child(sg)
	var sb := MB.new()
	sb.cyl(Vector3(0, 60, 0), Vector3(0, -10, 0), 45, 38, 12, D)
	_mi(sweep, sb.commit(Models.mat("fort"), Models.mat("glow")))
	return {"node": n, "tip": tip, "caps": caps, "sweep": sweep, "sweep_glow": sg}


# ------------------------------------------------------------------ SCENE 6：質量兵器
const ROCK_R := 650.0
const ROCK_SEED := 7
const ROCK_ROUGH := 0.12


static func rock_radius(dir: Vector3) -> float:
	var noise := FastNoiseLite.new()
	noise.seed = ROCK_SEED
	noise.frequency = 1.6
	noise.fractal_octaves = 4
	var v := dir.normalized()
	var nn := noise.get_noise_3dv(v)
	var n2 := noise.get_noise_3dv(v * 3.1 + Vector3(5, 1, 2))
	return ROCK_R * (1.0 + nn * ROCK_ROUGH * 1.6 + n2 * ROCK_ROUGH * 0.4)


## 方位 th（度。0 = +X、90 = -Z）と仰角成分 e の地表の点と、そこで外を向く基底
static func surface(th: float, e: float) -> Array:
	var a := deg_to_rad(th)
	var dir := Vector3(cos(a), e, -sin(a)).normalized()
	var r := rock_radius(dir)
	var y := dir
	var x := y.cross(Vector3.UP)
	if x.length() < 0.1:
		x = Vector3.RIGHT
	x = x.normalized()
	return [dir * (r - 10.0), Basis(x, y, x.cross(y))]


static func mass_weapon(root: Node3D, pos: Vector3, web: bool) -> Dictionary:
	var E = Game.enemies
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = pos
	var rock := _mi(n, Models.rock_mesh(ROCK_R, 3 if web else 4, ROCK_SEED, ROCK_ROUGH))
	# 地表の凹みに置いた部位を覆わないよう、装甲の球は地表の最も低い所より内側にとる
	E.add_armor_sphere(n, ROCK_R * 0.82)
	var thr: Array = []
	var flames: Array = []
	var fire_mat := StandardMaterial3D.new()
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire_mat.albedo_color = Color(1.2, 0.7, 1.6, 0.28)
	fire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fire_mat.disable_fog = true
	var spots := [[22.0, 0.3], [42.0, 0.02], [62.0, 0.26], [82.0, -0.02]]
	for sp in spots:
		var s: Array = surface(sp[0], sp[1])
		var t: Target = E.part(n, s[0], s[1], "thruster", {"hp": 26.0, "radius": 55.0, "label": "推進器", "group": "thr",
			"score": 1200, "hit_off": Vector3(0, 55, 0), "boom": 40.0})
		var fl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 6.0
		cm.bottom_radius = 36.0
		cm.height = 260.0
		cm.radial_segments = 16
		cm.material = fire_mat
		fl.mesh = cm
		fl.position = Vector3(0, 90 + 130, 0)
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.add_child(fl)
		var burn: Node3D = Game.fx.attach_fire(t, Vector3(0, 100, 0), 22.0)
		t.on_destroy = func(_e):
			fl.visible = false
			burn.visible = false
		thr.append(t)
		_scaffold(n, s[0], s[1])
	var ctl: Array = []
	for sp in [[112.0, 0.2], [134.0, 0.04]]:
		var s2: Array = surface(sp[0], sp[1])
		ctl.append(E.part(n, s2[0], s2[1], "control", {"hp": 30.0, "radius": 48.0, "label": "制御装置", "group": "ctl",
			"score": 1500, "hit_off": Vector3(0, 60, 0), "boom": 40.0}))
		_scaffold(n, s2[0], s2[1])
	var s3: Array = surface(154.0, 0.14)
	var core: Target = E.part(n, s3[0], s3[1], "blast_core", {"hp": 45.0, "radius": 58.0, "label": "爆破点", "group": "core",
		"score": 3000, "hit_off": Vector3(0, 12, 0), "boom": 60.0, "d": {"keep": true}})
	core.targetable = false
	core.visible = false
	var hatch := MB.new()
	var pa: Array = []
	var pb: Array = []
	for i in 6:
		var a := TAU * i / 6.0
		pa.append(Vector3(cos(a) * 95, 0, sin(a) * 95))
		pb.append(Vector3(cos(a) * 70, 26, sin(a) * 70))
	hatch.rings(pa, pb, Color(0.8, 0.76, 0.76))
	hatch.box(Vector3(0, 27, 0), Vector3(90, 3, 12), Color(0.9, 0.5, 0.9), true)
	var hatch_mi := _mi(n, hatch.commit(Models.mat("enemy"), Models.mat("glow_hot")), s3[0], s3[1])
	_scaffold(n, s3[0], s3[1])
	return {"node": n, "rock": rock, "thr": thr, "ctl": ctl, "core": core, "hatch": hatch_mi}


## 部位の周りの足場
static func _scaffold(n: Node3D, p: Vector3, b: Basis) -> void:
	var m := MB.new()
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var c := Vector3(cos(a) * 95, 20, sin(a) * 95)
		m.box(c, Vector3(10, 60, 10), Color(0.7, 0.66, 0.66))
		m.box(c + Vector3(0, 30, 0), Vector3(40, 6, 6), Color(0.7, 0.66, 0.66))
		m.box(c + Vector3(0, 40, 0), Vector3(3, 3, 3), Models.C_SPC, true)
	var mi := _mi(n, m.commit(Models.mat("enemy"), Models.mat("glow_hot")))
	mi.transform = Transform3D(b, p)
