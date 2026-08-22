extends SceneTree
## 场景接线冒烟：实例化各场景触发 _ready，验证 @onready 节点路径与按钮回调存在
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd

const Helper = preload("res://tests/test_helper.gd")

var h := Helper.new()


func _initialize() -> void:
	_check_login()
	_check_register()
	await _check_lobby()
	await _check_friend_room()
	h.finish(self)


func _check_login() -> void:
	var scene := load("res://scenes/login/login.tscn") as PackedScene
	if scene == null:
		h.check(false, "login 场景可加载")
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	h.check(page.get_node_or_null("Background/Center/VBox/ErrorLabel") != null, "login ErrorLabel 存在")
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
	h.check(page.has_method("_on_logout_pressed"), "lobby 登出回调存在")
	h.check(page.has_method("_on_quick_match_pressed"), "lobby 快速匹配回调存在")
	h.check(page.has_method("_on_friend_play_pressed"), "lobby 好友同玩回调存在")
	h.check(page.has_method("_set_action_hover"), "lobby 操作按钮悬停反馈存在")
	page.get_node("Background/CountCenter/PlayerCountPanel/Count6Button").pressed.emit()
	page.get_node("Background/Actions/QuickMatchButton").pressed.emit()
	h.check(page.player_count == 6, "lobby 人数选择会更新")
	h.check("6 人" in page.get_node("Background/StatusLabel").text, "lobby 匹配使用已选人数")
	page.queue_free()


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
	h.check(page.has_method("_on_create_room_pressed"), "friend_room 创建回调存在")
	h.check(page.has_method("_on_join_room_pressed"), "friend_room 加入回调存在")
	h.check(page.has_method("_on_back_home_pressed"), "friend_room 返回主页回调存在")
	h.check(page.has_method("_set_action_hover"), "friend_room 按钮悬停反馈存在")
	page.get_node("Background/ActionCenter/Actions/JoinRoomButton").pressed.emit()
	h.check(page.get_node("Background/StatusLabel").text == "请输入房间编号", "friend_room 空编号会提示")
	page.get_node("Background/CodeCenter/CodePanel/RoomCodeInput").text = "ABCD12"
	page.get_node("Background/ActionCenter/Actions/JoinRoomButton").pressed.emit()
	h.check("ABCD12" in page.get_node("Background/StatusLabel").text, "friend_room 加入会读取编号")
	page.queue_free()
