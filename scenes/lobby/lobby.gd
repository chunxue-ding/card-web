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
const CONFIRM_TIMEOUT_SECONDS := 15
const CONFIRM_POLL_INTERVAL := 0.6

@onready var name_label: Label = $Background/Header/NameLabel
@onready var balance_label: Label = $Background/Header/BalanceLabel
@onready var avatar_icon: TextureRect = $Background/Header/AvatarFrame/AvatarIcon
@onready var logout_button: Button = $Background/Header/LogoutButton
@onready var quick_match_button: TextureButton = $Background/Actions/QuickMatchButton
@onready var quick_match_label: Label = $Background/Actions/QuickMatchButton/Label
@onready var friend_play_button: TextureButton = $Background/Actions/FriendPlayButton
@onready var status_label: Label = $Background/StatusLabel
@onready var match_confirmation: Control = $MatchConfirmation
@onready var match_dim: ColorRect = $MatchConfirmation/Dim
@onready var match_panel: TextureRect = $MatchConfirmation/Panel
@onready var match_state_label: Label = $MatchConfirmation/Panel/StateLabel
@onready var confirm_button: TextureButton = $MatchConfirmation/Panel/Buttons/ConfirmButton
@onready var decline_button: TextureButton = $MatchConfirmation/Panel/Buttons/DeclineButton

var player_count := DEFAULT_PLAYER_COUNT
var _hover_tweens: Dictionary = {}
var _matching := false
var _match_player_count := DEFAULT_PLAYER_COUNT
var _match_id := ""
var _confirmation_generation := 0
var _confirming := false
var _transitioning := false


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
			await _transition_to_room()
			return
		var match_status := str(res.get("status", ""))
		if match_status == "queued":
			status_label.text = "正在匹配 %d 人局…（队列第 %d 位）" % [_match_player_count, int(res.get("position", 0))]
		elif match_status == "found" or match_status == "starting":
			_show_match_confirmation(res)
			return
		elif match_status == "dropped":
			_stop_match(Endpoints.match_drop_message(str(res.get("reason", ""))))
			return
		elif match_status == "cancelled":
			var reason := str(res.get("reason", ""))
			_stop_match(Endpoints.card_message_for(reason) if not reason.is_empty() else "本次匹配已取消")
			return
		else:
			_stop_match("")
			return
	return


func _cancel_match() -> void:
	if not _match_id.is_empty():
		_on_match_decline_pressed()
		return
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
	_matching = false
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
		if _match_id.is_empty():
			Session.card().match_cancel(Session.token)  # fire-and-forget：尽力清服务端队列
		else:
			Session.card().match_decline(Session.token, _match_id)
	await Session.logout()
	var error := get_tree().change_scene_to_file(LOGIN_SCENE)
	if error != OK:
		push_error("无法返回登录场景：%s" % error_string(error))


func _goto_room() -> void:
	var error := get_tree().change_scene_to_file(ROOM_SCENE)
	if error != OK:
		_stop_match("无法进入房间")
		push_error("无法进入房间场景：%s" % error_string(error))


func _show_match_confirmation(res: Dictionary) -> void:
	_match_id = str(res.get("match_id", ""))
	if _match_id.is_empty():
		_stop_match("匹配信息异常，请重新匹配")
		return
	_confirmation_generation += 1
	var generation := _confirmation_generation
	_confirming = false
	confirm_button.disabled = false
	decline_button.disabled = false
	_update_confirmation_state(res, CONFIRM_TIMEOUT_SECONDS)
	match_confirmation.visible = true
	match_panel.pivot_offset = match_panel.size * 0.5
	match_panel.scale = Vector2.ONE * 0.9
	match_panel.modulate = Color(1, 1, 1, 0)
	match_dim.color = Color(0, 0, 0, 0)
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(match_panel, "scale", Vector2.ONE, 0.28)
	tween.tween_property(match_panel, "modulate", Color.WHITE, 0.2)
	tween.tween_property(match_dim, "color", Color(0, 0, 0, 0.72), 0.22)
	_run_confirmation_countdown(generation)


func _run_confirmation_countdown(generation: int) -> void:
	for seconds_left in range(CONFIRM_TIMEOUT_SECONDS, 0, -1):
		if generation != _confirmation_generation or not is_inside_tree() or not match_confirmation.visible:
			return
		if not _confirming:
			match_state_label.text = "已找到 %d 人局，请在 %d 秒内确认" % [_match_player_count, seconds_left]
		await get_tree().create_timer(1.0).timeout
	if generation != _confirmation_generation or not is_inside_tree() or not match_confirmation.visible:
		return
	if not _confirming:
		await _decline_match("确认超时，已返回主页")


func _update_confirmation_state(res: Dictionary, seconds_left := -1) -> void:
	var confirmed := int(res.get("confirmed", 0))
	var required := int(res.get("required", _match_player_count))
	if _confirming:
		match_state_label.text = "已确认，等待其他玩家…（%d/%d）" % [confirmed, required]
	elif seconds_left >= 0:
		match_state_label.text = "已找到 %d 人局，请在 %d 秒内确认" % [_match_player_count, seconds_left]
	else:
		match_state_label.text = "已找到 %d 人局，请确认是否进入" % _match_player_count


func _on_match_confirm_pressed() -> void:
	if _confirming or _transitioning or _match_id.is_empty():
		return
	_confirming = true
	confirm_button.disabled = true
	decline_button.disabled = true
	match_state_label.text = "已确认，等待其他玩家…"
	var generation := _confirmation_generation
	while _matching and generation == _confirmation_generation:
		var res: Variant = await Session.card().match_confirm(Session.token, _match_id)
		if not is_inside_tree() or generation != _confirmation_generation:
			return
		if res is ApiError:
			_confirming = false
			confirm_button.disabled = false
			decline_button.disabled = false
			match_state_label.text = res.message
			return
		if res.has("room_code"):
			Session.pending_room_code = str(res["room_code"])
			await _transition_to_room()
			return
		var state := str(res.get("status", ""))
		if state == "cancelled":
			await _hide_match_confirmation()
			_stop_match(Endpoints.card_message_for(str(res.get("reason", ""))))
			return
		if state == "dropped":
			await _hide_match_confirmation()
			_stop_match(Endpoints.match_drop_message(str(res.get("reason", ""))))
			return
		_update_confirmation_state(res)
		await get_tree().create_timer(CONFIRM_POLL_INTERVAL).timeout


func _on_match_decline_pressed() -> void:
	await _decline_match("已拒绝本次对局")


func _decline_match(message: String) -> void:
	if _transitioning or _match_id.is_empty():
		return
	var declined_match_id := _match_id
	_confirmation_generation += 1
	_matching = false
	_confirming = false
	confirm_button.disabled = true
	decline_button.disabled = true
	match_state_label.text = "正在返回主页…"
	var res: Variant = await Session.card().match_decline(Session.token, declined_match_id)
	if not is_inside_tree():
		return
	if not (res is ApiError) and res.has("room_code"):
		Session.pending_room_code = str(res["room_code"])
		await _transition_to_room()
		return
	await _hide_match_confirmation()
	_match_id = ""
	_stop_match(res.message if res is ApiError else message)


func _hide_match_confirmation() -> void:
	if not match_confirmation.visible:
		return
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(match_panel, "scale", Vector2.ONE * 0.94, 0.16)
	tween.tween_property(match_panel, "modulate", Color(1, 1, 1, 0), 0.16)
	tween.tween_property(match_dim, "color", Color(0, 0, 0, 0), 0.16)
	await tween.finished
	match_confirmation.visible = false


func _transition_to_room() -> void:
	if _transitioning:
		return
	_transitioning = true
	_matching = false
	_confirmation_generation += 1
	confirm_button.disabled = true
	decline_button.disabled = true
	match_state_label.text = "全员已确认，即将进入对局…"
	if match_confirmation.visible:
		var tween := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(match_panel, "scale", Vector2.ONE * 1.04, 0.36)
		tween.tween_property(match_panel, "modulate", Color(1, 1, 1, 0), 0.36)
		tween.tween_property(match_dim, "color", Color(0, 0, 0, 1), 0.36)
		await tween.finished
	_goto_room()


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
