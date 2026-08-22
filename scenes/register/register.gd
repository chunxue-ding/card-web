extends Control
## 注册页：前置校验（两次密码一致）→ Session 注册（后端注册即登录）→ 进大厅

const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"
const LOGIN_SCENE := "res://scenes/login/login.tscn"
const REGISTER_NORMAL_TEXT := "注 册"
const REGISTER_LOADING_TEXT := "注册中…"

@onready var email_input: LineEdit = $Background/Center/VBox/AccountInput
@onready var password_input: LineEdit = $Background/Center/VBox/PasswordInput
@onready var confirm_input: LineEdit = $Background/Center/VBox/ConfirmPasswordInput
@onready var register_button: Button = $Background/Center/VBox/RegisterButton
@onready var error_label: Label = $Background/Center/VBox/ErrorLabel


func _on_register_pressed() -> void:
	var email := email_input.text.strip_edges()
	var password := password_input.text
	if not Validators.valid_email(email):
		_show_error("请输入正确的邮箱地址")
		return
	if not Validators.password_ok(password):
		_show_error("密码至少 8 位")
		return
	if password != confirm_input.text:
		_show_error("两次输入的密码不一致")
		return
	_clear_error()
	_set_loading(true)
	var err: ApiError = await Session.register(email, password)
	if not is_inside_tree():
		return
	_set_loading(false)
	if err != null:
		_show_error(err.message)
		return
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		push_error("无法进入大厅场景：%s" % error_string(error))


func _on_login_account_pressed() -> void:
	var error := get_tree().change_scene_to_file(LOGIN_SCENE)
	if error != OK:
		push_error("无法返回登录场景：%s" % error_string(error))


func _show_error(message: String) -> void:
	error_label.text = message


func _clear_error() -> void:
	error_label.text = ""


func _set_loading(loading: bool) -> void:
	register_button.disabled = loading
	register_button.text = REGISTER_LOADING_TEXT if loading else REGISTER_NORMAL_TEXT
