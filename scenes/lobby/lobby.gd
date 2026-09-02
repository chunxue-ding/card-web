extends Control
## 登录后的主页：选择对局人数，并用于对应人数的快速匹配或好友建房。

signal game_mode_selected(mode: String, player_count: int)

const LOGIN_SCENE := "res://scenes/login/login.tscn"
const FRIEND_ROOM_SCENE := "res://scenes/friend_room/friend_room.tscn"
const ROOM_SCENE := "res://scenes/room/room.tscn"
const QUICK_MATCH_LABEL_TEXT := "快速匹配"
const CANCEL_MATCH_LABEL_TEXT := "取消匹配"
const DEFAULT_PLAYER_COUNT := 3
const SUPPORTED_PLAYER_COUNTS := [3, 4]

@onready var name_label: Label = $Background/Header/NameLabel
@onready var balance_label: Label = $Background/Header/BalanceLabel
@onready var avatar_icon: TextureRect = $Background/Header/AvatarFrame/AvatarIcon
@onready var logout_button: Button = $Background/Header/LogoutButton
@onready var quick_match_button: TextureButton = $Background/Actions/QuickMatchButton
@onready var quick_match_label: Label = $Background/Actions/QuickMatchButton/Label
@onready var friend_play_button: TextureButton = $Background/Actions/FriendPlayButton
@onready var status_label: Label = $Background/StatusLabel

var player_count := DEFAULT_PLAYER_COUNT
var _hover_tweens: Dictionary = {}
var _matching := false
var _match_player_count := DEFAULT_PLAYER_COUNT


func _ready() -> void:
	Music.stop()
	if Session.pending_player_count in SUPPORTED_PLAYER_COUNTS:
		player_count = Session.pending_player_count
	_render_user()
	_refresh_user()
	for count in range(3, 7):
		var button := get_node("Background/CountCenter/PlayerCountPanel/Count%dButton" % count) as Button
		button.pressed.connect(_on_player_count_pressed.bind(count))
		button.button_pressed = count == DEFAULT_PLAYER_COUNT
		button.disabled = count not in SUPPORTED_PLAYER_COUNTS
		if count not in SUPPORTED_PLAYER_COUNTS:
			button.modulate = Color(0.58, 0.58, 0.58, 0.72)
			(get_node("Background/CountCenter/PlayerCountPanel/Slot%d" % count) as TextureRect).modulate = Color(0.48, 0.48, 0.48, 0.62)
		else:
			button.modulate = Color.WHITE
			(get_node("Background/CountCenter/PlayerCountPanel/Slot%d" % count) as TextureRect).modulate = Color.WHITE
	_setup_action_feedback(quick_match_button)
	_setup_action_feedback(friend_play_button)
	if Session.pending_quick_match:
		Session.pending_quick_match = false
		_on_quick_match_pressed()


func _render_user() -> void:
	var display_name := str(Session.user.get("name", ""))
	if display_name.is_empty():
		display_name = "游客" if Session.is_guest() else "玩家"
	name_label.text = display_name
	balance_label.text = _format_balance(int(Session.user.get("balance", 0)))
	_set_avatar(int(Session.user.get("avatar", 0)), Session.is_guest())


func _set_avatar(avatar_id: int, guest := false) -> void:
	var path := Avatars.user_path(avatar_id, guest)
	avatar_icon.texture = load(path) if not path.is_empty() else null
	avatar_icon.visible = not path.is_empty()


## 回大厅时重拉余额,对局派彩/扣费后展示不再是登录时的旧快照。
func _refresh_user() -> void:
	var err: ApiError = await Session.refresh_me()
	if err != null or not is_inside_tree():
		return
	_render_user()


func _on_player_count_pressed(count: int) -> void:
	if _matching or count not in SUPPORTED_PLAYER_COUNTS:
		return
	player_count = count
	status_label.text = ""


func _on_quick_match_pressed() -> void:
	if _matching:
		_cancel_match()
	else:
		_start_match()


func _start_match() -> void:
	_set_match_mode(true)
	_match_player_count = player_count
	Session.pending_player_count = _match_player_count
	game_mode_selected.emit("quick_match", _match_player_count)
	status_label.text = "正在匹配 %d 人局…" % _match_player_count
	while _matching:
		var res: Variant = await Session.card().match_wait(Session.token, _match_player_count)
		if not is_inside_tree():
			return
		if res is ApiError:
			if res.is_network_error:
				status_label.text = "无法连接匹配服务，正在重试…"
				await get_tree().create_timer(2.0).timeout
				if not is_inside_tree():
					return
				continue
			_stop_match(res.message)
			return
		if res.has("room_code"):
			Session.pending_room_code = str(res["room_code"])
			_goto_room()
			return
		var match_status := str(res.get("status", ""))
		if match_status == "queued":
			status_label.text = "正在匹配 %d 人局…（队列第 %d 位）" % [_match_player_count, int(res.get("position", 0))]
		elif match_status == "dropped":
			_stop_match(Endpoints.match_drop_message(str(res.get("reason", ""))))
			return
		else:
			_stop_match("")
			return
	return


func _cancel_match() -> void:
	_matching = false
	_set_match_mode(false)
	status_label.text = "正在取消匹配…"
	var res: Variant = await Session.card().match_cancel(Session.token)
	if not is_inside_tree():
		return
	if res is ApiError:
		status_label.text = res.message
		return
	status_label.text = ""


func _stop_match(message: String) -> void:
	_set_match_mode(false)
	status_label.text = message


func _set_match_mode(matching: bool) -> void:
	_matching = matching
	quick_match_label.text = CANCEL_MATCH_LABEL_TEXT if matching else QUICK_MATCH_LABEL_TEXT
	friend_play_button.disabled = matching
	for count in range(3, 7):
		(get_node("Background/CountCenter/PlayerCountPanel/Count%dButton" % count) as Button).disabled = matching or count not in SUPPORTED_PLAYER_COUNTS


func _on_friend_play_pressed() -> void:
	Session.pending_player_count = player_count
	game_mode_selected.emit("friend_play", player_count)
	var error := get_tree().change_scene_to_file(FRIEND_ROOM_SCENE)
	if error != OK:
		status_label.text = "无法打开好友同玩页面"
		push_error("无法打开好友同玩场景：%s" % error_string(error))


func _on_logout_pressed() -> void:
	logout_button.disabled = true
	if _matching:
		Session.card().match_cancel(Session.token)  # fire-and-forget：不 await，尽力清服务端队列
	await Session.logout()
	var error := get_tree().change_scene_to_file(LOGIN_SCENE)
	if error != OK:
		push_error("无法返回登录场景：%s" % error_string(error))


func _goto_room() -> void:
	var error := get_tree().change_scene_to_file(ROOM_SCENE)
	if error != OK:
		_stop_match("无法进入房间")
		push_error("无法进入房间场景：%s" % error_string(error))


func _setup_action_feedback(button: TextureButton) -> void:
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


func _format_balance(value: int) -> String:
	var digits := str(value)
	var formatted := ""
	while digits.length() > 3:
		formatted = ",%s%s" % [digits.right(3), formatted]
		digits = digits.left(-3)
	return digits + formatted
