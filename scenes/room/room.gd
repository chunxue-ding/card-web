extends Control
## 房间等待页：WS 实时渲染玩家/准备/机器人；房主开局；game_started 后显示占位 overlay
## （保持连接，断开会被后端判掉线代打）。断线显示重连条；离开房间=关闭 WS 回主页。

const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"

@onready var room_code_label: Label = $Background/Header/RoomCodeLabel
@onready var player_list: VBoxContainer = $Background/Center/PlayerList
@onready var ready_button: Button = $Background/Actions/ReadyButton
@onready var add_bot_button: Button = $Background/Actions/BotRow/AddBotButton
@onready var remove_bot_button: Button = $Background/Actions/BotRow/RemoveBotButton
@onready var start_button: Button = $Background/Actions/StartGameButton
@onready var status_label: Label = $Background/StatusLabel
@onready var disconnect_bar: Control = $Background/DisconnectBar
@onready var overlay: Control = $Background/GameStartedOverlay

var _socket: RoomSocket
var _view: Dictionary = {}
var _my_id := 0
var _room_code := ""


func _ready() -> void:
	_room_code = Session.pending_room_code
	Session.pending_room_code = ""
	_my_id = int(Session.user.get("id", 0))
	if _room_code == "":
		status_label.text = "缺少房间编号，请从主页进入"
		return
	room_code_label.text = "房间 %s" % _room_code
	_socket = RoomSocket.new()
	add_child(_socket)
	_socket.authenticated.connect(_on_authenticated)
	_socket.state_received.connect(_on_state)
	_socket.events_received.connect(_on_events)
	_socket.socket_error.connect(_on_socket_error)
	_socket.closed.connect(_on_closed)
	_socket.connect_room(Session.token, _room_code)


func _process(_delta: float) -> void:
	if _socket != null:
		_socket.poll()


func _on_authenticated() -> void:
	disconnect_bar.visible = false
	status_label.text = ""


func _on_state(view: Dictionary) -> void:
	_view = view
	_render()


func _on_events(events: Array, _version: int) -> void:
	for event in events:
		if str(event.get("event", "")) == "game_started":
			overlay.visible = true
			return


func _render() -> void:
	for child in player_list.get_children():
		child.queue_free()
	var players: Array = _view.get("players", [])
	var host_id := int(_view.get("host_id", 0))
	var is_host := host_id == _my_id
	var in_lobby := str(_view.get("status", "")) == "lobby"
	for player in players:
		var row := Label.new()
		var tags := ""
		if int(player.get("id", 0)) < 0:
			tags += "（机器人）"
		if int(player.get("id", 0)) == host_id:
			tags += "（房主）"
		if bool(player.get("ready", false)):
			tags += " ✓已准备"
		row.text = "%s%s" % [str(player.get("name", "")), tags]
		row.add_theme_font_size_override("font_size", 30)
		player_list.add_child(row)
	ready_button.text = "取消准备" if _is_ready(_my_id) else "准备"
	ready_button.disabled = not in_lobby
	add_bot_button.visible = is_host and in_lobby
	remove_bot_button.visible = is_host and in_lobby
	start_button.visible = is_host and in_lobby
	start_button.disabled = players.size() < 3


func _is_ready(player_id: int) -> bool:
	for player in _view.get("players", []):
		if int(player.get("id", 0)) == player_id:
			return bool(player.get("ready", false))
	return false


func _on_ready_pressed() -> void:
	_socket.set_ready(not _is_ready(_my_id))


func _on_add_bot_pressed() -> void:
	_socket.add_bot()


func _on_remove_bot_pressed() -> void:
	for player in _view.get("players", []):
		if int(player.get("id", 0)) < 0:
			_socket.remove_bot(int(player["id"]))
			return


func _on_start_pressed() -> void:
	start_button.disabled = true
	status_label.text = "正在开局…"
	_socket.start_game()


func _on_socket_error(message: String) -> void:
	status_label.text = message


func _on_closed() -> void:
	disconnect_bar.visible = true
	status_label.text = "房间连接已断开"


func _on_reconnect_pressed() -> void:
	disconnect_bar.visible = false
	status_label.text = "正在重新连接…"
	_socket.connect_room(Session.token, _room_code)


func _on_back_home_pressed() -> void:
	if _socket != null:
		_socket.close()
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		push_error("无法返回主页：%s" % error_string(error))
