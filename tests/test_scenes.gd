extends SceneTree
## 场景接线冒烟：实例化各场景触发 _ready，验证 @onready 节点路径与按钮回调存在
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd

const Helper = preload("res://tests/test_helper.gd")
const _SessionScript = preload("res://scripts/session.gd")

var h := Helper.new()


func _initialize() -> void:
	# 预加载 Session 脚本以避免 --script 模式下 autoload 未注册的编译错误
	# 实际登录/游客流程由 autoload Session 驱动，此处仅验证场景接线
	var _session := _SessionScript.new()
	_session.queue_free()
	_check_login()
	_check_register()
	_check_lobby()
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
	h.check(page.get_node_or_null("Background/Center/VBox/LogoutButton") != null, "lobby LogoutButton 存在")
	h.check(page.has_method("_on_logout_pressed"), "lobby 登出回调存在")
	page.queue_free()
