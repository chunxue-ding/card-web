extends SceneTree
## ApiClient.parse_response 归一化单测（纯静态逻辑，不发网络请求）
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_api_client.gd

const Helper = preload("res://tests/test_helper.gd")
const ApiClient = preload("res://scripts/api/api_client.gd")

var h := Helper.new()


func _initialize() -> void:
	# 网络层失败（连接不上/超时）→ 网络错误
	var r1: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	h.check(not r1["ok"] and r1["error"].code == -1 and r1["error"].is_network_error \
		and r1["error"].message == "无法连接服务器", "连接失败 → 网络错误")
	# HTTP 401
	var r2: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 401, '{"code":401,"message":"unauthorized"}')
	h.check(not r2["ok"] and r2["error"].code == 401 \
		and r2["error"].message == "登录已过期，请重新登录", "401 → 登录已过期")
	# 业务错误：HTTP 200 + code≠0，中文映射优先于后端英文 message
	var r3: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 200, '{"code":100004,"message":"email or password incorrect"}')
	h.check(not r3["ok"] and r3["error"].code == 100004 \
		and r3["error"].message == "邮箱或密码错误", "100004 → 中文映射优先")
	# 未知码但有后端 message → 显示后端 message
	var r4: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 200, '{"code":987654,"message":"weird"}')
	h.check(not r4["ok"] and r4["error"].code == 987654 \
		and r4["error"].message == "weird", "未知码 → 后端 message")
	# 未知码且无 message → 兜底文案
	var r5: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 200, '{"code":987655}')
	h.check(not r5["ok"] and r5["error"].message == "服务异常，请稍后再试", "未知码无 message → 兜底文案")
	# code=0 成功（logout/healthz 形态）
	var r6: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 200, '{"code":0,"message":"success"}')
	h.check(r6["ok"] and r6["data"].get("code") == 0, "code=0 → 成功")
	# AuthResp 成功（无 code 字段）
	var r7: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 200, '{"token":"t1","user":{"id":7,"name":"n"},"is_new_user":true}')
	h.check(r7["ok"] and r7["data"].get("token") == "t1", "AuthResp → 成功透传")
	# 非 JSON 响应
	var r8: Dictionary = ApiClient.parse_response(HTTPRequest.RESULT_SUCCESS, 200, "<html>bad</html>")
	h.check(not r8["ok"] and r8["error"].message == "服务异常，请稍后再试", "非 JSON → 兜底文案")
	h.finish(self)
