class_name ApiClient
extends Node
## HTTP + JSON 封装：单飞请求；响应统一归一化为 {ok:true,data} 或 {ok:false,error:ApiError}
## 归一化：网络失败 / 401 / HTTP≥400+code（card 形态）/ HTTP200+code≠0（user 形态）/ 其余成功
## 构造可注入 base_url（默认 user 服务）与默认超时；单请求可覆盖超时（/match 长轮询 30s）

const DEFAULT_TIMEOUT_SEC := 10.0

var _base_url: String
var _default_timeout := 0.0
var _http: HTTPRequest
var _busy := false


func _init(base_url := "", default_timeout := 0.0) -> void:
	_base_url = base_url
	_default_timeout = default_timeout


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)


func post_json(path: String, body: Dictionary, bearer_token := "", timeout := 0.0) -> Dictionary:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if bearer_token != "":
		headers.append("Authorization: Bearer %s" % bearer_token)
	return await _request_json(HTTPClient.METHOD_POST, path, headers, JSON.stringify(body), timeout)


func put_json(path: String, body: Dictionary, bearer_token := "", timeout := 0.0) -> Dictionary:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if bearer_token != "":
		headers.append("Authorization: Bearer %s" % bearer_token)
	return await _request_json(HTTPClient.METHOD_PUT, path, headers, JSON.stringify(body), timeout)


func get_json(path: String, bearer_token := "", timeout := 0.0) -> Dictionary:
	var headers := PackedStringArray()
	if bearer_token != "":
		headers.append("Authorization: Bearer %s" % bearer_token)
	return await _request_json(HTTPClient.METHOD_GET, path, headers, "", timeout)


func _request_json(method: int, path: String, headers: PackedStringArray, body_text: String, timeout := 0.0) -> Dictionary:
	if _busy:
		return _error_dict(ApiError.new(Endpoints.CODE_NETWORK, "请求进行中，请稍候"))
	var base := _base_url if _base_url != "" else AppConfig.get_base_url()
	var url := base + path
	var effective_timeout := timeout if timeout > 0.0 else (_default_timeout if _default_timeout > 0.0 else DEFAULT_TIMEOUT_SEC)
	_http.timeout = effective_timeout
	_busy = true
	var err := _http.request(url, headers, method, body_text)
	if err != OK:
		_busy = false
		return _error_dict(ApiError.new(Endpoints.CODE_NETWORK, Endpoints.message_for(Endpoints.CODE_NETWORK), true))
	var args: Array = await _http.request_completed
	_busy = false
	return parse_response(int(args[0]), int(args[1]), (args[3] as PackedByteArray).get_string_from_utf8())


static func parse_response(http_result: int, status: int, body_text: String) -> Dictionary:
	if http_result != HTTPRequest.RESULT_SUCCESS:
		return _error_dict(ApiError.new(Endpoints.CODE_NETWORK, Endpoints.message_for(Endpoints.CODE_NETWORK), true))
	if status == 401:
		return _error_dict(ApiError.new(Endpoints.CODE_UNAUTHORIZED, Endpoints.message_for(Endpoints.CODE_UNAUTHORIZED)))
	var parsed: Variant = JSON.parse_string(body_text)
	if not (parsed is Dictionary):
		if status >= 400:
			return _error_dict(ApiError.new(status, "服务异常（HTTP %d）" % status))
		return _error_dict(ApiError.new(Endpoints.CODE_NETWORK, "服务异常，请稍后再试"))
	var body := parsed as Dictionary
	if status >= 400:
		if body.has("code"):
			var code := int(body["code"])
			var raw := str(body.get("message", ""))
			var mapped := Endpoints.card_message_for(raw)
			if mapped == "":
				mapped = raw if raw != "" else "服务异常，请稍后再试"
			return _error_dict(ApiError.new(code, mapped))
		return _error_dict(ApiError.new(status, "服务异常（HTTP %d）" % status))
	if body.has("code") and int(body.get("code", 0)) != 0:
		var code := int(body["code"])
		var msg := str(body.get("message", ""))
		var mapped := Endpoints.message_for(code)
		if mapped != "" and code != Endpoints.CODE_NETWORK:
			msg = mapped
		if msg == "":
			msg = "服务异常，请稍后再试"
		return _error_dict(ApiError.new(code, msg))
	return {"ok": true, "data": body}


static func _error_dict(error: ApiError) -> Dictionary:
	return {"ok": false, "error": error}
