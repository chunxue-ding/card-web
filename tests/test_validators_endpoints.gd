extends SceneTree
## 纯逻辑单测：Validators / Endpoints / AppConfig
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_validators_endpoints.gd

const Helper = preload("res://tests/test_helper.gd")
const Validators = preload("res://scripts/api/validators.gd")
const Endpoints = preload("res://scripts/api/endpoints.gd")
const AppConfig = preload("res://scripts/config/app_config.gd")

var h := Helper.new()


func _initialize() -> void:
	# Validators.valid_email
	h.check(Validators.valid_email("dn@example.com"), "valid_email 普通邮箱")
	h.check(Validators.valid_email("a.b+tag@sub.domain.org"), "valid_email 含加号与子域")
	h.check(not Validators.valid_email("plainaddress"), "valid_email 缺 @ 拒绝")
	h.check(not Validators.valid_email("a@b"), "valid_email 缺后缀拒绝")
	h.check(not Validators.valid_email("a b@x.com"), "valid_email 含空格拒绝")
	h.check(not Validators.valid_email(""), "valid_email 空串拒绝")
	# Validators.password_ok
	h.check(Validators.password_ok("12345678"), "password_ok 恰好 8 位")
	h.check(not Validators.password_ok("1234567"), "password_ok 7 位拒绝")
	# Endpoints 路径
	h.check(Endpoints.LOGIN == "/api/v1/auth/login", "LOGIN 路径")
	h.check(Endpoints.REGISTER == "/api/v1/auth/register", "REGISTER 路径")
	h.check(Endpoints.GUEST_LOGIN == "/api/v1/auth/guest-login", "GUEST_LOGIN 路径")
	h.check(Endpoints.LOGOUT == "/api/v1/auth/logout", "LOGOUT 路径")
	# Endpoints.message_for 中文映射
	h.check(Endpoints.message_for(100001) == "邮箱或密码格式不正确", "100001 消息")
	h.check(Endpoints.message_for(100003) == "该邮箱已注册", "100003 消息")
	h.check(Endpoints.message_for(100004) == "邮箱或密码错误", "100004 消息")
	h.check(Endpoints.message_for(100005) == "该账号未设置密码", "100005 消息")
	h.check(Endpoints.message_for(100006) == "尝试过于频繁，请稍后再试", "100006 消息")
	h.check(Endpoints.message_for(401) == "登录已过期，请重新登录", "401 消息")
	h.check(Endpoints.message_for(-1) == "无法连接服务器", "-1 消息")
	h.check(Endpoints.message_for(999999) == "", "未知码返回空串")
	# AppConfig
	h.check(AppConfig.get_base_url() != "", "base_url 非空")
	h.finish(self)
