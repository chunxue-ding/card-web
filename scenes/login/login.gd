extends Control

const REGISTER_SCENE := "res://scenes/register/register.tscn"


func _on_create_account_pressed() -> void:
	var error := get_tree().change_scene_to_file(REGISTER_SCENE)
	if error != OK:
		push_error("无法打开注册场景：%s" % error_string(error))
