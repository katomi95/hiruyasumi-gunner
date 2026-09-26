extends Node3D
## PlayerGun：自艦の砲座。操作は照準（マウス）と射撃（左クリック・押しっぱなしで連射）だけ。
## 主砲はレーザー。撃った瞬間に照準点まで光の筋が伸び、そのまま当たる。砲身の加熱はない。
## 砲塔の模型は表示しない（砲口の位置だけ使い、光の筋はそこから出る）。砲口は照準位置へ追従する。自動ロックオンはしない（重なった時に照準の色が変わるだけ）

const RATE := 6.0
const DMG := 2.5
const COL := Color(0.5, 0.9, 1.0)
const CORE := Color(0.85, 0.97, 1.0)

var housing: Node3D
var pitch_node: Node3D
var barrels: Array = []
var muzzle_light: OmniLight3D
var cd := 0.0
var barrel_i := 0
var recoil := [0.0, 0.0]
var aim_screen := Vector2(640, 360)
var aim_point := Vector3.ZERO
var aim_target: Target = null
var aim_hit := {}
var last_lock: Target = null
var muzzle_t := 0.0

# 自動操縦（検証用）
var bot_pos := Vector2(640, 360)
var bot_target: Target = null
var bot_think := 0.0


func _ready() -> void:
	Game.gun = self
	position = Vector3(0, 8.2, -24)
	housing = Node3D.new()
	add_child(housing)
	var hm := MeshInstance3D.new()
	hm.mesh = Models.get_mesh("gun_housing")
	hm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hm.visible = false
	housing.add_child(hm)
	pitch_node = Node3D.new()
	pitch_node.position = Vector3(0, 0.4, -1.0)
	housing.add_child(pitch_node)
	for s in [-1.0, 1.0]:
		var b := MeshInstance3D.new()
		b.mesh = Models.get_mesh("gun_barrel")
		b.position = Vector3(s * 2.4, 0, 0)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visible = false
		pitch_node.add_child(b)
		barrels.append(b)
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = COL
	muzzle_light.omni_range = 18.0
	muzzle_light.light_energy = 0.0
	muzzle_light.position = Vector3(0, 0, -9)
	pitch_node.add_child(muzzle_light)


func muzzle_pos(i: int) -> Vector3:
	return (barrels[i] as Node3D).global_transform * Vector3(0, 0, -8.4)


func tick(dt: float) -> void:
	var rail = Game.rail
	var cam: Camera3D = rail.camera
	housing.rotation = Vector3(0, rail.cam_yaw, 0)
	var vp_size := get_viewport().get_visible_rect().size
	var playing: bool = Game.state == "play" and not Game.paused
	if Game.opts["autoplay"] and Game.state == "play":
		_bot(dt, cam, vp_size)
		aim_screen = bot_pos
	else:
		aim_screen = get_viewport().get_mouse_position()
		if Game.state != "play":
			aim_screen = vp_size * 0.5
	var o := cam.project_ray_origin(aim_screen)
	var d := cam.project_ray_normal(aim_screen)
	aim_hit = Game.enemies.raycast(o, d, 9000.0)
	if aim_hit.is_empty():
		aim_point = o + d * 3000.0
		aim_target = null
	else:
		aim_point = aim_hit["point"]
		aim_target = aim_hit["target"]
	if aim_target != null and aim_target != last_lock and playing:
		Game.audio.play("lock", -14.0, 1.0)
	last_lock = aim_target

	# 砲身を照準点へ追従
	var ld := housing.global_basis.inverse() * (aim_point - pitch_node.global_position)
	if ld.length() > 0.1:
		var want := Basis.looking_at(ld.normalized(), Vector3.UP).get_rotation_quaternion()
		var cur := pitch_node.basis.get_rotation_quaternion()
		pitch_node.basis = Basis(cur.slerp(want, clampf(dt * 16.0, 0.0, 1.0)))
	for i in 2:
		recoil[i] = maxf(0.0, recoil[i] - dt * 6.0)
		(barrels[i] as Node3D).position.z = recoil[i] * 1.1
	muzzle_t = maxf(0.0, muzzle_t - dt)
	muzzle_light.light_energy = muzzle_t * 30.0

	if not playing:
		return
	cd -= dt
	var want_fire := false
	if Game.opts["autoplay"]:
		want_fire = _bot_fire
	else:
		want_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if Game.opts["nofire"]:
		want_fire = false
	if want_fire and cd <= 0.0:
		_fire()
		cd = 1.0 / RATE


## レーザー：砲口から照準点まで一瞬で光の筋が伸びる。外側の光と白い芯の二重にして見やすくする
func _fire() -> void:
	var i := barrel_i
	barrel_i = 1 - barrel_i
	var mp := muzzle_pos(i)
	var to := aim_point
	Game.stats["shots"] += 1
	recoil[i] = 1.0
	Game.fx.beam(mp, to, COL, 1.5, 0.16, 2.6)
	Game.fx.beam(mp, to, CORE, 0.7, 0.1, 6.0)
	Game.fx.flash(mp, 5.0, COL, 0.08)
	Game.audio.laser()
	muzzle_t = 0.1
	if not aim_hit.is_empty():
		Game.enemies.shoot(aim_hit, DMG, 0.02, false)


# ------------------------------------------------------------------ 検証用の自動砲手
var _bot_fire := false
var bot_prev := Vector2.ZERO
var bot_prev_t: Target = null


func _bot(dt: float, cam: Camera3D, vs: Vector2) -> void:
	bot_think -= dt
	if bot_think <= 0.0 or bot_target == null or not is_instance_valid(bot_target) or not bot_target.alive:
		bot_think = 0.3
		bot_target = _bot_pick(cam, vs)
	_bot_fire = false
	if bot_target == null or not is_instance_valid(bot_target):
		bot_pos = bot_pos.move_toward(vs * 0.5, 600.0 * dt)
		return
	var p := bot_target.hit_center()
	if cam.is_position_behind(p):
		return
	var sp := cam.unproject_position(p)
	# 画面上の動きを一コマ分だけ先読みする
	var lead := sp - bot_prev if bot_prev_t == bot_target else Vector2.ZERO
	bot_prev = sp
	bot_prev_t = bot_target
	sp += lead
	bot_pos = bot_pos.move_toward(sp + Vector2(randf_range(-4, 4), randf_range(-4, 4)), 1500.0 * dt)
	var dist := cam.global_position.distance_to(p)
	var pr := bot_target.radius / maxf(dist, 1.0) * vs.y * 0.5 / tan(deg_to_rad(cam.fov * 0.5))
	if bot_pos.distance_to(sp) < pr + 5.0:
		_bot_fire = true


func _bot_pick(cam: Camera3D, vs: Vector2) -> Target:
	var best: Target = null
	var bs := -1e9
	for e in Game.enemies.targets:
		var t: Target = e
		if not t.alive or not t.targetable or not t.is_visible_in_tree():
			continue
		var p := t.hit_center()
		if cam.is_position_behind(p):
			continue
		var sp := cam.unproject_position(p)
		if sp.x < 0 or sp.y < 0 or sp.x > vs.x or sp.y > vs.y:
			continue
		var dist := cam.global_position.distance_to(p)
		var s := 0.0
		match t.kind:
			"missile": s = 100.0 - dist / 60.0
			"attacker": s = 60.0 + t.charge * 30.0
			"mine": s = (90.0 if t.dangerous else -50.0) - dist / 40.0
			"fighter": s = 40.0
			_: s = 50.0 if t.objective else 20.0
		if dist > 2600.0:
			s -= 40.0
		s -= sp.distance_to(bot_pos) / 40.0
		if s > bs:
			bs = s
			best = t
	return best
