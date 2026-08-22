extends Control
## 登录页：前置校验 → Session 密码登录 / 游客登录 → 进大厅；失败在表单底部展示错误

const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"
const REGISTER_SCENE := "res://scenes/register/register.tscn"
const LOGIN_NORMAL_TEXT := "登 录"
const LOGIN_LOADING_TEXT := "登录中…"
const GUEST_NORMAL_TEXT := "游客一键登录"

@onready var email_input: LineEdit = $Background/Center/VBox/EmailInput
@onready var password_input: LineEdit = $Background/Center/VBox/PasswordInput
@onready var login_button: Button = $Background/Center/VBox/LoginButton
@onready var guest_button: Button = $Background/Center/VBox/GuestButton
@onready var error_label: Label = $Background/Center/VBox/ErrorLabel


func _on_login_pressed() -> void:
	var email := email_input.text.strip_edges()
	var password := password_input.text
	if not Validators.valid_email(email):
		_show_error("请输入正确的邮箱地址")
		return
	if not Validators.password_ok(password):
		_show_error("密码至少 8 位")
		return
	_clear_error()
	_set_loading(login_button, true)
	var err: ApiError = await Session.login(email, password)
	if not is_inside_tree():
		return
	_set_loading(login_button, false)
	if err != null:
		_show_error(err.message)
		return
	_goto_lobby()


func _on_guest_pressed() -> void:
	_clear_error()
	_set_loading(guest_button, true)
	var err: ApiError = await Session.guest_login()
	if not is_inside_tree():
		return
	_set_loading(guest_button, false)
	if err != null:
		_show_error(err.message)
		return
	_goto_lobby()


func _on_create_account_pressed() -> void:
	var error := get_tree().change_scene_to_file(REGISTER_SCENE)
	if error != OK:
		push_error("无法打开注册场景：%s" % error_string(error))


func _show_error(message: String) -> void:
	error_label.text = message


func _clear_error() -> void:
	error_label.text = ""


func _set_loading(button: Button, loading: bool) -> void:
	button.disabled = loading
	button.text = LOGIN_LOADING_TEXT if loading else (LOGIN_NORMAL_TEXT if button == login_button else GUEST_NORMAL_TEXT)


func _goto_lobby() -> void:
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		push_error("无法进入大厅场景：%s" % error_string(error))
