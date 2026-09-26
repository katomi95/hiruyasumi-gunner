extends Path3D
## RailPath：自艦の自動航行。時刻つきの位置キーから Curve3D を組み、PathFollow3D を時刻で進める。
## 視線キーで砲座カメラの向きを決める。プレイヤーは進路にも速度にも関与しない。
## 旋回に合わせて艦がゆるく傾き、カメラもわずかに追う（照準を邪魔しない程度）

const TURRET := Vector3(0, 8.2, -24)     # 自艦の中の砲座の位置
const CAM_OFF := Vector3(0, 4.5, 3.4)    # 砲座から見た照準手の目の位置

@onready var follow: PathFollow3D = $Follow
@onready var ship_rig: Node3D = $Follow/ShipRig
@onready var cam_rig: Node3D = $CamRig
@onready var camera: Camera3D = $CamRig/Camera

var keys: Array = []
var offs := PackedFloat32Array()
var looks: Array = []

var pos := Vector3.ZERO       # 自艦の位置
var cam_pos := Vector3.ZERO
var fwd := Vector3.FORWARD
var vel := Vector3.ZERO
var look_dir := Vector3.FORWARD
var bank := 0.0
var cam_yaw := 0.0
var shake_amt := 0.0
var sway_t := 0.0
var title_mode := true
var _prev_look := Vector3.ZERO


func _ready() -> void:
	Game.rail = self
	follow.rotation_mode = PathFollow3D.ROTATION_NONE
	follow.loop = false
	var ship := MeshInstance3D.new()
	ship.mesh = Models.get_mesh("own_ship")
	ship.name = "OwnShip"
	ship_rig.add_child(ship)
	camera.fov = 70.0
	camera.near = 0.4
	camera.far = 40000.0
	camera.current = true


## pos_keys: [[t, Vector3], ...]  look_keys: [{t, target, w, yaw, pitch}, ...]
func build(pos_keys: Array, look_keys: Array) -> void:
	keys = pos_keys
	looks = look_keys
	var c := Curve3D.new()
	c.bake_interval = 1.0
	var n := keys.size()
	for i in n:
		var p: Vector3 = keys[i][1]
		var prev: Vector3 = keys[maxi(i - 1, 0)][1]
		var next: Vector3 = keys[mini(i + 1, n - 1)][1]
		var tn := (next - prev) / 6.0
		c.add_point(p, -tn, tn)
	curve = c
	offs = PackedFloat32Array()
	var last := 0.0
	for i in n:
		var o := c.get_closest_offset(keys[i][1])
		o = maxf(o, last)
		offs.append(o)
		last = o


func _slope(i: int) -> float:
	var n := keys.size()
	var a := maxi(i - 1, 0)
	var b := mini(i + 1, n - 1)
	return (offs[b] - offs[a]) / (float(keys[b][0]) - float(keys[a][0]))


func offset_at(t: float) -> float:
	var n := keys.size()
	if t <= float(keys[0][0]):
		return offs[0]
	if t >= float(keys[n - 1][0]):
		return offs[n - 1] + (t - float(keys[n - 1][0])) * _slope(n - 1)
	var i := 0
	while i < n - 2 and t > float(keys[i + 1][0]):
		i += 1
	var t0: float = keys[i][0]
	var t1: float = keys[i + 1][0]
	var h := t1 - t0
	var s := (t - t0) / h
	var m0 := _slope(i) * h
	var m1 := _slope(i + 1) * h
	var s2 := s * s
	var s3 := s2 * s
	var o := (2 * s3 - 3 * s2 + 1) * offs[i] + (s3 - 2 * s2 + s) * m0 + (-2 * s3 + 3 * s2) * offs[i + 1] + (s3 - s2) * m1
	return clampf(o, offs[i], offs[i + 1])


func pos_at(t: float) -> Vector3:
	var o := offset_at(t)
	var L := curve.get_baked_length()
	if o > L:
		var p := curve.sample_baked(L, true)
		var p2 := curve.sample_baked(L - 5.0, true)
		return p + (p - p2).normalized() * (o - L)
	return curve.sample_baked(o, true)


func fwd_at(t: float) -> Vector3:
	var d := pos_at(t + 0.3) - pos_at(t - 0.3)
	if d.length() < 0.01:
		return fwd
	return d.normalized()


## 自艦の進行方向の座標系（傾きなし）
func frame_at(t: float) -> Basis:
	return Basis.looking_at(fwd_at(t), Vector3.UP)


func frame() -> Basis:
	return Basis.looking_at(fwd, Vector3.UP)


## カメラの向きの座標系（傾きなし）。敵の出現位置はこれで決める
func view_basis() -> Basis:
	return Basis.looking_at(look_dir, Vector3.UP)


func _look_of(k: Dictionary, p: Vector3, f: Vector3) -> Vector3:
	var d := f
	var tg = k.get("target")
	if tg != null:
		var to: Vector3 = ((tg as Vector3) - p).normalized()
		d = f.slerp(to, float(k.get("w", 1.0))).normalized()
	var yaw: float = k.get("yaw", 0.0)
	var pitch: float = k.get("pitch", 0.0)
	if yaw != 0.0:
		d = d.rotated(Vector3.UP, deg_to_rad(yaw))
	if pitch != 0.0:
		var ax := d.cross(Vector3.UP)
		if ax.length() > 0.01:
			d = d.rotated(ax.normalized(), deg_to_rad(pitch))
	return d.normalized()


func look_at_time(t: float, p: Vector3, f: Vector3) -> Vector3:
	var n := looks.size()
	if n == 0:
		return f
	if t <= float(looks[0]["t"]):
		return _look_of(looks[0], p, f)
	if t >= float(looks[n - 1]["t"]):
		return _look_of(looks[n - 1], p, f)
	var i := 0
	while i < n - 2 and t > float(looks[i + 1]["t"]):
		i += 1
	var t0: float = looks[i]["t"]
	var t1: float = looks[i + 1]["t"]
	var w := smoothstep(0.0, 1.0, (t - t0) / (t1 - t0))
	var a := _look_of(looks[i], p, f)
	var b := _look_of(looks[i + 1], p, f)
	return a.slerp(b, w).normalized()


func shake(a: float) -> void:
	shake_amt = maxf(shake_amt, a)


func update(t: float, dt: float) -> void:
	var o := offset_at(t)
	follow.progress = minf(o, curve.get_baked_length())
	var new_pos := pos_at(t)
	if dt > 0.0:
		vel = vel.lerp((new_pos - pos) / dt, clampf(dt * 6.0, 0.0, 1.0))
	pos = new_pos
	follow.global_position = pos
	fwd = fwd_at(t)
	# 旋回に合わせた傾き
	var h := 0.6
	var acc := (pos_at(t + h) - 2.0 * pos + pos_at(t - h)) / (h * h)
	var right := fwd.cross(Vector3.UP).normalized()
	var target_bank := clampf(acc.dot(right) * 0.018, -0.32, 0.32)
	bank = lerpf(bank, target_bank, clampf(dt * 2.0, 0.0, 1.0))
	var up := (Vector3.UP * cos(bank) + right * sin(bank)).normalized()
	ship_rig.global_basis = Basis.looking_at(fwd, up)

	# 視線
	var ld := look_at_time(t, pos, fwd)
	if title_mode:
		sway_t += dt
		ld = fwd.rotated(Vector3.UP, sin(sway_t * 0.12) * 0.55 + 0.25).rotated(right, 0.06)
	if _prev_look == Vector3.ZERO:
		_prev_look = ld
	look_dir = _prev_look.slerp(ld, clampf(dt * 4.0, 0.0, 1.0)).normalized()
	_prev_look = look_dir
	# 照準手のわずかな揺れ
	sway_t += dt
	var sway := Vector3(sin(sway_t * 0.53) * 0.004, sin(sway_t * 0.71) * 0.003, 0.0)
	var cb := Basis.looking_at(look_dir, Vector3.UP)
	var local_dir := ship_rig.global_basis.inverse() * look_dir
	cam_yaw = atan2(-local_dir.x, -local_dir.z)
	var mount := ship_rig.global_transform * (TURRET + Basis(Vector3.UP, cam_yaw) * CAM_OFF)
	cb = cb * Basis(Vector3.BACK, -bank * 0.35) * Basis(Vector3.RIGHT, sway.y) * Basis(Vector3.UP, sway.x)
	cam_pos = mount
	cam_rig.global_transform = Transform3D(cb, mount)
	if shake_amt > 0.001:
		camera.h_offset = randf_range(-1, 1) * shake_amt * 0.35
		camera.v_offset = randf_range(-1, 1) * shake_amt * 0.35
		shake_amt = maxf(0.0, shake_amt - dt * 2.5)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
