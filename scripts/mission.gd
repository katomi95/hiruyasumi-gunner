extends Node
## MissionManager：一本のステージ（約9分）の進行。戦場は時間とともに自動で次の場面へ移る。
##   SCENE 1 艦隊進撃 → 2 敵戦列突入 → 3 機雷帯 → 4 巨大艦接近 → 5 巨大レーザー → 6 質量兵器 → 7 離脱
## プレイヤーが考えるのは「どこへ行くか」ではなく「今、何を撃つべきか」

const END_T := 552.0
const C2 := Vector3(220, 10, -5850)          # SCENE 2 の敵巡洋艦
const DREAD := Vector3(330, 0, -11900)       # SCENE 4 の敵戦艦
const FORT := Vector3(1500, 450, -18800)     # SCENE 5 の敵要塞
const LEFT := Vector3(-3400, -350, -18600)   # 友軍左翼（大型レーザーの射線の先）
const ASTER := Vector3(-1100, 0, -20300)     # SCENE 6 の質量兵器
const ORBIT_R := 1300.0
const LASER_T0 := 280.0
const LASER_T1 := 336.0
const MASS_T0 := 380.0
const MASS_T1 := 476.0

var events: Array = []
var ev_i := 0
var scene_no := 0
var fort := {}
var mass := {}
var laser_state := "idle"    # idle / charge / fired / stopped
var laser_charge := 0.0
var laser_beam: MeshInstance3D
var laser_t := 0.0
var sweep_beam: MeshInstance3D
var mass_state := "idle"     # idle / thr / ctl / core / done / failed
var mine_t := 0.0
var mine_n := 0
var s2_checked := 0
var ctl_shields: Array = []
var break_chunks: Array = []
var alarm_t := 0.0
var web := false
var active_groups: Array = []
## 舞台装置はその場面になってから現れる [node, 出現, 消える, 出現時に跳躍の閃光を出すか]
var pieces: Array = []
## 長距離跳躍（SCENE 3→4、5→6）。warn で充填開始、enter で突入、exit で離脱
const JUMPS := [
	{"warn": 183.5, "enter": 187.0, "exit": 191.0, "leg": 1},
	{"warn": 360.5, "enter": 364.0, "exit": 368.5, "leg": 2},
]
const SCENE_GROUPS := {2: ["s2"], 4: ["s4t", "s4m", "s4l", "s4s", "s4e"], 5: ["cap"], 6: ["thr", "ctl", "core"]}


func _ready() -> void:
	Game.mission = self
	web = OS.has_feature("web")


# ------------------------------------------------------------------ 準備
func setup() -> void:
	_build_rail()
	_build_world()
	_build_timeline()
	hide_pieces()


func _build_rail() -> void:
	var P := [
		[0, Vector3(0, 0, 0)], [20, Vector3(-10, 12, -1100)], [40, Vector3(15, 25, -2200)], [62, Vector3(0, 30, -3400)],
		[80, Vector3(-20, 20, -4400)], [100, Vector3(-10, 0, -5500)], [118, Vector3(10, -10, -6500)], [135, Vector3(40, -20, -7450)],
		[150, Vector3(30, -25, -8200)], [165, Vector3(0, -35, -8950)], [178, Vector3(-15, -25, -9600)], [190, Vector3(-20, -10, -10250)],
		[200, Vector3(0, -20, -10650)], [214, Vector3(40, -35, -11050)], [226, Vector3(55, 20, -11420)], [238, Vector3(60, 140, -11800)],
		[250, Vector3(75, 190, -12170)], [260, Vector3(60, 130, -12560)], [268, Vector3(40, 150, -12920)], [276, Vector3(200, 90, -13380)],
		[290, Vector3(400, 40, -14100)], [310, Vector3(460, 15, -15150)], [330, Vector3(420, -10, -16200)], [345, Vector3(330, -35, -16950)],
		[352, Vector3(300, -45, -17350)], [356, Vector3(290, -95, -17560)], [362, Vector3(280, -80, -17900)], [374, Vector3(240, -100, -18450)],
		[388, Vector3(215, -50, -19250)],
	]
	# 質量兵器の周りを半周する
	for k in 14:
		var th := deg_to_rad(-15.0 + 15.0 * k)
		P.append([400.0 + k * 6.2, ASTER + Vector3(cos(th) * ORBIT_R, -70, -sin(th) * ORBIT_R)])
	P.append_array([[495, Vector3(-2420, -10, -19530)], [510, Vector3(-2400, 40, -18700)], [525, Vector3(-2380, 20, -17880)],
		[540, Vector3(-2400, 0, -17060)], [556, Vector3(-2400, -10, -16200)]])
	var tip := _tip_world()
	var L := [
		{"t": 0, "pitch": 3}, {"t": 28, "yaw": 12, "pitch": 2}, {"t": 48, "yaw": -10, "pitch": 3}, {"t": 62},
		{"t": 84}, {"t": 96, "target": C2, "w": 0.38}, {"t": 108, "target": C2, "w": 0.45}, {"t": 120},
		{"t": 135, "pitch": -4}, {"t": 186, "pitch": -2},
		{"t": 198, "target": Vector3(180, -30, -11000), "w": 0.42}, {"t": 212, "target": Vector3(180, -35, -11350), "w": 0.5},
		{"t": 224, "target": Vector3(200, 40, -11650), "w": 0.5}, {"t": 236, "target": Vector3(250, 110, -11950), "w": 0.52},
		{"t": 248, "target": Vector3(330, 200, -12350), "w": 0.5}, {"t": 258, "target": Vector3(160, 20, -12830), "w": 0.55},
		{"t": 268, "target": Vector3(160, 0, -12950), "w": 0.45}, {"t": 278},
		{"t": 288, "target": FORT, "w": 0.3}, {"t": 318, "target": tip, "w": 0.38}, {"t": 338, "target": tip, "w": 0.45},
		{"t": 346, "target": tip, "w": 0.55}, {"t": 352, "pitch": 14}, {"t": 360, "pitch": 10}, {"t": 372, "pitch": 4},
		{"t": 386, "target": ASTER, "w": 0.35}, {"t": 400, "target": ASTER + Vector3(0, 60, 0), "w": 0.5, "pitch": 4}, {"t": 478, "target": ASTER + Vector3(0, 60, 0), "w": 0.5, "pitch": 4},
		{"t": 484, "yaw": 95}, {"t": 492, "yaw": 178, "pitch": 3}, {"t": 524, "yaw": 178, "pitch": 3},
		{"t": 532, "yaw": 90}, {"t": 540, "pitch": 2},
	]
	Game.rail.build(P, L)


func _tip_world() -> Vector3:
	var b := Basis.looking_at(LEFT - FORT, Vector3.UP)
	return FORT + b * Vector3(0, 0, -1170)


func _build_world() -> void:
	var A = Game.allies
	var root: Node3D = Game.enemies
	# 遠景の艦隊
	A.add_fleet("home", "A", Vector3(0, -150, -2200), 60, Vector3(1500, 350, 1200), Vector3.FORWARD, Vector3(0, 0, -38), 0, 290)
	A.add_fleet("e_line", "E", Vector3(0, 150, -9500), 70, Vector3(2600, 500, 500), Vector3.BACK, Vector3(0, 0, 6), 0, 187)
	A.add_fleet("left", "A", LEFT, 44, Vector3(1300, 300, 1500), Vector3.FORWARD, Vector3.ZERO, 268, 560)
	A.add_fleet("e_fort", "E", Vector3(2700, 350, -20600), 50, Vector3(1500, 400, 1500), Vector3(-1, 0, 0.3).normalized(), Vector3.ZERO, 268, 560)
	A.add_fleet("pursuit", "E", Vector3(-2400, 150, -27000), 40, Vector3(1000, 300, 800), Vector3.BACK, Vector3(0, 0, 45), 470, 560)
	A.add_fleet("rescue", "A", Vector3(-2400, -50, -15200), 40, Vector3(1200, 300, 900), Vector3.FORWARD, Vector3(0, 0, -30), 500, 560)
	A.add_battle("home", "e_line", 22, 187, 4.0, 4.0)
	A.add_battle("left", "e_fort", 270, 560, 3.5, 5.0)
	A.add_battle("rescue", "pursuit", 516, 560, 5.0, 3.0)
	# 近景：味方の艦列（SCENE 1〜2）
	var near_a := [Vector3(-600, -80, -700), Vector3(500, 120, -900), Vector3(-1100, 60, -1600), Vector3(900, -140, -1900),
		Vector3(-300, 250, -2600), Vector3(1400, 40, -2400), Vector3(-1600, -100, -900), Vector3(200, -260, -1500)]
	for i in near_a.size():
		A.add_ship("A", "ally_cruiser" if i % 3 != 2 else "ally_frigate", near_a[i], Vector3.FORWARD, Vector3(0, 0, -44), 0, 140, 1.4 if i % 3 != 2 else 1.8)
	# 近景：敵の艦列（SCENE 2）
	var near_e := [Vector3(-700, 80, -6400), Vector3(900, -120, -6900), Vector3(-1300, -60, -7300), Vector3(1500, 200, -6200),
		Vector3(-500, -250, -7800), Vector3(600, 300, -7600)]
	var eships: Array = []
	for p in near_e:
		eships.append(A.add_ship("E", "enemy_cruiser", p, Vector3.BACK, Vector3.ZERO, 55, 187, 1.6, 0.7))
	# SCENE 5〜6 の敵艦
	for p in [Vector3(1300, 0, -16500), Vector3(1900, 250, -17700), Vector3(1100, -300, -18300)]:
		A.add_ship("E", "enemy_cruiser", p, Vector3.LEFT, Vector3.ZERO, 268, 366, 1.7, 0.6)
	for p in [Vector3(-600, 450, -21700), Vector3(-2000, -350, -21300), Vector3(300, -250, -21900)]:
		A.add_ship("E", "enemy_frigate", p, Vector3.BACK, Vector3.ZERO, 366, 500, 2.2, 0.8)
	# SCENE 7：合流する友軍
	for p in [Vector3(-2250, -60, -16300), Vector3(-2650, 80, -16600), Vector3(-2100, 160, -17000), Vector3(-2750, -160, -17300)]:
		A.add_ship("A", "ally_cruiser", p, Vector3.FORWARD, Vector3(0, 0, -18), 505, 560, 1.5, 0.9)
	# 護衛艦（自艦隊）
	A.setup_escorts([
		[0, [Vector3(-170, 25, -230), Vector3(210, -35, -330), Vector3(-330, -60, -520), Vector3(380, 70, -620)]],
		[84, [Vector3(-170, 25, -230), Vector3(-260, -35, -380), Vector3(-330, -60, -540), Vector3(-430, 70, -640)]],
		[128, [Vector3(-150, 20, -280), Vector3(170, -30, -380), Vector3(-300, -50, -520), Vector3(330, 60, -640)]],
		[190, [Vector3(-160, 20, -200), Vector3(-270, -40, -380), Vector3(-390, 30, -560), Vector3(-520, -60, -300)]],
		[282, [Vector3(-180, 30, -250), Vector3(220, -40, -350), Vector3(-340, -50, -500), Vector3(360, 60, -650)]],
		[486, [Vector3(-150, 30, 300), Vector3(180, -30, 420), Vector3(-300, -40, 600), Vector3(320, 50, 700)]],
	])
	# 舞台装置
	# 敵巡洋艦は SCENE 2 の手前で跳躍してくる。戦艦・質量兵器は自艦隊の跳躍の先にある
	pieces.append([SetPieces.enemy_cruiser(root, C2), 58.0, 187.0, true])
	pieces.append([SetPieces.dreadnought(root, DREAD, web), 189.0, 300.0, false])
	fort = SetPieces.fortress(root, FORT, LEFT, Vector3(-0.3, -0.3, 1.0).normalized(), web)
	pieces.append([fort["node"], 268.0, 366.0, false])
	for c in fort["caps"]:
		var ct: Target = c
		ct.on_destroy = _cap_down
	mass = SetPieces.mass_weapon(root, ASTER, web)
	pieces.append([mass["node"], 366.0, 9999.0, false])
	for t in mass["thr"]:
		var tt: Target = t
		var old: Callable = tt.on_destroy
		tt.on_destroy = func(e):
			if old.is_valid():
				old.call(e)
			_mass_part_down()
	for t in mass["ctl"]:
		var tc: Target = t
		tc.targetable = false
		tc.objective = false
		tc.on_destroy = func(_e): _mass_part_down()
		ctl_shields.append(_shield(tc))
	var core: Target = mass["core"]
	core.on_destroy = func(_e): _mass_break()
	laser_beam = Game.fx.make_big_beam(Game.COL_LASER)
	sweep_beam = Game.fx.make_big_beam(Game.COL_LASER)


## 制御装置を守るシールド（推進器を全て壊すと消える）
func _shield(t: Target) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 120
	s.height = 240
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/shield.gdshader")
	s.material = m
	mi.mesh = s
	mi.position = Vector3(0, 70, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	t.add_child(mi)
	Game.enemies.add_armor_sphere(mi, 118.0)
	return mi


# ------------------------------------------------------------------ タイムライン
func ev(t: float, c: Callable, always := false) -> void:
	events.append([t, c, always])


func _build_timeline() -> void:
	var E = Game.enemies
	var H = Game.hud
	# ---------------- SCENE 1：艦隊進撃
	ev(0.0, func(): _scene(1, "艦隊進撃", "接近する敵小型機を撃墜せよ"), true)
	ev(1.5, func(): H.radio("旗艦", "全艦、前進。第七打撃群は中央を進め。"))
	ev(5.0, func(): H.radio("砲術長", "ヒルカゼ砲手、配置よし。マウスで狙い、左クリックで撃て。"))
	ev(8.0, func(): lr(3, 70, -650))
	ev(13.0, func(): rl(3, -40, -700))
	ev(19.0, func(): head(4, 40, 30))
	ev(24.0, func(): Game.allies.wing(4, Vector3(-600, 120, -500), Vector3(200, -10, -40)))
	ev(26.0, func(): lr(3, 150, -900))
	ev(30.0, func(): H.radio("旗艦", "前方に敵戦列。各艦、砲撃始め。"))
	ev(32.0, func(): head(5, -60, 60))
	ev(38.0, func(): lr(3, 40, -700))
	ev(38.0 + 0.01, func(): rl(3, -80, -800))
	ev(44.0, func(): missiles_far(2))
	ev(44.5, func(): H.radio("砲術長", "ミサイル接近！ 赤い菱形だ。先に落とせ！"))
	ev(50.0, func(): dive(4, -150, 0.2))
	ev(55.0, func(): head(3, 80, -20))
	ev(55.0 + 0.01, func(): missiles_far(1))
	# ---------------- SCENE 2：敵戦列突入
	ev(62.0, func(): _scene(2, "敵戦列突入", "敵巡洋艦の砲台を破壊せよ"), true)
	ev(63.0, func(): H.radio("艦長", "敵戦列へ突入する。右舷、敵巡洋艦！"))
	ev(66.0, func(): atk(-1.0, 30, -260))
	ev(70.0, func(): atk(1.0, -20, -300))
	ev(74.0, func(): lr(4, 60, -700, 0.2))
	ev(78.0, func(): H.radio("砲術長", "攻撃艇は居座って撃ってくる。赤く光ったら急げ。"))
	ev(84.0, func(): head(3, -40, 40, 0.2))
	ev(86.0, func(): atk(-1.0, -30, -240))
	ev(86.0 + 0.01, func(): atk(1.0, 40, -320))
	ev(92.0, func(): Game.allies.sink_ship(Game.allies.ships[8]))
	ev(94.0, func(): H.radio("旗艦", "砲台を潰せ！ 友軍が撃たれている！"))
	ev(98.0, func(): dive(4, 120, 0.2))
	ev(104.0, func(): atk(1.0, 0, -260))
	ev(108.0, func(): lr(4, -50, -650, 0.2))
	ev(110.0, func(): _s2_check())
	ev(112.0, func(): atk(-1.0, 20, -300))
	ev(112.0 + 0.01, func(): atk(1.0, -40, -280))
	ev(118.0, func(): rl(5, 30, -800, 0.2))
	ev(121.0, func(): Game.allies.sink_ship(Game.allies.ships[9]))
	ev(124.0, func(): missiles_far(3))
	ev(128.0, func(): _s2_check())
	ev(130.0, func(): head(3, 0, 50, 0.2))
	# ---------------- SCENE 3：機雷帯
	ev(135.0, func(): _scene(3, "機雷帯", "進路上の機雷を破壊せよ"), true)
	ev(136.0, func(): H.radio("航法", "機雷帯に入る。進路上の機雷だけ撃て。"))
	ev(141.0, func(): H.radio("砲術長", "橙の印が本艦の進路上だ。全部撃つ必要はない。"))
	ev(147.0, func(): H.radio("艦隊通信", "黄の印は護衛艦の進路上。余裕があれば撃て。"))
	ev(152.0, func(): lr(3, 40, -700))
	ev(166.0, func(): atk(1.0, 10, -300))
	ev(176.0, func(): rl(3, 60, -700))
	ev(182.5, func(): H.radio("航法", "機雷帯を抜けた。全艦、短距離跳躍に入る。"))
	ev(JUMPS[0]["warn"], func(): _jump_warn(0))
	ev(185.0, func(): H.radio("旗艦", "跳躍先は敵戦艦の真横だ。出たらすぐ撃てるようにしておけ。"))
	ev(JUMPS[0]["enter"], func(): _jump_enter(0))
	ev(JUMPS[0]["exit"], func(): _jump_exit(0))
	# ---------------- SCENE 4：巨大艦接近
	ev(191.5, func(): _scene(4, "巨大艦接近", "敵戦艦の砲台を破壊せよ"), true)
	ev(192.5, func(): H.radio("艦長", "敵戦艦の舷側を抜ける。砲台を片っ端から潰せ！"))
	ev(200.0, func(): lr(3, 80, -600, 0.2))
	ev(210.0, func(): atk(-1.0, 20, -250))
	ev(214.0, func(): H.radio("旗艦", "敵戦艦の主砲が友軍を狙っている！"))
	ev(222.0, func(): head(4, -60, 20, 0.2))
	ev(226.0, func(): H.set_objective("主砲を破壊せよ（友軍を砲撃中）"), true)
	ev(234.0, func(): atk(-1.0, 40, -260))
	ev(234.0 + 0.01, func(): atk(1.0, -10, -300))
	ev(246.0, func(): H.set_objective("艦橋のセンサーを破壊せよ"), true)
	ev(246.5, func(): dive(3, -100, 0.2))
	ev(256.0, func(): H.set_objective("推進器を破壊せよ"), true)
	ev(258.0, func(): lr(3, 0, -600, 0.2))
	ev(266.0, func(): rl(3, 40, -700))
	ev(272.0, func(): H.radio("艦長", "敵戦艦を抜けた。"))
	# ---------------- SCENE 5：巨大レーザー
	ev(276.0, func(): _scene(5, "巨大レーザー", "大型レーザー砲台の集束器を破壊せよ"), true)
	ev(277.0, func(): H.radio("旗艦", "敵要塞に高エネルギー反応！ 狙いは左翼艦隊だ！"))
	ev(LASER_T0, func(): _laser_begin(), true)
	ev(283.0, func(): H.radio("砲術長", "砲口の周りの集束器、三基を全部潰せ！"))
	ev(286.0, func(): head(4, 60, 20, 0.2))
	ev(292.0, func(): atk(-1.0, 20, -280))
	ev(292.0 + 0.01, func(): atk(1.0, -30, -260))
	ev(300.0, func(): lr(4, 40, -700, 0.2))
	ev(306.0, func(): _fort_missiles(2))
	ev(312.0, func(): atk(1.0, 30, -300))
	ev(320.0, func(): head(5, -40, 40, 0.2))
	ev(326.0, func(): _fort_missiles(3))
	ev(332.0, func(): rl(3, 20, -700))
	ev(342.0, func(): _sweep_warn())
	# ---------------- SCENE 6：質量兵器
	ev(359.5, func(): H.radio("旗艦", "要塞宙域を離脱する。全艦、跳躍！ 行き先は質量兵器の航路だ！"))
	ev(JUMPS[1]["warn"], func(): _jump_warn(1))
	ev(JUMPS[1]["enter"], func(): _jump_enter(1))
	ev(JUMPS[1]["exit"], func(): _jump_exit(1))
	ev(369.5, func(): _scene(6, "質量兵器", "質量兵器の推進器を破壊せよ（4基）"), true)
	ev(370.5, func(): H.radio("旗艦", "質量兵器が防衛ラインへ向かっている！ 推進器を止めろ！"))
	ev(MASS_T0, func(): _mass_begin(), true)
	ev(384.0, func(): head(4, 0, 50, 0.2))
	ev(392.0, func(): atk(1.0, 20, -280))
	ev(400.0, func(): missiles_far(2))
	ev(408.0, func(): lr(4, 60, -700, 0.2))
	ev(416.0, func(): atk(-1.0, 30, -260))
	ev(416.0 + 0.01, func(): atk(1.0, -20, -300))
	ev(426.0, func(): head(4, 40, 30, 0.2))
	ev(436.0, func(): missiles_far(2))
	ev(446.0, func(): atk(1.0, 10, -280))
	ev(456.0, func(): rl(5, 40, -800, 0.2))
	ev(466.0, func(): missiles_far(3))
	ev(MASS_T1, func(): _mass_timeout(), true)
	# ---------------- SCENE 7：離脱
	ev(482.0, func(): _scene(7, "離脱", "追撃を振り切り、友軍と合流せよ"), true)
	ev(483.0, func(): H.radio("艦長", "離脱する！ 砲座、後方へ旋回！"))
	ev(492.0, func(): H.radio("砲術長", "追撃機多数！ ミサイルも来るぞ！"))
	ev(494.0, func(): head(5, 0, 40, 0.2))
	ev(499.0, func(): missiles_far(2))
	ev(503.0, func(): atk(-1.0, 20, -280))
	ev(503.0 + 0.01, func(): atk(1.0, -30, -260))
	ev(509.0, func(): head(4, -80, 20, 0.25))
	ev(509.0 + 0.01, func(): lr(3, 60, -700))
	ev(514.0, func(): missiles_far(3))
	ev(518.0, func(): atk(1.0, 30, -300))
	ev(521.0, func(): H.radio("旗艦", "こちら友軍本隊。ヒルカゼ、よく戻った。後ろは任せろ。"))
	ev(523.0, func(): Game.allies.wing(5, Vector3(-500, 100, 200), Vector3(60, -5, -260)))
	ev(533.0, func(): H.radio("旗艦", "作戦終了。全艦、帰投する。"))
	ev(542.0, func(): H.notice("MISSION COMPLETE", "任務完了", Game.COL_GOAL), true)
	ev(END_T, func(): Game.main.finish(true), true)
	events.sort_custom(func(a, b): return a[0] < b[0])


# ------------------------------------------------------------------ 出現のひな形（カメラ基準）
func lr(n: int, y := 60.0, z := -700.0, fire := 0.12) -> void:
	Game.enemies.fighters(n, Vector3(-850, y, z), Vector3(240, -y * 0.05, 50), {"fire": fire})


func rl(n: int, y := -40.0, z := -750.0, fire := 0.12) -> void:
	Game.enemies.fighters(n, Vector3(850, y, z), Vector3(-240, -y * 0.05, 50), {"fire": fire})


func head(n: int, x := 0.0, y := 40.0, fire := 0.12) -> void:
	Game.enemies.fighters(n, Vector3(x, y, -1700), Vector3(-x * 0.03, -y * 0.04, 250), {"fire": fire})


func dive(n: int, x := 0.0, fire := 0.12) -> void:
	Game.enemies.fighters(n, Vector3(x, 620, -900), Vector3(-x * 0.05, -180, 100), {"fire": fire})


func atk(side: float, hy := 20.0, hz := -280.0) -> void:
	Game.enemies.attacker(Vector3(side * 950, 140, -900), Vector3(side * 140, hy, hz))


func missiles_far(n: int) -> void:
	for i in n:
		var p := Vector3(randf_range(-500, 500), randf_range(80, 320), randf_range(-2300, -2700))
		Game.fx.later(i * 0.5, func(): Game.enemies.missile_view(p))


func _fort_missiles(n: int) -> void:
	for i in n:
		var p: Vector3 = (fort["node"] as Node3D).global_transform * Vector3(randf_range(-200, 200), 230, randf_range(0, 300))
		Game.fx.later(i * 0.6, func(): Game.enemies.missile(p))


# ------------------------------------------------------------------ 場面
func is_active(g: String) -> bool:
	return g == "" or g in active_groups


func _scene(n: int, title: String, objective: String) -> void:
	scene_no = n
	active_groups = SCENE_GROUPS.get(n, [])
	Game.hud.scene_title(n, title)
	Game.hud.set_objective(objective)
	if n > 1 and Game.state == "play" and Game.t > float(Game.opts["start"]) + 1.0:
		var before: float = Game.stats["hull"]
		Game.stats["hull"] = minf(100.0, before + 15.0)
		if Game.stats["hull"] > before:
			Game.hud.flash_text("応急修理 +%d" % int(Game.stats["hull"] - before), Game.COL_PLAYER)


## SCENE 2：巡洋艦の砲台が残っていると友軍が撃たれる
func _s2_check() -> void:
	var alive: int = Game.enemies.group_alive("s2")
	if alive >= 2:
		Game.allies.lose("home", 1)
		Game.hud.radio("艦隊通信", "友軍巡洋艦、被弾……！ 砲台を黙らせろ！")


## 敵戦艦の主砲の砲撃（友軍の艦隊へ）
func big_gun_fire(e: Target, muzzle: Vector3, aim: Vector3) -> void:
	var fx = Game.fx
	fx.flash(muzzle, 160.0, Color(1.0, 0.7, 0.4), 0.45)
	fx.explosion(muzzle, 14.0, false, true)
	Game.audio.play_at("cannon", muzzle, 6.0, randf_range(0.85, 0.95), 400.0)
	Game.rail.shake(0.35)
	var travel := muzzle.distance_to(aim) / 2600.0
	fx.bolt(muzzle, aim, Color(1.0, 0.6, 0.3), 14.0, travel, 600.0, 4.0)
	if randf() < 0.45 and Game.allies_left() > 0:
		Game.fx.later(travel, _gun_hit_ally)


func _gun_hit_ally() -> void:
	Game.allies.lose("home", 1, 0.1)
	Game.hud.radio("艦隊通信", "敵戦艦の主砲、友軍に命中……！")


# ------------------------------------------------------------------ SCENE 5：大型レーザー
func _laser_begin() -> void:
	if laser_state != "idle":
		return
	laser_state = "charge"
	Game.hud.set_objective("大型レーザー砲台の集束器を破壊せよ（3基）")
	Game.hud.warning("警告　高エネルギー反応", 3.0)
	for c in fort["caps"]:
		(c as Target).objective = true


func _cap_down(_e: Target) -> void:
	var left: int = Game.enemies.group_alive("cap")
	if left > 0:
		Game.hud.flash_text("集束器 残り %d" % left, Game.COL_TARGET)
		return
	if laser_state != "charge" and laser_state != "idle":
		return
	laser_state = "stopped"
	Game.stats["laser_stopped"] = true
	Game.audio.loop("charge_loop", false)
	Game.add_score(5000)
	var tip: MeshInstance3D = fort["tip"]
	var n: Node3D = fort["node"]
	Game.fx.big_explosion(tip.global_position, 80.0, 160.0, 12, 2.5)
	for z in [-420.0, -640.0, -860.0, -1060.0]:
		Game.fx.later(randf_range(0.2, 2.0), Game.fx.explosion.bind(n.global_transform * Vector3(0, 0, z), 50.0))
	tip.visible = false
	Game.fx.attach_fire(n, Vector3(0, 0, -1000), 60.0)
	Game.hud.notice("TARGET DESTROYED", "大型レーザー砲台 沈黙", Game.COL_TARGET)
	Game.hud.radio("旗艦", "砲台沈黙！ 左翼艦隊は無事だ。よくやった！")
	Game.hud.hide_gauge()


func _laser_tick(dt: float) -> void:
	var t: float = Game.t
	var tip: MeshInstance3D = fort["tip"]
	if laser_state == "charge":
		laser_charge = clampf((t - LASER_T0) / (LASER_T1 - LASER_T0), 0.0, 1.0)
		var pulse := 1.0 + sin(t * (6.0 + laser_charge * 20.0)) * 0.08 * laser_charge
		tip.scale = Vector3.ONE * (0.25 + laser_charge * 1.6) * pulse
		Game.hud.gauge("大型レーザー砲台　充填", laser_charge, Game.COL_LASER, "%d%%" % int(laser_charge * 100.0))
		if t < LASER_T1 - 3.3:
			Game.audio.loop("charge_loop", true, lerpf(-16.0, -2.0, laser_charge), lerpf(0.8, 1.35, laser_charge))
		for c in fort["caps"]:
			var ct: Target = c
			if ct.alive:
				ct.scale = Vector3.ONE * (1.0 + sin(t * 8.0 + ct.position.y) * 0.03 * laser_charge)
		if laser_charge > 0.7:
			alarm_t -= dt
			if alarm_t <= 0.0:
				alarm_t = 1.2 - laser_charge * 0.6
				Game.audio.play("alarm", -10.0)
				Game.hud.warning("警告　大型レーザー発射まで %d 秒" % int(ceil(LASER_T1 - t)), 1.0)
		if t >= LASER_T1 - 3.3 and not fort.has("final"):
			fort["final"] = true
			Game.audio.loop("charge_loop", false)
			Game.audio.play("charge_final", 0.0)
		if t >= LASER_T1:
			laser_state = "silence"
			laser_t = 0.0
			Game.audio.duck(0.75)
			Game.hud.hide_gauge()
	elif laser_state == "silence":
		laser_t += dt
		tip.scale = Vector3.ONE * (2.0 + laser_t * 2.0)
		if laser_t >= 0.75:
			_laser_fire()
	elif laser_state == "fired":
		laser_t += dt
		var k := laser_t / 5.5
		var from := tip.global_position
		# 射角を数度だけ動かして左翼をなぎ払う
		var base := (LEFT - from)
		var sweep := base.rotated(Vector3.UP, deg_to_rad(lerpf(-4.0, 3.0, k)))
		var to := from + sweep.normalized() * 9000.0
		var w := 90.0 * (1.0 - smoothstep(0.75, 1.0, k)) + 10.0
		Game.fx.place_big_beam(laser_beam, from, to, w)
		(laser_beam.material_override as ShaderMaterial).set_shader_parameter("alpha", 1.0 - smoothstep(0.8, 1.0, k))
		(laser_beam.material_override as ShaderMaterial).set_shader_parameter("intensity", 5.0)
		tip.scale = Vector3.ONE * (2.6 - k * 1.8)
		if k >= 1.0:
			laser_state = "done"
			laser_beam.visible = false
			tip.scale = Vector3.ONE * 0.5


func _laser_fire() -> void:
	laser_state = "fired"
	laser_t = 0.0
	laser_beam.visible = true
	Game.audio.play("laser_fire", 3.0)
	Game.hud.white_flash(0.9)
	Game.rail.shake(1.2)
	Game.allies.lose("left", 6, 4.0)
	Game.hud.radio("艦隊通信", "大型レーザー、左翼艦隊に直撃……！")
	Game.hud.notice("WARNING", "左翼艦隊 被害甚大", Game.COL_LASER)
	var from: Vector3 = (fort["tip"] as MeshInstance3D).global_position
	for i in 8:
		var p := from.lerp(LEFT, randf_range(0.75, 1.1)) + Vector3(randf_range(-400, 400), randf_range(-150, 150), randf_range(-500, 500))
		Game.fx.later(randf_range(0.3, 4.5), Game.fx.explosion.bind(p, randf_range(40, 70), i % 3 == 0))


# ------------------------------------------------------------------ SCENE 5 後半：副砲の掃射（自艦は自動で潜って回避）
const SWEEP_T0 := 348.0
const SWEEP_T1 := 358.0


func _sweep_warn() -> void:
	Game.hud.radio("航法", "副砲の掃射が来る！ 潜るぞ、つかまれ！")
	Game.hud.warning("照射警報", 5.0)
	Game.audio.play("charge_final", -6.0, 1.2)


func _sweep_tick(dt: float) -> void:
	var t: float = Game.t
	var sw: Node3D = fort["sweep"]
	var sg: MeshInstance3D = fort["sweep_glow"]
	if t >= 342.0 and t < SWEEP_T0:
		sg.scale = Vector3.ONE * lerpf(0.3, 2.0, (t - 342.0) / 6.0)
	if t >= SWEEP_T0 and t <= SWEEP_T1 + 0.6:
		var k := clampf((t - SWEEP_T0) / (SWEEP_T1 - SWEEP_T0), 0.0, 1.0)
		var rail = Game.rail
		var s := lerpf(700.0, -500.0, k)
		var p: Vector3 = rail.pos_at(t) + Vector3.UP * 26.0 + rail.fwd_at(t) * s
		var from := sw.global_position
		var to := from + (p - from).normalized() * 7000.0
		var fade := 1.0 - smoothstep(SWEEP_T1, SWEEP_T1 + 0.6, t)
		sweep_beam.visible = true
		Game.fx.place_big_beam(sweep_beam, from, to, 34.0 * fade + 2.0)
		(sweep_beam.material_override as ShaderMaterial).set_shader_parameter("alpha", fade)
		var close := absf(s)
		Game.audio.loop("beam_loop", true, lerpf(4.0, -18.0, clampf(close / 700.0, 0.0, 1.0)))
		if close < 120.0:
			rail.shake(0.6)
			if randf() < dt * 20.0:
				Game.fx.sparks(rail.cam_pos + Vector3.UP * 20.0 + rail.fwd * randf_range(-10, 30) + Vector3(randf_range(-20, 20), 0, 0), 4.0, Vector3.DOWN, 2.0)
			Game.hud.heat_tint(0.35)
		if not fort.has("grazed") and s < 0.0:
			fort["grazed"] = true
			Game.allies.damage_escort(0)
			Game.hud.radio("艦隊通信", "アオバト被弾！ 航行に支障なし！")
	elif sweep_beam.visible:
		sweep_beam.visible = false
		Game.audio.loop("beam_loop", false)
		sg.scale = Vector3.ONE * 0.3


# ------------------------------------------------------------------ SCENE 6：質量兵器
func _mass_begin() -> void:
	if mass_state != "idle":
		return
	mass_state = "thr"
	for t in mass["thr"]:
		(t as Target).objective = true
	if Game.enemies.group_alive("thr") == 0:
		_mass_part_down()


func _mass_part_down() -> void:

	if mass_state == "thr":
		var left: int = Game.enemies.group_alive("thr")
		if left > 0:
			Game.hud.flash_text("推進器 残り %d" % left, Game.COL_TARGET)
			return
		mass_state = "ctl"
		for i in mass["ctl"].size():
			var c: Target = mass["ctl"][i]
			c.targetable = true
			c.objective = true
			(ctl_shields[i] as MeshInstance3D).visible = false
		Game.hud.notice("MISSION UPDATE", "推進器 全基破壊", Game.COL_TARGET)
		Game.hud.set_objective("制御装置を破壊せよ（2基）")
		Game.hud.radio("旗艦", "推進停止！ シールドが消えた、制御装置を狙え！")
	elif mass_state == "ctl":
		if Game.enemies.group_alive("ctl") > 0:
			Game.hud.flash_text("制御装置 残り %d" % Game.enemies.group_alive("ctl"), Game.COL_TARGET)
			return
		mass_state = "core"
		var hatch: MeshInstance3D = mass["hatch"]
		Game.fx.big_explosion(hatch.global_position, 40.0, 60.0, 6, 1.0)
		hatch.visible = false
		var core: Target = mass["core"]
		core.visible = true
		core.targetable = true
		core.objective = true
		Game.hud.notice("MISSION UPDATE", "爆破点 露出", Game.COL_TARGET)
		Game.hud.set_objective("爆破点を破壊せよ")
		Game.hud.radio("砲術長", "装甲が吹き飛んだ！ 爆破点を撃て！")


func _mass_break() -> void:
	if mass_state == "done" or mass_state == "failed":
		return
	mass_state = "done"
	Game.stats["mass_stopped"] = true
	Game.add_score(8000)
	Game.hud.hide_gauge()
	var n: Node3D = mass["node"]
	var rock: MeshInstance3D = mass["rock"]
	var core_pos: Vector3 = (mass["core"] as Target).global_position
	Game.audio.play("break", 4.0)
	Game.rail.shake(1.0)
	var mat: ShaderMaterial = rock.mesh.surface_get_material(0)
	var tw := create_tween()
	tw.tween_method(func(v): mat.set_shader_parameter("crack", v), 0.0, 1.0, 2.2)
	for i in 16:
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		Game.fx.later(randf_range(0.0, 2.4), Game.fx.explosion.bind(n.global_position + dir * 640.0, randf_range(50, 110), i % 3 == 0))
	Game.fx.later(2.6, func(): _mass_shatter(n, rock, core_pos))
	Game.hud.notice("MASS DESTROYED", "質量兵器 破壊", Game.COL_TARGET)
	Game.hud.radio("旗艦", "質量兵器、崩壊！ 防衛ラインは守られた！")
	Game.hud.set_objective("離脱に備えよ")


func _mass_shatter(n: Node3D, rock: MeshInstance3D, core_pos: Vector3) -> void:
	Game.hud.white_flash(0.7)
	Game.fx.flash(n.global_position, 3500.0, Color(1.0, 0.7, 0.5), 1.4)
	Game.fx.ring(n.global_position, 4000.0, Color(1.0, 0.6, 0.4), 2.5)
	Game.fx.big_explosion(core_pos, 160.0, 400.0, 14, 2.0)
	Game.audio.play("explo_l", 4.0, 0.7)
	rock.visible = false
	for c in n.get_children():
		if c is Target:
			(c as Target).visible = false
		elif c is MeshInstance3D and c != rock:
			(c as MeshInstance3D).visible = false
	for i in 11:
		var r := randf_range(110.0, 260.0)
		var mi := MeshInstance3D.new()
		mi.mesh = Models.rock_mesh(r, 2, 100 + i, 0.3)
		(mi.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("crack", 0.7)
		n.add_child(mi)
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1)).normalized()
		mi.position = dir * randf_range(150, 380)
		break_chunks.append({"mi": mi, "v": dir * randf_range(25, 70), "av": Vector3(randf(), randf(), randf()) * 0.25})
		Game.fx.attach_fire(mi, Vector3.ZERO, r * 0.25)


func _mass_timeout() -> void:
	if mass_state == "done" or mass_state == "idle":
		return
	mass_state = "failed"
	Game.hud.hide_gauge()
	var real := mini(8, Game.allies_left())
	Game.stats["allies_lost"] += real
	for t in mass["thr"]:
		var tt: Target = t
		if tt.alive:
			Game.fx.flash(tt.global_position + tt.global_basis.y * 300.0, 600.0, Color(0.9, 0.6, 1.0), 1.0)
	Game.hud.notice("WARNING", "質量兵器 防衛ラインへ到達", Game.COL_LASER)
	Game.hud.radio("旗艦", "……防衛ラインの艦隊が、やられた。だが作戦は続行する。離脱しろ！")
	Game.hud.set_objective("離脱に備えよ")


func _mass_tick(dt: float) -> void:
	var t: float = Game.t
	if mass_state in ["thr", "ctl", "core"]:
		var k := clampf((MASS_T1 - t) / (MASS_T1 - MASS_T0), 0.0, 1.0)
		var sec := int(ceil(MASS_T1 - t))
		Game.hud.gauge("防衛ライン到達まで", k, Game.COL_SPECIAL, "%d:%02d" % [sec / 60, sec % 60])
	for c in break_chunks:
		var mi: MeshInstance3D = c["mi"]
		mi.position += (c["v"] as Vector3) * dt
		mi.rotate_x(c["av"].x * dt)
		mi.rotate_y(c["av"].y * dt)


# ------------------------------------------------------------------ SCENE 3：機雷帯
func _mines_tick(dt: float) -> void:
	var t: float = Game.t
	if t < 136.0 or t > 183.0:
		return
	mine_t -= dt
	if mine_t > 0.0:
		return
	mine_t = 0.55
	mine_n += 1
	var rail = Game.rail
	var ta := t + 13.0
	var c: Vector3 = rail.pos_at(ta)
	var b: Basis = rail.frame_at(ta)
	for k in 3:
		var a := randf() * TAU
		var r := randf_range(70.0, 520.0)
		Game.enemies.mine(c + b * Vector3(cos(a) * r, sin(a) * r * 0.6, randf_range(-60, 60)), false)
	if mine_n % 5 == 0:
		var a2 := randf() * TAU
		var r2 := randf_range(0.0, 12.0)
		Game.enemies.mine(c + b * Vector3(cos(a2) * r2, sin(a2) * r2, 0), true)
	for pair in [[146.0, 0], [160.0, 1], [172.0, 2]]:
		var tt: float = pair[0]
		var i: int = pair[1]
		if t >= tt and t < tt + 0.56 and Game.allies.escort_alive(i):
			Game.enemies.mine(Game.allies.escort_pos(i, ta) + Vector3(randf_range(-4, 4), randf_range(-4, 4), 0), false, i)


# ------------------------------------------------------------------ 舞台装置の出現
func hide_pieces() -> void:
	for p in pieces:
		(p[0] as Node3D).visible = false


func _pieces_tick(t: float) -> void:
	for p in pieces:
		var n: Node3D = p[0]
		var vis := t >= float(p[1]) and t < float(p[2])
		if vis and not n.visible and p[3]:
			# 敵の増援が跳躍してくる
			Game.fx.flash(n.global_position, 1400.0, Color(0.8, 0.85, 1.0), 0.8)
			Game.fx.ring(n.global_position, 1600.0, Color(0.7, 0.8, 1.0), 1.2)
			Game.audio.play_at("jump_out", n.global_position, 6.0, 1.0, 600.0)
			Game.hud.radio("艦隊通信", "前方に敵巡洋艦、跳躍してきた！")
		n.visible = vis


# ------------------------------------------------------------------ 長距離跳躍
func _jump_warn(i: int) -> void:
	Game.audio.play("jump_charge", -2.0)
	Game.allies.jump_fx(true)


func _jump_enter(i: int) -> void:
	# 跳躍中は敵がいない
	Game.enemies.clear_kind(["fighter", "attacker", "missile", "mine"])
	Game.enemies.clear_bolts()
	Game.audio.play("jump_in", 2.0)
	Game.hud.set_objective("跳躍中")
	Game.hud.hide_gauge()
	Game.audio.loop("jump_loop", true, -4.0)
	Game.hud.white_flash(0.8)
	Game.rail.shake(0.8)


func _jump_exit(i: int) -> void:
	var J: Dictionary = JUMPS[i]
	Game.world.set_leg(J["leg"])
	Game.audio.loop("jump_loop", false)
	Game.audio.play("jump_out", 2.0)
	Game.hud.white_flash(0.7)
	Game.rail.shake(0.6)
	Game.allies.jump_fx(false)


## 充填中は星が光の筋に伸び視野が広がる。突入中は光のトンネル。離脱で元に戻る
func _jump_tick(t: float) -> void:
	var k := 0.0
	var cover := 0.0
	for J in JUMPS:
		var w: float = J["warn"]
		var en: float = J["enter"]
		var ex: float = J["exit"]
		if t >= w and t < en:
			k = pow((t - w) / (en - w), 2.0)
			cover = smoothstep(en - 0.3, en, t)
			if Game.state == "play":
				Game.hud.warning("HYPER JUMP　跳躍まで %d" % int(ceil(en - t)), 0.1)
		elif t >= en and t < ex:
			k = 1.0
			cover = 1.0
		elif t >= ex and t < ex + 1.6:
			var e := (t - ex) / 1.6
			k = 1.0 - smoothstep(0.0, 1.0, e)
			cover = 1.0 - smoothstep(0.0, 0.25, e)
	Game.world.set_jump(k)
	Game.hud.jump_cover = cover
	Game.rail.camera.fov = 70.0 + k * 24.0


# ------------------------------------------------------------------ 開始と毎フレーム
func begin(start_t: float) -> void:
	ev_i = 0
	Game.t = start_t
	# 開始時刻より前の出来事は飛ばす（場面の設定だけは順に適用する）
	while ev_i < events.size() and float(events[ev_i][0]) < start_t:
		if events[ev_i][2]:
			(events[ev_i][1] as Callable).call()
		ev_i += 1
	Game.audio.loop("amb_loop", true, -6.0)
	Game.world.set_leg(0 if start_t < JUMPS[0]["exit"] else (1 if start_t < JUMPS[1]["exit"] else 2))
	for p in pieces:
		(p[0] as Node3D).visible = start_t >= float(p[1]) and start_t < float(p[2])
	# 途中から始めた時は、終わっているはずの出来事を終わらせておく
	if start_t > LASER_T1:
		laser_state = "done"
		(fort["tip"] as MeshInstance3D).scale = Vector3.ONE * 0.5
		Game.hud.hide_gauge()


func tick(dt: float) -> void:
	var t: float = Game.t
	_pieces_tick(t)
	_jump_tick(t)
	while ev_i < events.size() and float(events[ev_i][0]) <= t:
		(events[ev_i][1] as Callable).call()
		ev_i += 1
	_mines_tick(dt)
	if not fort.is_empty():
		_laser_tick(dt)
		_sweep_tick(dt)
	if not mass.is_empty():
		_mass_tick(dt)
