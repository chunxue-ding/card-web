class_name AuthApi
extends Node
## 认证业务方法。成功返回 AuthResp Dictionary（login/register/guest_login）
## 或 CommonResp Dictionary（logout）；失败返回 ApiError。

var _client: ApiClient


func _ready() -> void:
	_client = ApiClient.new()
	add_child(_client)


func login(email: String, password: String) -> Variant:
	return await _auth(Endpoints.LOGIN, {"email": email, "password": password})


func register(email: String, password: String) -> Variant:
	return await _auth(Endpoints.REGISTER, {"email": email, "password": password})


func guest_login(device_id: String) -> Variant:
	return await _auth(Endpoints.GUEST_LOGIN, {"device_id": device_id})


func logout(token: String) -> Variant:
	return await _client.post_json(Endpoints.LOGOUT, {}, token)


func _auth(path: String, body: Dictionary) -> Variant:
	var res: Dictionary = await _client.post_json(path, body)
	if not res["ok"]:
		return res["error"]
	var data: Dictionary = res["data"]
	if not (data.has("token") and data.has("user")):
		return ApiError.new(Endpoints.CODE_NETWORK, "服务异常，请稍后再试")
	return data
