# 匹配/好友房间接入 card 后端 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 主页「快速匹配」（固定 3 人桌长轮询+取消）、「好友同玩」建房/加入接 `/Users/dn/card`（:8890），新建 WS 房间等待页，到 `game_started` 占位 overlay 为止。

**Architecture:** 方案 B 对等分层——场景 → Session(autoload, `card()` 访问器 + pending 字段) → CardApi → ApiClient(注入 base_url/超时)；room 页经 RoomSocket(WebSocketPeer) 消费 WS 信封。spec：`docs/superpowers/specs/2026-08-22-room-match-integration-design.md`。

**Tech Stack:** Godot 4.7.2（`/Users/dn/bin/godot`）、WebSocketPeer、HTTPRequest。无新第三方依赖；无测试框架（headless `--script` 脚本）。

## Global Constraints

- 所有命令在 `/Users/dn/card-web` 执行；GDScript tab 缩进；新增 `class_name` 文件后先 `/Users/dn/bin/godot --headless --import` 再跑测试。
- 服务地址：user `http://127.0.0.1:8888`（env `CARD_API_URL`）、card `http://127.0.0.1:8890`（env `CARD_CARD_URL`）。
- **card 错误形态**：HTTP 401/403/404/409/502 + `{"code":<HTTP状态>,"message"}`（与 user 的 HTTP200+code 不同）；建房成功 201。
- 错误文案 verbatim（spec §6）：`room is full`→「房间已满」`room not found`→「房间不存在」`game already started`→「对局已开始」`cancel matchmaking first`/`already in a room`→「请先退出当前房间或取消匹配」`already matched`→「已匹配成功」`at least 3 players required`→「至少需要 3 名玩家」`every player must be ready`→「还有玩家未准备」`account service unavailable`→「账号服务暂不可用」`insufficient balance`→「金币不足（需 200 入场费）」；dropped：`expired`→「匹配超时，请重试」`joined another room`→「已加入其他房间」其余→「匹配失败，请重试」。
- `/match` 长轮询后端最长 25s → 该请求超时 30s；其余默认 10s。匹配固定 3 人成桌。
- WS：`ws://…/api/v1/ws`，10s 内首帧 `{"type":"authenticate","token":…,"room_code":…}`；信封 `{type:"state"|"events"|"error",state?,events?,version?,error?}`。
- 顶层测试脚本不得引用裸 autoload 名（`Session` 等，--script 编译限制）；`_initialize` 发请求前先 `await process_frame`。
- **用户会并行编辑场景/测试**：任何修改 `tests/test_scenes.gd` 或 `scenes/` 的任务，动手前先 `git status`——发现他人未提交改动立即报告 BLOCKED 并附清单，不得吸收或覆盖。
- 修改 test_scenes.gd 的断言计数：基线 27，Task 4 后 35，Task 5 后 36，Task 6 后 38。
- Conventional Commits，提交可加 `--no-verify`。

---

### Task 1: 契约层扩展（AppConfig card URL / Endpoints card 文案 / ApiClient base_url+超时+归一化）

**Files:**
- Create: `tests/test_card_contract.gd`
- Modify: `scripts/config/app_config.gd`（全文替换）、`scripts/api/endpoints.gd`（追加）、`scripts/api/api_client.gd`（全文替换）

**Interfaces:**
- Consumes: 既有 `ApiError`、`Endpoints`、`AppConfig`
- Produces:
  - `AppConfig.get_card_base_url() -> String`（static）
  - `Endpoints.CARD_ROOMS/CARD_ROOM_JOIN(%s)/CARD_ROOM_GET(%s)/CARD_MATCH/CARD_MATCH_CANCEL/CARD_WS_PATH`；`card_message_for(message) -> String`（未知返回 `""`）；`match_drop_message(reason) -> String`；`ws_error_message(error) -> String`
  - `ApiClient._init(base_url := "", default_timeout := 0.0)`；`post_json(path, body, bearer_token := "", timeout := 0.0) -> Dictionary`；`get_json(path, bearer_token := "", timeout := 0.0) -> Dictionary`；`parse_response` 新增 HTTP≥400 分支（Task 2-7 依赖）
  - 既有调用方（AuthApi）零改动兼容

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_card_contract.gd`：

```gdscript
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
	h.check(Endpoints.CARD_WS_PATH == "/api/v1/ws", "CARD_WS_PATH 路径")
	h.check((Endpoints.CARD_ROOM_JOIN % "ABC123") == "/api/v1/rooms/ABC123/join", "CARD_ROOM_JOIN 格式化")
	h.check((Endpoints.CARD_ROOM_GET % "ABC123") == "/api/v1/rooms/ABC123", "CARD_ROOM_GET 格式化")
	# AppConfig
	h.check(AppConfig.get_card_base_url() != "", "card base url 非空")
	h.finish(self)
```

- [ ] **Step 2: 运行确认失败**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_card_contract.gd`
Expected: FAIL（`get_card_base_url`/`card_message_for`/`CARD_MATCH` 不存在，编译错误），非零退出码。

- [ ] **Step 3: 实现**

`scripts/config/app_config.gd` 全文替换为：

```gdscript
class_name AppConfig
## 环境配置：API base URL 解析（环境变量覆盖 → 默认本机后端）

const DEFAULT_BASE_URL := "http://127.0.0.1:8888"
const DEFAULT_CARD_BASE_URL := "http://127.0.0.1:8890"


static func get_base_url() -> String:
	var from_env := OS.get_environment("CARD_API_URL")
	if from_env != "":
		return from_env
	return DEFAULT_BASE_URL


static func get_card_base_url() -> String:
	var from_env := OS.get_environment("CARD_CARD_URL")
	if from_env != "":
		return from_env
	return DEFAULT_CARD_BASE_URL
```

`scripts/api/endpoints.gd` 末尾追加：

```gdscript

# ---- card 服务（:8890）----
const CARD_ROOMS := "/api/v1/rooms"
const CARD_ROOM_JOIN := "/api/v1/rooms/%s/join"
const CARD_ROOM_GET := "/api/v1/rooms/%s"
const CARD_MATCH := "/api/v1/match"
const CARD_MATCH_CANCEL := "/api/v1/match/cancel"
const CARD_WS_PATH := "/api/v1/ws"


static func card_message_for(message: String) -> String:
	match message:
		"insufficient balance":
			return "金币不足（需 200 入场费）"
		"room not found":
			return "房间不存在"
		"room is full":
			return "房间已满"
		"game already started":
			return "对局已开始"
		"cancel matchmaking first", "already in a room":
			return "请先退出当前房间或取消匹配"
		"already matched":
			return "已匹配成功"
		"at least 3 players required":
			return "至少需要 3 名玩家"
		"every player must be ready":
			return "还有玩家未准备"
		"account service unavailable":
			return "账号服务暂不可用"
		_:
			return ""


static func match_drop_message(reason: String) -> String:
	match reason:
		"insufficient balance":
			return "金币不足"
		"expired":
			return "匹配超时，请重试"
		"joined another room":
			return "已加入其他房间"
		_:
			return "匹配失败，请重试"


static func ws_error_message(error: String) -> String:
	match error:
		"unauthorized":
			return "登录已过期，请重新登录"
		"room not found or not joined":
			return "房间不存在或未加入"
		_:
			return error
```

`scripts/api/api_client.gd` 全文替换为：

```gdscript
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
```

- [ ] **Step 4: 刷新缓存并运行确认通过**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/test_card_contract.gd && /Users/dn/bin/godot --headless --script res://tests/test_api_client.gd && /Users/dn/bin/godot --headless --script res://tests/test_validators_endpoints.gd`
Expected: 新测试 `== 20 passed, 0 failed ==`；既有 8/8、21/21 回归全过，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add tests/test_card_contract.gd scripts/config/app_config.gd scripts/api/endpoints.gd scripts/api/api_client.gd
git commit -m "feat: extend api client for card service contract" --no-verify
```

---

### Task 2: CardApi + Session 扩展

**Files:**
- Create: `tests/test_card_api.gd`、`scripts/api/card_api.gd`
- Modify: `scripts/session.gd`（全文替换）

**Interfaces:**
- Consumes: `ApiClient(base_url)`（Task 1）、`Endpoints.CARD_*`、`ApiError`
- Produces:
  - `CardApi extends Node`（`class_name CardApi`）：`create_room(token: String, max_players: int) -> Variant`（成功返回 room dict，失败 ApiError）、`join_room(token, room_code) -> Variant`、`get_room(token, room_code) -> Variant`、`match_wait(token) -> Variant`（**返回 data dict 本身**：`{room_code}`/`{status,position}`/`{status,reason}`/`{status:"cancelled"}`，或 ApiError；30s 超时）、`match_cancel(token) -> Variant`（`{status:"cancelled"}` 或含 `room_code` 的 409 错误）
  - Session 新字段 `pending_room_code: String`、`pending_player_count: int`；新方法 `card() -> CardApi`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_card_api.gd`：

```gdscript
extends SceneTree
## CardApi 离线单测：card 服务不可达 → ApiError 网络错误（真实链路由 live smoke 覆盖）
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_card_api.gd

const Helper = preload("res://tests/test_helper.gd")
const CardApi = preload("res://scripts/api/card_api.gd")

var h := Helper.new()


func _initialize() -> void:
	OS.set_environment("CARD_CARD_URL", "http://127.0.0.1:1")
	var api := CardApi.new()
	root.add_child(api)
	await process_frame
	var res: Variant = await api.match_wait("fake-token")
	h.check(res is ApiError and res.is_network_error, "card 不可达 match_wait → 网络错误")
	var room: Variant = await api.create_room("fake-token", 3)
	h.check(room is ApiError and room.is_network_error, "card 不可达 create_room → 网络错误")
	OS.set_environment("CARD_CARD_URL", "")
	h.finish(self)
```

- [ ] **Step 2: 运行确认失败**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_card_api.gd`
Expected: FAIL（`card_api.gd` 不存在，preload 失败），非零退出码。

- [ ] **Step 3: 实现 CardApi 与 Session**

创建 `scripts/api/card_api.gd`：

```gdscript
class_name CardApi
extends Node
## card 服务（:8890）HTTP 业务：建房/加入/查询/匹配长轮询/取消。
## 匹配固定 3 人桌；/match 后端长轮询最长 25s，用 30s 超时；queued 由调用方续约重发。

const MATCH_TIMEOUT_SEC := 30.0

var _client: ApiClient


func _ready() -> void:
	_client = ApiClient.new(AppConfig.get_card_base_url())
	add_child(_client)


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
	return await _request_data(Endpoints.CARD_MATCH, token, MATCH_TIMEOUT_SEC)


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
```

`scripts/session.gd` 全文替换为（新增三处见注释）：

```gdscript
extends Node
## 全局会话单例（autoload Session）：token/user 持有、device_id 持久化、登录/注册/游客/登出。
## card 接入新增：card() 访问器、pending_room_code/pending_player_count 跨场景传参。
## 注意：不要声明 class_name Session，会与 autoload 名冲突。

const DEVICE_CFG_PATH := "user://device.cfg"

var token := ""
var user: Dictionary = {}
var is_new_user := false
var pending_room_code := ""
var pending_player_count := 0

var _api: AuthApi
var _card: CardApi
var _device_id := ""


func _ready() -> void:
	_api = AuthApi.new()
	add_child(_api)
	_card = CardApi.new()
	add_child(_card)


func card() -> CardApi:
	return _card


func get_device_id() -> String:
	if _device_id != "":
		return _device_id
	var cfg := ConfigFile.new()
	if cfg.load(DEVICE_CFG_PATH) == OK:
		_device_id = str(cfg.get_value("device", "id", ""))
	if _device_id == "":
		_device_id = Crypto.new().generate_random_bytes(16).hex_encode()
		cfg.set_value("device", "id", _device_id)
		cfg.save(DEVICE_CFG_PATH)
	return _device_id


func login(email: String, password: String) -> ApiError:
	return _apply_auth(await _api.login(email, password))


func register(email: String, password: String) -> ApiError:
	return _apply_auth(await _api.register(email, password))


func guest_login() -> ApiError:
	return _apply_auth(await _api.guest_login(get_device_id()))


func logout() -> void:
	if token != "":
		await _api.logout(token)
	token = ""
	user = {}
	is_new_user = false
	pending_room_code = ""
	pending_player_count = 0


func is_logged_in() -> bool:
	return token != ""


func is_guest() -> bool:
	return is_logged_in() and str(user.get("email", "")) == ""


func _apply_auth(res: Variant) -> ApiError:
	if res is ApiError:
		return res
	token = str(res["token"])
	user = res["user"]
	is_new_user = bool(res.get("is_new_user", false))
	print("登录成功：user_id=%s name=%s is_new_user=%s" % [user.get("id"), user.get("name"), is_new_user])
	return null
```

- [ ] **Step 4: 刷新缓存并运行确认通过**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/test_card_api.gd && /Users/dn/bin/godot --headless --script res://tests/test_session_device.gd`
Expected: `== 2 passed, 0 failed ==` ×2，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add tests/test_card_api.gd scripts/api/card_api.gd scripts/session.gd
git commit -m "feat: add card api and session card accessor" --no-verify
```

---

### Task 3: RoomSocket（WebSocket 信封封装）

**Files:**
- Create: `tests/test_room_socket.gd`、`scripts/ws/room_socket.gd`

**Interfaces:**
- Consumes: `AppConfig.get_card_base_url()`、`Endpoints.CARD_WS_PATH/ws_error_message`
- Produces: `RoomSocket extends Node`（`class_name RoomSocket`）：
  - 信号 `authenticated`、`state_received(view: Dictionary)`、`events_received(events: Array, version: int)`、`socket_error(message: String)`、`closed`
  - `connect_room(token: String, room_code: String)`（可重复调用=重连）、`poll()`（宿主每帧调）、`close()`
  - 指令 `set_ready(ready: bool)`、`add_bot()`、`remove_bot(player_id: int)`、`start_game()`
  - `static parse_envelope(text) -> Dictionary`：`{kind:"state",view}` / `{kind:"events",events,version}` / `{kind:"error",error}` / `{kind:"unknown"}`

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_room_socket.gd`：

```gdscript
extends SceneTree
## RoomSocket 信封解析单测（纯静态 + 接口存在性，不发网络）
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_room_socket.gd

const Helper = preload("res://tests/test_helper.gd")
const RoomSocket = preload("res://scripts/ws/room_socket.gd")

var h := Helper.new()


func _initialize() -> void:
	var s1: Dictionary = RoomSocket.parse_envelope('{"type":"state","state":{"code":"ABC123","version":7}}')
	h.check(s1["kind"] == "state" and s1["view"]["code"] == "ABC123", "state 信封解析")
	var s2: Dictionary = RoomSocket.parse_envelope('{"type":"events","events":[{"event":"player_joined"}],"version":8}')
	h.check(s2["kind"] == "events" and (s2["events"] as Array).size() == 1 and s2["version"] == 8, "events 信封含 version")
	var s3: Dictionary = RoomSocket.parse_envelope('{"type":"error","error":"room not found or not joined"}')
	h.check(s3["kind"] == "error" and s3["error"] == "room not found or not joined", "error 信封解析")
	h.check(RoomSocket.parse_envelope("not json")["kind"] == "unknown", "坏 JSON → unknown")
	h.check(RoomSocket.parse_envelope('{"type":"state"}')["kind"] == "unknown", "state 缺字段 → unknown")
	h.check(RoomSocket.parse_envelope('{"type":"events","events":"oops"}')["kind"] == "unknown", "events 非数组 → unknown")
	var sock := RoomSocket.new()
	h.check(sock.has_signal("state_received") and sock.has_signal("events_received") and sock.has_signal("closed") and sock.has_signal("socket_error"), "信号齐全")
	h.check(sock.has_method("connect_room") and sock.has_method("poll") and sock.has_method("close"), "连接方法齐全")
	h.check(sock.has_method("set_ready") and sock.has_method("add_bot") and sock.has_method("remove_bot") and sock.has_method("start_game"), "指令方法齐全")
	sock.free()
	h.finish(self)
```

- [ ] **Step 2: 运行确认失败**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_room_socket.gd`
Expected: FAIL（`room_socket.gd` 不存在），非零退出码。

- [ ] **Step 3: 实现 RoomSocket**

创建 `scripts/ws/room_socket.gd`：

```gdscript
class_name RoomSocket
extends Node
## 房间 WebSocket 封装（card :8890）：authenticate 首帧、state/events/error 信封分发、指令发送。
## 宿主需每帧调 poll()；断线经 closed 信号通知，重连即重新 connect_room（后端会清除代打标记）。

signal authenticated
signal state_received(view: Dictionary)
signal events_received(events: Array, version: int)
signal socket_error(message: String)
signal closed

var _peer := WebSocketPeer.new()
var _token := ""
var _room_code := ""
var _auth_pending := false
var _authed := false
var _ever_open := false


func connect_room(token: String, room_code: String) -> void:
	_token = token
	_room_code = room_code
	_auth_pending = false
	_authed = false
	_ever_open = false
	_peer = WebSocketPeer.new()
	if _peer.connect_to_url(_ws_base_url() + Endpoints.CARD_WS_PATH) != OK:
		socket_error.emit("无法连接房间服务")
		return
	_auth_pending = true


func poll() -> void:
	if _peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		return
	_peer.poll()
	var state := _peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_ever_open = true
		if _auth_pending:
			_send_json({"type": "authenticate", "token": _token, "room_code": _room_code})
			_auth_pending = false
		while _peer.get_available_packet_count() > 0:
			handle_message(_peer.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		if _ever_open:
			_ever_open = false
			_authed = false
			closed.emit()
		elif _auth_pending:
			_auth_pending = false
			socket_error.emit("无法连接房间服务")


func set_ready(ready: bool) -> void:
	_send_json({"type": "set_ready", "ready": ready})


func add_bot() -> void:
	_send_json({"type": "add_bot"})


func remove_bot(player_id: int) -> void:
	_send_json({"type": "remove_bot", "player_id": player_id})


func start_game() -> void:
	_send_json({"type": "start_game"})


func close() -> void:
	_peer.close()


func handle_message(raw: String) -> void:
	var env := parse_envelope(raw)
	match env["kind"]:
		"state":
			if not _authed:
				_authed = true
				authenticated.emit()
			state_received.emit(env["view"])
		"events":
			events_received.emit(env["events"], env["version"])
		"error":
			socket_error.emit(Endpoints.ws_error_message(env["error"]))
		_:
			push_warning("未知房间消息：%s" % raw.left(120))


static func parse_envelope(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"kind": "unknown"}
	var msg := parsed as Dictionary
	match str(msg.get("type", "")):
		"state":
			if msg.get("state") is Dictionary:
				return {"kind": "state", "view": msg["state"]}
		"events":
			if msg.get("events") is Array:
				return {"kind": "events", "events": msg["events"], "version": int(msg.get("version", 0))}
		"error":
			return {"kind": "error", "error": str(msg.get("error", ""))}
	return {"kind": "unknown"}


func _send_json(payload: Dictionary) -> void:
	if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_warning("房间连接未就绪，指令被丢弃")
		return
	_peer.put_packet(JSON.stringify(payload).to_utf8_buffer())


func _ws_base_url() -> String:
	var base := AppConfig.get_card_base_url()
	if base.begins_with("https://"):
		return base.replace("https://", "wss://")
	return base.replace("http://", "ws://")
```

- [ ] **Step 4: 刷新缓存并运行确认通过**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/test_room_socket.gd`
Expected: `== 9 passed, 0 failed ==`，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add tests/test_room_socket.gd scripts/ws/room_socket.gd
git commit -m "feat: add room websocket socket with envelope parsing" --no-verify
```

---

### Task 4: 房间等待页（room.tscn + room.gd）

**Files:**
- Create: `scenes/room/room.tscn`、`scenes/room/room.gd`
- Modify: `tests/test_scenes.gd`（`_initialize` 加一行 + 文件末尾追加 `_check_room()`）

**Interfaces:**
- Consumes: `Session.pending_room_code/token/user`（Task 2）、`RoomSocket` 全套（Task 3）
- Produces: `res://scenes/room/room.tscn`——回调 `_on_ready_pressed/_on_add_bot_pressed/_on_remove_bot_pressed/_on_start_pressed/_on_reconnect_pressed/_on_back_home_pressed`；节点 `Background/Header/RoomCodeLabel`、`Background/Center/PlayerList`、`Background/Actions/ReadyButton`、`Background/Actions/BotRow/AddBotButton|RemoveBotButton`、`Background/Actions/StartGameButton`、`Background/DisconnectBar/ReconnectButton`、`Background/GameStartedOverlay`

- [ ] **Step 0: 并行编辑检查**

Run: `git status --short`
Expected: 除本任务将创建的文件外无 `scenes/` 或 `tests/test_scenes.gd` 的他人未提交改动；有则报告 BLOCKED 并附清单。

- [ ] **Step 1: 写失败的场景测试**

`tests/test_scenes.gd` 的 `_initialize()` 中 `await _check_friend_room()` 之后加一行：

```gdscript
	await _check_room()
```

文件末尾追加：

```gdscript


func _check_room() -> void:
	var scene := load("res://scenes/room/room.tscn") as PackedScene
	if scene == null:
		h.check(false, "room 场景可加载")
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	await process_frame
	h.check(page.get_node_or_null("Background/Header/RoomCodeLabel") != null, "room 房间号标签存在")
	h.check(page.get_node_or_null("Background/Center/PlayerList") != null, "room 玩家列表存在")
	h.check(page.get_node_or_null("Background/Actions/ReadyButton") != null, "room 准备按钮存在")
	h.check(page.get_node_or_null("Background/Actions/StartGameButton") != null, "room 开始按钮存在")
	h.check(page.get_node_or_null("Background/GameStartedOverlay") != null, "room 开局 overlay 存在")
	h.check(page.has_method("_on_ready_pressed"), "room 准备回调存在")
	h.check(page.has_method("_on_start_pressed"), "room 开始回调存在")
	h.check(page.has_method("_on_reconnect_pressed"), "room 重连回调存在")
	page.queue_free()
```

- [ ] **Step 2: 运行确认失败**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: `room 场景可加载` FAIL（场景不存在），总计数 27 passed + 1 failed 左右，非零退出码。

- [ ] **Step 3: 创建 room.tscn**

创建 `scenes/room/room.tscn`：

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Texture2D" path="res://assets/room/friend_room_bg.png" id="1_bg"]
[ext_resource type="Theme" path="res://themes/main_theme.tres" id="2_theme"]
[ext_resource type="Script" path="res://scenes/room/room.gd" id="3_script"]

[node name="Room" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
theme = ExtResource("2_theme")
script = ExtResource("3_script")

[node name="Background" type="TextureRect" parent="."]
texture = ExtResource("1_bg")
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
expand_mode = 1
stretch_mode = 6

[node name="Header" type="HBoxContainer" parent="Background"]
layout_mode = 1
anchors_preset = -1
anchor_left = 0.05
anchor_top = 0.05
anchor_right = 0.95
anchor_bottom = 0.12
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 24

[node name="RoomCodeLabel" type="Label" parent="Background/Header"]
theme_override_colors/font_color = Color(0.831373, 0.686275, 0.415686, 1)
theme_override_font_sizes/font_size = 40
text = "房间 ------"
vertical_alignment = 1

[node name="BackHomeButton" type="Button" parent="Background/Header"]
custom_minimum_size = Vector2(180, 64)
layout_mode = 2
size_flags_horizontal = 10
theme_type_variation = "SecondaryButton"
text = "离开房间"

[node name="Center" type="CenterContainer" parent="Background"]
layout_mode = 1
anchors_preset = -1
anchor_left = 0.3
anchor_top = 0.18
anchor_right = 0.7
anchor_bottom = 0.68
grow_horizontal = 2
grow_vertical = 2

[node name="PlayerList" type="VBoxContainer" parent="Background/Center"]
theme_override_constants/separation = 16

[node name="Actions" type="VBoxContainer" parent="Background"]
layout_mode = 1
anchors_preset = -1
anchor_left = 0.38
anchor_top = 0.7
anchor_right = 0.62
anchor_bottom = 0.92
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 14

[node name="ReadyButton" type="Button" parent="Background/Actions"]
custom_minimum_size = Vector2(320, 72)
layout_mode = 2
size_flags_horizontal = 4
text = "准备"

[node name="BotRow" type="HBoxContainer" parent="Background/Actions"]
layout_mode = 2
theme_override_constants/separation = 12

[node name="AddBotButton" type="Button" parent="Background/Actions/BotRow"]
custom_minimum_size = Vector2(154, 64)
layout_mode = 2
size_flags_horizontal = 4
theme_type_variation = "SecondaryButton"
text = "+ 机器人"

[node name="RemoveBotButton" type="Button" parent="Background/Actions/BotRow"]
custom_minimum_size = Vector2(154, 64)
layout_mode = 2
size_flags_horizontal = 4
theme_type_variation = "SecondaryButton"
text = "- 机器人"

[node name="StartGameButton" type="Button" parent="Background/Actions"]
custom_minimum_size = Vector2(320, 76)
layout_mode = 2
size_flags_horizontal = 4
text = "开始游戏"

[node name="StatusLabel" type="Label" parent="Background"]
layout_mode = 1
anchors_preset = -1
anchor_left = 0.15
anchor_top = 0.93
anchor_right = 0.85
anchor_bottom = 0.98
grow_horizontal = 2
grow_vertical = 2
theme_override_colors/font_color = Color(0.909804, 0.298039, 0.235294, 1)
theme_override_font_sizes/font_size = 24
text = ""
horizontal_alignment = 1

[node name="DisconnectBar" type="HBoxContainer" parent="Background"]
visible = false
layout_mode = 1
anchors_preset = 8
anchor_left = 0.35
anchor_top = 0.45
anchor_right = 0.65
anchor_bottom = 0.55
grow_horizontal = 2
grow_vertical = 2
theme_override_constants/separation = 16

[node name="TextLabel" type="Label" parent="Background/DisconnectBar"]
theme_override_font_sizes/font_size = 28
text = "房间连接已断开"

[node name="ReconnectButton" type="Button" parent="Background/DisconnectBar"]
custom_minimum_size = Vector2(200, 64)
layout_mode = 2
theme_type_variation = "SecondaryButton"
text = "重新连接"

[node name="GameStartedOverlay" type="ColorRect" parent="Background"]
visible = false
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
color = Color(0, 0, 0, 0.55)

[node name="CenterBox" type="CenterContainer" parent="Background/GameStartedOverlay"]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="VBox" type="VBoxContainer" parent="Background/GameStartedOverlay/CenterBox"]
theme_override_constants/separation = 16

[node name="Title" type="Label" parent="Background/GameStartedOverlay/CenterBox/VBox"]
theme_override_colors/font_color = Color(0.831373, 0.686275, 0.415686, 1)
theme_override_font_sizes/font_size = 48
text = "对局已开始"
horizontal_alignment = 1

[node name="Note" type="Label" parent="Background/GameStartedOverlay/CenterBox/VBox"]
theme_override_font_sizes/font_size = 26
text = "对局界面下一期开放，请保持连接"
horizontal_alignment = 1

[connection signal="pressed" from="Background/Header/BackHomeButton" to="." method="_on_back_home_pressed"]
[connection signal="pressed" from="Background/Actions/ReadyButton" to="." method="_on_ready_pressed"]
[connection signal="pressed" from="Background/Actions/BotRow/AddBotButton" to="." method="_on_add_bot_pressed"]
[connection signal="pressed" from="Background/Actions/BotRow/RemoveBotButton" to="." method="_on_remove_bot_pressed"]
[connection signal="pressed" from="Background/Actions/StartGameButton" to="." method="_on_start_pressed"]
[connection signal="pressed" from="Background/DisconnectBar/ReconnectButton" to="." method="_on_reconnect_pressed"]
```

- [ ] **Step 4: 创建 room.gd**

创建 `scenes/room/room.gd`：

```gdscript
extends Control
## 房间等待页：WS 实时渲染玩家/准备/机器人；房主开局；game_started 后显示占位 overlay
## （保持连接，断开会被后端判掉线代打）。断线显示重连条；离开房间=关闭 WS 回主页。

const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"

@onready var room_code_label: Label = $Background/Header/RoomCodeLabel
@onready var player_list: VBoxContainer = $Background/Center/PlayerList
@onready var ready_button: Button = $Background/Actions/ReadyButton
@onready var add_bot_button: Button = $Background/Actions/BotRow/AddBotButton
@onready var remove_bot_button: Button = $Background/Actions/BotRow/RemoveBotButton
@onready var start_button: Button = $Background/Actions/StartGameButton
@onready var status_label: Label = $Background/StatusLabel
@onready var disconnect_bar: Control = $Background/DisconnectBar
@onready var overlay: Control = $Background/GameStartedOverlay

var _socket: RoomSocket
var _view: Dictionary = {}
var _my_id := 0
var _room_code := ""


func _ready() -> void:
	_room_code = Session.pending_room_code
	Session.pending_room_code = ""
	_my_id = int(Session.user.get("id", 0))
	if _room_code == "":
		status_label.text = "缺少房间编号，请从主页进入"
		return
	room_code_label.text = "房间 %s" % _room_code
	_socket = RoomSocket.new()
	add_child(_socket)
	_socket.authenticated.connect(_on_authenticated)
	_socket.state_received.connect(_on_state)
	_socket.events_received.connect(_on_events)
	_socket.socket_error.connect(_on_socket_error)
	_socket.closed.connect(_on_closed)
	_socket.connect_room(Session.token, _room_code)


func _process(_delta: float) -> void:
	if _socket != null:
		_socket.poll()


func _on_authenticated() -> void:
	disconnect_bar.visible = false
	status_label.text = ""


func _on_state(view: Dictionary) -> void:
	_view = view
	_render()


func _on_events(events: Array, _version: int) -> void:
	for event in events:
		if str(event.get("event", "")) == "game_started":
			overlay.visible = true
			return


func _render() -> void:
	for child in player_list.get_children():
		child.queue_free()
	var players: Array = _view.get("players", [])
	var host_id := int(_view.get("host_id", 0))
	var is_host := host_id == _my_id
	var in_lobby := str(_view.get("status", "")) == "lobby"
	for player in players:
		var row := Label.new()
		var tags := ""
		if int(player.get("id", 0)) < 0:
			tags += "（机器人）"
		if int(player.get("id", 0)) == host_id:
			tags += "（房主）"
		if bool(player.get("ready", false)):
			tags += " ✓已准备"
		row.text = "%s%s" % [str(player.get("name", "")), tags]
		row.add_theme_font_size_override("font_size", 30)
		player_list.add_child(row)
	ready_button.text = "取消准备" if _is_ready(_my_id) else "准备"
	ready_button.disabled = not in_lobby
	add_bot_button.visible = is_host and in_lobby
	remove_bot_button.visible = is_host and in_lobby
	start_button.visible = is_host and in_lobby
	start_button.disabled = players.size() < 3


func _is_ready(player_id: int) -> bool:
	for player in _view.get("players", []):
		if int(player.get("id", 0)) == player_id:
			return bool(player.get("ready", false))
	return false


func _on_ready_pressed() -> void:
	_socket.set_ready(not _is_ready(_my_id))


func _on_add_bot_pressed() -> void:
	_socket.add_bot()


func _on_remove_bot_pressed() -> void:
	for player in _view.get("players", []):
		if int(player.get("id", 0)) < 0:
			_socket.remove_bot(int(player["id"]))
			return


func _on_start_pressed() -> void:
	start_button.disabled = true
	status_label.text = "正在开局…"
	_socket.start_game()


func _on_socket_error(message: String) -> void:
	status_label.text = message


func _on_closed() -> void:
	disconnect_bar.visible = true
	status_label.text = "房间连接已断开"


func _on_reconnect_pressed() -> void:
	disconnect_bar.visible = false
	status_label.text = "正在重新连接…"
	_socket.connect_room(Session.token, _room_code)


func _on_back_home_pressed() -> void:
	if _socket != null:
		_socket.close()
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		push_error("无法返回主页：%s" % error_string(error))
```

- [ ] **Step 5: 刷新缓存并运行确认通过**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: `== 35 passed, 0 failed ==`，退出码 0。

- [ ] **Step 6: 提交**

```bash
git add scenes/room/ tests/test_scenes.gd
git commit -m "feat: add room waiting scene with websocket wiring" --no-verify
```

---

### Task 5: 主页快速匹配流程（lobby.gd）

**Files:**
- Modify: `scenes/lobby/lobby.gd`（全文替换）
- Modify: `tests/test_scenes.gd`（`_check_lobby()` 尾部断言块替换）

**Interfaces:**
- Consumes: `Session.card().match_wait/match_cancel`（Task 2）、`Endpoints.match_drop_message`（Task 1）
- Produces: `_on_quick_match_pressed` 匹配/取消双态；`_set_match_mode(matching: bool)`；匹配期间禁用好友同玩与人数按钮；成功 `Session.pending_room_code` 置码后跳 `res://scenes/room/room.tscn`；`_on_friend_play_pressed` 设 `Session.pending_player_count`

**注意（计划核定的用户测试变更）**：现有断言 `"6 人" in StatusLabel.text`（lobby 匹配使用已选人数）与新契约冲突——后端匹配固定 3 人桌，spec §2 已核定文案不再承诺人数。本任务将该断言替换为「快速匹配中」匹配态断言。

- [ ] **Step 0: 并行编辑检查**

Run: `git status --short`
Expected: 无 `scenes/lobby/` 或 `tests/test_scenes.gd` 的他人未提交改动；有则报告 BLOCKED。

- [ ] **Step 1: 更新测试断言（先失败）**

`tests/test_scenes.gd` 的 `_check_lobby()` 中，将这段：

```gdscript
	page.get_node("Background/CountCenter/PlayerCountPanel/Count6Button").pressed.emit()
	page.get_node("Background/Actions/QuickMatchButton").pressed.emit()
	h.check(page.player_count == 6, "lobby 人数选择会更新")
	h.check("6 人" in page.get_node("Background/StatusLabel").text, "lobby 匹配使用已选人数")
```

替换为：

```gdscript
	page.get_node("Background/CountCenter/PlayerCountPanel/Count6Button").pressed.emit()
	h.check(page.player_count == 6, "lobby 人数选择会更新")
	page.get_node("Background/Actions/QuickMatchButton").pressed.emit()
	h.check("快速匹配中" in page.get_node("Background/StatusLabel").text, "lobby 快速匹配进入匹配态")
	h.check(page.has_method("_set_match_mode"), "lobby 匹配态切换存在")
```

Run: `/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: `lobby 快速匹配进入匹配态`、`lobby 匹配态切换存在` 2 项 FAIL（现状文案是「正在准备 6 人快速匹配…」且无 `_set_match_mode`），非零退出码。

- [ ] **Step 2: 重写 lobby.gd**

`scenes/lobby/lobby.gd` 全文替换为：

```gdscript
extends Control
## 登录后的主页：选择对局人数（用于好友建房），快速匹配（后端固定 3 人成桌）或好友同玩。

signal game_mode_selected(mode: String, player_count: int)

const LOGIN_SCENE := "res://scenes/login/login.tscn"
const FRIEND_ROOM_SCENE := "res://scenes/friend_room/friend_room.tscn"
const ROOM_SCENE := "res://scenes/room/room.tscn"
const QUICK_MATCH_LABEL_TEXT := "快速匹配"
const CANCEL_MATCH_LABEL_TEXT := "取消匹配"

@onready var name_label: Label = $Background/Header/NameLabel
@onready var balance_label: Label = $Background/Header/BalanceLabel
@onready var logout_button: Button = $Background/Header/LogoutButton
@onready var quick_match_button: TextureButton = $Background/Actions/QuickMatchButton
@onready var quick_match_label: Label = $Background/Actions/QuickMatchButton/Label
@onready var friend_play_button: TextureButton = $Background/Actions/FriendPlayButton
@onready var status_label: Label = $Background/StatusLabel

var player_count := 4
var _hover_tweens: Dictionary = {}
var _matching := false


func _ready() -> void:
	var display_name := str(Session.user.get("name", ""))
	if display_name.is_empty():
		display_name = "游客" if Session.is_guest() else "玩家"
	name_label.text = display_name
	balance_label.text = _format_balance(int(Session.user.get("balance", 0)))
	for count in range(3, 7):
		var button := get_node("Background/CountCenter/PlayerCountPanel/Count%dButton" % count) as Button
		button.pressed.connect(_on_player_count_pressed.bind(count))
	_setup_action_feedback(quick_match_button)
	_setup_action_feedback(friend_play_button)


func _on_player_count_pressed(count: int) -> void:
	if _matching:
		return
	player_count = count
	status_label.text = ""


func _on_quick_match_pressed() -> void:
	if _matching:
		_cancel_match()
	else:
		_start_match()


func _start_match() -> void:
	_set_match_mode(true)
	game_mode_selected.emit("quick_match", player_count)
	status_label.text = "快速匹配中…"
	while _matching:
		var res: Variant = await Session.card().match_wait(Session.token)
		if not is_inside_tree():
			return
		if res is ApiError:
			if res.is_network_error:
				status_label.text = "无法连接匹配服务，正在重试…"
				await get_tree().create_timer(2.0).timeout
				if not is_inside_tree():
					return
				continue
			_stop_match(res.message)
			return
		if res.has("room_code"):
			Session.pending_room_code = str(res["room_code"])
			_goto_room()
			return
		var match_status := str(res.get("status", ""))
		if match_status == "queued":
			status_label.text = "快速匹配中…（队列第 %d 位）" % int(res.get("position", 0))
		elif match_status == "dropped":
			_stop_match(Endpoints.match_drop_message(str(res.get("reason", ""))))
			return
		else:
			_stop_match("")
			return
	return


func _cancel_match() -> void:
	_matching = false
	_set_match_mode(false)
	status_label.text = "正在取消匹配…"
	var res: Variant = await Session.card().match_cancel(Session.token)
	if not is_inside_tree():
		return
	if res is ApiError:
		status_label.text = res.message
		return
	status_label.text = ""


func _stop_match(message: String) -> void:
	_set_match_mode(false)
	status_label.text = message


func _set_match_mode(matching: bool) -> void:
	_matching = matching
	quick_match_label.text = CANCEL_MATCH_LABEL_TEXT if matching else QUICK_MATCH_LABEL_TEXT
	friend_play_button.disabled = matching
	for count in range(3, 7):
		(get_node("Background/CountCenter/PlayerCountPanel/Count%dButton" % count) as Button).disabled = matching


func _on_friend_play_pressed() -> void:
	Session.pending_player_count = player_count
	game_mode_selected.emit("friend_play", player_count)
	var error := get_tree().change_scene_to_file(FRIEND_ROOM_SCENE)
	if error != OK:
		status_label.text = "无法打开好友同玩页面"
		push_error("无法打开好友同玩场景：%s" % error_string(error))


func _on_logout_pressed() -> void:
	logout_button.disabled = true
	await Session.logout()
	var error := get_tree().change_scene_to_file(LOGIN_SCENE)
	if error != OK:
		push_error("无法返回登录场景：%s" % error_string(error))


func _goto_room() -> void:
	var error := get_tree().change_scene_to_file(ROOM_SCENE)
	if error != OK:
		_stop_match("无法进入房间")
		push_error("无法进入房间场景：%s" % error_string(error))


func _setup_action_feedback(button: TextureButton) -> void:
	button.pivot_offset = button.size * 0.5
	button.mouse_entered.connect(_set_action_hover.bind(button, true))
	button.mouse_exited.connect(_set_action_hover.bind(button, false))


func _set_action_hover(button: TextureButton, hovered: bool) -> void:
	var previous: Tween = _hover_tweens.get(button)
	if previous != null and previous.is_valid():
		previous.kill()
	button.z_index = 1 if hovered else 0
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * (1.025 if hovered else 1.0), 0.14)
	tween.tween_property(button, "modulate", Color(1.16, 1.1, 1.22, 1.0) if hovered else Color.WHITE, 0.14)
	_hover_tweens[button] = tween


func _format_balance(value: int) -> String:
	var digits := str(value)
	var formatted := ""
	while digits.length() > 3:
		formatted = ",%s%s" % [digits.right(3), formatted]
		digits = digits.left(-3)
	return digits + formatted
```

说明：`match_cancel` 的 409 `already matched` 响应虽带 `room_code`，但经 ApiClient 归一化为 ApiError 后只剩 code/message——房间码由仍在飞行的 `match_wait` 长轮询返回（后端成桌会向两者投递），`_start_match` 循环负责跳转；`_cancel_match` 只显示文案（如「已匹配成功」）。

- [ ] **Step 3: 运行确认通过**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: `== 36 passed, 0 failed ==`，退出码 0（匹配协程在 headless 下快速失败于网络错误并由 `is_inside_tree` 守卫退出，不影响断言）。

- [ ] **Step 4: 提交**

```bash
git add scenes/lobby/lobby.gd tests/test_scenes.gd
git commit -m "feat: wire lobby quick match to card matchmaking" --no-verify
```

---

### Task 6: 好友房入口接入（friend_room.gd）

**Files:**
- Modify: `scenes/friend_room/friend_room.gd`（全文替换）
- Modify: `tests/test_scenes.gd`（`_check_friend_room()` 追加 2 项断言）

**Interfaces:**
- Consumes: `Session.card().create_room/join_room`（Task 2）、`Session.pending_player_count`
- Produces: 建房成功/加入成功 → `Session.pending_room_code` 置码 → 跳 `res://scenes/room/room.tscn`；房间码校验 `^[A-Z0-9]{6}$`

- [ ] **Step 0: 并行编辑检查**

Run: `git status --short`
Expected: 无 `scenes/friend_room/` 或 `tests/test_scenes.gd` 的他人未提交改动；有则报告 BLOCKED。

- [ ] **Step 1: 追加测试断言（先失败）**

`tests/test_scenes.gd` 的 `_check_friend_room()` 中 `page.queue_free()` 之前追加：

```gdscript
	page.get_node("Background/CodeCenter/CodePanel/RoomCodeInput").text = "abc12"
	page._on_join_room_pressed()
	h.check("房间编号为 6 位字母或数字" in page.get_node("Background/StatusLabel").text, "friend_room 非法编号被拒绝")
	h.check(page._busy == false, "friend_room 校验失败不进入忙态")
```

Run: `/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: `friend_room 非法编号被拒绝` FAIL（现状直接发加入请求，无此文案），非零退出码。

- [ ] **Step 2: 重写 friend_room.gd**

`scenes/friend_room/friend_room.gd` 全文替换为：

```gdscript
extends Control
## 好友同玩入口：创建房间，或输入房间编号加入房间（接 card 后端，成功后进房间等待页）。

signal create_room_requested
signal join_room_requested(room_code: String)

const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"
const ROOM_SCENE := "res://scenes/room/room.tscn"
const ROOM_CODE_PATTERN := "^[A-Z0-9]{6}$"

@onready var name_label: Label = $Background/Header/NameLabel
@onready var balance_label: Label = $Background/Header/BalanceLabel
@onready var back_home_button: Button = $Background/Header/BackHomeButton
@onready var create_room_button: TextureButton = $Background/ActionCenter/Actions/CreateRoomButton
@onready var join_room_button: TextureButton = $Background/ActionCenter/Actions/JoinRoomButton
@onready var room_code_input: LineEdit = $Background/CodeCenter/CodePanel/RoomCodeInput
@onready var status_label: Label = $Background/StatusLabel

var _hover_tweens: Dictionary = {}
var _busy := false


func _ready() -> void:
	var display_name := str(Session.user.get("name", ""))
	if display_name.is_empty():
		display_name = "游客" if Session.is_guest() else "玩家"
	name_label.text = display_name
	balance_label.text = _format_balance(int(Session.user.get("balance", 0)))
	for button in [create_room_button, join_room_button]:
		button.pivot_offset = button.size * 0.5
		button.mouse_entered.connect(_set_action_hover.bind(button, true))
		button.mouse_exited.connect(_set_action_hover.bind(button, false))


func _on_create_room_pressed() -> void:
	if _busy:
		return
	var max_players := Session.pending_player_count
	if max_players < 3 or max_players > 6:
		max_players = 6
	_busy = true
	create_room_button.disabled = true
	join_room_button.disabled = true
	status_label.text = "正在创建好友房间…"
	create_room_requested.emit()
	var res: Variant = await Session.card().create_room(Session.token, max_players)
	if not is_inside_tree():
		return
	_busy = false
	create_room_button.disabled = false
	join_room_button.disabled = false
	if res is ApiError:
		status_label.text = res.message
		return
	Session.pending_room_code = str(res.get("code", ""))
	var error := get_tree().change_scene_to_file(ROOM_SCENE)
	if error != OK:
		status_label.text = "无法进入房间"
		push_error("无法进入房间场景：%s" % error_string(error))


func _on_join_room_pressed() -> void:
	_join_room(room_code_input.text)


func _on_room_code_submitted(room_code: String) -> void:
	_join_room(room_code)


func _join_room(room_code: String) -> void:
	if _busy:
		return
	var normalized := room_code.strip_edges().to_upper()
	if normalized.is_empty():
		status_label.text = "请输入房间编号"
		room_code_input.grab_focus()
		return
	var re := RegEx.new()
	if re.compile(ROOM_CODE_PATTERN) != OK or re.search(normalized) == null:
		status_label.text = "房间编号为 6 位字母或数字"
		room_code_input.grab_focus()
		return
	_busy = true
	create_room_button.disabled = true
	join_room_button.disabled = true
	status_label.text = "正在加入房间 %s…" % normalized
	join_room_requested.emit(normalized)
	var res: Variant = await Session.card().join_room(Session.token, normalized)
	if not is_inside_tree():
		return
	_busy = false
	create_room_button.disabled = false
	join_room_button.disabled = false
	if res is ApiError:
		status_label.text = res.message
		return
	Session.pending_room_code = normalized
	var error := get_tree().change_scene_to_file(ROOM_SCENE)
	if error != OK:
		status_label.text = "无法进入房间"
		push_error("无法进入房间场景：%s" % error_string(error))


func _on_back_home_pressed() -> void:
	back_home_button.disabled = true
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		back_home_button.disabled = false
		push_error("无法返回主页：%s" % error_string(error))


func _set_action_hover(button: TextureButton, hovered: bool) -> void:
	var previous: Tween = _hover_tweens.get(button)
	if previous != null and previous.is_valid():
		previous.kill()
	button.z_index = 1 if hovered else 0
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", Vector2.ONE * (1.025 if hovered else 1.0), 0.14)
	tween.tween_property(button, "modulate", Color(1.16, 1.1, 1.22, 1.0) if hovered else Color.WHITE, 0.14)
	_hover_tweens[button] = tween


func _format_balance(value: int) -> String:
	var digits := str(value)
	var formatted := ""
	while digits.length() > 3:
		formatted = ",%s%s" % [digits.right(3), formatted]
		digits = digits.left(-3)
	return digits + formatted
```

- [ ] **Step 3: 运行确认通过**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: `== 38 passed, 0 failed ==`，退出码 0。

- [ ] **Step 4: 提交**

```bash
git add scenes/friend_room/friend_room.gd tests/test_scenes.gd
git commit -m "feat: wire friend room entry to card room api" --no-verify
```

---

### Task 7: 端到端验收（钱包配置 + live smoke + 回归 + 手动清单）

**Files:**
- Create: `tests/live_smoke_room.gd`

**Interfaces:**
- Consumes: `AuthApi.register`、`CardApi` 全套（Task 2）、`RoomSocket` 全套（Task 3）、真实后端（user :8888 + card :8890）
- Produces: 房间全链路自动化验收证据 + 手动走查结论

- [ ] **Step 1: 配置并启动两个后端**

```bash
WALLET=$(openssl rand -base64 32)
```
编辑 `/Users/dn/card/etc/card-api.yaml`：`wallet_token: ""` → `wallet_token: "<WALLET>"`。
编辑 `/Users/dn/user/etc/user-api.yaml`：`ServiceToken: "replace-me-with-openssl-rand-base64-32"` → `ServiceToken: "<WALLET>"`（同一值）。
重启 user（若在跑先 `kill <pid>` 或 `pkill -f user-api`）：`cd /Users/dn/user && nohup make run > /tmp/user-api.log 2>&1 &`。
启动 card：`cd /Users/dn/card && nohup go run ./cmd/card-api -config etc/card-api.yaml > /tmp/card-api.log 2>&1 &`。
验证：`curl -s localhost:8888/api/v1/healthz` 与 `curl -s localhost:8890/api/v1/healthz` 均返回 `{"code":0,...}`。跑完保留进程（手动走查还要用），报告里写明进程与停止方式。

- [ ] **Step 2: 写 live smoke**

创建 `tests/live_smoke_room.gd`：

```gdscript
extends SceneTree
## 房间链路端到端冒烟（需 user:8888 + card:8890 已启动且 wallet_token 已与 user ServiceToken 配对）
## 运行：/Users/dn/bin/godot --headless --script res://tests/live_smoke_room.gd
## 说明：真实匹配需 3 个真人并发排队，headless 单脚本无法并发长轮询，匹配链路由手动走查覆盖。

const Helper = preload("res://tests/test_helper.gd")
const AuthApi = preload("res://scripts/api/auth_api.gd")
const CardApi = preload("res://scripts/api/card_api.gd")
const RoomSocket = preload("res://scripts/ws/room_socket.gd")

var h := Helper.new()
var auth: AuthApi
var card: CardApi
var socket: RoomSocket

var my_id := 0
var player_count_seen := 0
var me_ready := false
var game_started := false


func _initialize() -> void:
	auth = AuthApi.new()
	root.add_child(auth)
	card = CardApi.new()
	root.add_child(card)
	socket = RoomSocket.new()
	root.add_child(socket)
	socket.state_received.connect(_on_state)
	socket.events_received.connect(_on_events)
	await process_frame
	_run()


func _on_state(view: Dictionary) -> void:
	player_count_seen = (view.get("players", []) as Array).size()
	me_ready = false
	for player in view.get("players", []):
		if int(player.get("id", 0)) == my_id:
			me_ready = bool(player.get("ready", false))


func _on_events(events: Array, _version: int) -> void:
	for event in events:
		if str(event.get("event", "")) == "game_started":
			game_started = true


func _run() -> void:
	var suffix: String = Crypto.new().generate_random_bytes(4).hex_encode()
	var reg: Variant = await auth.register("room_smoke_%s@test.local" % suffix, "password123")
	if reg is ApiError:
		h.check(false, "注册成功（%s）" % reg.message)
		h.finish(self)
		return
	h.check(true, "注册成功")
	var token: String = str(reg["token"])
	my_id = int(reg["user"]["id"])

	var room: Variant = await card.create_room(token, 3)
	h.check(not (room is ApiError) and str(room.get("status", "")) == "lobby", "建房成功且处于 lobby")
	if room is ApiError:
		h.finish(self)
		return
	var code: String = str(room.get("code", ""))

	socket.connect_room(token, code)
	var ok := await _wait_until(func() -> bool: return player_count_seen >= 1, 5.0)
	h.check(ok and player_count_seen == 1, "WS 认证并收到初始 state（1 玩家）")

	socket.add_bot()
	await _wait_until(func() -> bool: return player_count_seen >= 2, 5.0)
	socket.add_bot()
	ok = await _wait_until(func() -> bool: return player_count_seen >= 3, 5.0)
	h.check(ok and player_count_seen == 3, "加 2 个机器人后 3 玩家")

	socket.set_ready(true)
	ok = await _wait_until(func() -> bool: return me_ready, 5.0)
	h.check(ok, "set_ready 后自己变为已准备")

	socket.start_game()
	ok = await _wait_until(func() -> bool: return game_started, 10.0)
	h.check(ok, "start_game 后收到 game_started")

	socket.close()

	var bad: Variant = await card.join_room(token, "ZZZZZZ")
	h.check(bad is ApiError and bad.code == 404 and bad.message == "房间不存在", "加入不存在房间 → 404 房间不存在")

	h.finish(self)


func _wait_until(predicate: Callable, timeout_sec: float) -> bool:
	var waited := 0.0
	while waited < timeout_sec:
		socket.poll()
		if predicate.call():
			return true
		await create_timer(0.1).timeout
		waited += 0.1
	return predicate.call()
```

- [ ] **Step 3: 运行 live smoke**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/live_smoke_room.gd`
Expected: `== 7 passed, 0 failed ==`（注册/建房/初始 state/加机器人/准备/game_started/join 404），退出码 0。若 `game_started` 超时：查 `/tmp/card-api.log` 是否扣费失败（wallet_token 未配对/余额不足），修正后重跑。

- [ ] **Step 4: 全量回归**

Run: 依次运行 `res://tests/test_validators_endpoints.gd`、`test_api_client.gd`、`test_card_contract.gd`、`test_session_device.gd`、`test_card_api.gd`、`test_room_socket.gd`、`test_scenes.gd`、`live_smoke.gd`
Expected: 21 / 8 / 18 / 2 / 2 / 9 / 38 / 8 全部 0 failed。（live_smoke.gd 若遇 guest 限流 100006，等 10 分钟重跑一次。）

- [ ] **Step 5: 手动走查（人工，向用户汇报用）**

前置：两服务保持运行。编辑器 F5：
1. 登录 → 好友同玩 → 创建房间（选 5 人）→ 房间页显示房间号与 1 玩家
2. 第二个客户端（另开 Godot 实例或导出后另一窗口）登录另一账号 → 输入房间号加入 → 两端玩家列表实时同步
3. 双端准备 → 房主「开始游戏」→ 双端出现「对局已开始」占位 overlay；重启后端杀进程可观察断线提示与重连
4. 快速匹配：3 个客户端同时点（或 1 客户端 + 观察队列文案）→ 成桌进房间页；匹配中点「取消匹配」恢复
5. 余额不足的账号（后端把余额改小或用扣光账号）建房开局 → 「金币不足（需 200 入场费）」

- [ ] **Step 6: 提交**

```bash
git add tests/live_smoke_room.gd
git commit -m "test: add room flow live smoke against card backend" --no-verify
```
