extends Node3D
## PlayerGun：自艦の砲座。操作は照準（マウス）と射撃（左クリック）だけ。
## 右クリックは重粒子砲（高威力だが一発で大きく熱を持つ）。撃ち続けるとオーバーヒートして一時射撃不能。
## 砲身は照準位置へ追従する。自動ロックオンはしない（重なった時に照準の色が変わるだけ）

const RATE := 8.5
const HEAT_SHOT := 0.036
const HEAT_HEAVY := 0.5
const COOL := 0.62
const COOL_OVER := 0.5
const DMG := 1.0
const DMG_HEAVY := 10.0
const BOLT_SPEED := 2600.0
const COL := Color(0.5, 0.9, 1.0)

var housing: Node3D
var pitch_node: Node3D
var barrels: Array = []
var muzzle_light: OmniLight3D
var heat := 0.0
var overheated := false
var idle_t := 0.0
var cd := 0.0
var barrel_i := 0
var recoil := [0.0, 0.0]
var aim_screen := Vector2(640, 360)
var aim_point := Vector3.ZERO
var aim_target: Target = null
var aim_hit := {}
var heavy_req := false
var last_lock: Target = null
var muzzle_t := 0.0
var heat_mat: StandardMaterial3D
var heat_warned := false
var steam: CPUParticles3D

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
	housing.add_child(hm)
	pitch_node = Node3D.new()
	pitch_node.position = Vector3(0, 0.4, -1.0)
	housing.add_child(pitch_node)
	for s in [-1.0, 1.0]:
		var b := MeshInstance3D.new()
		b.mesh = Models.get_mesh("gun_barrel")
		b.position = Vector3(s * 2.4, 0, 0)
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pitch_node.add_child(b)
		barrels.append(b)
	# 砲身の赤熱（熱に応じて重ねる発光）
	heat_mat = StandardMaterial3D.new()
	heat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	heat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	heat_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	heat_mat.albedo_color = Color(1.0, 0.3, 0.08, 0.0)
	for b2 in barrels:
		(b2 as MeshInstance3D).material_overlay = heat_mat
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = COL
	muzzle_light.omni_range = 18.0
	muzzle_light.light_energy = 0.0
	muzzle_light.position = Vector3(0, 0, -9)
	pitch_node.add_child(muzzle_light)


func _unhandled_input(event: InputEvent) -> void:
	if Game.state != "play" or Game.paused:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		heavy_req = true


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
	_heat_visual(dt)

	if not playing:
		return
	cd -= dt
	var want_fire := false
	var want_heavy := heavy_req
	heavy_req = false
	if Game.opts["autoplay"]:
		want_fire = _bot_fire
		want_heavy = _bot_heavy
		_bot_heavy = false
	else:
		want_fire = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if Game.opts["nofire"]:
		want_fire = false
		want_heavy = false
	if overheated:
		heat -= COOL_OVER * dt
		if heat <= 0.25:
			overheated = false
		return
	if want_heavy and heat < 0.4:
		_fire(true, o, d)
		cd = 1.0 / RATE
		idle_t = 0.0
	elif want_fire and cd <= 0.0:
		_fire(false, o, d)
		cd = 1.0 / RATE
		idle_t = 0.0
	else:
		idle_t += dt
		if idle_t > 0.18:
			heat = maxf(0.0, heat - COOL * dt)
	if heat >= 1.0:
		heat = 1.0
		overheated = true
		Game.audio.play("overheat", -2.0)
		_steam_burst()


## 砲身の見た目：熱いほど赤く光り、過熱の手前で警告音、オーバーヒートで蒸気
func _heat_visual(_dt: float) -> void:
	var k := clampf((heat - 0.45) / 0.55, 0.0, 1.0)
	var a := k * k * 0.75
	if overheated:
		a = maxf(a, 0.35 + 0.25 * sin(Time.get_ticks_msec() * 0.02))
	heat_mat.albedo_color = Color(1.0, 0.35 - k * 0.2, 0.08, a)
	if heat > 0.75 and not heat_warned and not overheated and Game.state == "play":
		heat_warned = true
		Game.audio.play("missile_warn", -10.0, 0.6)
	elif heat < 0.6:
		heat_warned = false


func _steam_burst() -> void:
	if steam == null:
		steam = CPUParticles3D.new()
		var q := QuadMesh.new()
		q.material = Game.fx.mat_smoke
		steam.mesh = q
		steam.amount = 24
		steam.lifetime = 1.4
		steam.one_shot = true
		steam.explosiveness = 0.2
		steam.local_coords = false
		steam.direction = Vector3.UP
		steam.spread = 35.0
		steam.gravity = Vector3.ZERO
		steam.initial_velocity_min = 3.0
		steam.initial_velocity_max = 7.0
		steam.scale_amount_min = 1.0
		steam.scale_amount_max = 2.2
		var g := Gradient.new()
		g.set_color(0, Color(0.9, 0.9, 0.95, 0.0))
		g.set_color(1, Color(0.8, 0.8, 0.85, 0.0))
		g.add_point(0.15, Color(0.85, 0.85, 0.9, 0.45))
		steam.color_ramp = g
		steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		steam.emission_box_extents = Vector3(2.4, 0.3, 3.0)
		steam.position = Vector3(0, 0.6, -4.0)
		steam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pitch_node.add_child(steam)
	steam.restart()


func _fire(heavy: bool, o: Vector3, d: Vector3) -> void:
	var i := barrel_i
	barrel_i = 1 - barrel_i
	var mp := muzzle_pos(i)
	var hit := aim_hit
	var to := aim_point
	var dist := mp.distance_to(to)
	var travel := clampf(dist / BOLT_SPEED, 0.02, 0.35)
	Game.stats["shots"] += 1
	if heavy:
		heat += HEAT_HEAVY
		recoil[0] = 1.0
		recoil[1] = 1.0
		Game.fx.bolt(muzzle_pos(0), to, Color(0.7, 0.85, 1.0), 2.6, travel, 400.0, 5.0)
		Game.fx.bolt(muzzle_pos(1), to, Color(0.7, 0.85, 1.0), 2.6, travel, 400.0, 5.0)
		Game.fx.beam(mp, to, Color(0.45, 0.7, 1.0), 4.0, 0.3, 2.0)
		Game.fx.flash(muzzle_pos(0), 9.0, COL, 0.12)
		Game.fx.flash(muzzle_pos(1), 9.0, COL, 0.12)
		Game.audio.play("heavy", -1.0, randf_range(0.95, 1.05))
		Game.rail.shake(0.5)
		muzzle_t = 0.2
	else:
		heat += HEAT_SHOT
		recoil[i] = 1.0
		Game.fx.bolt(mp, to, COL, 0.55, travel, 60.0, 3.5)
		Game.fx.flash(mp, 3.2, COL, 0.06)
		Game.audio.play("shot", -7.0, randf_range(0.94, 1.08))
		muzzle_t = 0.08
	if not hit.is_empty():
		Game.enemies.shoot(hit, DMG_HEAVY if heavy else DMG, travel, heavy)


# ------------------------------------------------------------------ 検証用の自動砲手
var _bot_fire := false
var bot_prev := Vector2.ZERO
var bot_prev_t: Target = null
var _bot_heavy := false


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
	if bot_pos.distance_to(sp) < pr + 5.0 and heat < 0.9:
		_bot_fire = true
		if bot_target.objective and heat < 0.3 and randf() < 0.1:
			_bot_heavy = true


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
