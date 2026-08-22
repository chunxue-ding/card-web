# 登录/注册/游客登录接入后端 API 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 card-web 登录页的「登 录」「游客一键登录」和注册页的「注 册」接到 `/Users/dn/user` 后端（go-zero, `:8888`），成功后进入极简大厅占位场景。

**Architecture:** 方案 C 完整客户端层——`UI 场景脚本 → Session(autoload) → AuthApi → ApiClient(HTTPRequest 封装 + 错误归一化) → Endpoints/ApiError/AppConfig/Validators`。分层见 spec `docs/superpowers/specs/2026-08-22-login-api-integration-design.md`。

**Tech Stack:** Godot 4.7.2（GDScript，tab 缩进）、HTTPRequest 节点、JSON/ConfigFile/Crypto 内置库。无第三方依赖、无测试框架——用 headless `--script` 测试脚本（SceneTree 子类 + 断言输出 + 退出码）。

## Global Constraints

- 所有命令在 `/Users/dn/card-web` 下执行；Godot 二进制：`/Users/dn/bin/godot`（4.7.2）。
- 新增 `class_name` 文件后必须先刷新导入缓存再跑测试：`/Users/dn/bin/godot --headless --import`（否则 `--script` 模式下全局类解析失败）。
- base URL 默认 `http://127.0.0.1:8888`，环境变量 `CARD_API_URL` 可覆盖（`AppConfig` 每次请求实时读取）。
- 后端错误形态：业务错误 **HTTP 200 + `{code,message}`**；未授权 HTTP 401；网络/超时由客户端判定。错误码与中文文案（verbatim，勿改）：100001「邮箱或密码格式不正确」/ 100003「该邮箱已注册」/ 100004「邮箱或密码错误」/ 100005「该账号未设置密码」/ 100006「尝试过于频繁，请稍后再试」/ 401「登录已过期，请重新登录」/ -1「无法连接服务器」/ 兜底「服务异常，请稍后再试」。
- 鉴权：`Authorization: Bearer <token>`；`Content-Type: application/json`；超时 10s。
- 邮箱正则 `^[^@\s]+@[^@\s]+\.[^@\s]+$`、密码 ≥ 8 位（与后端 `internal/authx` 对齐）。
- `scripts/session.gd` **不得**声明 `class_name Session`（与 autoload 名冲突）。
- 提交信息用 Conventional Commits（`feat:`/`test:`/`docs:`）。
- 本计划新增 `scripts/api/validators.gd`（spec 文件清单之外的 DRY 补充）：登录页与注册页共用前置校验，对应 spec §2「客户端前置校验与后端 authx 对齐」。

---

### Task 1: 纯逻辑层（AppConfig / ApiError / Endpoints / Validators）+ headless 测试基建

**Files:**
- Create: `tests/test_helper.gd`、`tests/test_validators_endpoints.gd`
- Create: `scripts/config/app_config.gd`、`scripts/api/api_error.gd`、`scripts/api/endpoints.gd`、`scripts/api/validators.gd`

**Interfaces:**
- Consumes: 无（首批文件）
- Produces（后续任务按此引用）:
  - `AppConfig.get_base_url() -> String`（static）
  - `ApiError`（RefCounted）：`code: int`、`message: String`、`is_network_error: bool`，`_init(p_code, p_message, p_network_error := false)`
  - `Endpoints.LOGIN/REGISTER/GUEST_LOGIN/LOGOUT`（const String）；`Endpoints.CODE_NETWORK=-1/CODE_INVALID_PARAM=100001/CODE_EMAIL_REGISTERED=100003/CODE_BAD_CREDENTIALS=100004/CODE_PASSWORD_NOT_SET=100005/CODE_TOO_MANY_ATTEMPTS=100006/CODE_UNAUTHORIZED=401`；`Endpoints.message_for(code) -> String`（static，未知码返回 `""`）
  - `Validators.valid_email(email) -> bool`、`Validators.password_ok(password) -> bool`（static）、`Validators.MIN_PASSWORD_LEN := 8`
  - `tests/test_helper.gd`：`check(condition, label)`、`finish(tree)`、`failures/passed` 计数

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_helper.gd`：

```gdscript
extends RefCounted
## headless 测试小工具：断言 + 汇总退出码（本项目不引入测试框架，见 spec §5）

var failures := 0
var passed := 0


func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS %s" % label)
	else:
		failures += 1
		printerr("FAIL %s" % label)


func finish(tree: SceneTree) -> void:
	print("== %d passed, %d failed ==" % [passed, failures])
	tree.quit(1 if failures > 0 else 0)
```

创建 `tests/test_validators_endpoints.gd`：

```gdscript
extends SceneTree
## 纯逻辑单测：Validators / Endpoints / AppConfig
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_validators_endpoints.gd

const Helper = preload("res://tests/test_helper.gd")
const Validators = preload("res://scripts/api/validators.gd")
const Endpoints = preload("res://scripts/api/endpoints.gd")
const AppConfig = preload("res://scripts/config/app_config.gd")

var h := Helper.new()


func _initialize() -> void:
	# Validators.valid_email
	h.check(Validators.valid_email("dn@example.com"), "valid_email 普通邮箱")
	h.check(Validators.valid_email("a.b+tag@sub.domain.org"), "valid_email 含加号与子域")
	h.check(not Validators.valid_email("plainaddress"), "valid_email 缺 @ 拒绝")
	h.check(not Validators.valid_email("a@b"), "valid_email 缺后缀拒绝")
	h.check(not Validators.valid_email("a b@x.com"), "valid_email 含空格拒绝")
	h.check(not Validators.valid_email(""), "valid_email 空串拒绝")
	# Validators.password_ok
	h.check(Validators.password_ok("12345678"), "password_ok 恰好 8 位")
	h.check(not Validators.password_ok("1234567"), "password_ok 7 位拒绝")
	# Endpoints 路径
	h.check(Endpoints.LOGIN == "/api/v1/auth/login", "LOGIN 路径")
	h.check(Endpoints.REGISTER == "/api/v1/auth/register", "REGISTER 路径")
	h.check(Endpoints.GUEST_LOGIN == "/api/v1/auth/guest-login", "GUEST_LOGIN 路径")
	h.check(Endpoints.LOGOUT == "/api/v1/auth/logout", "LOGOUT 路径")
	# Endpoints.message_for 中文映射
	h.check(Endpoints.message_for(100001) == "邮箱或密码格式不正确", "100001 消息")
	h.check(Endpoints.message_for(100003) == "该邮箱已注册", "100003 消息")
	h.check(Endpoints.message_for(100004) == "邮箱或密码错误", "100004 消息")
	h.check(Endpoints.message_for(100005) == "该账号未设置密码", "100005 消息")
	h.check(Endpoints.message_for(100006) == "尝试过于频繁，请稍后再试", "100006 消息")
	h.check(Endpoints.message_for(401) == "登录已过期，请重新登录", "401 消息")
	h.check(Endpoints.message_for(-1) == "无法连接服务器", "-1 消息")
	h.check(Endpoints.message_for(999999) == "", "未知码返回空串")
	# AppConfig
	h.check(AppConfig.get_base_url() != "", "base_url 非空")
	h.finish(self)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_validators_endpoints.gd`
Expected: FAIL（脚本解析错误，`Could not preload` — `validators.gd`/`endpoints.gd`/`app_config.gd` 尚不存在），非零退出码。

- [ ] **Step 3: 实现四个纯逻辑文件**

创建 `scripts/config/app_config.gd`：

```gdscript
class_name AppConfig
## 环境配置：API base URL 解析（环境变量 CARD_API_URL → 默认本机后端）

const DEFAULT_BASE_URL := "http://127.0.0.1:8888"


static func get_base_url() -> String:
	var from_env := OS.get_environment("CARD_API_URL")
	if from_env != "":
		return from_env
	return DEFAULT_BASE_URL
```

创建 `scripts/api/api_error.gd`：

```gdscript
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
```

创建 `scripts/api/endpoints.gd`：

```gdscript
class_name Endpoints
## API 路径与错误码，与 user 后端 api/user.api、internal/errs/errs.go 对齐

const LOGIN := "/api/v1/auth/login"
const REGISTER := "/api/v1/auth/register"
const GUEST_LOGIN := "/api/v1/auth/guest-login"
const LOGOUT := "/api/v1/auth/logout"

const CODE_NETWORK := -1
const CODE_INVALID_PARAM := 100001
const CODE_EMAIL_REGISTERED := 100003
const CODE_BAD_CREDENTIALS := 100004
const CODE_PASSWORD_NOT_SET := 100005
const CODE_TOO_MANY_ATTEMPTS := 100006
const CODE_UNAUTHORIZED := 401


static func message_for(code: int) -> String:
	match code:
		CODE_NETWORK:
			return "无法连接服务器"
		CODE_INVALID_PARAM:
			return "邮箱或密码格式不正确"
		CODE_EMAIL_REGISTERED:
			return "该邮箱已注册"
		CODE_BAD_CREDENTIALS:
			return "邮箱或密码错误"
		CODE_PASSWORD_NOT_SET:
			return "该账号未设置密码"
		CODE_TOO_MANY_ATTEMPTS:
			return "尝试过于频繁，请稍后再试"
		CODE_UNAUTHORIZED:
			return "登录已过期，请重新登录"
		_:
			return ""
```

创建 `scripts/api/validators.gd`：

```gdscript
class_name Validators
## 前置校验，与后端 internal/authx 规则对齐（邮箱正则、密码 ≥ 8 位）

const EMAIL_PATTERN := "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"
const MIN_PASSWORD_LEN := 8


static func valid_email(email: String) -> bool:
	var re := RegEx.new()
	if re.compile(EMAIL_PATTERN) != OK:
		push_error("邮箱正则编译失败")
		return false
	return re.search(email.strip_edges()) != null


static func password_ok(password: String) -> bool:
	return password.length() >= MIN_PASSWORD_LEN
```

- [ ] **Step 4: 刷新导入缓存并运行测试确认通过**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/test_validators_endpoints.gd`
Expected: 每行 `PASS ...`，最后一行 `== 21 passed, 0 failed ==`，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add tests/ scripts/
git commit -m "feat: add api config, error and validation primitives with headless tests"
```

---

### Task 2: ApiClient（错误归一化 + HTTP 请求封装）

**Files:**
- Create: `tests/test_api_client.gd`
- Create: `scripts/api/api_client.gd`

**Interfaces:**
- Consumes: `AppConfig.get_base_url()`、`ApiError._init`、`Endpoints`（Task 1）
- Produces:
  - `ApiClient.parse_response(http_result: int, status: int, body_text: String) -> Dictionary`（static）——返回 `{"ok": true, "data": Dictionary}` 或 `{"ok": false, "error": ApiError}`
  - `ApiClient extends Node`：`_ready()` 内建 HTTPRequest 子节点（timeout 10s）；`post_json(path: String, body: Dictionary, bearer_token := "") -> Dictionary`（async，await 调用）——返回同上 envelope；单飞（busy 时返回 `{"ok":false,"error":ApiError{-1,"请求进行中，请稍候"}}`）

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_api_client.gd`：

```gdscript
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_api_client.gd`
Expected: FAIL（`Could not preload` — `api_client.gd` 不存在），非零退出码。

- [ ] **Step 3: 实现 ApiClient**

创建 `scripts/api/api_client.gd`：

```gdscript
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
```

- [ ] **Step 4: 刷新缓存并运行测试确认通过**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/test_api_client.gd`
Expected: 8 个 PASS，`== 8 passed, 0 failed ==`，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add tests/test_api_client.gd scripts/api/api_client.gd
git commit -m "feat: add api client with normalized response parsing"
```

---

### Task 3: AuthApi + Session autoload（device_id 持久化）

**Files:**
- Create: `tests/test_session_device.gd`
- Create: `scripts/api/auth_api.gd`、`scripts/session.gd`
- Modify: `project.godot`（`[display]` 段之后、`[rendering]` 段之前插入 `[autoload]` 段）

**Interfaces:**
- Consumes: `ApiClient.post_json`、`Endpoints`、`ApiError`（Task 1-2）
- Produces:
  - `AuthApi extends Node`：`login(email, password) -> Variant`、`register(email, password) -> Variant`、`guest_login(device_id) -> Variant`（三者 async，成功返回 `{token, user, is_new_user}` Dictionary，失败返回 `ApiError`）；`logout(token) -> Variant`（成功返回 `{code,message}` Dictionary，失败 `ApiError`）
  - autoload `Session`（`scripts/session.gd`，**无 class_name**）：`token: String`、`user: Dictionary`、`is_new_user: bool`；`login(email, password) -> ApiError`、`register(email, password) -> ApiError`、`guest_login() -> ApiError`（async，成功返回 `null` 并写入状态）、`logout() -> void`（async，失败忽略并清态）、`is_logged_in() -> bool`、`is_guest() -> bool`（email 为空串即游客）、`get_device_id() -> String`（`user://device.cfg` 持久化）

- [ ] **Step 1: 写失败的测试**

创建 `tests/test_session_device.gd`：

```gdscript
extends SceneTree
## Session 的 device_id 生成与持久化（不发网络请求；直接实例化脚本，不依赖 autoload 注册）
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_session_device.gd

const Helper = preload("res://tests/test_helper.gd")
const SessionScript = preload("res://scripts/session.gd")

var h := Helper.new()


func _initialize() -> void:
	var first := SessionScript.new()
	root.add_child(first)  # 触发 _ready 挂 AuthApi（不发请求）
	var id1 := first.get_device_id()
	var id2 := first.get_device_id()
	h.check(id1 != "" and id1 == id2, "同实例两次取 device_id 一致")
	first.queue_free()
	# 新实例模拟重启 → 从 user://device.cfg 读回同一 id
	var second := SessionScript.new()
	root.add_child(second)
	h.check(second.get_device_id() == id1, "新实例复用持久化的 device_id")
	second.queue_free()
	h.finish(self)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_session_device.gd`
Expected: FAIL（`Could not preload` — `session.gd` 不存在），非零退出码。

- [ ] **Step 3: 实现 AuthApi 与 Session**

创建 `scripts/api/auth_api.gd`：

```gdscript
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
```

创建 `scripts/session.gd`：

```gdscript
extends Node
## 全局会话单例（autoload Session）：token/user 持有、device_id 持久化、登录/注册/游客/登出。
## 注意：不要声明 class_name Session，会与 autoload 名冲突。

const DEVICE_CFG_PATH := "user://device.cfg"

var token := ""
var user: Dictionary = {}
var is_new_user := false

var _api: AuthApi
var _device_id := ""


func _ready() -> void:
	_api = AuthApi.new()
	add_child(_api)


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

- [ ] **Step 4: 注册 autoload**

编辑 `project.godot`，在 `[display]` 段（`window/stretch/aspect="expand"` 行）之后、`[rendering]` 段之前插入：

```ini
[autoload]

Session="*res://scripts/session.gd"
```

- [ ] **Step 5: 刷新缓存并运行测试确认通过**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/test_session_device.gd`
Expected: 2 个 PASS，`== 2 passed, 0 failed ==`，退出码 0。

- [ ] **Step 6: 提交**

```bash
git add tests/test_session_device.gd scripts/api/auth_api.gd scripts/session.gd project.godot
git commit -m "feat: add auth api and session autoload with device persistence"
```

---

### Task 4: 登录页接线（ErrorLabel + signal + 登录/游客流程）

**Files:**
- Create: `tests/test_scenes.gd`
- Modify: `scenes/login/login.tscn`（CreateAccountButton 节点块后加 ErrorLabel 节点；文件末尾 connection 区加两条连接）
- Modify: `scenes/login/login.gd`（整体重写，保留 `_on_create_account_pressed` 语义）

**Interfaces:**
- Consumes: `Session.login/guest_login`（Task 3）、`Validators`（Task 1）、`ApiError.message`
- Produces: 登录页按钮行为——`LoginButton.pressed → _on_login_pressed()`、`GuestButton.pressed → _on_guest_pressed()`；错误显示于 `Background/Center/VBox/ErrorLabel`；成功 `change_scene_to_file("res://scenes/lobby/lobby.tscn")`（Task 6 提供该场景，本任务与 Task 6 完成前点击会报场景缺失——顺序执行即可）

- [ ] **Step 1: 写失败的场景接线测试**

创建 `tests/test_scenes.gd`：

```gdscript
extends SceneTree
## 场景接线冒烟：实例化各场景触发 _ready，验证 @onready 节点路径与按钮回调存在
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd

const Helper = preload("res://tests/test_helper.gd")

var h := Helper.new()


func _initialize() -> void:
	if Session == null:
		h.check(false, "Session autoload 未注册")
		h.finish(self)
		return
	_check_login()
	_check_register()
	_check_lobby()
	h.finish(self)


func _check_login() -> void:
	var scene := load("res://scenes/login/login.tscn") as PackedScene
	if scene == null:
		h.check(false, "login 场景可加载")
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	h.check(page.get_node_or_null("Background/Center/VBox/ErrorLabel") != null, "login ErrorLabel 存在")
	h.check(page.has_method("_on_login_pressed"), "login 登录回调存在")
	h.check(page.has_method("_on_guest_pressed"), "login 游客回调存在")
	h.check(page.has_method("_on_create_account_pressed"), "login 新建账号回调存在")
	page.queue_free()


func _check_register() -> void:
	var scene := load("res://scenes/register/register.tscn") as PackedScene
	if scene == null:
		h.check(false, "register 场景可加载")
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	h.check(page.get_node_or_null("Background/Center/VBox/ErrorLabel") != null, "register ErrorLabel 存在")
	h.check(page.has_method("_on_register_pressed"), "register 注册回调存在")
	h.check(page.has_method("_on_login_account_pressed"), "register 返回登录回调存在")
	page.queue_free()


func _check_lobby() -> void:
	var scene := load("res://scenes/lobby/lobby.tscn") as PackedScene
	if scene == null:
		h.check(false, "lobby 场景可加载")
		return
	var page := scene.instantiate() as Control
	root.add_child(page)
	h.check(page.get_node_or_null("Background/Center/VBox/LogoutButton") != null, "lobby LogoutButton 存在")
	h.check(page.has_method("_on_logout_pressed"), "lobby 登出回调存在")
	page.queue_free()
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: FAIL —— `login ErrorLabel 存在`、`login 登录回调存在`、`login 游客回调存在` 为 FAIL（register 的注册回调、lobby 场景同样未就绪，属后续任务），非零退出码。

- [ ] **Step 3: 修改 login.tscn**

在 `CreateAccountButton` 节点块（`underline = 1` 行）之后、`[connection]` 区之前插入：

```
[node name="ErrorLabel" type="Label" parent="Background/Center/VBox"]
custom_minimum_size = Vector2(560, 30)
layout_mode = 2
theme_override_colors/font_color = Color(0.909804, 0.298039, 0.235294, 1)
theme_override_font_sizes/font_size = 22
text = ""
horizontal_alignment = 1
```

在文件末尾现有 `[connection ... CreateAccountButton ...]` 行后追加两行：

```
[connection signal="pressed" from="Background/Center/VBox/LoginButton" to="." method="_on_login_pressed"]
[connection signal="pressed" from="Background/Center/VBox/GuestButton" to="." method="_on_guest_pressed"]
```

- [ ] **Step 4: 重写 login.gd**

将 `scenes/login/login.gd` 全文替换为：

```gdscript
extends Control
## 登录页：前置校验 → Session 密码登录 / 游客登录 → 进大厅；失败在表单底部展示错误

const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"
const REGISTER_SCENE := "res://scenes/register/register.tscn"
const LOGIN_NORMAL_TEXT := "登 录"
const LOGIN_LOADING_TEXT := "登录中…"
const GUEST_NORMAL_TEXT := "游客一键登录"

@onready var email_input: LineEdit = $Background/Center/VBox/EmailInput
@onready var password_input: LineEdit = $Background/Center/VBox/PasswordInput
@onready var login_button: Button = $Background/Center/VBox/LoginButton
@onready var guest_button: Button = $Background/Center/VBox/GuestButton
@onready var error_label: Label = $Background/Center/VBox/ErrorLabel


func _on_login_pressed() -> void:
	var email := email_input.text.strip_edges()
	var password := password_input.text
	if not Validators.valid_email(email):
		_show_error("请输入正确的邮箱地址")
		return
	if not Validators.password_ok(password):
		_show_error("密码至少 8 位")
		return
	_clear_error()
	_set_loading(login_button, true)
	var err: ApiError = await Session.login(email, password)
	_set_loading(login_button, false)
	if err != null:
		_show_error(err.message)
		return
	_goto_lobby()


func _on_guest_pressed() -> void:
	_clear_error()
	_set_loading(guest_button, true)
	var err: ApiError = await Session.guest_login()
	_set_loading(guest_button, false)
	if err != null:
		_show_error(err.message)
		return
	_goto_lobby()


func _on_create_account_pressed() -> void:
	var error := get_tree().change_scene_to_file(REGISTER_SCENE)
	if error != OK:
		push_error("无法打开注册场景：%s" % error_string(error))


func _show_error(message: String) -> void:
	error_label.text = message


func _clear_error() -> void:
	error_label.text = ""


func _set_loading(button: Button, loading: bool) -> void:
	button.disabled = loading
	button.text = LOGIN_LOADING_TEXT if loading else (LOGIN_NORMAL_TEXT if button == login_button else GUEST_NORMAL_TEXT)


func _goto_lobby() -> void:
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		push_error("无法进入大厅场景：%s" % error_string(error))
```

- [ ] **Step 5: 运行测试确认登录部分通过**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: login 相关 4 项 PASS；register 注册回调、lobby 相关仍 FAIL（后续任务实现），整体非零退出码——本步只确认 login 项全 PASS 且无脚本解析错误。

- [ ] **Step 6: 提交**

```bash
git add tests/test_scenes.gd scenes/login/
git commit -m "feat: wire login scene to session login flows"
```

---

### Task 5: 注册页接线（placeholder/ErrorLabel/signal + 注册流程）

**Files:**
- Modify: `scenes/register/register.tscn`（`AccountInput` 的 `placeholder_text = "账号"` 改 `"邮箱"`；`ExistingAccount` 节点块后加 ErrorLabel；connection 区追加一条）
- Modify: `scenes/register/register.gd`（整体重写，保留 `_on_login_account_pressed` 语义）
- Test: `tests/test_scenes.gd`（Task 4 已含 register 断言，无需改）

**Interfaces:**
- Consumes: `Session.register`（Task 3）、`Validators`（Task 1）
- Produces: `RegisterButton.pressed → _on_register_pressed()`；前置校验含两次密码一致；成功进 `res://scenes/lobby/lobby.tscn`

- [ ] **Step 1: 运行场景测试确认当前失败项**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: `register ErrorLabel 存在`、`register 注册回调存在` FAIL。

- [ ] **Step 2: 修改 register.tscn**

1. `AccountInput` 节点块内：`placeholder_text = "账号"` → `placeholder_text = "邮箱"`（后端仅支持邮箱注册，对齐输入预期）。
2. 在 `ExistingAccount` 节点块（其子节点 `LoginAccountButton` 的 `underline = 1` 行）之后、`[connection]` 区之前插入：

```
[node name="ErrorLabel" type="Label" parent="Background/Center/VBox"]
custom_minimum_size = Vector2(560, 30)
layout_mode = 2
theme_override_colors/font_color = Color(0.909804, 0.298039, 0.235294, 1)
theme_override_font_sizes/font_size = 22
text = ""
horizontal_alignment = 1
```

3. 文件末尾追加：

```
[connection signal="pressed" from="Background/Center/VBox/RegisterButton" to="." method="_on_register_pressed"]
```

- [ ] **Step 3: 重写 register.gd**

将 `scenes/register/register.gd` 全文替换为：

```gdscript
extends Control
## 注册页：前置校验（两次密码一致）→ Session 注册（后端注册即登录）→ 进大厅

const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"
const LOGIN_SCENE := "res://scenes/login/login.tscn"
const REGISTER_NORMAL_TEXT := "注 册"
const REGISTER_LOADING_TEXT := "注册中…"

@onready var email_input: LineEdit = $Background/Center/VBox/AccountInput
@onready var password_input: LineEdit = $Background/Center/VBox/PasswordInput
@onready var confirm_input: LineEdit = $Background/Center/VBox/ConfirmPasswordInput
@onready var register_button: Button = $Background/Center/VBox/RegisterButton
@onready var error_label: Label = $Background/Center/VBox/ErrorLabel


func _on_register_pressed() -> void:
	var email := email_input.text.strip_edges()
	var password := password_input.text
	if not Validators.valid_email(email):
		_show_error("请输入正确的邮箱地址")
		return
	if not Validators.password_ok(password):
		_show_error("密码至少 8 位")
		return
	if password != confirm_input.text:
		_show_error("两次输入的密码不一致")
		return
	_clear_error()
	_set_loading(true)
	var err: ApiError = await Session.register(email, password)
	_set_loading(false)
	if err != null:
		_show_error(err.message)
		return
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		push_error("无法进入大厅场景：%s" % error_string(error))


func _on_login_account_pressed() -> void:
	var error := get_tree().change_scene_to_file(LOGIN_SCENE)
	if error != OK:
		push_error("无法返回登录场景：%s" % error_string(error))


func _show_error(message: String) -> void:
	error_label.text = message


func _clear_error() -> void:
	error_label.text = ""


func _set_loading(loading: bool) -> void:
	register_button.disabled = loading
	register_button.text = REGISTER_LOADING_TEXT if loading else REGISTER_NORMAL_TEXT
```

- [ ] **Step 4: 运行测试确认 register 项通过**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: register 相关 4 项 PASS；lobby 项仍 FAIL，整体非零退出码。

- [ ] **Step 5: 提交**

```bash
git add scenes/register/
git commit -m "feat: wire register scene to session register flow"
```

---

### Task 6: 大厅占位场景 + 退出登录

**Files:**
- Create: `scenes/lobby/lobby.tscn`、`scenes/lobby/lobby.gd`
- Test: `tests/test_scenes.gd`（已含 lobby 断言，无需改）

**Interfaces:**
- Consumes: `Session.user/is_guest/logout`（Task 3）；`assets/login/login_bg.png`、`themes/main_theme.tres`
- Produces: `res://scenes/lobby/lobby.tscn`——`LogoutButton.pressed → _on_logout_pressed()`；显示 `昵称/账号（游客标识）/余额`

- [ ] **Step 1: 运行场景测试确认 lobby 项失败**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: `lobby 场景可加载` FAIL。

- [ ] **Step 2: 创建 lobby.tscn**

创建 `scenes/lobby/lobby.tscn`：

```
[gd_scene load_steps=4 format=3]

[ext_resource type="Texture2D" path="res://assets/login/login_bg.png" id="1_bg"]
[ext_resource type="Theme" path="res://themes/main_theme.tres" id="2_theme"]
[ext_resource type="Script" path="res://scenes/lobby/lobby.gd" id="3_script"]

[node name="Lobby" type="Control"]
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

[node name="Center" type="CenterContainer" parent="Background"]
layout_mode = 1
anchors_preset = 8
grow_horizontal = 2
grow_vertical = 2

[node name="VBox" type="VBoxContainer" parent="Background/Center"]
theme_override_constants/separation = 24

[node name="TitleLabel" type="Label" parent="Background/Center/VBox"]
theme_override_colors/font_color = Color(0.831373, 0.686275, 0.415686, 1)
theme_override_font_sizes/font_size = 48
text = "大 厅"
horizontal_alignment = 1

[node name="NameLabel" type="Label" parent="Background/Center/VBox"]
theme_override_font_sizes/font_size = 32
text = "昵称："
horizontal_alignment = 1

[node name="EmailLabel" type="Label" parent="Background/Center/VBox"]
theme_override_font_sizes/font_size = 28
text = "账号："
horizontal_alignment = 1

[node name="BalanceLabel" type="Label" parent="Background/Center/VBox"]
theme_override_font_sizes/font_size = 28
text = "余额："
horizontal_alignment = 1

[node name="Gap" type="Control" parent="Background/Center/VBox"]
custom_minimum_size = Vector2(0, 40)
layout_mode = 2
mouse_filter = 2

[node name="LogoutButton" type="Button" parent="Background/Center/VBox"]
custom_minimum_size = Vector2(440, 84)
layout_mode = 2
size_flags_horizontal = 4
theme_type_variation = "SecondaryButton"
text = "退出登录"

[connection signal="pressed" from="Background/Center/VBox/LogoutButton" to="." method="_on_logout_pressed"]
```

- [ ] **Step 3: 创建 lobby.gd**

创建 `scenes/lobby/lobby.gd`：

```gdscript
extends Control
## 大厅占位：展示登录用户信息；退出登录（调 logout，失败忽略）后回登录页

const LOGIN_SCENE := "res://scenes/login/login.tscn"

@onready var name_label: Label = $Background/Center/VBox/NameLabel
@onready var email_label: Label = $Background/Center/VBox/EmailLabel
@onready var balance_label: Label = $Background/Center/VBox/BalanceLabel
@onready var logout_button: Button = $Background/Center/VBox/LogoutButton


func _ready() -> void:
	name_label.text = "昵称：%s" % str(Session.user.get("name", ""))
	if Session.is_guest():
		email_label.text = "账号：游客"
	else:
		email_label.text = "账号：%s" % str(Session.user.get("email", ""))
	balance_label.text = "余额：%d" % int(Session.user.get("balance", 0))


func _on_logout_pressed() -> void:
	logout_button.disabled = true
	await Session.logout()
	var error := get_tree().change_scene_to_file(LOGIN_SCENE)
	if error != OK:
		push_error("无法返回登录场景：%s" % error_string(error))
```

- [ ] **Step 4: 运行场景测试确认全部通过**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: 全部 PASS，`== 9 passed, 0 failed ==`，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add scenes/lobby/
git commit -m "feat: add lobby placeholder scene with logout"
```

---

### Task 7: 端到端验收（live smoke + 手动清单）

**Files:**
- Create: `tests/live_smoke.gd`

**Interfaces:**
- Consumes: `AuthApi` 全部方法（Task 3）、`ApiClient` 网络错误分支（Task 2）、真实后端（`/Users/dn/user`）
- Produces: 自动化 spec §5 验收项 1-5 的接口层等价物 + 手动 UI 走查结论

- [ ] **Step 1: 启动后端**

Run: `cd /Users/dn/user && make up && make run`（后者前台运行；另开终端继续。若 docker 已起可跳过 `make up`）
Expected: 服务监听 `:8888`，`curl -s localhost:8888/api/v1/healthz` 返回 `{"code":0,"message":"ok"}`。

- [ ] **Step 2: 写 live smoke 脚本**

创建 `tests/live_smoke.gd`：

```gdscript
extends SceneTree
## 端到端冒烟（需后端已启动：make up && make run）
## 运行：/Users/dn/bin/godot --headless --script res://tests/live_smoke.gd
## 注意：guest-login 按 IP 限流（10 分钟 5 次），10 分钟内不要跑超过 2 次。

const Helper = preload("res://tests/test_helper.gd")
const AuthApi = preload("res://scripts/api/auth_api.gd")

var h := Helper.new()
var api: AuthApi


func _initialize() -> void:
	api = AuthApi.new()
	root.add_child(api)
	_run()


func _run() -> void:
	var suffix: String = Crypto.new().generate_random_bytes(4).hex_encode()
	var email := "smoke_%s@test.local" % suffix
	var password := "password123"

	# 1. 注册 → 注册即登录
	var reg: Variant = await api.register(email, password)
	h.check(not (reg is ApiError) and reg.get("is_new_user") == true, "注册成功且 is_new_user=true")
	var user_id: int = int(reg["user"]["id"]) if not (reg is ApiError) else -1

	# 2. 重复注册 → 100003
	var dup: Variant = await api.register(email, password)
	h.check(dup is ApiError and dup.code == 100003, "重复注册 → 100003")

	# 3. 密码登录同一账号
	var login: Variant = await api.login(email, password)
	h.check(not (login is ApiError) and int(login["user"]["id"]) == user_id, "密码登录同一 user_id")
	var token: String = str(login["token"]) if not (login is ApiError) else ""

	# 4. 错误密码 → 100004
	var bad: Variant = await api.login(email, "wrongpass1")
	h.check(bad is ApiError and bad.code == 100004, "错误密码 → 100004")

	# 5. 登出 → code=0
	var out: Variant = await api.logout(token)
	h.check(not (out is ApiError) and int(out.get("code", -1)) == 0, "登出 code=0")

	# 6. 游客登录两次（同一 device_id）→ 同一 user，第二次 is_new_user=false
	var device_id := "smoke-device-%s" % suffix
	var g1: Variant = await api.guest_login(device_id)
	h.check(not (g1 is ApiError) and int(g1["user"]["balance"]) == 5000, "游客登录成功且初始余额 5000")
	var g2: Variant = await api.guest_login(device_id)
	h.check(not (g2 is ApiError) and int(g2["user"]["id"]) == int(g1["user"]["id"]) \
		and g2.get("is_new_user") == false, "游客复用同一账号且非新用户")

	# 7. 后端不可达 → 网络错误
	OS.set_environment("CARD_API_URL", "http://127.0.0.1:1")
	var dead: Variant = await api.login(email, password)
	h.check(dead is ApiError and dead.is_network_error, "后端不可达 → 网络错误")
	OS.set_environment("CARD_API_URL", "")

	h.finish(self)
```

- [ ] **Step 3: 运行 live smoke**

Run: `/Users/dn/bin/godot --headless --import && /Users/dn/bin/godot --headless --script res://tests/live_smoke.gd`
Expected: 8 个 PASS，`== 8 passed, 0 failed ==`，退出码 0。（若 100006 项失败且 message 为限流，等 10 分钟重跑。）

- [ ] **Step 4: 回归全部单测**

Run: `/Users/dn/bin/godot --headless --script res://tests/test_validators_endpoints.gd && /Users/dn/bin/godot --headless --script res://tests/test_api_client.gd && /Users/dn/bin/godot --headless --script res://tests/test_session_device.gd && /Users/dn/bin/godot --headless --script res://tests/test_scenes.gd`
Expected: 四个脚本全部 0 failed，退出码 0。

- [ ] **Step 5: 手动 UI 走查（spec §5）**

编辑器 F5（需后端保持运行），逐项确认并向用户汇报：
1. 注册页注册新邮箱 → 直接进大厅，昵称/余额正确
2. 重复注册同一邮箱 → 「该邮箱已注册」；两次密码不一致 → 客户端提示
3. 密码登录 → 进大厅；错误密码 → 「邮箱或密码错误」不切场景
4. 游客登录进大厅；退出后再游客登录 → 同一账号（输出栏确认 `is_new_user=false`）
5. 停掉后端（`make down` 或杀进程）→ 点登录 → 「无法连接服务器」

- [ ] **Step 6: 提交**

```bash
git add tests/live_smoke.gd
git commit -m "test: add end-to-end live smoke against user backend"
```
