extends Node
## 効果音。tools/gen_audio.py で合成した WAV をプールで鳴らす
## 巨大レーザーは「低音のチャージ → 一瞬の静寂（duck） → 強烈な発射音」

const NAMES := ["shot", "heavy", "hit", "armor", "overheat", "lock", "explo_s", "explo_m", "explo_l", "far_boom",
	"cannon", "break", "enemy_shot", "missile_launch", "missile_warn", "flyby", "mine_beep", "player_hit", "alarm",
	"charge_loop", "charge_final", "laser_fire", "beam_loop", "amb_loop", "radio", "start", "clear", "gameover",
	"jump_charge", "jump_in", "jump_loop", "jump_out"]
const LOOPS := ["charge_loop", "beam_loop", "amb_loop", "jump_loop"]

var streams := {}
var pool2d: Array = []
var pool3d: Array = []
var i2 := 0
var i3 := 0
var loops := {}
var sfx_bus := 1
var duck_t := 0.0
var duck_total := 0.0
var muted := false
# 無線の声（英語）。重なったら順番に流す。話している間は効果音を少し下げる
var voice_player: AudioStreamPlayer
var voice_queue: Array = []   # [id, 要求された時刻]
var fx_bus := 2
var voice_duck := 0.0
# レーザーの発射音（ポケットサウンドの laser.mp3）。長い音なので同時に鳴らすのは 4 つまで、それぞれ短く切る
const LASER_PATH := "res://audio/laser.mp3"
var laser_stream: AudioStream
var laser_pool: Array = []
var laser_i := 0


func _ready() -> void:
	Game.audio = self
	# バスは default_bus_layout.tres で定義する（実行中に足したバスは Web 版の再生側に伝わらない）
	sfx_bus = maxi(AudioServer.get_bus_index("SFX"), 0)
	fx_bus = maxi(AudioServer.get_bus_index("FX"), 0)
	for n in NAMES:
		var s = load("res://audio/%s.wav" % n)
		if s is AudioStreamWAV and n in LOOPS:
			var w: AudioStreamWAV = s
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
		streams[n] = s
	# 元の mp3 は公開リポジトリに含めない。無い時は合成の発射音で代用する
	if ResourceLoader.exists(LASER_PATH):
		laser_stream = load(LASER_PATH)
	for i in 4:
		var lp := AudioStreamPlayer.new()
		lp.bus = "FX"
		add_child(lp)
		laser_pool.append(lp)
	for i in 20:
		var p := AudioStreamPlayer.new()
		p.bus = "FX"
		add_child(p)
		pool2d.append(p)
	for i in 20:
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "FX"
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.max_db = 4.0
		p3.panning_strength = 0.8
		add_child(p3)
		pool3d.append(p3)


func play(n: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not streams.has(n):
		return
	var p: AudioStreamPlayer = pool2d[i2]
	i2 = (i2 + 1) % pool2d.size()
	p.stream = streams[n]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


## 位置つき。unit は音が減衰し始める距離のめやす
func play_at(n: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, unit := 60.0) -> void:
	if not streams.has(n):
		return
	var p: AudioStreamPlayer3D = pool3d[i3]
	i3 = (i3 + 1) % pool3d.size()
	p.stream = streams[n]
	p.global_position = pos
	p.volume_db = vol_db
	p.unit_size = unit
	p.pitch_scale = pitch
	p.play()


func loop(n: String, on: bool, vol_db := 0.0, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = loops.get(n)
	if p == null:
		if not on:
			return
		p = AudioStreamPlayer.new()
		p.stream = streams[n]
		p.bus = "FX"
		add_child(p)
		loops[n] = p
	p.volume_db = vol_db
	p.pitch_scale = pitch
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()


## レーザーの発射音
func laser() -> void:
	if laser_stream == null:
		play("shot", -6.0, randf_range(0.94, 1.08))
		return
	var p: AudioStreamPlayer = laser_pool[laser_i]
	laser_i = (laser_i + 1) % laser_pool.size()
	if p.has_meta("tween"):
		var old: Tween = p.get_meta("tween")
		if old and old.is_valid():
			old.kill()
	p.stream = laser_stream
	p.volume_db = -5.0
	p.pitch_scale = randf_range(0.97, 1.04)
	p.play()
	var tw := create_tween()
	tw.tween_interval(0.22)
	tw.tween_property(p, "volume_db", -50.0, 0.2)
	tw.tween_callback(p.stop)
	p.set_meta("tween", tw)


## 無線の声を流す。id は VoiceLines の値
func voice(id: String) -> void:
	var path := "res://audio/voice/%s.wav" % id
	if not ResourceLoader.exists(path):
		return
	if voice_player == null:
		voice_player = AudioStreamPlayer.new()
		voice_player.bus = "Voice"
		add_child(voice_player)
	if voice_player.playing:
		voice_queue.append([id, Time.get_ticks_msec()])
		while voice_queue.size() > 2:
			voice_queue.pop_front()
		return
	voice_player.stream = load(path)
	voice_player.play()


func has_voice(key: String) -> bool:
	return VoiceLines.BY_TEXT.has(key)


func stop_voice() -> void:
	voice_queue.clear()
	if voice_player:
		voice_player.stop()


func stop_all_loops() -> void:
	for n in loops:
		(loops[n] as AudioStreamPlayer).stop()


## 一瞬の静寂。効果音バスを一時的に落とす
func duck(seconds: float) -> void:
	duck_t = seconds
	duck_total = seconds


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)


func tick(dt: float) -> void:
	if voice_player:
		if not voice_player.playing and not voice_queue.is_empty():
			var q: Array = voice_queue.pop_front()
			# 古くなったセリフは捨てる
			if Time.get_ticks_msec() - int(q[1]) < 5000:
				voice_player.stream = load("res://audio/voice/%s.wav" % q[0])
				voice_player.play()
		var target := -5.0 if voice_player.playing else 0.0
		voice_duck = move_toward(voice_duck, target, dt * 20.0)
		AudioServer.set_bus_volume_db(fx_bus, voice_duck)
	if duck_t > 0.0:
		duck_t -= dt
		AudioServer.set_bus_volume_db(sfx_bus, -60.0)
		if duck_t <= 0.0:
			AudioServer.set_bus_volume_db(sfx_bus, 0.0)
