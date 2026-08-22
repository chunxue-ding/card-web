extends Control
## 好友同玩入口：创建房间，或输入房间编号加入房间。

signal create_room_requested
signal join_room_requested(room_code: String)

const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"

@onready var name_label: Label = $Background/Header/NameLabel
@onready var balance_label: Label = $Background/Header/BalanceLabel
@onready var back_home_button: Button = $Background/Header/BackHomeButton
@onready var create_room_button: TextureButton = $Background/ActionCenter/Actions/CreateRoomButton
@onready var join_room_button: TextureButton = $Background/ActionCenter/Actions/JoinRoomButton
@onready var room_code_input: LineEdit = $Background/CodeCenter/CodePanel/RoomCodeInput
@onready var status_label: Label = $Background/StatusLabel

var _hover_tweens: Dictionary = {}


func _ready() -> void:
	var display_name := str(Session.user.get("name", ""))
	if display_name.is_empty():
		display_name = "游客" if Session.is_guest() else "玩家"
	name_label.text = display_name
	balance_label.text = _format_balance(int(Session.user.get("balance", 0)))
	for button in [create_room_button, join_room_button]:
		button.pivot_offset = button.size * 0.5
		button.mouse_entered.connect(_set_action_hover.bind(button, true))
		button.mouse_exited.connect(_set_action_hover.bind(button, false))


func _set_action_hover(button: TextureButton, hovered: bool) -> void:
	var previous: Tween = _hover_tweens.get(button)
	if previous != null and previous.is_valid():
		previous.kill()
	button.z_index = 1 if hovered else 0
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * (1.025 if hovered else 1.0), 0.14)
	tween.tween_property(button, "modulate", Color(1.16, 1.1, 1.22, 1.0) if hovered else Color.WHITE, 0.14)
	_hover_tweens[button] = tween


func _on_create_room_pressed() -> void:
	status_label.text = "正在创建好友房间…"
	create_room_requested.emit()


func _on_join_room_pressed() -> void:
	_join_room(room_code_input.text)


func _on_room_code_submitted(room_code: String) -> void:
	_join_room(room_code)


func _join_room(room_code: String) -> void:
	var normalized_code := room_code.strip_edges()
	if normalized_code.is_empty():
		status_label.text = "请输入房间编号"
		room_code_input.grab_focus()
		return
	status_label.text = "正在加入房间 %s…" % normalized_code
	join_room_requested.emit(normalized_code)


func _on_back_home_pressed() -> void:
	back_home_button.disabled = true
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		back_home_button.disabled = false
		push_error("无法返回主页：%s" % error_string(error))


func _format_balance(value: int) -> String:
	var digits := str(value)
	var formatted := ""
	while digits.length() > 3:
		formatted = ",%s%s" % [digits.right(3), formatted]
		digits = digits.left(-3)
	return digits + formatted
