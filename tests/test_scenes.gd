extends SceneTree
## 场景接线冒烟：实例化各场景触发 _ready，验证 @onready 节点路径与按钮回调存在
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd

const Helper = preload("res://tests/test_helper.gd")

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
	var lobby_font := page.get_node("Background/Actions/QuickMatchButton/Label").get_theme_font("font") as Font
	h.check(lobby_font.has_char("中".unicode_at(0)), "lobby 局部字体包含中文字形")
	h.check(page.has_method("_on_logout_pressed"), "lobby 登出回调存在")
	h.check(page.has_method("_on_quick_match_pressed"), "lobby 快速匹配回调存在")
	h.check(page.has_method("_on_friend_play_pressed"), "lobby 好友同玩回调存在")
	h.check(page.has_method("_set_action_hover"), "lobby 操作按钮悬停反馈存在")
	var count3 := page.get_node("Background/CountCenter/PlayerCountPanel/Count3Button") as Button
	var count6 := page.get_node("Background/CountCenter/PlayerCountPanel/Count6Button") as Button
	h.check(page.player_count == 3 and count3.button_pressed and not count3.disabled, "lobby 默认选择当前支持的 3 人模式")
	h.check(count6.disabled and count6.modulate.a < 1.0, "lobby 4 至 6 人模式置灰禁用")
	count6.pressed.emit()
	h.check(page.player_count == 3, "lobby 禁用人数不能改变对局人数")
	page.get_node("Background/Actions/QuickMatchButton").pressed.emit()
	h.check("快速匹配中" in page.get_node("Background/StatusLabel").text, "lobby 快速匹配进入匹配态")
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
	h.check(page.get_node_or_null("Background/GameStartedOverlay/GameBoard") != null, "room 三人游戏界面存在")
	var room_font := page.get_node("Background/Header/RoomCodeLabel").get_theme_font("font") as Font
	h.check(room_font.has_char("中".unicode_at(0)), "room 默认字体包含中文字形")
	h.check(page.has_method("_on_ready_pressed"), "room 准备回调存在")
	h.check(page.has_method("_on_start_pressed"), "room 开始回调存在")
	h.check(page.has_method("_on_reconnect_pressed"), "room 重连回调存在")
	h.check(page.has_method("_on_prediction_submitted"), "room 排名预测回调存在")
	h.check(page.has_method("_on_rank_selected"), "room 选择排名回调存在")
	h.check(page.has_method("_on_rematch_requested"), "room 再来一局回调存在")
	page._on_state({"status": "playing", "players": []})
	h.check(page.get_node("Background/GameStartedOverlay").visible, "room 非 lobby 态显示开局 overlay")
	page._on_state({"status": "lobby", "players": []})
	h.check(not page.get_node("Background/GameStartedOverlay").visible, "room 回到大厅态隐藏开局 overlay")
	page.queue_free()
