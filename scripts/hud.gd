extends CanvasLayer
## HUD：照準・自艦耐久・現在の目標・必要な時だけのゲージと TARGET 表示。情報は増やしすぎない。
## 配色はシリーズ共通：自艦隊＝水色 / 敵＝赤 / TARGET＝桃 / レーザー＝橙 / 機雷＝橙

const FONT := preload("res://fonts/NotoSansJP-Bold-subset.ttf")
const C_UI := Color(0.56, 0.86, 1.0)
const C_DIM := Color(0.56, 0.86, 1.0, 0.45)

var ctl: Control
var objective := ""
var radios: Array = []      # {who, text, en, t}
var title_info := {"n": 0, "name": "", "t": 99.0}
var gauge_info := {"on": false, "label": "", "v": 0.0, "col": Color.WHITE, "text": ""}
var warn_info := {"text": "", "t": 0.0}
var notice_info := {"en": "", "jp": "", "col": Color.WHITE, "t": 99.0}
var flash_info := {"text": "", "col": Color.WHITE, "t": 99.0}
var dmg := 0.0
var white := 0.0
var tint := 0.0
var popups: Array = []
var lock_spin := 0.0
var clock := 0.0
var fade := 0.0
var fade_target := 0.0
var jump_cover := 0.0      # 跳躍のトンネル（0〜1）
var streaks: Array = []


func _ready() -> void:
	Game.hud = self
	layer = 10
	ctl = Control.new()
	ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ctl)
	ctl.draw.connect(_draw_hud)


# ------------------------------------------------------------------ 公開
func set_objective(t: String) -> void:
	objective = t


## 無線。key を渡すと字幕の文言ではなくその鍵で英語音声を引く
func radio(who: String, text: String, key := "") -> void:
	var k := key if key != "" else text
	var id: String = VoiceLines.BY_TEXT.get(k, "")
	var en: String = VoiceLines.EN.get(id, "")
	radios.append({"who": who, "text": text, "en": en, "t": 0.0})
	while radios.size() > 2:
		radios.pop_front()
	if Game.audio and Game.state == "play":
		if id != "":
			Game.audio.voice(id)
		else:
			Game.audio.play("radio", -8.0)


func scene_title(n: int, name_s: String) -> void:
	title_info = {"n": n, "name": name_s, "t": 0.0}


func gauge(label: String, v: float, col: Color, text: String) -> void:
	gauge_info = {"on": true, "label": label, "v": v, "col": col, "text": text}


func hide_gauge() -> void:
	gauge_info["on"] = false


func warning(text: String, dur: float) -> void:
	warn_info = {"text": text, "t": dur}


func notice(en: String, jp: String, col: Color) -> void:
	notice_info = {"en": en, "jp": jp, "col": col, "t": 0.0}


func flash_text(text: String, col: Color) -> void:
	flash_info = {"text": text, "col": col, "t": 0.0}


func damage_flash(a: float) -> void:
	dmg = minf(1.0, dmg + a)


func white_flash(a: float) -> void:
	white = maxf(white, a)


func heat_tint(a: float) -> void:
	tint = maxf(tint, a)


func popup_score(v: int, pos: Vector3) -> void:
	popups.append({"v": v, "pos": pos, "t": 0.0})


func tick(dt: float) -> void:
	clock += dt
	lock_spin += dt * 3.0
	for r in radios:
		r["t"] += dt
	while not radios.is_empty() and float(radios[0]["t"]) > 6.0:
		radios.pop_front()
	title_info["t"] += dt
	notice_info["t"] += dt
	flash_info["t"] += dt
	warn_info["t"] -= dt
	dmg = maxf(0.0, dmg - dt * 1.6)
	white = maxf(0.0, white - dt * 0.9)
	tint = maxf(0.0, tint - dt * 1.5)
	fade = move_toward(fade, fade_target, dt * 1.2)
	var i := 0
	while i < popups.size():
		popups[i]["t"] += dt
		if popups[i]["t"] > 1.0:
			popups.remove_at(i)
		else:
			i += 1
	ctl.queue_redraw()


# ------------------------------------------------------------------ 描画
func _str(p: Vector2, text: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 0) -> void:
	# 中央・右揃えは幅を与えないと効かないので、基準点から幅を広げて描く
	if align != HORIZONTAL_ALIGNMENT_LEFT:
		width = 2400.0
		p.x -= width * (0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
	if outline > 0:
		ctl.draw_string_outline(FONT, p, text, align, width, size, outline, Color(0, 0, 0, col.a * 0.7))
	ctl.draw_string(FONT, p, text, align, width, size, col)


func _draw_hud() -> void:
	var vs := ctl.size
	var s := vs.y / 720.0
	match Game.state:
		"title":
			_draw_title(vs, s)
		"play", "sinking":
			_draw_play(vs, s)
		"result":
			_draw_result(vs, s)
	if white > 0.0:
		ctl.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.92, 0.85, minf(white, 1.0)))
	if fade > 0.0:
		ctl.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, fade))


func _draw_play(vs: Vector2, s: float) -> void:
	var cam: Camera3D = Game.rail.camera
	# 被弾・照射の色
	if dmg > 0.0:
		var a := dmg * 0.45
		var w := 90.0 * s
		for k in 6:
			var kk := float(k) / 6.0
			var c := Color(1.0, 0.12, 0.08, a * (1.0 - kk) * 0.5)
			var d := w * kk
			ctl.draw_rect(Rect2(d, d, vs.x - d * 2, vs.y - d * 2), c, false, w / 6.0)
	if tint > 0.0:
		ctl.draw_rect(Rect2(Vector2.ZERO, vs), Color(1.0, 0.45, 0.2, tint * 0.25))
	if jump_cover > 0.0:
		_draw_tunnel(vs, s)
	_draw_markers(vs, s, cam)
	# 得点の浮き文字
	for p in popups:
		var wp: Vector3 = p["pos"]
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp) + Vector2(0, -24.0 * s - float(p["t"]) * 30.0 * s)
		_str(sp, "+%d" % p["v"], int(15 * s), Color(1.0, 0.9, 0.6, 1.0 - float(p["t"])), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))
	_draw_reticle(vs, s)
	# 左上：目標
	_str(Vector2(28, 38) * s, "目標", int(13 * s), C_DIM)
	_str(Vector2(66, 38) * s, objective, int(17 * s), C_UI, HORIZONTAL_ALIGNMENT_LEFT, -1, int(3 * s))
	# 右上：得点
	_str(Vector2(vs.x - 28 * s, 38 * s), "%07d" % int(Game.stats["score"]), int(20 * s), C_UI, HORIZONTAL_ALIGNMENT_RIGHT, 0, int(3 * s))
	_str(Vector2(vs.x - 28 * s, 58 * s), "味方艦 %d / %d" % [Game.allies_left(), int(Game.stats["allies_total"])], int(12 * s),
		Game.COL_ALLY * Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_RIGHT)
	# 左下：自艦耐久
	var hull: float = Game.stats["hull"]
	var hx := 28.0 * s
	var hy := vs.y - 40.0 * s
	var hc := C_UI if hull > 35.0 else (Color(1.0, 0.35, 0.25) if fmod(clock, 0.5) < 0.3 else Color(1.0, 0.6, 0.4))
	_str(Vector2(hx, hy - 10 * s), "巡洋艦ヒルカゼ　艦体", int(12 * s), C_DIM)
	for k in 20:
		var on := hull > k * 5.0
		var r := Rect2(hx + k * 11.0 * s, hy, 8.0 * s, 12.0 * s)
		if on:
			ctl.draw_rect(r, hc)
		else:
			ctl.draw_rect(r, Color(hc.r, hc.g, hc.b, 0.18))
	_str(Vector2(hx + 226 * s, hy + 11 * s), "%d%%" % int(ceil(hull)), int(14 * s), hc)
	# 上中央：必要な時だけのゲージ
	if gauge_info["on"]:
		var gw := 380.0 * s
		var gx := (vs.x - gw) * 0.5
		var gy := 30.0 * s
		var gc: Color = gauge_info["col"]
		_str(Vector2(gx, gy - 6 * s), gauge_info["label"], int(13 * s), gc, HORIZONTAL_ALIGNMENT_LEFT, -1, int(3 * s))
		_str(Vector2(gx + gw, gy - 6 * s), gauge_info["text"], int(15 * s), gc, HORIZONTAL_ALIGNMENT_RIGHT, 0, int(3 * s))
		ctl.draw_rect(Rect2(gx, gy, gw, 7 * s), Color(gc.r, gc.g, gc.b, 0.18))
		ctl.draw_rect(Rect2(gx, gy, gw * float(gauge_info["v"]), 7 * s), gc)
	# 警告
	if warn_info["t"] > 0.0 and fmod(clock, 0.6) < 0.4:
		var wy := 118.0 * s
		var tw := 420.0 * s
		var wr := Rect2((vs.x - tw) * 0.5, wy - 24 * s, tw, 34 * s)
		ctl.draw_rect(wr, Color(1.0, 0.3, 0.15, 0.18))
		ctl.draw_rect(wr, Color(1.0, 0.44, 0.25, 0.9), false, 2.0 * s)
		_str(Vector2(vs.x * 0.5, wy), warn_info["text"], int(18 * s), Color(1.0, 0.6, 0.4), HORIZONTAL_ALIGNMENT_CENTER, 0)
	# 場面の題
	var tt: float = title_info["t"]
	if tt < 4.0:
		var a := clampf(tt / 0.4, 0.0, 1.0) * clampf((4.0 - tt) / 0.8, 0.0, 1.0)
		_str(Vector2(vs.x * 0.5, vs.y * 0.3), "SCENE %d" % title_info["n"], int(15 * s), Color(C_UI.r, C_UI.g, C_UI.b, a), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))
		_str(Vector2(vs.x * 0.5, vs.y * 0.3 + 44 * s), title_info["name"], int(38 * s), Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 0, int(5 * s))
	# 通知（シリーズと同じ二行）
	var nt: float = notice_info["t"]
	if nt < 3.2:
		var a2 := clampf(nt / 0.3, 0.0, 1.0) * clampf((3.2 - nt) / 0.6, 0.0, 1.0)
		var nc: Color = notice_info["col"]
		_str(Vector2(vs.x * 0.5, vs.y * 0.4), notice_info["en"], int(14 * s), Color(nc.r, nc.g, nc.b, a2), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))
		_str(Vector2(vs.x * 0.5, vs.y * 0.4 + 34 * s), notice_info["jp"], int(28 * s), Color(1, 1, 1, a2), HORIZONTAL_ALIGNMENT_CENTER, 0, int(4 * s))
	var ft: float = flash_info["t"]
	if ft < 1.6:
		var fc: Color = flash_info["col"]
		_str(Vector2(vs.x * 0.5, vs.y * 0.62), flash_info["text"], int(16 * s), Color(fc.r, fc.g, fc.b, clampf((1.6 - ft) / 0.5, 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))
	# 無線
	var ry := vs.y - 70.0 * s
	for k in range(radios.size() - 1, -1, -1):
		var r2: Dictionary = radios[k]
		var ra := clampf((6.0 - float(r2["t"])) / 0.8, 0.0, 1.0) * clampf(float(r2["t"]) / 0.15, 0.0, 1.0)
		var line := "［%s］%s" % [r2["who"], r2["text"]]
		var en2: String = r2.get("en", "")
		if en2 != "":
			_str(Vector2(vs.x * 0.5, ry), en2, int(12 * s), Color(0.75, 0.82, 0.9, ra * 0.85), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))
			ry -= 20.0 * s
		_str(Vector2(vs.x * 0.5, ry), line, int(16 * s), Color(0.92, 0.96, 1.0, ra), HORIZONTAL_ALIGNMENT_CENTER, 0, int(4 * s))
		ry -= 26.0 * s
	if Game.paused:
		ctl.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.5))
		_str(Vector2(vs.x * 0.5, vs.y * 0.45), "一時停止", int(34 * s), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 0)
		_str(Vector2(vs.x * 0.5, vs.y * 0.45 + 36 * s), "Esc / P で再開　　M で消音", int(15 * s), C_UI, HORIZONTAL_ALIGNMENT_CENTER, 0)


## 跳躍中の光のトンネル：中心から外へ流れる光の筋
func _draw_tunnel(vs: Vector2, s: float) -> void:
	if streaks.is_empty():
		for i in 160:
			streaks.append([randf() * TAU, randf(), randf_range(0.6, 1.6), randf()])
	var a := jump_cover
	var c := vs * 0.5
	ctl.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.02, 0.06, a))
	var maxr := vs.length() * 0.6
	for i in 6:
		var rr := maxr * (0.08 + i * 0.05)
		ctl.draw_circle(c, rr, Color(0.3, 0.5, 1.0, a * 0.05))
	for st in streaks:
		var ang: float = st[0] + clock * 0.15
		var ph := fmod(float(st[1]) + clock * 0.55 * float(st[2]), 1.0)
		var r0 := ph * ph * maxr
		var r1 := r0 + (20.0 + ph * 220.0) * s
		var d := Vector2.from_angle(ang)
		var col := Color(0.55, 0.75, 1.0).lerp(Color(1.0, 0.85, 1.0), float(st[3]))
		col.a = a * clampf(ph * 2.0, 0.0, 1.0) * 0.9
		ctl.draw_line(c + d * r0, c + d * r1, col, (1.0 + ph * 3.0) * s)
	ctl.draw_circle(c, 40.0 * s, Color(0.8, 0.9, 1.0, a * 0.35))
	ctl.draw_circle(c, 14.0 * s, Color(1.0, 1.0, 1.0, a * 0.8))


func _screen_r(cam: Camera3D, p: Vector3, r: float, vs: Vector2) -> float:
	var d := cam.global_position.distance_to(p)
	return r / maxf(d, 1.0) * vs.y * 0.5 / tan(deg_to_rad(cam.fov * 0.5))


func _draw_markers(vs: Vector2, s: float, cam: Camera3D) -> void:
	var gun = Game.gun
	for x in Game.enemies.targets:
		var e: Target = x
		if not e.alive or not e.is_visible_in_tree():
			continue
		var show := e.objective or e.marker != ""
		if not show:
			continue
		var p := e.hit_center()
		var dist := cam.global_position.distance_to(p)
		# TARGET は今の場面の目標で、ある程度近いものだけ
		if e.marker == "" and (not Game.mission.is_active(e.group) or dist > 2800.0):
			continue
		var col := Game.COL_TARGET
		match e.marker:
			"missile": col = Color(1.0, 0.3, 0.25)
			"attacker": col = Color(1.0, 0.45, 0.3)
			"mine": col = Game.COL_MINE
			"mine_escort": col = Color(1.0, 0.9, 0.35)
		if e.marker == "mine" and dist > 1100.0:
			continue
		if e.marker == "mine_escort" and dist > 900.0:
			continue
		if e.marker == "attacker" and e.charge <= 0.0 and e.st != "hold":
			continue
		var behind := cam.is_position_behind(p)
		var sp := cam.unproject_position(p)
		var on := not behind and sp.x > 20 * s and sp.y > 20 * s and sp.x < vs.x - 20 * s and sp.y < vs.y - 20 * s
		if not on:
			if (e.objective and not behind) or e.marker == "missile":
				_edge_arrow(vs, s, sp, behind, col, e.marker == "missile")
			continue
		var r := maxf(_screen_r(cam, p, e.radius, vs), 9.0 * s)
		match e.marker:
			"missile":
				var rr := r + 6.0 * s
				var pts := PackedVector2Array([sp + Vector2(0, -rr), sp + Vector2(rr, 0), sp + Vector2(0, rr), sp + Vector2(-rr, 0), sp + Vector2(0, -rr)])
				ctl.draw_polyline(pts, col, 2.0 * s)
				if fmod(clock, 0.3) < 0.18:
					_str(sp + Vector2(rr + 4 * s, 4 * s), "MSL", int(11 * s), col, HORIZONTAL_ALIGNMENT_LEFT, -1, int(2 * s))
			"mine", "mine_escort":
				var rr2 := r + 5.0 * s
				ctl.draw_arc(sp, rr2, 0, TAU, 20, col, 1.6 * s)
				_str(sp + Vector2(0, -rr2 - 3 * s), "!", int(13 * s), col, HORIZONTAL_ALIGNMENT_CENTER, 0, int(2 * s))
			"attacker":
				var a := 0.5 + e.charge * 0.5
				var rr3 := r + 8.0 * s - e.charge * 4.0 * s
				ctl.draw_arc(sp, rr3, 0, TAU, 20, Color(col.r, col.g, col.b, a), (1.5 + e.charge * 2.0) * s)
			_:
				_brackets(sp, r + 6.0 * s, col, 1.8 * s, 8.0 * s)
				_str(sp + Vector2(0, -r - 12 * s), "TARGET", int(11 * s), col, HORIZONTAL_ALIGNMENT_CENTER, 0, int(2 * s))
				if e.label != "":
					_str(sp + Vector2(0, r + 22 * s), e.label, int(12 * s), col, HORIZONTAL_ALIGNMENT_CENTER, 0, int(2 * s))
				if e.hp < e.max_hp:
					var bw := maxf(r * 1.6, 40.0 * s)
					var br := Rect2(sp.x - bw * 0.5, sp.y + r + 28 * s, bw, 4 * s)
					ctl.draw_rect(br, Color(col.r, col.g, col.b, 0.25))
					ctl.draw_rect(Rect2(br.position, Vector2(bw * e.hp_ratio(), br.size.y)), col)
	# 照準が重なった敵（自動ロックオンではない）
	var lt = gun.aim_target
	if lt != null and is_instance_valid(lt) and (lt as Target).alive:
		var e2: Target = lt
		var p2 := e2.hit_center()
		if not cam.is_position_behind(p2):
			var sp2 := cam.unproject_position(p2)
			var r2 := maxf(_screen_r(cam, p2, e2.radius, vs), 10.0 * s) + 10.0 * s
			for k in 4:
				var a0 := lock_spin + k * PI * 0.5
				ctl.draw_arc(sp2, r2, a0, a0 + 0.6, 6, Color(1.0, 0.55, 0.3), 2.2 * s)


func _brackets(c: Vector2, r: float, col: Color, w: float, l: float) -> void:
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := c + Vector2(sx * r, sy * r)
			ctl.draw_line(p, p - Vector2(sx * l, 0), col, w)
			ctl.draw_line(p, p - Vector2(0, sy * l), col, w)


func _edge_arrow(vs: Vector2, s: float, sp: Vector2, behind: bool, col: Color, small: bool) -> void:
	var c := vs * 0.5
	var d := sp - c
	if behind:
		d = -d
	if d.length() < 1.0:
		d = Vector2(0, 1)
	d = d.normalized()
	var m := 36.0 * s
	var k := minf((vs.x * 0.5 - m) / maxf(absf(d.x), 0.001), (vs.y * 0.5 - m) / maxf(absf(d.y), 0.001))
	var p := c + d * k
	var sz := (8.0 if small else 12.0) * s
	var n := Vector2(-d.y, d.x)
	ctl.draw_colored_polygon(PackedVector2Array([p + d * sz, p - d * sz * 0.6 + n * sz * 0.7, p - d * sz * 0.6 - n * sz * 0.7]),
		Color(col.r, col.g, col.b, 0.85))


func _draw_reticle(vs: Vector2, s: float) -> void:
	var gun = Game.gun
	var p: Vector2 = gun.aim_screen
	var locked: bool = gun.aim_target != null
	var col := C_UI
	if locked:
		col = Color(1.0, 0.5, 0.3)
	var r := 16.0 * s
	ctl.draw_arc(p, r, 0, TAU, 32, Color(col.r, col.g, col.b, 0.9), 1.6 * s)
	for k in 4:
		var d := Vector2.from_angle(k * PI * 0.5)
		ctl.draw_line(p + d * (r + 3 * s), p + d * (r + 11 * s), col, 2.0 * s)
	ctl.draw_circle(p, 2.0 * s, col)
	if locked:
		_str(p + Vector2(r + 14 * s, -r), "LOCK", int(10 * s), col, HORIZONTAL_ALIGNMENT_LEFT, -1, int(2 * s))


func _draw_title(vs: Vector2, s: float) -> void:
	ctl.draw_rect(Rect2(0, vs.y * 0.24, vs.x, vs.y * 0.52), Color(0.0, 0.01, 0.03, 0.7))
	_str(Vector2(vs.x * 0.5, vs.y * 0.34), "昼休みの宇宙戦争", int(22 * s), Color(0.8, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 0, int(4 * s))
	_str(Vector2(vs.x * 0.5, vs.y * 0.34 + 74 * s), "GUNNER", int(72 * s), C_UI, HORIZONTAL_ALIGNMENT_CENTER, 0, int(6 * s))
	_str(Vector2(vs.x * 0.5, vs.y * 0.34 + 108 * s), "巡洋艦ヒルカゼ　主砲砲手", int(15 * s), Color(0.8, 0.88, 1.0, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))
	var y := vs.y * 0.34 + 150 * s
	_str(Vector2(vs.x * 0.5, y), "マウス：照準　　左クリック：レーザー射撃（押しっぱなしで連射）", int(14 * s), Color(0.85, 0.92, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))
	_str(Vector2(vs.x * 0.5, y + 24 * s), "艦の操縦はしない。航路は艦橋が決める。君は、何を撃つかだけを決める。", int(13 * s), Color(0.7, 0.8, 0.9, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))
	var a := 0.75 + 0.25 * sin(clock * 3.0)
	_str(Vector2(vs.x * 0.5, y + 70 * s), "クリックで出撃", int(20 * s), Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 0, int(4 * s))
	_str(Vector2(vs.x * 0.5, vs.y - 64 * s), "約9分・ヘッドホン推奨　　Esc / P：一時停止　　M：消音", int(12 * s), Color(0.7, 0.8, 0.9, 0.6), HORIZONTAL_ALIGNMENT_CENTER, 0)
	_str(Vector2(vs.x * 0.5, vs.y - 42 * s), "無線の英語音声は Azure AI Speech による AI 合成音声です", int(12 * s), Color(0.8, 0.88, 0.95, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))
	_str(Vector2(vs.x * 0.5, vs.y - 22 * s), "効果音（レーザー）：ポケットサウンド – https://pocket-se.info/", int(12 * s), Color(0.8, 0.88, 0.95, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))


func _draw_result(vs: Vector2, s: float) -> void:
	ctl.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.01, 0.03, 0.62))
	var st := Game.stats
	var cleared: bool = st["cleared"]
	var cx := vs.x * 0.5
	var y := vs.y * 0.2
	_str(Vector2(cx, y), "MISSION COMPLETE" if cleared else "SHIP LOST", int(16 * s), C_UI if cleared else Color(1.0, 0.4, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))
	_str(Vector2(cx, y + 46 * s), "任務完了" if cleared else "ヒルカゼ 撃沈", int(40 * s), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 0, int(5 * s))
	var shots: int = st["shots"]
	var acc := 0.0 if shots == 0 else float(st["hits"]) / float(shots) * 100.0
	var rows := [
		["撃破数", "%d" % int(st["kills"])],
		["ミサイル迎撃", "%d" % int(st["missiles"])],
		["砲台・部位破壊", "%d" % int(st["parts"])],
		["機雷処理", "%d" % int(st["mines"])],
		["命中率", "%.1f%%" % acc],
		["味方艦残存", "%d / %d" % [Game.allies_left(), int(st["allies_total"])]],
		["大型レーザー砲台", "阻止" if st["laser_stopped"] else "発射を許した"],
		["質量兵器", "破壊" if st["mass_stopped"] else "阻止できず"],
	]
	var ly := y + 100 * s
	for r in rows:
		_str(Vector2(cx - 20 * s, ly), r[0], int(17 * s), Color(0.75, 0.85, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, 0)
		_str(Vector2(cx + 20 * s, ly), r[1], int(19 * s), Color.WHITE)
		ly += 30 * s
	_str(Vector2(cx, ly + 22 * s), "SCORE  %07d" % int(st["score"]), int(28 * s), C_UI, HORIZONTAL_ALIGNMENT_CENTER, 0, int(4 * s))
	if st.has("bonus"):
		_str(Vector2(cx, ly + 48 * s), "（味方艦残存ボーナス +%d を含む）" % int(st["bonus"]), int(12 * s), Color(0.7, 0.8, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 0)
	var a := 0.55 + 0.45 * sin(clock * 3.0)
	_str(Vector2(cx, vs.y - 50 * s), "クリックでタイトルへ", int(17 * s), Color(1, 1, 1, a), HORIZONTAL_ALIGNMENT_CENTER, 0, int(3 * s))
