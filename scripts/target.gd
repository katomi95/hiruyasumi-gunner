class_name Target
extends Node3D
## 撃てる対象（敵機・ミサイル・機雷・砲台・大型目標の部位）。行動は EnemyManager が種類ごとに動かす

static var flash_mat: StandardMaterial3D

var kind := ""
var hp := 1.0
var max_hp := 1.0
var radius := 5.0
var score := 100
var alive := true
var targetable := true
var objective := false        # TARGET 表示
var label := ""
var marker := ""              # "missile" / "mine" / "attacker" / ""
var group := ""
var boom := 8.0               # 撃破時の爆発の大きさ

## 自艦に固定した座標系で動くもの（敵機・ミサイル・敵弾の発射元）
var anchored := false
var frame := Basis()
var local := Vector3.ZERO
var lvel := Vector3.ZERO

var age := 0.0
var life := 999.0
var st := ""
var d := {}
var head: Node3D
var flash_meshes: Array = []
var flash_t := 0.0
var stage := 0
var dangerous := false
var threat_escort := -1
var charge := 0.0
var on_destroy := Callable()
var on_hit := Callable()


func setup_flash() -> void:
	if flash_mat == null:
		flash_mat = StandardMaterial3D.new()
		flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		flash_mat.albedo_color = Color(1.0, 0.85, 0.7, 0.55)
	for c in find_children("*", "MeshInstance3D", true, false):
		flash_meshes.append(c)


## 被弾。撃破したら true
func hit(amount: float) -> bool:
	if not alive or not targetable:
		return false
	hp -= amount
	if flash_t <= 0.0:
		for m in flash_meshes:
			if is_instance_valid(m):
				(m as MeshInstance3D).material_overlay = flash_mat
	flash_t = 0.05
	if on_hit.is_valid():
		on_hit.call(self)
	if hp <= 0.0:
		alive = false
		return true
	return false


func tick_flash(dt: float) -> void:
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t <= 0.0:
			for m in flash_meshes:
				if is_instance_valid(m):
					(m as MeshInstance3D).material_overlay = null


var hit_off := Vector3.ZERO


## 当たり判定の中心（部位はメッシュの原点が台座にあるので少し持ち上げる）
func hit_center() -> Vector3:
	return to_global(hit_off)


func hp_ratio() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)
