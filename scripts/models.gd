class_name Models
extends RefCounted
## 手続き的に組み立てる艦艇・兵装のメッシュ。
## シルエットで陣営と大きさが分かるようにする：
##   味方 … 細長い船体＋左右のナセル、白灰の装甲、水色の噴射
##   敵   … 二股の衝角と背びれ、赤褐色の装甲、赤い灯火と橙の噴射
##   特殊（砲台・質量兵器の機構）… 紫の発光

const HULL_SHADER := preload("res://shaders/hull.gdshader")
const GLOW_SHADER := preload("res://shaders/glow.gdshader")
const ROCK_SHADER := preload("res://shaders/rock.gdshader")

const ALLY_BASE := Color(0.74, 0.78, 0.85)
const ENEMY_BASE := Color(0.44, 0.31, 0.29)
const C_ENG := Color(0.55, 0.85, 1.0)    # 味方の噴射
const C_NAV := Color(0.45, 1.0, 0.6)     # 味方の灯火
const C_RED := Color(1.0, 0.22, 0.12)    # 敵の灯火
const C_ORG := Color(1.0, 0.5, 0.2)      # 敵の噴射
const C_SPC := Color(0.8, 0.6, 1.0)      # 特殊

static var _cache := {}
static var _mats := {}


static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"ally":
			m = hull_mat(ALLY_BASE, Color(0.7, 0.92, 1.0), 3.2, 0.035, 0.55)
		"own":
			m = hull_mat(Color(0.62, 0.67, 0.74), Color(0.7, 0.92, 1.0), 2.2, 0.02, 0.25)
		"enemy":
			m = hull_mat(ENEMY_BASE, Color(1.0, 0.45, 0.25), 3.5, 0.03, 0.5)
		"enemy_part":
			m = hull_mat(Color(0.42, 0.31, 0.3), Color(1.0, 0.5, 0.3), 8.0, 0.0, 0.55)
		"enemy_big":
			m = hull_mat(Color(0.4, 0.3, 0.29), Color(1.0, 0.5, 0.3), 9.0, 0.045, 0.5, 5.0)
		"fort":
			m = hull_mat(Color(0.36, 0.31, 0.33), Color(1.0, 0.5, 0.35), 14.0, 0.04, 0.45, 5.0)
		"metal":
			m = hull_mat(Color(0.34, 0.35, 0.38), Color(0.6, 0.9, 1.0), 1.2, 0.0, 0.7)
		"small_e":
			m = hull_mat(Color(0.38, 0.3, 0.3), Color(1, 0.4, 0.2), 1.0, 0.0, 0.5)
		"small_a":
			m = hull_mat(Color(0.8, 0.84, 0.9), Color(0.6, 0.9, 1.0), 1.0, 0.0, 0.5)
		"far_ally":
			m = hull_mat(ALLY_BASE, Color(0.7, 0.92, 1.0), 6.0, 0.0, 0.4)
		"far_enemy":
			m = hull_mat(ENEMY_BASE * 1.1, Color(1, 0.45, 0.25), 6.0, 0.0, 0.4)
		"glow":
			m = glow_mat(1.3)
		"glow_hot":
			m = glow_mat(2.4)
		"rock":
			var r := ShaderMaterial.new()
			r.shader = ROCK_SHADER
			m = r
	_mats[key] = m
	return m


static func hull_mat(base: Color, lights: Color, panel := 4.0, density := 0.03, metal := 0.5, energy := 4.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HULL_SHADER
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("light_color", lights)
	m.set_shader_parameter("panel_size", panel)
	m.set_shader_parameter("light_density", density)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("light_energy", energy)
	return m


static func glow_mat(energy := 3.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("energy", energy)
	return m


# ------------------------------------------------------------------ 組み立て
class MB:
	var hull := SurfaceTool.new()
	var glow := SurfaceTool.new()
	var nh := 0
	var ng := 0
	var xf := Transform3D.IDENTITY

	func _init() -> void:
		hull.begin(Mesh.PRIMITIVE_TRIANGLES)
		glow.begin(Mesh.PRIMITIVE_TRIANGLES)

	## 三角形を外向きの法線・Godot の表面（時計回り）で追加
	func tri(a: Vector3, b: Vector3, c: Vector3, inside: Vector3, col: Color, g: bool) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-10:
			return
		if n.dot((a + b + c) / 3.0 - inside) > 0.0:
			var tmp := b
			b = c
			c = tmp
		else:
			n = -n
		n = n.normalized()
		var st: SurfaceTool = glow if g else hull
		for v in [a, b, c]:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(v)
		if g:
			ng += 3
		else:
			nh += 3

	## 同じ頂点数の凸な輪を二つつないだ立体（箱・錐台・円柱・楔）
	func rings(ra: Array, rb: Array, col: Color, g := false, caps := true) -> void:
		var a: Array = []
		var b: Array = []
		for p in ra:
			a.append(xf * p)
		for p in rb:
			b.append(xf * p)
		var n := a.size()
		var cen := Vector3.ZERO
		for p in a:
			cen += p
		for p in b:
			cen += p
		cen /= float(2 * n)
		for i in n:
			var j := (i + 1) % n
			tri(a[i], a[j], b[j], cen, col, g)
			tri(a[i], b[j], b[i], cen, col, g)
		if caps:
			for i in range(1, n - 1):
				tri(a[0], a[i], a[i + 1], cen, col, g)
				tri(b[0], b[i], b[i + 1], cen, col, g)

	## Z に垂直な長方形の断面（幅 w・高さ h・中心 cx, cy）
	func sec(z: float, w: float, h: float, cx := 0.0, cy := 0.0) -> Array:
		return [Vector3(cx - w * 0.5, cy - h * 0.5, z), Vector3(cx + w * 0.5, cy - h * 0.5, z),
			Vector3(cx + w * 0.5, cy + h * 0.5, z), Vector3(cx - w * 0.5, cy + h * 0.5, z)]

	## 断面を順につないだ船体
	func loft(secs: Array, col: Color, g := false) -> void:
		for i in secs.size() - 1:
			rings(secs[i], secs[i + 1], col, g)

	func box(c: Vector3, s: Vector3, col: Color, g := false) -> void:
		rings(sec(c.z + s.z * 0.5, s.x, s.y, c.x, c.y), sec(c.z - s.z * 0.5, s.x, s.y, c.x, c.y), col, g)

	## 回転つきの箱
	func obox(c: Vector3, s: Vector3, b: Basis, col: Color, g := false) -> void:
		var old := xf
		xf = xf * Transform3D(b, c)
		box(Vector3.ZERO, s, col, g)
		xf = old

	func cyl(p0: Vector3, p1: Vector3, r0: float, r1: float, seg: int, col: Color, g := false) -> void:
		var ax := (p1 - p0).normalized()
		var ref := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
		var u := ax.cross(ref).normalized()
		var v := ax.cross(u)
		var a: Array = []
		var b: Array = []
		for i in seg:
			var ang := TAU * float(i) / float(seg)
			var d := u * cos(ang) + v * sin(ang)
			a.append(p0 + d * maxf(r0, 0.001))
			b.append(p1 + d * maxf(r1, 0.001))
		rings(a, b, col, g)

	func sphere(c: Vector3, r: float, seg: int, col: Color, g := false, sq := Vector3.ONE) -> void:
		var rows := maxi(seg / 2, 3)
		var cc := xf * c
		for j in rows:
			var t0 := PI * float(j) / rows
			var t1 := PI * float(j + 1) / rows
			for i in seg:
				var p0 := TAU * float(i) / seg
				var p1 := TAU * float(i + 1) / seg
				var q := [_sp(t0, p0), _sp(t0, p1), _sp(t1, p1), _sp(t1, p0)]
				var w: Array = []
				for k in q:
					w.append(xf * (c + (k as Vector3) * r * sq))
				tri(w[0], w[1], w[2], cc, col, g)
				tri(w[0], w[2], w[3], cc, col, g)

	func _sp(th: float, ph: float) -> Vector3:
		return Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))

	func commit(hmat: Material, gmat: Material) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if nh > 0:
			hull.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, hmat)
		if ng > 0:
			glow.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, gmat)
		return mesh


static func get_mesh(key: String) -> Mesh:
	if _cache.has(key):
		return _cache[key]
	var m: Mesh
	match key:
		"ally_cruiser": m = _ally_cruiser(false)
		"ally_far": m = _ally_cruiser(true)
		"ally_frigate": m = _ally_frigate(false)
		"ally_frigate_far": m = _ally_frigate(true)
		"own_ship": m = _own_ship()
		"enemy_cruiser": m = _enemy_cruiser(false)
		"enemy_far": m = _enemy_cruiser(true)
		"enemy_frigate": m = _enemy_frigate(false)
		"enemy_frigate_far": m = _enemy_frigate(true)
		"fighter": m = _fighter()
		"attacker": m = _attacker()
		"ally_fighter": m = _ally_fighter()
		"missile": m = _missile()
		"mine": m = _mine()
		"turret_base": m = _turret_base(1.0)
		"turret_head": m = _turret_head(1.0, 2)
		"mturret_base": m = _turret_base(2.8)
		"mturret_head": m = _turret_head(2.8, 3)
		"launcher": m = _launcher()
		"sensor": m = _sensor()
		"engine_pod": m = _engine_pod()
		"capacitor": m = _capacitor()
		"thruster": m = _thruster()
		"control": m = _control()
		"blast_core": m = _blast_core()
		"gun_housing": m = _gun_housing()
		"gun_barrel": m = _gun_barrel()
		"chunk": m = _chunk()
	_cache[key] = m
	return m


# ------------------------------------------------------------------ 味方
static func _ally_cruiser(far: bool) -> ArrayMesh:
	var m := MB.new()
	var H := Color(1, 1, 1)
	var D := Color(0.66, 0.7, 0.76)
	m.loft([m.sec(45, 16, 12), m.sec(5, 19, 14), m.sec(-45, 13, 10, 0, -1), m.sec(-72, 3, 3, 0, -2.5)], H)
	m.loft([m.sec(35, 10, 6, 0, 9), m.sec(0, 8, 5, 0, 8.5)], D)
	for s in [-1.0, 1.0]:
		m.cyl(Vector3(s * 15.5, -1, 46), Vector3(s * 15.5, -1, 5), 4.5, 4.5, 8 if far else 12, H)
		m.cyl(Vector3(s * 15.5, -1, 5), Vector3(s * 15.5, -1, -8), 4.5, 1.8, 8 if far else 12, H)
		m.box(Vector3(s * 11, -1, 24), Vector3(7, 2.2, 18), D)
		m.cyl(Vector3(s * 15.5, -1, 46.1), Vector3(s * 15.5, -1, 46.6), 3.6, 3.6, 8, C_ENG, true)
	for x in [-4.0, 4.0]:
		m.cyl(Vector3(x, 0, 45.1), Vector3(x, 0, 45.6), 3.2, 3.2, 8, C_ENG, true)
	if not far:
		m.box(Vector3(0, 13.5, 20), Vector3(6, 3.5, 9), D)
		m.box(Vector3(0, 13.2, 15.4), Vector3(5.0, 0.7, 0.3), C_ENG * 0.8, true)
		m.box(Vector3(0, 18, 24), Vector3(0.5, 6, 0.5), D)
		m.rings(m.sec(40, 2, 3, 0, -7.5), m.sec(14, 1.2, 2, 0, -6.5), D)
		for z in [-18.0, -30.0]:
			var y: float = 5.5 + (z + 18.0) * 0.05
			m.box(Vector3(0, y + 1.0, z), Vector3(4.5, 1.8, 4.5), D)
			m.box(Vector3(-0.8, y + 1.3, z - 4), Vector3(0.6, 0.6, 5), D)
			m.box(Vector3(0.8, y + 1.3, z - 4), Vector3(0.6, 0.6, 5), D)
		for s in [-1.0, 1.0]:
			m.box(Vector3(s * 20.1, -1, 25), Vector3(0.3, 0.6, 18), C_NAV, true)
			m.box(Vector3(s * 9.6, 1, -40), Vector3(0.3, 0.5, 8), C_NAV, true)
	return m.commit(mat("far_ally" if far else "ally"), mat("glow"))


static func _ally_frigate(far: bool) -> ArrayMesh:
	var m := MB.new()
	var H := Color(1, 1, 1)
	var D := Color(0.66, 0.7, 0.76)
	m.loft([m.sec(22, 8, 6), m.sec(0, 10, 7), m.sec(-24, 6, 5, 0, -0.5), m.sec(-38, 1.5, 1.5, 0, -1.5)], H)
	m.cyl(Vector3(0, 5, 22), Vector3(0, 5, 2), 2.5, 2.5, 8, D)
	m.cyl(Vector3(0, 5, 22.1), Vector3(0, 5, 22.5), 2.0, 2.0, 8, C_ENG, true)
	m.cyl(Vector3(0, 0, 22.1), Vector3(0, 0, 22.5), 2.6, 2.6, 8, C_ENG, true)
	if not far:
		m.box(Vector3(0, 5.2, 6), Vector3(3, 2, 5), D)
		for s in [-1.0, 1.0]:
			m.rings(m.sec(18, 1, 2, s * 5, 0), m.sec(4, 0.8, 1.5, s * 10, -2), D)
			m.box(Vector3(s * 10, -2, 10), Vector3(0.3, 0.4, 5), C_NAV, true)
	return m.commit(mat("far_ally" if far else "ally"), mat("glow"))


## 自艦（砲手が乗っている巡洋艦）。砲座は (0, 9, -25) 付近。前甲板は急に下がって視界を空ける
static func _own_ship() -> ArrayMesh:
	var m := MB.new()
	var H := Color(1, 1, 1)
	var D := Color(0.62, 0.66, 0.72)
	# 前部：砲座の前から艦首へ急に下がる
	m.loft([m.sec(-12, 24, 14), m.sec(-34, 19, 10, 0, -3), m.sec(-60, 11, 6, 0, -9), m.sec(-80, 3, 2, 0, -13)], H)
	# 中部・後部
	m.loft([m.sec(70, 20, 12), m.sec(20, 24, 14), m.sec(-12, 24, 14)], H)
	m.loft([m.sec(60, 12, 7, 0, 10), m.sec(10, 12, 7, 0, 10), m.sec(-4, 8, 4, 0, 8)], D)
	m.box(Vector3(0, 16, 32), Vector3(8, 5, 12), D)
	m.box(Vector3(0, 16.5, 25.9), Vector3(6.6, 1.0, 0.3), C_ENG * 0.9, true)
	m.box(Vector3(0, 23, 36), Vector3(0.6, 9, 0.6), D)
	m.box(Vector3(0, 26, 36), Vector3(7, 0.4, 0.4), D)
	# 砲座の台座
	m.cyl(Vector3(0, 3.0, -24), Vector3(0, 5.2, -24), 5.5, 4.8, 16, D)
	# 甲板の縁の灯火（水色）
	for s in [-1.0, 1.0]:
		m.obox(Vector3(s * 9.8, -3.2, -46), Vector3(0.2, 0.2, 26), Basis(Vector3.RIGHT, 0.2), C_ENG * 0.35, true)
		m.box(Vector3(s * 12.1, 7.1, 20), Vector3(0.2, 0.2, 40), C_ENG * 0.35, true)
		m.cyl(Vector3(s * 18, -1, 72), Vector3(s * 18, -1, 20), 5.5, 5.5, 14, H)
		m.cyl(Vector3(s * 18, -1, 20), Vector3(s * 18, -1, 6), 5.5, 2.2, 14, H)
		m.box(Vector3(s * 13, -1, 45), Vector3(7, 2.6, 22), D)
		m.cyl(Vector3(s * 18, -1, 72.1), Vector3(s * 18, -1, 72.6), 4.5, 4.5, 14, C_ENG, true)
		# 副砲
		m.box(Vector3(s * 8, 8.2, 2), Vector3(4, 2, 4), D)
		m.box(Vector3(s * 8, 8.6, -2.5), Vector3(0.6, 0.6, 5), D)
	for x in [-5.0, 5.0]:
		m.cyl(Vector3(x, 0, 70.1), Vector3(x, 0, 70.6), 4, 4, 12, C_ENG, true)
	# 前甲板の細部
	m.box(Vector3(0, -2.6, -40), Vector3(3, 1.4, 10), D)
	m.box(Vector3(0, 6.9, -14), Vector3(10, 0.6, 2), D)
	return m.commit(mat("own"), mat("glow"))


static func _ally_fighter() -> ArrayMesh:
	var m := MB.new()
	var H := Color(1, 1, 1)
	m.loft([m.sec(3, 1.4, 1.0), m.sec(-1, 1.6, 1.2), m.sec(-4, 0.3, 0.3)], H)
	for s in [-1.0, 1.0]:
		m.rings([Vector3(s * 0.7, 0, 2.5), Vector3(s * 0.7, 0.2, -1.0), Vector3(s * 0.7, -0.2, -1.0)],
			[Vector3(s * 3.8, 0.2, 2.8), Vector3(s * 3.8, 0.3, 1.8), Vector3(s * 3.8, 0.1, 1.8)], H)
		m.box(Vector3(s * 3.8, 0.2, 2.3), Vector3(0.25, 0.25, 0.6), C_NAV, true)
	m.cyl(Vector3(0, 0, 3.0), Vector3(0, 0, 3.3), 0.6, 0.6, 6, C_ENG, true)
	return m.commit(mat("small_a"), mat("glow_hot"))


# ------------------------------------------------------------------ 敵
static func _enemy_cruiser(far: bool) -> ArrayMesh:
	var m := MB.new()
	var H := Color(1, 1, 1)
	var D := Color(0.62, 0.56, 0.56)
	m.loft([m.sec(50, 18, 10), m.sec(5, 26, 13), m.sec(-30, 14, 9, 0, -1)], H)
	for s in [-1.0, 1.0]:
		m.rings(m.sec(-18, 7, 8, s * 9, -1), m.sec(-84, 1.5, 2.5, s * 12.5, -3), H)
		m.rings(m.sec(34, 1.5, 3, s * 14, -2), m.sec(0, 1.2, 2, s * 25, -9), D)
	m.rings(m.sec(45, 2.5, 3, 0, 7), m.sec(8, 1.5, 13, 0, 12), D)
	m.rings(m.sec(8, 1.5, 13, 0, 12), m.sec(-6, 1, 2, 0, 7), D)
	for x in [-5.0, 5.0]:
		m.cyl(Vector3(x, 0, 50.1), Vector3(x, 0, 50.6), 3.8, 3.8, 8, C_ORG, true)
	if not far:
		m.rings(m.sec(48, 2, 3, 0, -6), m.sec(22, 1.2, 10, 0, -10), D)
		for s in [-1.0, 1.0]:
			m.box(Vector3(s * 12.7, 1, -6), Vector3(0.3, 0.5, 20), C_RED, true)
			m.box(Vector3(s * 11.5, -3.5, -60), Vector3(0.3, 0.4, 12), C_RED, true)
			m.box(Vector3(s * 6, 7.2, 20), Vector3(4, 2, 5), D)
			m.box(Vector3(s * 6, 7.6, 15), Vector3(0.6, 0.6, 5), D)
		m.box(Vector3(0, -1, -30.3), Vector3(6, 0.8, 0.3), C_RED, true)
	else:
		m.box(Vector3(0, 1, -10), Vector3(26.4, 0.6, 3), C_RED, true)
	return m.commit(mat("far_enemy" if far else "enemy"), mat("glow"))


static func _enemy_frigate(far: bool) -> ArrayMesh:
	var m := MB.new()
	var H := Color(1, 1, 1)
	var D := Color(0.62, 0.56, 0.56)
	m.loft([m.sec(24, 9, 6), m.sec(0, 13, 7), m.sec(-18, 5, 4, 0, -0.5)], H)
	for s in [-1.0, 1.0]:
		m.rings(m.sec(-8, 3, 4, s * 4, -0.5), m.sec(-40, 1, 1.5, s * 6, -1.5), H)
	m.rings(m.sec(22, 1.5, 2, 0, 4), m.sec(4, 1, 7, 0, 6.5), D)
	m.cyl(Vector3(0, 0, 24.1), Vector3(0, 0, 24.5), 3, 3, 8, C_ORG, true)
	if not far:
		for s in [-1.0, 1.0]:
			m.box(Vector3(s * 6.6, 0.5, 2), Vector3(0.3, 0.4, 10), C_RED, true)
	return m.commit(mat("far_enemy" if far else "enemy"), mat("glow"))


static func _fighter() -> ArrayMesh:
	var m := MB.new()
	var H := Color(1, 1, 1)
	m.loft([m.sec(3, 2.4, 1.4), m.sec(-1, 2.2, 1.5), m.sec(-5.5, 0.3, 0.3, 0, -0.2)], H)
	for s in [-1.0, 1.0]:
		m.rings([Vector3(s * 1.0, 0.0, 3.0), Vector3(s * 1.0, 0.3, -1.2), Vector3(s * 1.0, -0.3, -1.2)],
			[Vector3(s * 5.2, -0.9, 3.6), Vector3(s * 5.2, -0.8, 2.3), Vector3(s * 5.2, -1.0, 2.3)], H)
		m.rings([Vector3(s * 1.0, 0.0, 3.0), Vector3(s * 1.0, 0.3, 0.0), Vector3(s * 1.0, -0.3, 0.0)],
			[Vector3(s * 1.4, 2.0, 3.6), Vector3(s * 1.4, 2.0, 2.8), Vector3(s * 1.4, 1.8, 2.8)], H)
		m.box(Vector3(s * 5.2, -0.9, 3.0), Vector3(0.35, 0.35, 0.9), C_RED, true)
	m.cyl(Vector3(0, 0, 3.0), Vector3(0, 0, 3.35), 0.8, 0.8, 6, C_ORG, true)
	m.box(Vector3(0, 0.6, -1.8), Vector3(0.7, 0.3, 1.2), C_RED, true)
	return m.commit(mat("small_e"), mat("glow_hot"))


static func _attacker() -> ArrayMesh:
	var m := MB.new()
	var H := Color(1, 1, 1)
	var D := Color(0.65, 0.58, 0.58)
	m.loft([m.sec(6, 5, 3), m.sec(-3, 6.5, 3.6), m.sec(-9, 2.5, 2, 0, -0.5)], H)
	for s in [-1.0, 1.0]:
		m.cyl(Vector3(s * 4.6, -0.6, 5.5), Vector3(s * 4.6, -0.6, -7), 1.3, 0.8, 8, D)
		m.box(Vector3(s * 4.6, -0.6, -9.3), Vector3(0.45, 0.45, 3.2), D)
		m.rings([Vector3(s * 5.6, -0.6, 3), Vector3(s * 5.6, -0.3, -1), Vector3(s * 5.6, -0.9, -1)],
			[Vector3(s * 9.5, -1.8, 4.5), Vector3(s * 9.5, -1.7, 2.8), Vector3(s * 9.5, -1.9, 2.8)], H)
		m.cyl(Vector3(s * 4.6, -0.6, 5.6), Vector3(s * 4.6, -0.6, 6.0), 1.0, 1.0, 8, C_ORG, true)
		m.box(Vector3(s * 9.5, -1.8, 3.6), Vector3(0.4, 0.4, 0.9), C_RED, true)
	m.box(Vector3(0, 2.0, -2.5), Vector3(2.8, 0.45, 1.2), C_RED, true)
	return m.commit(mat("small_e"), mat("glow_hot"))


static func _missile() -> ArrayMesh:
	var m := MB.new()
	var H := Color(0.9, 0.85, 0.82)
	m.cyl(Vector3(0, 0, 2), Vector3(0, 0, -1.5), 0.5, 0.5, 6, H)
	m.cyl(Vector3(0, 0, -1.5), Vector3(0, 0, -3), 0.5, 0.05, 6, C_RED, true)
	for i in 4:
		var b := Basis(Vector3.BACK, PI * 0.5 * i + PI * 0.25)
		m.obox(b * Vector3(0, 0.8, 1.4), Vector3(0.12, 0.7, 1.0), b, H)
	m.cyl(Vector3(0, 0, 2.0), Vector3(0, 0, 2.3), 0.45, 0.45, 6, Color(1.0, 0.8, 0.5), true)
	return m.commit(mat("metal"), mat("glow_hot"))


static func _mine() -> ArrayMesh:
	var m := MB.new()
	var H := Color(0.8, 0.72, 0.66)
	m.sphere(Vector3.ZERO, 3.0, 10, H)
	var dirs := [Vector3.UP, Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK,
		Vector3(1, 1, 1).normalized(), Vector3(-1, 1, -1).normalized(), Vector3(1, -1, -1).normalized(), Vector3(-1, -1, 1).normalized()]
	for d in dirs:
		m.cyl(d * 2.6, d * 5.0, 0.45, 0.08, 5, H)
		m.cyl(d * 4.9, d * 5.2, 0.25, 0.25, 5, C_MINE_GLOW(), true)
	m.cyl(Vector3(0, -0.25, 0), Vector3(0, 0.25, 0), 3.15, 3.15, 14, C_MINE_GLOW(), true)
	return m.commit(mat("small_e"), mat("glow_hot"))


static func C_MINE_GLOW() -> Color:
	return Color(1.0, 0.5, 0.12)


# ------------------------------------------------------------------ 兵装・部位（敵）
static func _turret_base(s: float) -> ArrayMesh:
	var m := MB.new()
	m.cyl(Vector3(0, -1.5 * s, 0), Vector3(0, 1.2 * s, 0), 7.0 * s, 6.0 * s, 12, Color(0.8, 0.75, 0.75))
	m.box(Vector3(0, -2.0 * s, 0), Vector3(16 * s, 1.5 * s, 16 * s), Color(0.6, 0.55, 0.55))
	return m.commit(mat("enemy"), mat("glow"))


static func _turret_head(s: float, barrels: int) -> ArrayMesh:
	var m := MB.new()
	var H := Color(1, 1, 1)
	var D := Color(0.55, 0.5, 0.5)
	m.loft([m.sec(5 * s, 9 * s, 4 * s, 0, 3 * s), m.sec(-3 * s, 10 * s, 5 * s, 0, 3.2 * s), m.sec(-6 * s, 6 * s, 3 * s, 0, 3 * s)], H)
	for i in barrels:
		var x := (float(i) - (barrels - 1) * 0.5) * 2.6 * s
		m.box(Vector3(x, 3.2 * s, -12 * s), Vector3(1.0 * s, 1.0 * s, 13 * s), D)
		m.box(Vector3(x, 3.2 * s, -18.6 * s), Vector3(1.3 * s, 1.3 * s, 1.0 * s), D)
	m.box(Vector3(0, 5.6 * s, -1 * s), Vector3(3 * s, 0.4 * s, 1.5 * s), C_RED, true)
	return m.commit(mat("enemy"), mat("glow_hot"))


static func _launcher() -> ArrayMesh:
	var m := MB.new()
	m.box(Vector3(0, 5, 0), Vector3(34, 10, 22), Color(0.9, 0.85, 0.85))
	m.box(Vector3(0, 11, 0), Vector3(30, 2, 18), Color(0.6, 0.55, 0.55))
	for i in 4:
		for j in 2:
			m.box(Vector3(-10.5 + i * 7, 12.1, -4 + j * 8), Vector3(5, 0.3, 5), C_ORG, true)
	return m.commit(mat("enemy"), mat("glow_hot"))


static func _sensor() -> ArrayMesh:
	var m := MB.new()
	m.cyl(Vector3(0, 0, 0), Vector3(0, 60, 0), 8, 5, 10, Color(0.8, 0.75, 0.75))
	m.box(Vector3(0, 62, 0), Vector3(50, 6, 12), Color(0.7, 0.65, 0.65))
	m.cyl(Vector3(0, 66, 0), Vector3(0, 80, 0), 14, 2, 12, Color(0.9, 0.85, 0.85))
	for x in [-22.0, 22.0]:
		m.box(Vector3(x, 62, -6.2), Vector3(4, 3, 0.4), C_RED, true)
	m.sphere(Vector3(0, 82, 0), 3, 8, C_RED, true)
	return m.commit(mat("enemy"), mat("glow_hot"))


static func _engine_pod() -> ArrayMesh:
	var m := MB.new()
	m.cyl(Vector3(0, 0, -60), Vector3(0, 0, 50), 26, 34, 14, Color(0.85, 0.8, 0.8))
	m.cyl(Vector3(0, 0, 50), Vector3(0, 0, 70), 34, 28, 14, Color(0.6, 0.55, 0.55))
	for i in 6:
		var b := Basis(Vector3.BACK, TAU * i / 6.0)
		m.obox(b * Vector3(0, 36, 0), Vector3(3, 8, 60), b, Color(0.7, 0.65, 0.65))
	m.cyl(Vector3(0, 0, 70.2), Vector3(0, 0, 71), 24, 24, 14, C_ORG, true)
	m.cyl(Vector3(0, 0, 71), Vector3(0, 0, 150), 22, 2, 10, Color(1.0, 0.45, 0.2) * 0.5, true)
	return m.commit(mat("enemy_part"), mat("glow_hot"))


## 大型レーザー砲台の集束器（紫の発光）
static func _capacitor() -> ArrayMesh:
	var m := MB.new()
	m.cyl(Vector3(0, -40, 0), Vector3(0, 40, 0), 16, 16, 8, Color(0.75, 0.7, 0.75))
	for i in 4:
		var b := Basis(Vector3.UP, PI * 0.5 * i)
		m.obox(b * Vector3(20, 0, 0), Vector3(6, 90, 10), b, Color(0.6, 0.55, 0.6))
	m.cyl(Vector3(0, -30, 0), Vector3(0, 30, 0), 18.5, 18.5, 8, C_SPC, true)
	m.cyl(Vector3(0, 40, 0), Vector3(0, 55, 0), 12, 3, 8, Color(0.75, 0.7, 0.75))
	return m.commit(mat("enemy"), mat("glow_hot"))


## 質量兵器の推進器
static func _thruster() -> ArrayMesh:
	var m := MB.new()
	m.box(Vector3(0, 8, 0), Vector3(110, 16, 110), Color(0.7, 0.66, 0.66))
	m.cyl(Vector3(0, 10, 0), Vector3(0, 50, 0), 40, 46, 16, Color(0.85, 0.8, 0.8))
	m.cyl(Vector3(0, 50, 0), Vector3(0, 90, 0), 46, 60, 16, Color(0.6, 0.56, 0.56))
	m.cyl(Vector3(0, 88, 0), Vector3(0, 89, 0), 52, 52, 16, C_SPC, true)
	for i in 4:
		var b := Basis(Vector3.UP, PI * 0.5 * i + PI * 0.25)
		m.obox(b * Vector3(0, 40, 62), Vector3(8, 70, 8), b * Basis(Vector3.RIGHT, -0.35), Color(0.6, 0.56, 0.56))
	return m.commit(mat("enemy"), mat("glow_hot"))


## 質量兵器の制御装置
static func _control() -> ArrayMesh:
	var m := MB.new()
	m.box(Vector3(0, 30, 0), Vector3(50, 60, 50), Color(0.85, 0.8, 0.8))
	m.box(Vector3(0, 70, 0), Vector3(34, 20, 34), Color(0.7, 0.65, 0.65))
	m.cyl(Vector3(0, 80, 0), Vector3(0, 150, 0), 3, 1, 6, Color(0.7, 0.65, 0.65))
	m.cyl(Vector3(14, 80, 10), Vector3(14, 120, 10), 2, 1, 6, Color(0.7, 0.65, 0.65))
	m.box(Vector3(0, 70, -17.3), Vector3(26, 6, 0.6), C_SPC, true)
	m.box(Vector3(-25.3, 30, 0), Vector3(0.6, 30, 30), C_SPC * 0.7, true)
	m.sphere(Vector3(0, 152, 0), 3, 8, C_SPC, true)
	return m.commit(mat("enemy"), mat("glow_hot"))


## 質量兵器の爆破点（装甲の奥の炉心）
static func _blast_core() -> ArrayMesh:
	var m := MB.new()
	var pts_a: Array = []
	var pts_b: Array = []
	for i in 6:
		var a := TAU * i / 6.0
		pts_a.append(Vector3(cos(a) * 80, 0, sin(a) * 80))
		pts_b.append(Vector3(cos(a) * 66, 14, sin(a) * 66))
	m.rings(pts_a, pts_b, Color(0.8, 0.75, 0.75), false, false)
	m.sphere(Vector3(0, 10, 0), 34, 14, Color(1.0, 0.45, 0.9), true, Vector3(1, 0.6, 1))
	return m.commit(mat("enemy"), mat("glow_hot"))


# ------------------------------------------------------------------ 自砲
static func _gun_housing() -> ArrayMesh:
	var m := MB.new()
	var H := Color(0.95, 0.97, 1.0)
	var D := Color(0.55, 0.58, 0.64)
	# 照準手の真下は空けておく（視界を狭くしない）。旋回リングと、砲身の根元を包む左右の防盾だけ
	m.cyl(Vector3(0, -1.2, 0), Vector3(0, -0.5, 0), 4.4, 4.0, 24, D)
	for s in [-1.0, 1.0]:
		m.loft([m.sec(0.8, 1.3, 1.3, s * 2.4, 0.0), m.sec(-2.0, 1.6, 1.6, s * 2.4, 0.0), m.sec(-3.0, 1.1, 1.1, s * 2.4, 0.0)], H)
		m.box(Vector3(s * 3.25, 0.1, -1.0), Vector3(0.1, 0.18, 2.2), C_ENG * 0.5, true)
	return m.commit(mat("own"), mat("glow"))


static func _gun_barrel() -> ArrayMesh:
	var m := MB.new()
	var D := Color(0.62, 0.64, 0.7)
	m.cyl(Vector3(0, 0, 1.5), Vector3(0, 0, -6.5), 0.62, 0.5, 10, D)
	m.cyl(Vector3(0, 0, -6.5), Vector3(0, 0, -8.2), 0.72, 0.72, 10, Color(0.45, 0.47, 0.52))
	for z in [-2.0, -3.2, -4.4]:
		m.cyl(Vector3(0, 0, z), Vector3(0, 0, z - 0.4), 0.7, 0.7, 10, Color(0.4, 0.42, 0.47))
	m.cyl(Vector3(0, 0, -8.21), Vector3(0, 0, -8.3), 0.42, 0.42, 10, C_ENG, true)
	return m.commit(mat("own"), mat("glow"))


static func _chunk() -> ArrayMesh:
	var m := MB.new()
	m.rings([Vector3(-1, -0.6, 0.8), Vector3(0.9, -0.8, 0.7), Vector3(1.1, 0.7, 0.9), Vector3(-0.8, 0.9, 0.6)],
		[Vector3(-0.6, -0.4, -1.0), Vector3(0.5, -0.9, -0.8), Vector3(0.7, 0.3, -1.1), Vector3(-0.3, 0.6, -0.9)], Color(0.7, 0.66, 0.64))
	return m.commit(mat("metal"), mat("glow"))


# ------------------------------------------------------------------ 岩
## ノイズで歪めた球（質量兵器・破片）。seed で形を変える
static func rock_mesh(radius: float, subdiv: int, seed_v: int, rough := 0.18) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 1.6
	noise.fractal_octaves = 4
	var verts := _icosphere(subdiv)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cache := {}
	var disp := func(v: Vector3) -> Vector3:
		if cache.has(v):
			return cache[v]
		var n := noise.get_noise_3dv(v)
		var n2 := noise.get_noise_3dv(v * 3.1 + Vector3(5, 1, 2))
		var r := radius * (1.0 + n * rough * 1.6 + n2 * rough * 0.4)
		var p: Vector3 = v * r
		cache[v] = p
		return p
	for i in range(0, verts.size(), 3):
		var a: Vector3 = disp.call(verts[i])
		var b: Vector3 = disp.call(verts[i + 1])
		var c: Vector3 = disp.call(verts[i + 2])
		# 外向き・時計回り
		if (b - a).cross(c - a).dot(a + b + c) > 0.0:
			var tmp := b
			b = c
			c = tmp
		for p in [a, b, c]:
			st.set_color(Color(1, 1, 1))
			st.add_vertex(p)
	st.index()
	st.generate_normals()
	var mesh := st.commit()
	var m := ShaderMaterial.new()
	m.shader = ROCK_SHADER
	m.set_shader_parameter("scale", 3.0 / radius)
	mesh.surface_set_material(0, m)
	return mesh


static func _icosphere(subdiv: int) -> PackedVector3Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var tris := PackedVector3Array()
	for q in f:
		tris.append((v[q[0]] as Vector3).normalized())
		tris.append((v[q[1]] as Vector3).normalized())
		tris.append((v[q[2]] as Vector3).normalized())
	for _s in subdiv:
		var nt := PackedVector3Array()
		for i in range(0, tris.size(), 3):
			var a := tris[i]
			var b := tris[i + 1]
			var c := tris[i + 2]
			var ab := ((a + b) * 0.5).normalized()
			var bc := ((b + c) * 0.5).normalized()
			var ca := ((c + a) * 0.5).normalized()
			nt.append_array(PackedVector3Array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]))
		tris = nt
	return tris
