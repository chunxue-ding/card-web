extends Node
## 背景音乐自动加载:登录/注册页循环播放克苏鲁氛围曲,进大厅淡出。

const AMBIENT_PATH := "res://assets/audio/cthulhu_ambient_30s.wav"
const VOLUME_DB := -12.0
const FADE_IN_SEC := 1.5
const FADE_OUT_SEC := 0.8
const SILENT_DB := -60.0

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "AmbientPlayer"
	_player.volume_db = SILENT_DB
	add_child(_player)
	var stream := load(AMBIENT_PATH) as AudioStreamWAV
	if stream == null:
		push_warning("背景音乐缺失:%s" % AMBIENT_PATH)
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_player.stream = stream


func play_ambient() -> void:
	if _player.stream == null or _player.playing:
		return
	_player.volume_db = SILENT_DB
	_player.play()
	var tween := create_tween()
	tween.tween_property(_player, "volume_db", VOLUME_DB, FADE_IN_SEC)


func stop() -> void:
	if not _player.playing:
		return
	var tween := create_tween()
	tween.tween_property(_player, "volume_db", SILENT_DB, FADE_OUT_SEC)
	tween.tween_callback(_player.stop)
