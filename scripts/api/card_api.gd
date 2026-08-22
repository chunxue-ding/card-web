class_name CardApi
extends Node
## card 服务（:8890）HTTP 业务：建房/加入/查询/匹配长轮询/取消。
## 匹配固定 3 人桌；/match 后端长轮询最长 25s，用 30s 超时；queued 由调用方续约重发。
## match_wait 使用专用 ApiClient 实例：长轮询在飞时不得阻塞取消/建房等其他请求。

const MATCH_TIMEOUT_SEC := 30.0

var _client: ApiClient
var _match_client: ApiClient


func _ready() -> void:
	_client = ApiClient.new(AppConfig.get_card_base_url())
	add_child(_client)
	_match_client = ApiClient.new(AppConfig.get_card_base_url(), MATCH_TIMEOUT_SEC)
	add_child(_match_client)


func create_room(token: String, max_players: int) -> Variant:
	var res: Dictionary = await _client.post_json(Endpoints.CARD_ROOMS, {"max_players": max_players}, token)
	return _unwrap_room(res)


func join_room(token: String, room_code: String) -> Variant:
	var res: Dictionary = await _client.post_json(Endpoints.CARD_ROOM_JOIN % room_code, {}, token)
	return _unwrap_room(res)


func get_room(token: String, room_code: String) -> Variant:
	var res: Dictionary = await _client.get_json(Endpoints.CARD_ROOM_GET % room_code, token)
	return _unwrap_room(res)


func match_wait(token: String) -> Variant:
	var res: Dictionary = await _match_client.post_json(Endpoints.CARD_MATCH, {}, token)
	if not res["ok"]:
		return res["error"]
	return res["data"]


func match_cancel(token: String) -> Variant:
	return await _request_data(Endpoints.CARD_MATCH_CANCEL, token)


func _request_data(path: String, token: String, timeout := 0.0) -> Variant:
	var res: Dictionary = await _client.post_json(path, {}, token, timeout)
	if not res["ok"]:
		return res["error"]
	return res["data"]


func _unwrap_room(res: Dictionary) -> Variant:
	if not res["ok"]:
		return res["error"]
	var data: Dictionary = res["data"]
	if not data.has("room"):
		return ApiError.new(Endpoints.CODE_NETWORK, "服务异常，请稍后再试")
	return data["room"]
