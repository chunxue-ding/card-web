extends Control
## 登录后的主页：选择对局人数，并进入快速匹配或好友同玩流程。

signal game_mode_selected(mode: String, player_count: int)

const LOGIN_SCENE := "res://scenes/login/login.tscn"

@onready var name_label: Label = $Background/Header/NameLabel
@onready var balance_label: Label = $Background/Header/BalanceLabel
@onready var logout_button: Button = $Background/Header/LogoutButton
@onready var quick_match_button: TextureButton = $Background/Actions/QuickMatchButton
@onready var friend_play_button: TextureButton = $Background/Actions/FriendPlayButton
@onready var status_label: Label = $Background/StatusLabel

var player_count := 4


func _ready() -> void:
	var display_name := str(Session.user.get("name", ""))
	if display_name.is_empty():
		display_name = "游客" if Session.is_guest() else "玩家"
	name_label.text = display_name
	balance_label.text = "◉ %s" % _format_balance(int(Session.user.get("balance", 0)))
	for count in range(3, 7):
		var button := get_node("Background/CountCenter/PlayerCountPanel/Count%dButton" % count) as Button
		button.pressed.connect(_on_player_count_pressed.bind(count))
	_setup_action_feedback(quick_match_button)
	_setup_action_feedback(friend_play_button)


func _on_player_count_pressed(count: int) -> void:
	player_count = count
	status_label.text = ""


func _on_quick_match_pressed() -> void:
	status_label.text = "正在准备 %d 人快速匹配…" % player_count
	game_mode_selected.emit("quick_match", player_count)


func _on_friend_play_pressed() -> void:
	status_label.text = "正在创建 %d 人好友对局…" % player_count
	game_mode_selected.emit("friend_play", player_count)


func _on_logout_pressed() -> void:
	logout_button.disabled = true
	await Session.logout()
	var error := get_tree().change_scene_to_file(LOGIN_SCENE)
	if error != OK:
		push_error("无法返回登录场景：%s" % error_string(error))


func _setup_action_feedback(button: TextureButton) -> void:
	button.mouse_entered.connect(func() -> void: button.modulate = Color(1.08, 1.04, 1.12, 1))
	button.mouse_exited.connect(func() -> void: button.modulate = Color.WHITE)
	button.button_down.connect(func() -> void: button.modulate = Color(0.78, 0.72, 0.82, 1))
	button.button_up.connect(func() -> void: button.modulate = Color(1.08, 1.04, 1.12, 1) if button.is_hovered() else Color.WHITE)


func _format_balance(value: int) -> String:
	var digits := str(value)
	var formatted := ""
	while digits.length() > 3:
		formatted = ",%s%s" % [digits.right(3), formatted]
		digits = digits.left(-3)
	return digits + formatted
