extends SceneTree
## card 契约层单测：ApiClient 归一化扩展 / Endpoints card 文案 / AppConfig card base url
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_card_contract.gd

const Helper = preload("res://tests/test_helper.gd")
const ApiClient = preload("res://scripts/api/api_client.gd")
const Endpoints = preload("res://scripts/api/endpoints.gd")
const AppConfig = preload("res://scripts/config/app_config.gd")

var h := Helper.new()


func _initialize() -> void:
	# ApiClient.parse_response —— card 形态（HTTP≥400 + code/message）
	var r1: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 409, '{"code":409,"message":"room is full"}')
	h.check(not r1["ok"] and r1["error"].code == 409 and r1["error"].message == "房间已满", "card 409 room is full → 中文")
	var r2: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 404, '{"code":404,"message":"room not found"}')
	h.check(not r2["ok"] and r2["error"].code == 404 and r2["error"].message == "房间不存在", "card 404 → 房间不存在")
	var r3: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 409, '{"code":409,"message":"weird conflict"}')
	h.check(not r3["ok"] and r3["error"].message == "weird conflict", "card 未知 message 显示原文")
	var r4: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 502, '{"code":502,"message":"account service unavailable"}')
	h.check(not r4["ok"] and r4["error"].message == "账号服务暂不可用", "card 502 → 账号服务暂不可用")
	var r5: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 403, "<html></html>")
	h.check(not r5["ok"] and r5["error"].code == 403, "card 非 JSON 错误 → 用 HTTP 状态码")
	var r6: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 201, '{"room":{"code":"ABC123"}}')
	h.check(r6["ok"] and r6["data"]["room"]["code"] == "ABC123", "201 建房成功透传")
	var r7: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 401, '{"code":401,"message":"unauthorized"}')
	h.check(not r7["ok"] and r7["error"].message == "登录已过期，请重新登录", "card 401 → 登录已过期")
	# ApiClient.parse_response —— user 形态回归（HTTP 200 + code≠0 不变）
	var r8: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 200, '{"code":100004,"message":"email or password incorrect"}')
	h.check(not r8["ok"] and r8["error"].code == 100004 and r8["error"].message == "邮箱或密码错误", "user 100004 回归不变")
	# Endpoints card 文案与路径
	h.check(Endpoints.card_message_for("insufficient balance") == "金币不足（需 200 入场费）", "insufficient balance 文案")
	h.check(Endpoints.card_message_for("cancel matchmaking first") == "请先退出当前房间或取消匹配", "cancel matchmaking 文案")
	h.check(Endpoints.card_message_for("already in a room") == "请先退出当前房间或取消匹配", "already in a room 文案")
	h.check(Endpoints.card_message_for("nope") == "", "card 未知 message 返回空串")
	h.check(Endpoints.match_drop_message("expired") == "匹配超时，请重试", "dropped expired 文案")
	h.check(Endpoints.match_drop_message("whatever") == "匹配失败，请重试", "dropped 未知兜底")
	h.check(Endpoints.ws_error_message("room not found or not joined") == "房间不存在或未加入", "ws error 文案")
	h.check(Endpoints.CARD_MATCH == "/api/v1/match", "CARD_MATCH 路径")
	h.check(Endpoints.CARD_MATCH_CONFIRM == "/api/v1/match/confirm", "CARD_MATCH_CONFIRM 路径")
	h.check(Endpoints.CARD_MATCH_DECLINE == "/api/v1/match/decline", "CARD_MATCH_DECLINE 路径")
	h.check(Endpoints.CARD_WS_PATH == "/api/v1/ws", "CARD_WS_PATH 路径")
	h.check((Endpoints.CARD_ROOM_JOIN % "ABC123") == "/api/v1/rooms/ABC123/join", "CARD_ROOM_JOIN 格式化")
	h.check((Endpoints.CARD_ROOM_GET % "ABC123") == "/api/v1/rooms/ABC123", "CARD_ROOM_GET 格式化")
	# AppConfig
	h.check(AppConfig.get_card_base_url() != "", "card base url 非空")
	h.finish(self)
