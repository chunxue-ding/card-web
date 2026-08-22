extends Control
## 大厅占位：展示登录用户信息；退出登录（调 logout，失败忽略）后回登录页

const LOGIN_SCENE := "res://scenes/login/login.tscn"

@onready var name_label: Label = $Background/Center/VBox/NameLabel
@onready var email_label: Label = $Background/Center/VBox/EmailLabel
@onready var balance_label: Label = $Background/Center/VBox/BalanceLabel
@onready var logout_button: Button = $Background/Center/VBox/LogoutButton


func _ready() -> void:
	name_label.text = "昵称：%s" % str(Session.user.get("name", ""))
	if Session.is_guest():
		email_label.text = "账号：游客"
	else:
		email_label.text = "账号：%s" % str(Session.user.get("email", ""))
	balance_label.text = "余额：%d" % int(Session.user.get("balance", 0))


func _on_logout_pressed() -> void:
	logout_button.disabled = true
	await Session.logout()
	var error := get_tree().change_scene_to_file(LOGIN_SCENE)
	if error != OK:
		push_error("无法返回登录场景：%s" % error_string(error))
