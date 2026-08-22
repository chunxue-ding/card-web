extends Control

const LOGIN_SCENE := "res://scenes/login/login.tscn"


func _on_login_account_pressed() -> void:
	var error := get_tree().change_scene_to_file(LOGIN_SCENE)
	if error != OK:
		push_error("无法返回登录场景：%s" % error_string(error))
