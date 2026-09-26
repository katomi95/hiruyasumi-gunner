extends Node3D
## 昼休みの宇宙戦争：GUNNER — 起動・画面遷移（タイトル → 出撃 → 結果）・自艦の被弾。
## 更新順はここで一元化する：任務 → 航行 → 味方 → 敵 → 砲 → 効果 → HUD
##
## 検証用の引数（`godot --path . -- <引数>`）
##   --autoplay            自動砲手で最後まで遊ぶ
##   --fast=4              時間を速める
##   --start=276           その時刻から始める（それ以前の出現は飛ばす）
##   --nofire              撃たない（被害の上限を見る）
##   --quit                結果が出たら終了して戦績を表示
##   --shots=<dir> --at=10,100,...   その時刻の画面を撮影して終了

var sink_t := -1.0
var result_t := 0.0
var shot_t := -1.0
var alarm_cd := 0.0


func _ready() -> void:
	Game.main = self
	Game.state = "title"
	Game.paused = false
	Game.t = 0.0
	Game.reset_stats()
	Engine.time_scale = float(Game.opts["fast"])
	Game.mission.setup()
	Game.rail.title_mode = true
	Game.rail.update(0.0, 0.016)
	Game.audio.loop("amb_loop", true, -12.0)
	var shots: String = Game.opts["shots"]
	if shots != "":
		var ts: Array = Game.opts["shot_times"]
		var i: int = Game.opts["shot_i"]
		if i >= ts.size():
			get_tree().quit()
			return
		var at: float = ts[i]
		if at < 0.0:
			# 負の時刻はタイトル画面
			shot_t = 1.5
			return
		Game.opts["start"] = maxf(0.0, at - 5.0)
		Game.opts["autoplay"] = true
		start_game()
		shot_t = at - float(Game.opts["start"])
	elif Game.opts["autostart"] or Game.opts["autoplay"]:
		start_game()


func start_game() -> void:
	Game.reset_stats()
	Game.state = "play"
	Game.paused = false
	Game.rail.title_mode = false
	if not Game.opts["autoplay"]:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	Game.audio.play("start", -6.0)
	Game.mission.begin(float(Game.opts["start"]))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_M:
			Game.audio.toggle_mute()
		elif Game.state == "play" and (k == KEY_ESCAPE or k == KEY_P):
			_set_pause(not Game.paused)
	if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if Game.state == "title":
			start_game()
		elif Game.state == "result" and result_t > 1.2:
			get_tree().reload_current_scene()
		elif Game.state == "play" and Game.paused:
			_set_pause(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Game.state == "play" and not Game.opts["autoplay"]:
		_set_pause(true)


func _set_pause(p: bool) -> void:
	Game.paused = p
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if p else Input.MOUSE_MODE_HIDDEN
	AudioServer.set_bus_mute(1, p)


func damage_player(amount: float, from_pos: Vector3, src := "") -> void:
	if Game.state != "play":
		return
	var key := "dmg_" + src
	Game.stats[key] = float(Game.stats.get(key, 0.0)) + amount
	Game.stats["hull"] = maxf(0.0, float(Game.stats["hull"]) - amount)
	Game.stats["damage_taken"] += amount
	Game.hud.damage_flash(0.25 + amount * 0.06)
	Game.rail.shake(0.25 + amount * 0.05)
	Game.audio.play("player_hit", -3.0 + amount * 0.3, randf_range(0.9, 1.1))
	var cam: Vector3 = Game.rail.cam_pos
	var p := cam + (from_pos - cam).normalized() * 9.0 + Vector3(0, -4, 0)
	Game.fx.sparks(p, 3.0, (from_pos - cam).normalized(), 2.0)
	Game.fx.flash(p, 14.0, Color(1.0, 0.6, 0.3), 0.15)
	if float(Game.stats["hull"]) <= 30.0 and alarm_cd <= 0.0:
		alarm_cd = 4.0
		Game.audio.play("alarm", -6.0)
		Game.hud.flash_text("艦体損傷 危険域", Color(1.0, 0.4, 0.3))
	if float(Game.stats["hull"]) <= 0.0:
		_sink()


func _sink() -> void:
	Game.state = "sinking"
	sink_t = 0.0
	var cam: Vector3 = Game.rail.cam_pos
	Game.fx.big_explosion(cam + Game.rail.fwd * 40.0 + Vector3(0, -12, 0), 20.0, 30.0, 8, 1.8)
	Game.hud.white_flash(0.6)
	Game.rail.shake(1.5)
	Game.audio.loop("charge_loop", false)
	Game.audio.loop("beam_loop", false)


func finish(cleared: bool) -> void:
	if Game.state == "result":
		return
	Game.stats["cleared"] = cleared
	if cleared:
		var bonus := Game.allies_left() * 300
		Game.stats["bonus"] = bonus
		Game.stats["score"] += bonus
		Game.audio.play("clear", -2.0)
	else:
		Game.audio.play("gameover", -2.0)
	Game.audio.stop_all_loops()
	Game.audio.stop_voice()
	Game.audio.loop("amb_loop", true, -14.0)
	Game.state = "result"
	Game.hud.fade_target = 0.0
	result_t = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var st := Game.stats
	print("RESULT cleared=%s t=%.1f score=%d kills=%d missiles=%d parts=%d mines=%d acc=%.1f%% hull=%.0f dmg=%.0f allies=%d/%d laser=%s mass=%s" % [
		cleared, Game.t, st["score"], st["kills"], st["missiles"], st["parts"], st["mines"],
		100.0 * float(st["hits"]) / maxf(1.0, float(st["shots"])), st["hull"], st["damage_taken"],
		Game.allies_left(), st["allies_total"], st["laser_stopped"], st["mass_stopped"]])
	var parts := ""
	for k in st:
		if str(k).begins_with("dmg_"):
			parts += " %s=%d" % [k, st[k]]
	print("DAMAGE", parts)
	if Game.opts["quit_at_end"]:
		get_tree().quit()


func _process(dt: float) -> void:
	var st: String = Game.state
	var run := (st == "play" and not Game.paused) or st == "sinking"
	var sdt := dt if run else 0.0
	if st == "play" and not Game.paused:
		Game.t += dt
		Game.mission.tick(dt)
	elif st == "sinking":
		Game.t += dt
		sink_t += dt
		Game.hud.fade_target = 0.85
		if sink_t > 2.8:
			finish(false)
	alarm_cd -= sdt
	Game.rail.update(Game.t, dt if st != "result" else 0.0)
	Game.world.tick(dt)
	Game.allies.tick(sdt)
	if run:
		Game.enemies.tick(sdt)
		Game.fx.tick(sdt)
	elif st != "play":
		Game.fx.tick(dt)
	Game.gun.tick(dt)
	Game.audio.tick(dt)
	Game.hud.tick(dt)
	if st == "result":
		result_t += dt
	if shot_t >= 0.0:
		shot_t -= dt
		if shot_t < 0.0:
			_capture()


func _capture() -> void:
	await RenderingServer.frame_post_draw
	var dir: String = Game.opts["shots"]
	DirAccess.make_dir_recursive_absolute(dir)
	var i: int = Game.opts["shot_i"]
	var ts: Array = Game.opts["shot_times"]
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join("shot_%02d_t%03d.png" % [i, int(ts[i])]))
	print("shot ", i, " t=", Game.t)
	Game.opts["shot_i"] = i + 1
	if i + 1 >= ts.size():
		get_tree().quit()
	else:
		get_tree().reload_current_scene()
