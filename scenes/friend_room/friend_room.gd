extends Control
## 好友同玩入口：创建房间，或输入房间编号加入房间（接 card 后端，成功后进房间等待页）。

signal create_room_requested
signal join_room_requested(room_code: String)

const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"
const ROOM_SCENE := "res://scenes/room/room.tscn"
const ROOM_CODE_PATTERN := "^[A-Z0-9]{6}$"

@onready var name_label: Label = $Background/Header/NameLabel
@onready var balance_label: Label = $Background/Header/BalanceLabel
@onready var back_home_button: Button = $Background/Header/BackHomeButton
@onready var create_room_button: TextureButton = $Background/ActionCenter/Actions/CreateRoomButton
@onready var join_room_button: TextureButton = $Background/ActionCenter/Actions/JoinRoomButton
@onready var room_code_input: LineEdit = $Background/CodeCenter/CodePanel/RoomCodeInput
@onready var status_label: Label = $Background/StatusLabel

var _hover_tweens: Dictionary = {}
var _busy := false


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


func _on_create_room_pressed() -> void:
	if _busy:
		return
	var max_players := Session.pending_player_count
	if max_players != 3:
		max_players = 3
	_busy = true
	create_room_button.disabled = true
	join_room_button.disabled = true
	status_label.text = "正在创建好友房间…"
	create_room_requested.emit()
	var res: Variant = await Session.card().create_room(Session.token, max_players)
	if not is_inside_tree():
		return
	_busy = false
	create_room_button.disabled = false
	join_room_button.disabled = false
	if res is ApiError:
		status_label.text = res.message
		return
	Session.pending_room_code = str(res.get("code", ""))
	var error := get_tree().change_scene_to_file(ROOM_SCENE)
	if error != OK:
		status_label.text = "无法进入房间"
		push_error("无法进入房间场景：%s" % error_string(error))


func _on_join_room_pressed() -> void:
	_join_room(room_code_input.text)


func _on_room_code_submitted(room_code: String) -> void:
	_join_room(room_code)


func _join_room(room_code: String) -> void:
	if _busy:
		return
	var normalized := room_code.strip_edges().to_upper()
	if normalized.is_empty():
		status_label.text = "请输入房间编号"
		room_code_input.grab_focus()
		return
	var re := RegEx.new()
	if re.compile(ROOM_CODE_PATTERN) != OK or re.search(normalized) == null:
		status_label.text = "房间编号为 6 位字母或数字"
		room_code_input.grab_focus()
		return
	_busy = true
	create_room_button.disabled = true
	join_room_button.disabled = true
	status_label.text = "正在加入房间 %s…" % normalized
	join_room_requested.emit(normalized)
	var res: Variant = await Session.card().join_room(Session.token, normalized)
	if not is_inside_tree():
		return
	_busy = false
	create_room_button.disabled = false
	join_room_button.disabled = false
	if res is ApiError:
		status_label.text = res.message
		return
	Session.pending_room_code = normalized
	var error := get_tree().change_scene_to_file(ROOM_SCENE)
	if error != OK:
		status_label.text = "无法进入房间"
		push_error("无法进入房间场景：%s" % error_string(error))


func _on_back_home_pressed() -> void:
	back_home_button.disabled = true
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		back_home_button.disabled = false
		push_error("无法返回主页：%s" % error_string(error))


func _set_action_hover(button: TextureButton, hovered: bool) -> void:
	var previous: Tween = _hover_tweens.get(button)
	if previous != null and previous.is_valid():
		previous.kill()
	button.z_index = 1 if hovered else 0
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * (1.025 if hovered else 1.0), 0.14)
	tween.tween_property(button, "modulate", Color(1.16, 1.1, 1.22, 1.0) if hovered else Color.WHITE, 0.14)
	_hover_tweens[button] = tween


func _format_balance(value: int) -> String:
	var digits := str(value)
	var formatted := ""
	while digits.length() > 3:
		formatted = ",%s%s" % [digits.right(3), formatted]
		digits = digits.left(-3)
	return digits + formatted
