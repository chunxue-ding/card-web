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
@onready var game_board: GameBoard = $Background/GameStartedOverlay/GameBoard

var _socket: RoomSocket
var _view: Dictionary = {}
var _my_id := 0
var _room_code := ""
var _leaving := false


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
	status_label.text = "连接房间服务器…"
	get_tree().create_timer(8.0).timeout.connect(_check_socket_connected)


func _check_socket_connected() -> void:
	if _socket == null or _socket.is_authed():
		return
	disconnect_bar.visible = true
	status_label.text = "连接房间服务器失败，请改用 Safari/Chrome 打开本页"


func _process(_delta: float) -> void:
	if _socket != null:
		_socket.poll()


func _on_authenticated() -> void:
	disconnect_bar.visible = false
	status_label.text = ""


func _on_state(view: Dictionary) -> void:
	var previous_status := str(_view.get("status", ""))
	var next_status := str(view.get("status", ""))
	var starts_new_round := (
		next_status == "playing"
		and previous_status in ["lobby", "round_complete", "finished"]
	)
	if starts_new_round:
		game_board.arm_new_round_animation()
	elif previous_status != "":
		var previous_public_cards := (_view.get("community_cards", []) as Array).size()
		var next_public_cards := (view.get("community_cards", []) as Array).size()
		if next_public_cards > previous_public_cards:
			game_board.arm_community_animation()
	_view = view
	_render()


func _on_events(events: Array, _version: int) -> void:
	game_board.show_events(events)
	for event in events:
		if str(event.get("event", "")) == "game_started":
			overlay.visible = true


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
	var required_players := clampi(int(_view.get("max_players", 3)), 3, 4)
	start_button.disabled = players.size() < required_players
	var status := str(_view.get("status", ""))
	if status != "" and status != "lobby":
		overlay.visible = true
		game_board.apply_state(_view, _my_id)
	else:
		overlay.visible = false


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


func _on_prediction_submitted(rank: int) -> void:
	if _socket == null:
		return
	# 选择排名时已经 claim；提交只负责确认，避免移动端一次点击连续
	# 发送重复 claim_chip 后再 confirm_phase。
	_socket.confirm_phase()


func _on_rank_selected(rank: int) -> void:
	if _socket == null:
		return
	_socket.claim_chip(rank)


func _on_next_round_requested() -> void:
	if _socket != null:
		_socket.next_round()


func _on_rematch_requested() -> void:
	if _socket != null:
		_socket.rematch()


func _on_quick_match_requested() -> void:
	_leaving = true
	if _socket != null:
		_socket.close()
	Session.pending_quick_match = true
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		push_error("无法返回主页：%s" % error_string(error))


func _on_socket_error(message: String) -> void:
	if message == RoomSocket.CONNECT_FAIL_MESSAGE:
		disconnect_bar.visible = true
	status_label.text = message
	_render()


func _on_closed() -> void:
	if _leaving:
		return
	disconnect_bar.visible = true
	status_label.text = "房间连接已断开"


func _on_reconnect_pressed() -> void:
	disconnect_bar.visible = false
	status_label.text = "正在重新连接…"
	_socket.connect_room(Session.token, _room_code)


func _on_back_home_pressed() -> void:
	_leaving = true
	if _socket != null:
		_socket.close()
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		push_error("无法返回主页：%s" % error_string(error))
