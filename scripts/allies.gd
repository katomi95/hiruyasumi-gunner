extends Node3D
## AllyManager：自艦隊の護衛艦・周囲の艦（近景）・遠くの艦隊（遠景、MultiMesh）・艦隊どうしの撃ち合い・友軍戦闘機。
## プレイヤーが撃っていない所でも戦争が進んでいるように見せる。遠景はすべて簡易演出

const ESCORT_NAMES := ["アオバト", "シラサギ", "カワセミ", "ツバメ"]

var fleets := {}          # 名前 -> {mmi, locals, alive, fac, vel, t0, t1, far, scale}
var battles: Array = []   # {a, b, t0, t1, rate, acc, boom_t, cannon_t}
var ships: Array = []     # 近景の艦 {node, fac, vel, t0, t1, cd, alive, rate}
var escorts: Array = []   # {node, alive, cd, i}
var formation: Array = [] # [t, [offset×4]]
var wings: Array = []     # 友軍戦闘機 {node, local, v, frame, t, life, cd}
var escort_count := 4


func _ready() -> void:
	Game.allies = self


# ------------------------------------------------------------------ 遠景の艦隊
func add_fleet(fname: String, fac: String, center: Vector3, count: int, spread: Vector3, heading: Vector3, vel: Vector3,
		t0: float, t1: float, size := 1.0) -> void:
	var near_key := "ally_far" if fac == "A" else "enemy_far"
	var small_key := "ally_frigate_far" if fac == "A" else "enemy_frigate_far"
	var root := Node3D.new()
	add_child(root)
	root.global_position = center
	var groups: Array = []
	var locals: Array = []
	var alive: Array = []
	var inst: Array = []
	for g in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = Models.get_mesh(near_key if g == 0 else small_key)
		var n := count / 3 if g == 0 else count - count / 3
		mm.instance_count = n
		for i in n:
			var p := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread
			var h := heading.rotated(Vector3.UP, randf_range(-0.12, 0.12))
			var s := size * randf_range(0.8, 1.4) * (1.6 if g == 0 else 1.0)
			mm.set_instance_transform(i, Transform3D(Basis.looking_at(h, Vector3.UP).scaled(Vector3(s, s, s)), p))
			locals.append(p)
			alive.append(true)
			inst.append([g, i, s, h])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		groups.append(mm)
	fleets[fname] = {"root": root, "mms": groups, "locals": locals, "alive": alive, "inst": inst, "fac": fac,
		"vel": vel, "t0": t0, "t1": t1, "lost": 0}


func fleet_point(fname: String, i: int) -> Vector3:
	var f: Dictionary = fleets[fname]
	return (f["root"] as Node3D).global_transform * (f["locals"][i] as Vector3)


func random_alive(fname: String) -> int:
	var f: Dictionary = fleets[fname]
	var n: int = f["alive"].size()
	for _k in 12:
		var i := randi() % n
		if f["alive"][i]:
			return i
	return -1


## 遠景の艦を一隻沈める
func explode_instance(fname: String, i: int, big := false) -> void:
	var f: Dictionary = fleets[fname]
	if i < 0 or not f["alive"][i]:
		return
	f["alive"][i] = false
	f["lost"] += 1
	var info: Array = f["inst"][i]
	var mm: MultiMesh = f["mms"][info[0]]
	var p := fleet_point(fname, i)
	var s: float = info[2]
	Game.fx.explosion(p, 22.0 * s * (1.6 if big else 1.0), true, true)
	Game.fx.flash(p, 260.0 * s, Color(1.0, 0.75, 0.5), 0.5)
	Game.fx.ring(p, 300.0 * s, Color(1.0, 0.6, 0.35), 1.2)
	mm.set_instance_transform(info[1], Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), f["locals"][i]))


func add_battle(a: String, b: String, t0: float, t1: float, rate := 3.0, boom_every := 5.0) -> void:
	battles.append({"a": a, "b": b, "t0": t0, "t1": t1, "rate": rate, "acc": 0.0, "boom": boom_every,
		"boom_t": randf() * boom_every, "cannon_t": randf() * 3.0})


# ------------------------------------------------------------------ 近景の艦
func add_ship(fac: String, mesh_key: String, pos: Vector3, heading: Vector3, vel: Vector3, t0: float, t1: float,
		scale_v := 1.0, rate := 0.6) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var mi := MeshInstance3D.new()
	mi.mesh = Models.get_mesh(mesh_key)
	mi.scale = Vector3.ONE * scale_v
	n.add_child(mi)
	n.global_position = pos
	n.global_basis = Basis.looking_at(heading, Vector3.UP)
	n.visible = false
	ships.append({"node": n, "fac": fac, "vel": vel, "t0": t0, "t1": t1, "cd": randf() * 3.0, "alive": true,
		"rate": rate, "scale": scale_v})
	return n


func sink_ship(s: Dictionary) -> void:
	if not s["alive"]:
		return
	s["alive"] = false
	var n: Node3D = s["node"]
	var sc: float = s["scale"]
	Game.fx.big_explosion(n.global_position, 30.0 * sc, 50.0 * sc, 6, 1.6)
	Game.fx.later(1.6, func(): n.visible = false)


# ------------------------------------------------------------------ 護衛艦（自艦隊）
func setup_escorts(form_keys: Array) -> void:
	formation = form_keys
	for i in escort_count:
		var n := Node3D.new()
		add_child(n)
		var mi := MeshInstance3D.new()
		mi.mesh = Models.get_mesh("ally_cruiser")
		mi.scale = Vector3.ONE * 1.25
		n.add_child(mi)
		escorts.append({"node": n, "alive": true, "cd": randf_range(0.5, 2.0), "i": i, "burn": false})


func escort_offset(i: int, t: float) -> Vector3:
	var n := formation.size()
	var k := 0
	while k < n - 1 and t >= float(formation[k + 1][0]):
		k += 1
	var a: Vector3 = formation[k][1][i]
	if k < n - 1:
		var t1: float = formation[k + 1][0]
		var w := smoothstep(t1 - 7.0, t1, t)
		var b: Vector3 = formation[k + 1][1][i]
		return a.lerp(b, w)
	return a


func escort_pos(i: int, t: float) -> Vector3:
	var off := escort_offset(i, t)
	var bob := Vector3(sin(t * 0.3 + i) * 6.0, sin(t * 0.41 + i * 2.0) * 5.0, 0)
	return Game.rail.pos_at(t) + Game.rail.frame_at(t) * (off + bob)


func escort_alive(i: int) -> bool:
	return escorts[i]["alive"]


func lose_escort(i: int, reason := "") -> void:
	var e: Dictionary = escorts[i]
	if not e["alive"]:
		return
	e["alive"] = false
	var n: Node3D = e["node"]
	Game.fx.big_explosion(n.global_position, 34.0, 60.0, 8, 2.0)
	Game.fx.later(2.0, func(): n.visible = false)
	Game.stats["allies_lost"] += 1
	Game.hud.radio("艦隊通信", "護衛艦%s、轟沈……%s" % [ESCORT_NAMES[i], reason], "escort_%d" % i)


func damage_escort(i: int) -> void:
	var e: Dictionary = escorts[i]
	if not e["alive"] or e["burn"]:
		return
	e["burn"] = true
	var n: Node3D = e["node"]
	Game.fx.explosion(n.global_position + Vector3(0, 10, 0), 16.0)
	Game.fx.attach_fire(n, Vector3(6, 8, 10), 7.0)
	Game.fx.attach_sparks(n, Vector3(-5, 4, -20), 4.0)


## 機雷が護衛艦に触れたら護衛艦が沈む
func mine_check(m: Target) -> bool:
	if m.threat_escort < 0:
		return false
	var e: Dictionary = escorts[m.threat_escort]
	if not e["alive"]:
		return false
	if (e["node"] as Node3D).global_position.distance_to(m.global_position) < 55.0:
		Game.fx.explosion(m.global_position, 16.0)
		lose_escort(m.threat_escort, "機雷に触雷")
		return true
	return false


## 敵の大型砲が狙う味方の位置
func random_ally_point(_from: Vector3) -> Vector3:
	var cands: Array = []
	for fname in fleets:
		var f: Dictionary = fleets[fname]
		if f["fac"] == "A" and (f["root"] as Node3D).visible:
			cands.append(fname)
	if cands.is_empty():
		return Game.rail.pos + Vector3(-2000, 0, 0)
	var fname2: String = cands[randi() % cands.size()]
	var i := random_alive(fname2)
	if i < 0:
		return (fleets[fname2]["root"] as Node3D).global_position
	return fleet_point(fname2, i)


## 筋書きどおりの味方の損害（指定の艦隊から n 隻）
func lose(fname: String, n: int, spread_t := 2.0) -> void:
	var real := mini(n, Game.allies_left())
	Game.stats["allies_lost"] += real
	for k in real:
		var i := random_alive(fname)
		if i >= 0:
			Game.fx.later(randf() * spread_t, explode_instance.bind(fname, i, true))


## 自艦隊も一緒に跳躍する。突入時・離脱時に各艦の位置で閃光
func jump_fx(entering: bool) -> void:
	for e in escorts:
		if not e["alive"]:
			continue
		var p: Vector3 = (e["node"] as Node3D).global_position
		var d := randf_range(0.0, 0.5)
		if entering:
			Game.fx.later(3.2 + d, Game.fx.flash.bind(p, 160.0, Color(0.7, 0.85, 1.0), 0.4))
		else:
			Game.fx.later(d, Game.fx.flash.bind(p, 180.0, Color(0.7, 0.85, 1.0), 0.45))
			Game.fx.later(d, Game.fx.ring.bind(p, 260.0, Color(0.6, 0.8, 1.0), 0.7))


# ------------------------------------------------------------------ 友軍戦闘機
func wing(n: int, start: Vector3, vel: Vector3) -> void:
	var b: Basis = Game.rail.view_basis()
	var dirv := vel.normalized()
	var side := dirv.cross(Vector3.UP)
	if side.length() < 0.1:
		side = Vector3.RIGHT
	side = side.normalized()
	for i in n:
		var k := (i + 1) / 2 * (1 if i % 2 == 1 else -1)
		var node := Node3D.new()
		add_child(node)
		var mi := MeshInstance3D.new()
		mi.mesh = Models.get_mesh("ally_fighter")
		mi.scale = Vector3.ONE * 1.2
		node.add_child(mi)
		var local := start + side * k * 14.0 - dirv * absf(k) * 12.0
		wings.append({"node": node, "local": local, "v": vel, "frame": b, "t": 0.0, "life": 14.0, "cd": randf_range(0.3, 1.2), "ph": randf() * TAU})


# ------------------------------------------------------------------ 毎フレーム
func tick(dt: float) -> void:
	var t: float = Game.t
	var cam: Vector3 = Game.rail.cam_pos
	for fname in fleets:
		var f: Dictionary = fleets[fname]
		var root: Node3D = f["root"]
		root.visible = t >= float(f["t0"]) and t <= float(f["t1"])
		if root.visible:
			root.global_position += (f["vel"] as Vector3) * dt
	for b in battles:
		if t < float(b["t0"]) or t > float(b["t1"]):
			continue
		b["acc"] += float(b["rate"]) * dt
		while b["acc"] >= 1.0:
			b["acc"] -= 1.0
			_exchange(b, cam)
		b["boom_t"] -= dt
		if b["boom_t"] <= 0.0:
			b["boom_t"] = float(b["boom"]) * randf_range(0.6, 1.4)
			var side: String = b["a"] if randf() < 0.5 else b["b"]
			var f2: Dictionary = fleets[side]
			if int(f2["lost"]) < int(f2["alive"].size() * 0.35):
				explode_instance(side, random_alive(side))
		b["cannon_t"] -= dt
		if b["cannon_t"] <= 0.0:
			b["cannon_t"] = randf_range(1.5, 4.0)
			_cannon(b, cam)
	for s in ships:
		var n: Node3D = s["node"]
		var vis: bool = t >= float(s["t0"]) and t <= float(s["t1"])
		if not s["alive"]:
			continue
		n.visible = vis
		if not vis:
			continue
		n.global_position += (s["vel"] as Vector3) * dt
		s["cd"] -= dt
		if s["cd"] <= 0.0:
			s["cd"] = randf_range(0.6, 1.6) / float(s["rate"])
			_ship_fire(s)
	_tick_escorts(dt, t)
	_tick_wings(dt)


func _exchange(b: Dictionary, cam: Vector3) -> void:
	var from_a := randf() < 0.5
	var sf: String = b["a"] if from_a else b["b"]
	var tf: String = b["b"] if from_a else b["a"]
	var i := random_alive(sf)
	var j := random_alive(tf)
	if i < 0 or j < 0:
		return
	var p0 := fleet_point(sf, i)
	var p1 := fleet_point(tf, j) + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 40.0
	var dist := cam.distance_to((p0 + p1) * 0.5)
	var w := clampf(dist * 0.0025, 1.5, 14.0)
	var col := Game.COL_ALLY if fleets[sf]["fac"] == "A" else Game.COL_ENEMY
	Game.fx.beam(p0, p1, col, w, randf_range(0.25, 0.6), 2.2)
	if randf() < 0.35:
		Game.fx.flash(p1, w * 10.0, Color(1.0, 0.8, 0.6), 0.3)


func _cannon(b: Dictionary, cam: Vector3) -> void:
	var from_a := randf() < 0.5
	var sf: String = b["a"] if from_a else b["b"]
	var tf: String = b["b"] if from_a else b["a"]
	var i := random_alive(sf)
	var j := random_alive(tf)
	if i < 0 or j < 0:
		return
	var p0 := fleet_point(sf, i)
	var p1 := fleet_point(tf, j)
	var dist := cam.distance_to(p0)
	var w := clampf(dist * 0.005, 4.0, 30.0)
	var col := Color(0.6, 1.0, 0.8) if fleets[sf]["fac"] == "A" else Color(1.0, 0.55, 0.3)
	var travel := p0.distance_to(p1) / 2200.0
	Game.fx.bolt(p0, p1, col, w, travel, 300.0, 3.0)
	Game.fx.flash(p0, w * 14.0, col, 0.35)
	Game.fx.later(travel, Game.fx.flash.bind(p1, w * 22.0, Color(1.0, 0.75, 0.5), 0.6))
	if dist < 3500.0:
		Game.audio.play_at("cannon", p0, -6.0, randf_range(0.8, 1.0), 300.0)


func _ship_fire(s: Dictionary) -> void:
	var n: Node3D = s["node"]
	var fac: String = s["fac"]
	var p0 := n.global_position + Vector3(0, 8, 0) * float(s["scale"])
	var p1: Vector3
	var cands: Array = []
	for o in ships:
		if o["alive"] and o["fac"] != fac and (o["node"] as Node3D).visible:
			cands.append(o)
	if not cands.is_empty() and randf() < 0.7:
		var o2: Dictionary = cands[randi() % cands.size()]
		p1 = (o2["node"] as Node3D).global_position + Vector3(randf_range(-30, 30), randf_range(-15, 15), randf_range(-60, 60))
	else:
		var fl := ""
		for fname in fleets:
			if fleets[fname]["fac"] != fac and (fleets[fname]["root"] as Node3D).visible:
				fl = fname
				break
		if fl == "":
			return
		var j := random_alive(fl)
		if j < 0:
			return
		p1 = fleet_point(fl, j)
	var col := Game.COL_ALLY if fac == "A" else Game.COL_ENEMY
	var dist: float = Game.rail.cam_pos.distance_to(p0)
	Game.fx.beam(p0, p1, col, clampf(dist * 0.002, 1.2, 8.0), 0.35, 2.4)
	Game.fx.flash(p1, 30.0, Color(1.0, 0.8, 0.6), 0.25)


func _tick_escorts(dt: float, t: float) -> void:
	for e in escorts:
		var n: Node3D = e["node"]
		if not e["alive"]:
			continue
		var i: int = e["i"]
		n.global_position = escort_pos(i, t)
		var f: Vector3 = Game.rail.fwd_at(t)
		n.global_basis = Basis.looking_at(f, Vector3.UP) * Basis(Vector3.BACK, sin(t * 0.2 + i) * 0.05)
		if Game.state != "play":
			continue
		e["cd"] -= dt
		if e["cd"] <= 0.0:
			e["cd"] = randf_range(0.9, 2.2)
			_escort_fire(n)


func _escort_fire(n: Node3D) -> void:
	var p0 := n.global_position + n.global_basis * Vector3(0, 8, -20)
	var best: Target = null
	var bd := 1400.0
	for x in Game.enemies.targets:
		var e: Target = x
		if not e.alive or not (e.kind in ["fighter", "attacker", "turret"]):
			continue
		var dd := e.global_position.distance_to(p0)
		if dd < bd:
			bd = dd
			best = e
	if best != null:
		var p1 := best.global_position + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 12.0
		Game.fx.bolt(p0, p1, Color(0.55, 0.9, 1.0), 1.2, p0.distance_to(p1) / 1800.0, 50.0, 3.0)
		# 護衛艦もときどき敵機を落とす（得点にはならない）
		if best.kind == "fighter" and randf() < 0.12:
			Game.fx.later(p0.distance_to(p1) / 1800.0, _escort_kill.bind(best))
		return
	for fname in fleets:
		var f: Dictionary = fleets[fname]
		if f["fac"] == "E" and (f["root"] as Node3D).visible:
			var j := random_alive(fname)
			if j >= 0:
				var p2 := fleet_point(fname, j)
				Game.fx.beam(p0, p2, Color(0.55, 0.9, 1.0), 2.0, 0.4, 2.2)
			return


func _escort_kill(e) -> void:
	if is_instance_valid(e) and e.alive:
		Game.enemies.kill(e, false)


func _tick_wings(dt: float) -> void:
	var i := 0
	while i < wings.size():
		var w: Dictionary = wings[i]
		w["t"] += dt
		var node: Node3D = w["node"]
		if w["t"] > w["life"]:
			node.queue_free()
			wings.remove_at(i)
			continue
		var v: Vector3 = w["v"] + Vector3(0, cos(w["t"] * 1.3 + w["ph"]) * 10.0, 0)
		w["local"] += v * dt
		var fr: Basis = w["frame"]
		node.global_position = Game.rail.pos + fr * (w["local"] as Vector3)
		node.look_at(node.global_position + fr * v, Vector3.UP)
		w["cd"] -= dt
		if w["cd"] <= 0.0:
			w["cd"] = randf_range(0.5, 1.2)
			for x in Game.enemies.targets:
				var e: Target = x
				if e.alive and e.kind == "fighter" and e.global_position.distance_to(node.global_position) < 500.0:
					var p0 := node.global_position
					var tr := p0.distance_to(e.global_position) / 1500.0
					Game.fx.bolt(p0, e.global_position, Color(0.55, 1.0, 0.7), 0.5, tr, 30.0, 3.0)
					if randf() < 0.18:
						Game.fx.later(tr, _escort_kill.bind(e))
					break
		i += 1
