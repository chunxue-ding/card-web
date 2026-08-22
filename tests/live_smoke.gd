extends SceneTree
## 端到端冒烟（需后端已启动：make up && make run）
## 运行：/Users/dn/bin/godot --headless --script res://tests/live_smoke.gd
## 注意：guest-login 按 IP 限流（10 分钟 5 次），10 分钟内不要跑超过 2 次。

const Helper = preload("res://tests/test_helper.gd")
const AuthApi = preload("res://scripts/api/auth_api.gd")

var h := Helper.new()
var api: AuthApi


func _initialize() -> void:
	api = AuthApi.new()
	root.add_child(api)
	# _initialize 阶段 root 尚未进入树，HTTPRequest 会报 ERR_UNCONFIGURED；等一帧再跑
	await process_frame
	_run()


func _run() -> void:
	var suffix: String = Crypto.new().generate_random_bytes(4).hex_encode()
	var email := "smoke_%s@test.local" % suffix
	var password := "password123"

	# 1. 注册 → 注册即登录
	var reg: Variant = await api.register(email, password)
	h.check(not (reg is ApiError) and reg.get("is_new_user") == true, "注册成功且 is_new_user=true")
	var user_id: int = int(reg["user"]["id"]) if not (reg is ApiError) else -1

	# 2. 重复注册 → 100003
	var dup: Variant = await api.register(email, password)
	h.check(dup is ApiError and dup.code == 100003, "重复注册 → 100003")

	# 3. 密码登录同一账号
	var login: Variant = await api.login(email, password)
	h.check(not (login is ApiError) and int(login["user"]["id"]) == user_id, "密码登录同一 user_id")
	var token: String = str(login["token"]) if not (login is ApiError) else ""

	# 4. 错误密码 → 100004
	var bad: Variant = await api.login(email, "wrongpass1")
	h.check(bad is ApiError and bad.code == 100004, "错误密码 → 100004")

	# 5. 登出 → code=0
	var out: Variant = await api.logout(token)
	h.check(not (out is ApiError) and int(out.get("code", -1)) == 0, "登出 code=0")

	# 6. 游客登录两次（同一 device_id）→ 同一 user，第二次 is_new_user=false
	var device_id := "smoke-device-%s" % suffix
	var g1: Variant = await api.guest_login(device_id)
	h.check(not (g1 is ApiError) and int(g1["user"]["balance"]) == 5000, "游客登录成功且初始余额 5000")
	var g2: Variant = await api.guest_login(device_id)
	h.check(not (g2 is ApiError) and int(g2["user"]["id"]) == int(g1["user"]["id"]) \
		and g2.get("is_new_user") == false, "游客复用同一账号且非新用户")

	# 7. 后端不可达 → 网络错误
	OS.set_environment("CARD_API_URL", "http://127.0.0.1:1")
	var dead: Variant = await api.login(email, password)
	h.check(dead is ApiError and dead.is_network_error, "后端不可达 → 网络错误")
	OS.set_environment("CARD_API_URL", "")

	h.finish(self)
