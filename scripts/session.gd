extends Node
## 全局会话单例（autoload Session）：token/user 持有、device_id 持久化、登录/注册/游客/登出。
## card 接入新增：card() 访问器、pending_room_code/pending_player_count 跨场景传参。
## 注意：不要声明 class_name Session，会与 autoload 名冲突。

const DEVICE_CFG_PATH := "user://device.cfg"
const ACCOUNT_CFG_PATH := "user://account.cfg"

var token := ""
var user: Dictionary = {}
var is_new_user := false
var pending_room_code := ""
var pending_player_count := 0
var pending_quick_match := false

var _api: AuthApi
var _card: CardApi
var _device_id := ""
var _remembered_email := ""

# 可在测试中替换，避免读写玩家真实的浏览器账号记录。
var account_cfg_path := ACCOUNT_CFG_PATH


func _ready() -> void:
	_api = AuthApi.new()
	add_child(_api)
	_card = CardApi.new()
	add_child(_card)


func card() -> CardApi:
	return _card


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


func get_remembered_email() -> String:
	if _remembered_email != "":
		return _remembered_email
	var cfg := ConfigFile.new()
	if cfg.load(account_cfg_path) == OK:
		_remembered_email = str(cfg.get_value("account", "email", "")).strip_edges().to_lower()
	return _remembered_email


func remember_email(email: String) -> void:
	var normalized := email.strip_edges().to_lower()
	if normalized == "":
		return
	_remembered_email = normalized
	var cfg := ConfigFile.new()
	cfg.set_value("account", "email", normalized)
	var save_error := cfg.save(account_cfg_path)
	if save_error != OK:
		push_warning("保存登录邮箱失败：%s" % error_string(save_error))


func login(email: String, password: String) -> ApiError:
	var err := _apply_auth(await _api.login(email, password))
	if err == null:
		remember_email(email)
	return err


func register(email: String, password: String) -> ApiError:
	var err := _apply_auth(await _api.register(email, password))
	if err == null:
		remember_email(email)
	return err


func guest_login() -> ApiError:
	return _apply_auth(await _api.guest_login(get_device_id()))


## 重新拉取当前用户资料(余额/昵称),用于对局结束回到大厅时刷新展示。
func refresh_me() -> ApiError:
	if token == "":
		return ApiError.new(Endpoints.CODE_UNAUTHORIZED, "未登录")
	var res: Variant = await _api.me(token)
	if res is ApiError:
		return res
	var payload := res as Dictionary
	var data: Dictionary = payload.get("user", payload)
	for key in ["id", "name", "avatar_color", "avatar", "has_password", "balance"]:
		if data.has(key):
			user[key] = data[key]
	return null


## 首次登录或资料尚不完整时先走设置页。
## 仅邮箱用户进入；游客一键登录保持原逻辑直进主页。
func needs_profile_setup() -> bool:
	if not is_logged_in() or is_guest():
		return false
	var name_missing := str(user.get("name", "")).strip_edges().is_empty()
	var avatar_missing := int(user.get("avatar", 0)) == 0
	return is_new_user or name_missing or avatar_missing


func update_profile(nickname: String, avatar: int) -> ApiError:
	var res: Variant = await _api.update_me(token, nickname, avatar)
	if res is ApiError:
		return res
	var payload := res as Dictionary
	var data: Dictionary = payload.get("user", payload)
	for key in ["name", "avatar_color", "avatar"]:
		if data.has(key):
			user[key] = data[key]
	is_new_user = false
	return null


func logout() -> void:
	if token != "":
		await _api.logout(token)
	token = ""
	user = {}
	is_new_user = false
	pending_room_code = ""
	pending_player_count = 0
	pending_quick_match = false


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
