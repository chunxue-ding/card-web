extends Node
## 全局会话单例（autoload Session）：token/user 持有、device_id 持久化、登录/注册/游客/登出。
## 注意：不要声明 class_name Session，会与 autoload 名冲突。

const DEVICE_CFG_PATH := "user://device.cfg"

var token := ""
var user: Dictionary = {}
var is_new_user := false

var _api: AuthApi
var _device_id := ""


func _ready() -> void:
	_api = AuthApi.new()
	add_child(_api)


func get_device_id() -> String:
	if _device_id != "":
		return _device_id
	var cfg := ConfigFile.new()
	if cfg.load(DEVICE_CFG_PATH) == OK:
		_device_id = str(cfg.get_value("device", "id", ""))
	if _device_id == "":
		_device_id = Crypto.new().generate_random_bytes(16).hex_encode()
		cfg.set_value("device", "id", _device_id)
		cfg.save(DEVICE_CFG_PATH)
	return _device_id


func login(email: String, password: String) -> ApiError:
	return _apply_auth(await _api.login(email, password))


func register(email: String, password: String) -> ApiError:
	return _apply_auth(await _api.register(email, password))


func guest_login() -> ApiError:
	return _apply_auth(await _api.guest_login(get_device_id()))


func logout() -> void:
	if token != "":
		await _api.logout(token)
	token = ""
	user = {}
	is_new_user = false


func is_logged_in() -> bool:
	return token != ""


func is_guest() -> bool:
	return is_logged_in() and str(user.get("email", "")) == ""


func _apply_auth(res: Variant) -> ApiError:
	if res is ApiError:
		return res
	token = str(res["token"])
	user = res["user"]
	is_new_user = bool(res.get("is_new_user", false))
	print("登录成功：user_id=%s name=%s is_new_user=%s" % [user.get("id"), user.get("name"), is_new_user])
	return null
