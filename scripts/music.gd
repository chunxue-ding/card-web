extends Node
## 背景音乐自动加载:登录/注册页循环播放克苏鲁氛围曲,游戏场景循环播放
## game.mp3,进大厅淡出。同一播放器按曲目切换,切歌即淡入。

const AMBIENT_PATH := "res://assets/audio/cthulhu_ambient_30s.wav"
const GAME_PATH := "res://assets/audio/game.mp3"
const VOLUME_DB := -12.0
const FADE_IN_SEC := 1.5
const FADE_OUT_SEC := 0.8
const SILENT_DB := -60.0

var _player: AudioStreamPlayer
var _fade_tween: Tween


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "AmbientPlayer"
	_player.volume_db = SILENT_DB
	add_child(_player)


func play_ambient() -> void:
	_play_track(AMBIENT_PATH)


func play_game() -> void:
	_play_track(GAME_PATH)


func stop() -> void:
	if not _player.playing:
		return
	_cancel_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", SILENT_DB, FADE_OUT_SEC)
	_fade_tween.tween_callback(_finish_stop.bind(_fade_tween))


func _play_track(path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("背景音乐缺失:%s" % path)
		return
	_enable_loop(stream)
	_cancel_fade()
	if _player.playing and _player.stream == stream:
		_fade_tween = create_tween()
		_fade_tween.tween_property(_player, "volume_db", VOLUME_DB, FADE_IN_SEC)
		return
	_player.stop()
	_player.stream = stream
	_player.volume_db = SILENT_DB
	_player.play()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_player, "volume_db", VOLUME_DB, FADE_IN_SEC)


func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


func _cancel_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


func _finish_stop(fade: Tween) -> void:
	if _fade_tween != fade:
		return
	_player.stop()
	_fade_tween = null
