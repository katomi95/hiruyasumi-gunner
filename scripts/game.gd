extends Node
## 共有の参照・配色・戦績（オートロード "Game"）
## 配色は「昼休みの宇宙戦争」と共通：自艦隊＝水色 / 友軍＝緑 / 敵＝赤 / 砲台・質量兵器＝紫 / TARGET＝桃 / レーザー＝橙

const COL_PLAYER := Color(0.56, 0.86, 1.0)
const COL_ALLY := Color(0.53, 0.96, 0.64)
const COL_ENEMY := Color(1.0, 0.37, 0.3)
const COL_SPECIAL := Color(0.83, 0.72, 1.0)
const COL_TARGET := Color(1.0, 0.47, 0.84)
const COL_LASER := Color(1.0, 0.44, 0.25)
const COL_MINE := Color(1.0, 0.59, 0.16)
const COL_GOAL := Color(1.0, 0.82, 0.47)

var main: Node
var world: Node
var rail: Node
var gun: Node
var enemies: Node
var allies: Node
var mission: Node
var fx: Node
var hud: Node
var audio: Node

var t := 0.0
var state := "title"   # title / play / result
var paused := false
var stats := {}
## 起動引数（検証用）。シーンを読み直しても残る
var opts := {"autoplay": false, "fast": 1.0, "start": 0.0, "shots": "", "shot_times": [], "shot_i": 0,
	"autostart": false, "nofire": false, "quit_at_end": false}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a == "--autoplay":
			opts["autoplay"] = true
		elif a == "--nofire":
			opts["nofire"] = true
		elif a == "--autostart":
			opts["autostart"] = true
		elif a == "--quit":
			opts["quit_at_end"] = true
		elif a.begins_with("--fast="):
			opts["fast"] = float(a.get_slice("=", 1))
		elif a.begins_with("--start="):
			opts["start"] = float(a.get_slice("=", 1))
		elif a.begins_with("--shots="):
			opts["shots"] = a.get_slice("=", 1)
		elif a.begins_with("--at="):
			var ts: Array = []
			for s in a.get_slice("=", 1).split(","):
				ts.append(float(s))
			opts["shot_times"] = ts
	reset_stats()


func reset_stats() -> void:
	stats = {"score": 0, "kills": 0, "missiles": 0, "parts": 0, "mines": 0, "shots": 0, "hits": 0,
		"allies_total": 32, "allies_lost": 0, "hull": 100.0, "laser_stopped": false, "mass_stopped": false,
		"damage_taken": 0.0, "cleared": false}


func add_score(v: int, pos = null) -> void:
	stats["score"] += v
	if hud and pos != null:
		hud.popup_score(v, pos)


func allies_left() -> int:
	return int(stats["allies_total"]) - int(stats["allies_lost"])
