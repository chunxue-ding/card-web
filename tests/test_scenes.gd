extends SceneTree
## 场景接线冒烟：实例化各场景触发 _ready，验证 @onready 节点路径与按钮回调存在
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd

const Helper = preload("res://tests/test_helper.gd")

class PredictionSocket extends RoomSocket:
	var claim_count := 0
	var confirm_count := 0

	func claim_chip(_rank: int) -> void:
		claim_count += 1

	func confirm_phase() -> void:
		confirm_count += 1

var h := Helper.new()


func _initialize() -> void:
	_check_login()
	_check_register()
	await _check_profile()
	await _check_lobby()
	await _check_friend_room()
	await _check_room()
	h.finish(self)


func _check_profile() -> void:
	var scene := load("res://scenes/profile/profile.tscn") as PackedScene
	if scene == null:
		h.check(false, "profile 场景可加载")
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	await process_frame
	var grid := page.get_node("Background/Center/VBox/AvatarGrid") as GridContainer
	h.check(grid.get_child_count() == 6, "profile 六个头像按钮")
	h.check((page.get_node("Background") as TextureRect).texture.resource_path.ends_with("用户名和头像设置背景图.png"), "profile 使用新增背景素材")
	h.check((page.get_node("Background/Center/PanelFrame") as TextureRect).texture is AtlasTexture, "profile 使用裁剪后的档案面板")
	var with_texture := 0
	for index in 6:
		var button := grid.get_node("Avatar%d" % (index + 1)) as TextureButton
		if button.texture_normal != null and button.get_node_or_null("AvatarIcon") != null:
			with_texture += 1
	h.check(with_texture == 6, "profile 头像按钮全部绑定素材")
	h.check(page.get_node("Background/Center/VBox/NameInput") is LineEdit, "profile 昵称输入框存在")
	h.check(page.has_method("_select_avatar"), "profile 头像选择回调存在")
	h.check(page.has_method("_on_save_pressed"), "profile 保存回调存在")
	page.get_node("Background/Center/VBox/AvatarGrid/Avatar3").pressed.emit()
	h.check(not (page.get_node("Background/Center/VBox/AvatarGrid/Avatar3") as TextureButton).modulate.is_equal_approx(Color.WHITE), "profile 选中头像高亮")
	page.queue_free()


func _check_login() -> void:
	var scene := load("res://scenes/login/login.tscn") as PackedScene
	if scene == null:
		h.check(false, "login 场景可加载")
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	h.check(page.get_node_or_null("Background/Center/VBox/ErrorLabel") != null, "login ErrorLabel 存在")
	var login_input := page.get_node("Background/Center/VBox/EmailInput") as LineEdit
	h.check(login_input.get_theme_color("font_color", login_input.theme_type_variation).get_luminance() < 0.3, "login 输入文字使用深色高对比字体")
	h.check(page.has_method("_on_login_pressed"), "login 登录回调存在")
	h.check(page.has_method("_on_guest_pressed"), "login 游客回调存在")
	h.check(page.has_method("_on_create_account_pressed"), "login 新建账号回调存在")
	page.queue_free()


func _check_register() -> void:
	var scene := load("res://scenes/register/register.tscn") as PackedScene
	if scene == null:
		h.check(false, "register 场景可加载")
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	h.check(page.get_node_or_null("Background/Center/VBox/ErrorLabel") != null, "register ErrorLabel 存在")
	var register_input := page.get_node("Background/Center/VBox/AccountInput") as LineEdit
	h.check(register_input.get_theme_color("font_color", register_input.theme_type_variation).get_luminance() < 0.3, "register 输入文字使用深色高对比字体")
	h.check(page.has_method("_on_register_pressed"), "register 注册回调存在")
	h.check(page.has_method("_on_login_account_pressed"), "register 返回登录回调存在")
	page.queue_free()


func _check_lobby() -> void:
	var scene := load("res://scenes/lobby/lobby.tscn") as PackedScene
	if scene == null:
		h.check(false, "lobby 场景可加载")
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	await process_frame
	h.check(page.get_node_or_null("Background/Header/LogoutButton") != null, "lobby LogoutButton 存在")
	h.check(page.get_node_or_null("Background/Actions/QuickMatchButton") != null, "lobby 快速匹配按钮存在")
	h.check(page.get_node_or_null("Background/Actions/FriendPlayButton") != null, "lobby 好友同玩按钮存在")
	h.check(page.get_node_or_null("Background/CountCenter/PlayerCountPanel/Count4Button") != null, "lobby 人数选择存在")
	page._set_avatar(2)
	var lobby_avatar := page.get_node("Background/Header/AvatarFrame/AvatarIcon") as TextureRect
	h.check(lobby_avatar.visible and lobby_avatar.texture != null, "lobby 用户头像显示在头像框内")
	page._set_avatar(0, true)
	h.check(lobby_avatar.texture.resource_path.ends_with("克苏鲁游客头像.png"), "lobby 游客显示专属头像")
	page._set_avatar(2)
	h.check(lobby_avatar.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "lobby 用户头像保持比例居中")
	h.check((load("res://scenes/lobby/lobby.tscn") as PackedScene).instantiate().get_node("Background/Header/AvatarFrame/AvatarIcon").texture != null, "lobby 2D 编辑器提供头像预览")
	var lobby_font := page.get_node("Background/Actions/QuickMatchButton/Label").get_theme_font("font") as Font
	h.check(lobby_font.has_char("中".unicode_at(0)), "lobby 局部字体包含中文字形")
	h.check(page.has_method("_on_logout_pressed"), "lobby 登出回调存在")
	h.check(page.has_method("_on_quick_match_pressed"), "lobby 快速匹配回调存在")
	h.check(page.has_method("_on_friend_play_pressed"), "lobby 好友同玩回调存在")
	h.check(page.has_method("_set_action_hover"), "lobby 操作按钮悬停反馈存在")
	var confirmation := page.get_node_or_null("MatchConfirmation") as Control
	h.check(confirmation != null and not confirmation.visible, "lobby 匹配成功确认框存在且默认隐藏")
	h.check(page.get_node_or_null("MatchConfirmation/Panel/Buttons/ConfirmButton") != null, "lobby 匹配确认按钮存在")
	h.check(page.get_node_or_null("MatchConfirmation/Panel/Buttons/DeclineButton") != null, "lobby 匹配拒绝按钮存在")
	h.check(page.has_method("_on_match_confirm_pressed") and page.has_method("_on_match_decline_pressed"), "lobby 匹配确认与拒绝回调存在")
	h.check(page.has_method("_transition_to_room"), "lobby 确认后平滑入场过渡存在")
	var count3 := page.get_node("Background/CountCenter/PlayerCountPanel/Count3Button") as Button
	var count6 := page.get_node("Background/CountCenter/PlayerCountPanel/Count6Button") as Button
	var count4 := page.get_node("Background/CountCenter/PlayerCountPanel/Count4Button") as Button
	h.check(page.player_count == 3 and count3.button_pressed and not count3.disabled, "lobby 默认选择 3 人模式")
	h.check(not count4.disabled, "lobby 开放 4 人好友房模式")
	h.check(count6.disabled and count6.modulate.a < 1.0, "lobby 5 至 6 人模式置灰禁用")
	count4.pressed.emit()
	h.check(page.player_count == 4, "lobby 可选择 4 人模式")
	count6.pressed.emit()
	h.check(page.player_count == 4, "lobby 禁用人数不能改变对局人数")
	page.get_node("Background/Actions/QuickMatchButton").pressed.emit()
	h.check(int(page.get("_match_player_count")) == 4, "lobby 快速匹配进入所选 4 人队列")
	h.check(page.has_method("_set_match_mode"), "lobby 匹配态切换存在")
	page.queue_free()
	await process_frame
	# 等待快速匹配长轮询请求结束（真实后端在跑时 /match 会占用共享 ApiClient，同帧发
	# 起其它请求会被单飞守卫拒绝），避免 friend_room 加入用例与环境相关的竞态。
	await create_timer(1.0).timeout


func _check_friend_room() -> void:
	var scene := load("res://scenes/friend_room/friend_room.tscn") as PackedScene
	if scene == null:
		h.check(false, "friend_room 场景可加载")
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	await process_frame
	h.check(page.get_node_or_null("Background/Header/BackHomeButton") != null, "friend_room 返回主页按钮存在")
	h.check(page.get_node_or_null("Background/ActionCenter/Actions/CreateRoomButton") != null, "friend_room 创建按钮存在")
	h.check(page.get_node_or_null("Background/ActionCenter/Actions/JoinRoomButton") != null, "friend_room 加入按钮存在")
	h.check(page.get_node_or_null("Background/CodeCenter/CodePanel/RoomCodeInput") != null, "friend_room 房间编号输入框存在")
	page._set_avatar(3)
	var friend_avatar := page.get_node("Background/Header/AvatarFrame/AvatarIcon") as TextureRect
	h.check(friend_avatar.visible and friend_avatar.texture != null, "friend_room 用户头像显示在头像框内")
	page._set_avatar(0, true)
	h.check(friend_avatar.texture.resource_path.ends_with("克苏鲁游客头像.png"), "friend_room 游客显示专属头像")
	page._set_avatar(3)
	h.check(friend_avatar.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "friend_room 用户头像保持比例居中")
	h.check((load("res://scenes/friend_room/friend_room.tscn") as PackedScene).instantiate().get_node("Background/Header/AvatarFrame/AvatarIcon").texture != null, "friend_room 2D 编辑器提供头像预览")
	var friend_room_font := page.get_node("Background/ActionCenter/Actions/CreateRoomButton/Label").get_theme_font("font") as Font
	h.check(friend_room_font.has_char("中".unicode_at(0)), "friend_room 局部字体包含中文字形")
	h.check(page.has_method("_on_create_room_pressed"), "friend_room 创建回调存在")
	h.check(page.has_method("_on_join_room_pressed"), "friend_room 加入回调存在")
	h.check(page.has_method("_on_back_home_pressed"), "friend_room 返回主页回调存在")
	h.check(page.has_method("_set_action_hover"), "friend_room 按钮悬停反馈存在")
	page.get_node("Background/ActionCenter/Actions/JoinRoomButton").pressed.emit()
	h.check(page.get_node("Background/StatusLabel").text == "请输入房间编号", "friend_room 空编号会提示")
	page.get_node("Background/CodeCenter/CodePanel/RoomCodeInput").text = "ABCD12"
	page.get_node("Background/ActionCenter/Actions/JoinRoomButton").pressed.emit()
	h.check("ABCD12" in page.get_node("Background/StatusLabel").text, "friend_room 加入会读取编号")
	# 等待上一条 join 请求落地（真实后端会快速返回 404 并释放单飞锁），避免
	# 下一个用例仍在忙态而被跳过。
	await create_timer(1.0).timeout
	page.get_node("Background/CodeCenter/CodePanel/RoomCodeInput").text = "abc12"
	page._on_join_room_pressed()
	h.check("房间编号为 6 位字母或数字" in page.get_node("Background/StatusLabel").text, "friend_room 非法编号被拒绝")
	h.check(page._busy == false, "friend_room 校验失败不进入忙态")
	page.queue_free()


func _check_room() -> void:
	var scene := load("res://scenes/room/room.tscn") as PackedScene
	if scene == null:
		h.check(false, "room 场景可加载")
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	await process_frame
	h.check(page.get_node_or_null("Background/Header/RoomCodeLabel") != null, "room 房间号标签存在")
	h.check(page.get_node_or_null("Background/Center/PlayerList") != null, "room 玩家列表存在")
	h.check(page.get_node_or_null("Background/Actions/ReadyButton") != null, "room 准备按钮存在")
	h.check(page.get_node_or_null("Background/Actions/StartGameButton") != null, "room 开始按钮存在")
	h.check(page.get_node_or_null("Background/GameStartedOverlay") != null, "room 开局 overlay 存在")
	h.check(page.get_node_or_null("Background/GameStartedOverlay/GameBoard") != null, "room 三/四人游戏界面存在")
	var room_font := page.get_node("Background/Header/RoomCodeLabel").get_theme_font("font") as Font
	h.check(room_font.has_char("中".unicode_at(0)), "room 默认字体包含中文字形")
	h.check(page.has_method("_on_ready_pressed"), "room 准备回调存在")
	h.check(page.has_method("_on_start_pressed"), "room 开始回调存在")
	h.check(page.has_method("_on_reconnect_pressed"), "room 重连回调存在")
	h.check(page.has_method("_on_prediction_submitted"), "room 排名预测回调存在")
	h.check(page.has_method("_on_rank_selected"), "room 选择排名回调存在")
	h.check(page.has_method("_on_rematch_requested"), "room 再来一局回调存在")
	page._my_id = 1
	page._on_state({
		"status": "lobby", "host_id": 1, "max_players": 4,
		"players": [{"id": 1, "name": "本人"}, {"id": 2, "name": "甲"}, {"id": 3, "name": "乙"}],
	})
	h.check(page.get_node("Background/Actions/StartGameButton").disabled, "room 四人房未满四人不能开局")
	page._on_state({
		"status": "lobby", "host_id": 1, "max_players": 4,
		"players": [{"id": 1, "name": "本人"}, {"id": 2, "name": "甲"}, {"id": 3, "name": "乙"}, {"id": 4, "name": "丙"}],
	})
	h.check(not page.get_node("Background/Actions/StartGameButton").disabled, "room 四人房满四人后允许开局")
	page._on_state({"status": "playing", "players": []})
	h.check(page.get_node("Background/GameStartedOverlay").visible, "room 非 lobby 态显示开局 overlay")
	page._on_state({"status": "lobby", "players": []})
	h.check(not page.get_node("Background/GameStartedOverlay").visible, "room 回到大厅态隐藏开局 overlay")
	page._on_state({
		"status": "playing",
		"phase": "white",
		"players": [
			{"id": 2, "name": "对手甲", "hole_cards": []},
			{"id": 3, "name": "对手乙", "hole_cards": []},
			{"id": 1, "name": "本人", "hole_cards": [{"rank": 5, "suit": 0}, {"rank": 3, "suit": 3}]},
		],
	})
	var board := page.get_node("Background/GameStartedOverlay/GameBoard") as GameBoard
	h.check(bool(board.get("_dealing")), "room 状态先于事件到达时仍会启动发牌动画")
	var prediction_socket := PredictionSocket.new()
	page.add_child(prediction_socket)
	page._socket = prediction_socket
	page._on_rank_selected(2)
	page._on_prediction_submitted(2)
	h.check(prediction_socket.claim_count == 1 and prediction_socket.confirm_count == 1, "room 预测选择和提交各发送一次 claim/confirm，不重复抢占排名")
	page._on_state({"version": 20, "status": "lobby", "players": []})
	page._on_state({"version": 19, "status": "playing", "players": []})
	h.check(int(page._view.get("version", 0)) == 20, "room 丢弃并发广播中后到达的旧版本快照")
	page.queue_free()
