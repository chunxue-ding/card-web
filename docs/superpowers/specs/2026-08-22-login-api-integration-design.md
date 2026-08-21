# card-web 登录接入后端 API 设计

日期：2026-08-22
前置：`2026-08-21-godot-login-layout-design.md`（登录页纯布局版）
后端：`/Users/dn/user`（go-zero, `:8888`，spec `2026-08-19-login-system-design.md`）

## 1. 目标与非目标

**目标**：把登录页的「登 录」与「游客一键登录」接到真实后端，登录成功进入极简大厅占位场景。

**非目标**：注册（「新建账号」）、忘记密码、token 持久化自动登录、Web 导出 CORS（首次导出时后端补 CORS 中间件）。

## 2. 后端契约（已核对 /Users/dn/user/api/user.api 与 errs.go）

| 接口 | 方法/路径 | 请求 | 成功响应 |
|---|---|---|---|
| 密码登录 | POST `/api/v1/auth/login` | `{email, password}` | `{token, user, is_new_user}` |
| 游客登录 | POST `/api/v1/auth/guest-login` | `{device_id}` | 同上 |
| 登出 | POST `/api/v1/auth/logout` | Bearer token | `{code:0, message}` |

- `user`：`{id, email, name, avatar_color, has_password, balance}`（email 游客为空串）
- 鉴权：`Authorization: Bearer <token>`；JWT 7 天有效、滑动续期
- **错误形态**：业务错误 HTTP 200 + `{code, message}`；未授权 HTTP 401；其余 HTTP 500
- 错误码：100001 参数不合法 / 100003 邮箱已注册 / 100004 邮箱或密码错误 / 100005 未设密码 / 100006 尝试过于频繁（游客登录按 IP 限流 10 分钟 5 次）
- 客户端前置校验与后端 `authx` 对齐：邮箱 `^[^@\s]+@[^@\s]+\.[^@\s]+$`，密码 ≥ 8 位

## 3. 架构（方案 C：完整客户端层）

```
UI(login.gd / lobby.gd)
  → Session(autoload，登录态)
    → AuthApi(业务方法)
      → ApiClient(HTTP + JSON + 错误归一化)
        → Endpoints / ApiError / AppConfig
```

新增文件：

| 文件 | 职责 |
|---|---|
| `scripts/config/app_config.gd` | `AppConfig.get_base_url()`：环境变量 `CARD_API_URL` → 默认 `http://127.0.0.1:8888` |
| `scripts/api/api_error.gd` | `ApiError`：`code`、`message`、`is_network_error`；供 UI 直接展示 |
| `scripts/api/endpoints.gd` | 路径常量；错误码枚举 + 中文消息映射（100001/100004/100006/401/-1） |
| `scripts/api/api_client.gd` | `ApiClient extends Node`：内部 HTTPRequest，`await post_json()/get_json()`；10s 超时 |
| `scripts/api/auth_api.gd` | `AuthApi.login/guest_login/logout`，返回 `(user_dict 或 ApiError)` |
| `scripts/session.gd` | autoload `Session`：持有 token/user；device_id 生成与持久化；登录/登出入口 |
| `scenes/login/login.gd` | 输入收集、前置校验、调 Session、错误展示、切场景 |
| `scenes/lobby/lobby.tscn` + `lobby.gd` | 极简大厅：昵称/邮箱或「游客」/余额 + 退出按钮 |

修改：`project.godot`（`[autoload] Session="*res://scripts/session.gd"`）、`login.tscn`（挂脚本、signal 连接、表单底部错误 Label）。

**错误归一化规则**（ApiClient 内）：
1. HTTPRequest result ≠ SUCCESS → `ApiError{-1, "无法连接服务器"}`（is_network_error）
2. HTTP 401 → `ApiError{401, "登录已过期"}`
3. body 含 `code` 且 ≠ 0 → `ApiError{code, 中文映射}`（未映射 code 兜底显示「服务异常，请稍后再试」）
4. 其余 → 返回 body Dictionary

## 4. 数据流

**密码登录**：点「登 录」→ 前置校验（不过直接显示错误）→ `await Session.login(email, pwd)` → 成功存 token/user 并 `change_scene_to_file` 到大厅；失败在错误 Label 显示中文消息。

**游客登录**：device_id 首次由 `Crypto` 生成 UUID，存 `user://device.cfg`（ConfigFile），之后复用（同一机器回到同一账号，对应后端 device 绑定复用）→ `Session.guest_login()` → 同上。

**退出（大厅）**：调 logout（失败忽略）→ 清 Session → 切回登录页。

**UI 反馈**：请求期间按钮 disabled + 文本「登录中…」；「忘记密码？」「新建账号」保持现状不接。

## 5. 验收（手动）

前置：`cd /Users/dn/user && make up && make run`。

1. curl 注册账号 → 编辑器 F5 密码登录 → 进大厅，昵称/余额正确
2. 错误密码 → 显示「邮箱或密码错误」，不切场景
3. 游客登录进大厅；退出后再游客登录 → 同一账号（日志确认 `is_new_user=false`）
4. 停掉后端 → 点登录 → 显示「无法连接服务器」

不引入 GUT 测试框架（规模不值），后端侧沿用其 `make smoke`。
