class_name ApiClient
extends Node
## HTTP + JSON 封装：单飞请求；响应统一归一化为 {ok:true,data} 或 {ok:false,error:ApiError}
## 归一化规则见 spec §3：网络失败 / 401 / HTTP200+code≠0 / 其余成功

const TIMEOUT_SEC := 10.0

var _http: HTTPRequest
var _busy := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_SEC
	add_child(_http)


func post_json(path: String, body: Dictionary, bearer_token := "") -> Dictionary:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if bearer_token != "":
		headers.append("Authorization: Bearer %s" % bearer_token)
	return await _request_json(HTTPClient.METHOD_POST, path, headers, JSON.stringify(body))


func _request_json(method: int, path: String, headers: PackedStringArray, body_text: String) -> Dictionary:
	if _busy:
		return _error_dict(ApiError.new(Endpoints.CODE_NETWORK, "请求进行中，请稍候"))
	var url := AppConfig.get_base_url() + path
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
		return _error_dict(ApiError.new(Endpoints.CODE_NETWORK, "服务异常，请稍后再试"))
	var body := parsed as Dictionary
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
