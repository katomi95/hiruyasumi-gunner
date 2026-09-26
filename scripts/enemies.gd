extends Node3D
## EnemyManager：敵の出現・行動・当たり判定・敵弾。
## 敵の行動は「画面内へ侵入 → 攻撃 → 離脱」の短いものだけ。
## 敵機・ミサイル・敵弾は自艦に固定した座標系で動かす（自艦がどこを航行していても同じ見え方になる）

const BEAM_SHADER := preload("res://shaders/beam.gdshader")

var targets: Array = []
var armor: Array = []          # {node, aabb} または {node, r}
var bolts: Array = []          # 敵弾
var bolt_free: Array = []
var flyby_cd := 0.0
## 敵の攻撃の激しさ（射撃の頻度・命中率）。レーザー化で自艦の火力が上がった分、敵も強める
const FIGHTER_HIT := 0.2
const ATTACKER_HIT := 0.24
const ATTACKER_BURST := 4
const TURRET_HIT := 0.27
var warn_cd := 0.0


func _ready() -> void:
	Game.enemies = self
	for i in 48:
		var mi := MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		var m := ShaderMaterial.new()
		m.shader = BEAM_SHADER
		m.set_shader_parameter("color", Color(1.0, 0.35, 0.25))
		m.set_shader_parameter("intensity", 3.5)
		m.set_shader_parameter("tail", 1.0)
		mi.material_override = m
		mi.custom_aabb = AABB(Vector3(-1, -1, -1.2), Vector3(2, 2, 1.4))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		bolt_free.append(mi)


# ------------------------------------------------------------------ 生成
func _make(kind: String, mesh_key: String, hp: float, radius: float, score: int, parent: Node3D = null) -> Target:
	var e := Target.new()
	e.kind = kind
	e.hp = hp
	e.max_hp = hp
	e.radius = radius
	e.score = score
	if mesh_key != "":
		var mi := MeshInstance3D.new()
		mi.mesh = Models.get_mesh(mesh_key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.add_child(mi)
	(parent if parent else self).add_child(e)
	targets.append(e)
	return e


func _glow_ball(parent: Node3D, r: float, col: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 10
	s.rings = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r * 3.0, col.g * 3.0, col.b * 3.0)
	s.material = m
	mi.mesh = s
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _anchor(e: Target, local: Vector3, vel: Vector3, b: Basis) -> void:
	e.anchored = true
	e.frame = b
	e.local = local
	e.lvel = vel
	e.global_position = Game.rail.pos + b * local


## 小型戦闘艇の編隊。start / vel は出現時のカメラ基準（x 右・y 上・-z 前方）
func fighters(n: int, start: Vector3, vel: Vector3, opts := {}) -> void:
	var b: Basis = Game.rail.view_basis()
	var dirv := vel.normalized()
	var side := dirv.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	side = side.normalized()
	var sp: float = opts.get("spacing", 16.0)
	for i in n:
		var k := (i + 1) / 2 * (1 if i % 2 == 1 else -1)
		var off := side * k * sp - dirv * absf(k) * sp * 0.9 + Vector3(0, randf_range(-3, 3), 0)
		var e := _make("fighter", "fighter", 3.0, 5.5, 100)
		e.boom = 7.0
		e.life = opts.get("life", 14.0)
		e.d = {"amp": randf_range(8, 22), "f": randf_range(0.8, 1.6), "ph": randf() * TAU,
			"fire": opts.get("fire", 0.0), "cd": randf_range(1.0, 3.0), "flyby": false}
		_anchor(e, start + off, vel * randf_range(0.95, 1.05), b)
		e.setup_flash()


## 攻撃艇：画面外から持ち場（hover）へ入り、しばらく撃ってから離脱する
func attacker(start: Vector3, hover: Vector3, opts := {}) -> Target:
	var b: Basis = Game.rail.view_basis()
	var e := _make("attacker", "attacker", 7.0, 8.5, 250)
	e.boom = 10.0
	e.marker = "attacker"
	e.st = "in"
	e.life = 40.0
	e.d = {"p0": start, "h": hover, "tin": 2.6, "hold": opts.get("hold", 7.0), "cd": randf_range(1.2, 2.0),
		"exit": Vector3(signf(hover.x) * 1.0 if hover.x != 0.0 else 1.0, 0.6, -0.4).normalized(), "shots": 0}
	e.d["glow"] = _glow_ball(e, 1.4, Color(1.0, 0.3, 0.15), Vector3(0, 2.0, -3.4))
	_anchor(e, start, Vector3.ZERO, b)
	e.setup_flash()
	return e


## ミサイル：発射位置（ワールド）から自艦へ向かう。撃ち落とせる
func missile(from_world: Vector3, opts := {}) -> Target:
	var e := _make("missile", "missile", 1.0, 5.5, 150)
	e.boom = 5.0
	e.marker = "missile"
	e.life = 26.0
	var rel: Vector3 = from_world - Game.rail.pos
	var up: Vector3 = opts.get("up", Vector3.UP)
	e.d = {"speed": 60.0, "vmax": opts.get("speed", 165.0), "ph": randf() * TAU, "wob": randf_range(20, 40), "dmg": opts.get("dmg", 5.0)}
	# 必ず一度カメラの前方を通ってから自艦へ向かう（画面外から不意打ちしない）
	var cam_l: Vector3 = Game.rail.cam_pos - Game.rail.pos
	var vb: Basis = Game.rail.view_basis()
	e.d["via"] = cam_l + vb * Vector3(randf_range(-160, 160), randf_range(-60, 110), -650.0)
	e.st = "via"
	_anchor(e, rel, up * 70.0 + (-rel.normalized()) * 30.0, Basis())
	# 噴射煙
	var tr := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.material = Game.fx.mat_fire
	tr.mesh = q
	tr.amount = 24
	tr.lifetime = 0.5
	tr.local_coords = false
	tr.spread = 10.0
	tr.direction = Vector3(0, 0, 1)
	tr.initial_velocity_min = 8.0
	tr.initial_velocity_max = 14.0
	tr.gravity = Vector3.ZERO
	tr.scale_amount_min = 1.6
	tr.scale_amount_max = 2.6
	tr.color_ramp = Game.fx._fire_ramp()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.5))
	c.add_point(Vector2(1, 1.6))
	tr.scale_amount_curve = c
	tr.position = Vector3(0, 0, 2.4)
	tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.add_child(tr)
	_glow_ball(e, 0.9, Color(1.0, 0.7, 0.4), Vector3(0, 0, 2.3))
	e.setup_flash()
	if Game.audio:
		Game.audio.play_at("missile_launch", from_world, 2.0, randf_range(0.9, 1.1), 200.0)
		if warn_cd <= 0.0:
			Game.audio.play("missile_warn", -6.0)
			warn_cd = 0.8
	return e


## カメラ基準の位置から発射されるミサイル
func missile_view(local_start: Vector3, opts := {}) -> Target:
	var w: Vector3 = Game.rail.pos + Game.rail.view_basis() * local_start
	return missile(w, opts)


## 機雷（空間に固定）。dangerous = 自艦の進路上。escort >= 0 = その護衛艦の進路上
func mine(world_pos: Vector3, dangerous: bool, escort := -1) -> Target:
	var e := _make("mine", "mine", 2.0, 6.0, 60)
	e.boom = 11.0
	e.dangerous = dangerous
	e.threat_escort = escort
	e.marker = "mine" if dangerous else ("mine_escort" if escort >= 0 else "")
	e.score = 120 if dangerous else 60
	e.life = 120.0
	e.global_position = world_pos
	e.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
	e.d = {"spin": Vector3(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6), 0), "blink": randf() * 2.0}
	e.d["lamp"] = _glow_ball(e, 1.3, Color(1.0, 0.45, 0.1))
	e.setup_flash()
	return e


## 大型目標の砲台（旋回する砲塔。自艦か友軍を撃つ）
func turret(parent: Node3D, pos: Vector3, up: Vector3, opts := {}) -> Target:
	var big: bool = opts.get("big", false)
	var e := _make("turret", "", opts.get("hp", 22.0), 16.0 if big else 9.0, opts.get("score", 500), parent)
	e.position = pos
	var fwdv := up.cross(Vector3.RIGHT) if absf(up.dot(Vector3.RIGHT)) < 0.9 else up.cross(Vector3.FORWARD)
	e.basis = Basis.looking_at(fwdv.normalized(), up.normalized())
	var base := MeshInstance3D.new()
	base.mesh = Models.get_mesh("mturret_base" if big else "turret_base")
	e.add_child(base)
	e.head = Node3D.new()
	e.add_child(e.head)
	var hm := MeshInstance3D.new()
	hm.mesh = Models.get_mesh("mturret_head" if big else "turret_head")
	e.head.add_child(hm)
	e.radius = 26.0 if big else 11.0
	e.hit_off = Vector3(0, 8.0 if big else 3.0, 0)
	e.boom = 26.0 if big else 14.0
	e.objective = opts.get("objective", true)
	e.label = opts.get("label", "砲台")
	e.group = opts.get("group", "")
	e.d = {"mode": opts.get("mode", "player"), "rate": opts.get("rate", 3.6), "cd": randf_range(1.0, 3.0),
		"range": opts.get("range", 1500.0), "big": big, "hit": opts.get("hit", TURRET_HIT), "dmg": opts.get("dmg", 3.0)}
	e.setup_flash()
	return e


## 大型目標の部位（ミサイル発射機・センサー・推進器・集束器 など）
func part(parent: Node3D, pos: Vector3, basis_v: Basis, mesh_key: String, opts := {}) -> Target:
	var e := _make("part", mesh_key, opts.get("hp", 40.0), opts.get("radius", 20.0), opts.get("score", 800), parent)
	e.position = pos
	e.basis = basis_v
	e.boom = opts.get("boom", 24.0)
	e.objective = opts.get("objective", true)
	e.label = opts.get("label", "")
	e.group = opts.get("group", "")
	e.d = opts.get("d", {})
	e.hit_off = opts.get("hit_off", Vector3.ZERO)
	e.setup_flash()
	return e


func add_armor(node: Node3D, aabb: AABB) -> void:
	armor.append({"node": node, "aabb": aabb})


func add_armor_sphere(node: Node3D, r: float) -> void:
	armor.append({"node": node, "r": r})


func group_alive(g: String) -> int:
	var n := 0
	for e in targets:
		if (e as Target).group == g and (e as Target).alive:
			n += 1
	return n


# ------------------------------------------------------------------ 当たり判定
func raycast(o: Vector3, d: Vector3, maxd: float) -> Dictionary:
	var best := maxd
	var res := {}
	for x in targets:
		var e: Target = x
		if not e.alive or not e.targetable or not e.is_visible_in_tree():
			continue
		var c := e.hit_center()
		var r := e.radius
		if e.kind == "missile" or e.kind == "fighter":
			r *= 1.3
		var oc := c - o
		var tca := oc.dot(d)
		if tca < 0.0:
			continue
		var d2 := oc.length_squared() - tca * tca
		if d2 > r * r:
			continue
		var t0 := tca - sqrt(r * r - d2)
		if t0 < 0.0:
			t0 = tca
		if t0 < best:
			best = t0
			res = {"t": t0, "point": o + d * t0, "target": e, "armor": null, "normal": -d}
	for a in armor:
		var node: Node3D = a["node"]
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		if a.has("r"):
			var r2: float = a["r"]
			var oc2 := node.global_position - o
			var tca2 := oc2.dot(d)
			var dd := oc2.length_squared() - tca2 * tca2
			if tca2 < 0.0 or dd > r2 * r2:
				continue
			var t1 := tca2 - sqrt(r2 * r2 - dd)
			if t1 > 0.0 and t1 < best:
				best = t1
				var p := o + d * t1
				res = {"t": t1, "point": p, "target": null, "armor": node, "normal": (p - node.global_position).normalized()}
		else:
			var inv := node.global_transform.affine_inverse()
			var lo := inv * o
			var ldir := inv.basis * d
			var box: AABB = a["aabb"]
			var hp = box.intersects_ray(lo, ldir)
			if hp == null:
				continue
			var wp: Vector3 = node.global_transform * (hp as Vector3)
			var t2 := (wp - o).length()
			if t2 < best:
				best = t2
				res = {"t": t2, "point": wp, "target": null, "armor": node, "normal": -d}
	return res


## 自弾の命中を予約する（弾が届いた時に効く）
func shoot(hit: Dictionary, dmg: float, travel: float, heavy: bool) -> void:
	var tg = hit["target"]
	var info := {"dmg": dmg, "heavy": heavy, "normal": hit["normal"]}
	if tg != null:
		var e: Target = tg
		info["target"] = e
		info["local"] = e.to_local(hit["point"])
	else:
		var an: Node3D = hit["armor"]
		info["armor"] = an
		info["local"] = an.to_local(hit["point"])
	Game.fx.later(travel, _land.bind(info))


func _land(info: Dictionary) -> void:
	var heavy: bool = info["heavy"]
	if info.has("target"):
		if not is_instance_valid(info["target"]):
			return
		var e: Target = info["target"]
		var p := e.to_global(info["local"])
		if not e.alive:
			Game.fx.impact(p, info["normal"], Color(0.6, 0.9, 1.0), heavy)
			return
		Game.stats["hits"] += 1
		Game.fx.impact(p, info["normal"], Color(1.0, 0.7, 0.4), heavy)
		if e.kind == "turret" or e.kind == "part":
			Game.audio.play_at("armor", p, -4.0, randf_range(0.9, 1.15), 80.0)
		else:
			Game.audio.play_at("hit", p, -2.0, randf_range(0.9, 1.2), 60.0)
		damage(e, info["dmg"], p)
		if heavy:
			_splash(p, 45.0, 5.0, e)
	elif info.has("armor"):
		if not is_instance_valid(info["armor"]):
			return
		var an: Node3D = info["armor"]
		var p2 := an.to_global(info["local"])
		Game.fx.impact(p2, info["normal"], Color(1.0, 0.75, 0.45), heavy)
		Game.audio.play_at("armor", p2, -10.0, randf_range(0.8, 1.2), 60.0)
		if heavy:
			_splash(p2, 45.0, 5.0, null)


func _splash(p: Vector3, r: float, dmg: float, skip: Target) -> void:
	for x in targets.duplicate():
		var e: Target = x
		if e == skip or not e.alive or not e.targetable:
			continue
		if e.global_position.distance_to(p) < r + e.radius:
			damage(e, dmg, e.global_position)


func damage(e: Target, amount: float, p: Vector3) -> void:
	if e.hit(amount):
		kill(e, true)
	else:
		_damage_stage(e)


## 大型目標は被弾が進むと火花、さらに進むと火を噴く
func _damage_stage(e: Target) -> void:
	if e.kind != "turret" and e.kind != "part":
		return
	var r := e.hp_ratio()
	if e.stage == 0 and r < 0.66:
		e.stage = 1
		Game.fx.attach_sparks(e, Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)) * e.radius * 0.4, e.radius * 0.35)
	if e.stage == 1 and r < 0.33:
		e.stage = 2
		Game.fx.attach_fire(e, Vector3(randf_range(-1, 1), 0.8, randf_range(-1, 1)) * e.radius * 0.35, e.radius * 0.35)
		Game.fx.explosion(e.hit_center(), e.radius * 0.35, true, false)


func kill(e: Target, by_player: bool) -> void:
	e.alive = false
	targets.erase(e)
	var p := e.hit_center()
	match e.kind:
		"turret", "part":
			Game.fx.big_explosion(p, e.boom, e.radius * 0.8, 4, 0.8)
			Game.rail.shake(clampf(600.0 / maxf(p.distance_to(Game.rail.cam_pos), 1.0), 0.05, 0.6))
			if e.head:
				e.head.visible = false
			if e.kind == "part" and not e.d.get("keep", false):
				for c in e.get_children():
					if c is MeshInstance3D:
						(c as MeshInstance3D).visible = false
			Game.fx.attach_fire(e, Vector3(0, e.radius * 0.2, 0), e.radius * 0.45)
			if by_player:
				Game.stats["parts"] += 1
				Game.stats["kills"] += 1
		"mine":
			Game.fx.explosion(p, e.boom)
			Game.fx.ring(p, 90.0, Color(1.0, 0.6, 0.3), 0.6)
			if by_player:
				Game.stats["mines"] += 1
			# 誘爆
			for x in targets.duplicate():
				var m: Target = x
				if m.kind == "mine" and m.alive and m.global_position.distance_to(e.global_position) < 70.0:
					Game.fx.later(0.15 + randf() * 0.1, _chain.bind(m))
			e.queue_free()
		"missile":
			Game.fx.explosion(p, e.boom)
			Game.fx.ring(p, 30.0, Color(1.0, 0.8, 0.5), 0.35)
			if by_player:
				Game.stats["missiles"] += 1
			e.queue_free()
		_:
			Game.fx.explosion(p, e.boom)
			if by_player:
				Game.stats["kills"] += 1
			e.queue_free()
	if by_player:
		Game.add_score(e.score, p)
	if e.on_destroy.is_valid():
		e.on_destroy.call(e)


func _chain(m) -> void:
	if is_instance_valid(m) and m.alive:
		m.alive = false
		kill(m, true)


func clear_bolts() -> void:
	for b in bolts:
		_free_bolt(b)
	bolts.clear()


func clear_kind(kinds: Array) -> void:
	for x in targets.duplicate():
		var e: Target = x
		if e.kind in kinds:
			targets.erase(e)
			e.queue_free()


# ------------------------------------------------------------------ 敵弾
## 自艦へ向かう敵弾。hit なら自艦に当たる、外れなら近くをかすめて飛び去る
func enemy_bolt(from_world: Vector3, hit: bool, dmg: float, speed := 420.0, src := "bolt", col := Color(1.0, 0.35, 0.25)) -> void:
	var mi: MeshInstance3D
	if bolt_free.is_empty():
		var old: Dictionary = bolts.pop_front()
		mi = old["mi"]
	else:
		mi = bolt_free.pop_back()
	(mi.material_override as ShaderMaterial).set_shader_parameter("color", col)
	mi.visible = true
	var rel: Vector3 = from_world - Game.rail.pos
	var cam_l: Vector3 = Game.rail.cam_pos - Game.rail.pos
	var miss := Vector3.ZERO
	if not hit:
		miss = Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized() * randf_range(14, 40)
	else:
		miss = Vector3(randf_range(-1, 1), randf_range(-1.5, 0), randf_range(-1, 1)) * 2.0
	var v: Vector3 = (cam_l + miss - rel).normalized() * speed
	bolts.append({"mi": mi, "p": rel, "v": v, "hit": hit, "dmg": dmg, "aim": miss, "t": 0.0, "done": false, "src": src})
	Game.fx.flash(from_world, 12.0, col, 0.12)
	Game.audio.play_at("enemy_shot", from_world, 0.0, randf_range(0.9, 1.1), 90.0)


func _tick_bolts(dt: float) -> void:
	var cam_l: Vector3 = Game.rail.cam_pos - Game.rail.pos
	var i := 0
	while i < bolts.size():
		var b: Dictionary = bolts[i]
		b["t"] += dt
		var p: Vector3 = b["p"]
		var v: Vector3 = b["v"]
		if not b["done"]:
			var tgt: Vector3 = cam_l + b["aim"]
			var to := tgt - p
			if to.length() < v.length() * dt * 1.2 or to.dot(v) < 0.0:
				b["done"] = true
				if b["hit"]:
					Game.main.damage_player(b["dmg"], Game.rail.pos + tgt, b["src"])
					_free_bolt(b)
					bolts.remove_at(i)
					continue
			else:
				v = to.normalized() * v.length()
				b["v"] = v
		p += v * dt
		b["p"] = p
		if b["t"] > 6.0:
			_free_bolt(b)
			bolts.remove_at(i)
			continue
		var w: Vector3 = Game.rail.pos + p
		Game.fx._place_beam(b["mi"], w - v.normalized() * 14.0, w, 0.9)
		i += 1


func _free_bolt(b: Dictionary) -> void:
	(b["mi"] as MeshInstance3D).visible = false
	bolt_free.append(b["mi"])


# ------------------------------------------------------------------ 行動
func tick(dt: float) -> void:
	flyby_cd -= dt
	warn_cd -= dt
	var rail = Game.rail
	var cam_pos: Vector3 = rail.cam_pos
	var cam_l: Vector3 = cam_pos - rail.pos
	for x in targets.duplicate():
		var e: Target = x
		if not is_instance_valid(e) or not e.alive:
			continue
		e.age += dt
		e.tick_flash(dt)
		# まだ現れていない（または去った）大型目標の砲台・部位は動かさない
		if not e.anchored and (e.kind == "turret" or e.kind == "part") and not e.is_visible_in_tree():
			continue
		match e.kind:
			"fighter": _fighter(e, dt, cam_pos)
			"attacker": _attacker(e, dt, cam_l)
			"missile": _missile(e, dt, cam_l)
			"mine": _mine(e, dt)
			"turret": _turret(e, dt, cam_pos)
			"part": _part(e, dt)
		if e.anchored and e.alive:
			e.global_position = rail.pos + e.frame * e.local
		if e.alive and e.age > e.life:
			targets.erase(e)
			e.queue_free()
	_tick_bolts(dt)


func _fighter(e: Target, dt: float, cam_pos: Vector3) -> void:
	var dd := e.d
	var w := Vector3(0, cos(e.age * dd["f"] + dd["ph"]) * dd["amp"], 0) * 0.6
	var v: Vector3 = e.lvel + w
	e.local += v * dt
	var wv := e.frame * v
	if wv.length() > 1.0:
		e.global_position = Game.rail.pos + e.frame * e.local
		e.look_at(e.global_position + wv, Vector3.UP)
		e.rotate_object_local(Vector3.BACK, sin(e.age * dd["f"] + dd["ph"]) * 0.6)
	var dist := e.global_position.distance_to(cam_pos)
	if not dd["flyby"] and dist < 110.0 and flyby_cd <= 0.0:
		dd["flyby"] = true
		flyby_cd = 0.4
		Game.audio.play_at("flyby", e.global_position, 4.0, randf_range(0.85, 1.15), 60.0)
	if float(dd["fire"]) > 0.0 and e.local.z < -120.0:
		dd["cd"] -= dt
		if dd["cd"] <= 0.0:
			dd["cd"] = randf_range(1.5, 3.0)
			if randf() < float(dd["fire"]) * 4.0:
				enemy_bolt(e.global_position, randf() < FIGHTER_HIT, 2.0, 380.0, "fighter")
	if absf(e.local.x) > 2200.0 or e.local.z > 250.0 or e.local.z < -4000.0 or absf(e.local.y) > 1500.0:
		targets.erase(e)
		e.queue_free()


func _attacker(e: Target, dt: float, cam_l: Vector3) -> void:
	var dd := e.d
	var glow: MeshInstance3D = dd["glow"]
	match e.st:
		"in":
			var k := clampf(e.age / float(dd["tin"]), 0.0, 1.0)
			var s := k * k * (3.0 - 2.0 * k)
			e.local = (dd["p0"] as Vector3).lerp(dd["h"], s)
			if k >= 1.0:
				e.st = "hold"
				dd["t0"] = e.age
		"hold":
			var h: Vector3 = dd["h"]
			var tt := e.age - float(dd["t0"])
			e.local = h + Vector3(sin(tt * 0.9) * 26.0, sin(tt * 1.3) * 12.0, sin(tt * 0.7) * 18.0)
			dd["cd"] -= dt
			if dd["cd"] < 0.8:
				e.charge = clampf(1.0 - dd["cd"] / 0.8, 0.0, 1.0)
			if dd["cd"] <= 0.0:
				dd["cd"] = randf_range(1.7, 2.4)
				e.charge = 0.0
				for i in ATTACKER_BURST:
					Game.fx.later(i * 0.13, _attacker_shot.bind(e))
			if tt > float(dd["hold"]):
				e.st = "out"
				e.charge = 0.0
		"out":
			e.lvel += (dd["exit"] as Vector3) * 260.0 * dt
			e.local += e.lvel * dt
			if e.lvel.length() > 400.0:
				targets.erase(e)
				e.queue_free()
				return
	glow.scale = Vector3.ONE * (0.6 + e.charge * 2.2)
	e.global_position = Game.rail.pos + e.frame * e.local
	var cam_w: Vector3 = Game.rail.cam_pos
	if e.st == "out":
		var dv: Vector3 = e.frame * (e.lvel if e.lvel.length() > 1.0 else (dd["exit"] as Vector3))
		e.look_at(e.global_position + dv, Vector3.UP if absf(dv.normalized().y) < 0.95 else Vector3.BACK)
	elif e.global_position.distance_to(cam_w) > 1.0:
		var to_cam: Vector3 = (cam_w - e.global_position).normalized()
		e.look_at(cam_w, Vector3.UP if absf(to_cam.y) < 0.95 else Vector3.BACK)


func _attacker_shot(e) -> void:
	if is_instance_valid(e) and e.alive:
		enemy_bolt(e.global_position + (Game.rail.cam_pos - e.global_position).normalized() * 8.0, randf() < ATTACKER_HIT, 3.0, 440.0, "attacker")


func _missile(e: Target, dt: float, cam_l: Vector3) -> void:
	var dd := e.d
	dd["speed"] = minf(float(dd["vmax"]), float(dd["speed"]) + 70.0 * dt)
	var tgt := cam_l + Vector3(0, -2.5, 0)
	if e.st == "via":
		tgt = dd["via"]
		if e.local.distance_to(tgt) < 90.0 or e.age > 12.0:
			e.st = "home"
	var to := tgt - e.local
	var dist := to.length()
	var desired := to.normalized() * float(dd["speed"])
	# 遠いうちは少し蛇行する
	var side := to.cross(Vector3.UP).normalized()
	desired += side * sin(e.age * 2.3 + dd["ph"]) * float(dd["wob"]) * clampf(dist / 600.0, 0.0, 1.0)
	e.lvel = e.lvel.lerp(desired, clampf(dt * 1.8, 0.0, 1.0))
	e.local += e.lvel * dt
	e.global_position = Game.rail.pos + e.local
	if e.lvel.length() > 1.0:
		e.look_at(e.global_position + e.lvel, Vector3.UP)
	if e.st == "home" and dist < 9.0:
		# 着弾
		e.alive = false
		targets.erase(e)
		Game.fx.explosion(e.global_position, 7.0)
		Game.main.damage_player(dd["dmg"], e.global_position, "missile")
		e.queue_free()


func _mine(e: Target, dt: float) -> void:
	var dd := e.d
	e.rotate_x((dd["spin"] as Vector3).x * dt)
	e.rotate_y((dd["spin"] as Vector3).y * dt)
	dd["blink"] += dt * (3.2 if e.dangerous else 1.4)
	(dd["lamp"] as MeshInstance3D).visible = fmod(dd["blink"], 1.0) < 0.5
	var ship: Vector3 = Game.rail.pos
	var dist := e.global_position.distance_to(ship)
	if dist < 26.0:
		e.alive = false
		targets.erase(e)
		Game.fx.explosion(e.global_position, 12.0)
		Game.main.damage_player(8.0, e.global_position, "mine")
		e.queue_free()
		return
	if Game.allies and Game.allies.mine_check(e):
		e.alive = false
		targets.erase(e)
		e.queue_free()
		return
	if dist < 300.0:
		if not dd.has("beeped") and e.dangerous:
			dd["beeped"] = true
			Game.audio.play_at("mine_beep", e.global_position, 0.0, 1.0, 80.0)
	if (e.global_position - ship).dot(Game.rail.fwd) < -400.0:
		targets.erase(e)
		e.queue_free()


func _turret(e: Target, dt: float, cam_pos: Vector3) -> void:
	var dd := e.d
	if e.head == null:
		return
	var mode: String = dd["mode"]
	var aim := cam_pos
	if mode == "allies":
		if not dd.has("aim") or randf() < dt * 0.1:
			dd["aim"] = Game.allies.random_ally_point(e.global_position)
		aim = dd["aim"]
	# 砲塔は台座の上面の平面内で旋回し、砲身を上下させる
	var lp := e.to_local(aim)
	var yaw := atan2(-lp.x, -lp.z)
	e.head.rotation = Vector3(0, lerp_angle(e.head.rotation.y, yaw, clampf(dt * 2.5, 0.0, 1.0)), 0)
	var dist := e.global_position.distance_to(aim)
	if lp.y < -e.radius:
		return
	if mode == "player" and dist > float(dd["range"]):
		return
	# 友軍を撃つ大型砲も、自艦の近くにいる間だけ動かす
	if mode == "allies" and e.global_position.distance_to(cam_pos) > 2600.0:
		return
	dd["cd"] -= dt
	if dd["cd"] <= 0.0:
		dd["cd"] = float(dd["rate"]) * randf_range(0.7, 1.05)
		var mz: Vector3 = e.head.global_transform * Vector3(0, 3.2 * (2.8 if dd["big"] else 1.0), -19.0 * (2.8 if dd["big"] else 1.0))
		if mode == "player":
			enemy_bolt(mz, randf() < float(dd["hit"]), float(dd["dmg"]), 520.0, "turret")
		else:
			Game.mission.big_gun_fire(e, mz, aim)


func _part(e: Target, dt: float) -> void:
	var dd := e.d
	if dd.has("launch"):
		var L: Dictionary = dd["launch"]
		if Game.rail.cam_pos.distance_to(e.global_position) < float(L.get("range", 2600.0)):
			L["cd"] = float(L.get("cd", 3.0)) - dt
			if L["cd"] <= 0.0:
				L["cd"] = float(L["rate"])
				var n: int = L.get("n", 2)
				for i in n:
					Game.fx.later(i * 0.35, _launch.bind(e))


func _launch(e) -> void:
	if is_instance_valid(e) and e.alive:
		var up: Vector3 = e.global_basis.y.normalized()
		missile(e.hit_center() + up * e.radius, {"up": up})
