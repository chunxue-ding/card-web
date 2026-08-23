extends SceneTree
## Session 的 device_id 生成与持久化（不发网络请求；直接实例化脚本，不依赖 autoload 注册）
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_session_device.gd

const Helper = preload("res://tests/test_helper.gd")
const SessionScript = preload("res://scripts/session.gd")

var h := Helper.new()


func _initialize() -> void:
	var first := SessionScript.new()
	root.add_child(first)  # 触发 _ready 挂 AuthApi（不发请求）
	var id1 := first.get_device_id()
	var id2 := first.get_device_id()
	h.check(id1 != "" and id1 == id2, "同实例两次取 device_id 一致")
	first.token = "token"
	first.user = {"email": "new@example.com", "name": "", "avatar": 0}
	h.check(first.needs_profile_setup(), "非游客名称头像未设置时进入资料页")
	first.user = {"email": "new@example.com", "name": "调查员", "avatar": 2}
	first.is_new_user = false
	h.check(not first.needs_profile_setup(), "资料完整的非游客直接进入主页")
	first.user = {"email": "", "name": "游客", "avatar": 0}
	first.is_new_user = true
	h.check(not first.needs_profile_setup(), "游客首次登录不进入资料页")
	first.queue_free()
	# 新实例模拟重启 → 从 user://device.cfg 读回同一 id
	var second := SessionScript.new()
	root.add_child(second)
	h.check(second.get_device_id() == id1, "新实例复用持久化的 device_id")
	second.queue_free()
	h.finish(self)
