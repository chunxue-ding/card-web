class_name ApiError
extends RefCounted
## 归一化错误：业务码 / 未授权 / 网络错误；message 可直接展示给用户

var code: int
var message: String
var is_network_error: bool


func _init(p_code: int, p_message: String, p_network_error := false) -> void:
	code = p_code
	message = p_message
	is_network_error = p_network_error
