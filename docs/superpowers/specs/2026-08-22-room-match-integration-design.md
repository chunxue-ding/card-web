# card-web 匹配/好友房间接入 card 后端设计（到开局为止）

日期：2026-08-22
前置：`2026-08-22-login-api-integration-design.md`（登录接入，已落地）
后端：`/Users/dn/card`（Go stdlib + x/net/websocket，`:8890`，内存态无 DB）

## 1. 目标与非目标

**目标**：主页「快速匹配」「好友同玩（创建/加入房间）」接到真实 card 后端；新建功能占位房间等待页（WS 实时：玩家列表/准备/机器人/开始游戏）；以收到 `game_started` 事件为终点——显示「对局已开始，对局界面下一期」占位 overlay 并**保持 WS 连接**（断开会被后端判掉线代打）。

**非目标**：对局桌面 UI（发牌/筹码认领/四阶段/结算/game_over，下一期 spec）、忘记密码、token 持久化、Web 导出 CORS。

## 2. 后端契约要点（已核对 /Users/dn/card）

| 接口 | 方法/路径 | 说明 |
|---|---|---|
| 建房 | POST `/api/v1/rooms`，body `{max_players: 3..6}`（可选，默认 6） | 201 `{room}`；409 `cancel matchmaking first`/`max_players must be 3..6` |
| 加入 | POST `/api/v1/rooms/{code}/join` | 200 `{room}`；404 `room not found`；409 `room is full`/`game already started` |
| 查询 | GET `/api/v1/rooms/{code}` | 200 `{room}`；403 `join the room first` |
| 匹配 | POST `/api/v1/match`（无 body，**长轮询最长 25s**） | 成桌 `{room_code}`；续约 `{status:"queued",position}`；`{status:"cancelled"}`；`{status:"dropped",reason}` |
| 取消 | POST `/api/v1/match/cancel` | `{status:"cancelled"}`；409 `already matched`（可能带 `room_code`） |
| WS | `ws://…:8890/api/v1/ws` | 连接后 10s 内首帧 `{"type":"authenticate","token":…,"room_code":…}`；成功即收 `{type:"state",state:View}` |

- **鉴权**：全部 Bearer JWT（card 转发到 user `/users/me` 校验）
- **错误格式与 user 不同**：HTTP 401/403/404/409/502 + `{"code":<HTTP状态>, "message"}`
- **匹配固定 3 人成桌**（matcher `freezeLocked` 至多取 3 人）；人数选择只对建房生效
- WS 信封：`{type:"state"|"events"|"error", state?, events?, version?, error?}`，广播顺序 events→state（version 一致）
- 房间等待期指令：`set_ready{ready}`、`add_bot`、`remove_bot{player_id}`（负数 id）、`start_game`（触发扣费）
- `room` View 关键字段：`code/host_id/max_players/status("lobby")/players[{id,name,avatar_color,ready,confirmed,balance}]/version`
- 经济：入场费 200/人（`start_game` 扣）；奖励 500×N/人（胜利发）；余额不足 409 `insufficient balance`

## 3. 运行前提（验收前置）

1. user（:8888）+ card（:8890）都启动：card 为 `cd /Users/dn/card && go run ./cmd/card-api -config etc/card-api.yaml`
2. **开局扣费配置**：card `etc/card-api.yaml` 的 `wallet_token` 与 user `etc/user-api.yaml` 的 `Wallet.ServiceToken` 配成同值（当前均为占位符；不配则 `start_game` 报 `account service unavailable` 类失败）
3. 账号余额 ≥ 200

## 4. 架构（方案 B：对等分层）

```
lobby.gd / friend_room.gd / room.gd（场景脚本）
  → Session(autoload，新增 pending_room_code)
    → CardApi（建房/加入/查询/匹配/取消）
      → ApiClient（小重构：构造注入 base_url；post_json 可选 timeout）
room.gd ← RoomSocket（WebSocketPeer 封装，room 页 _process 驱动 poll）
```

| 文件 | 职责 |
|---|---|
| `scripts/config/app_config.gd`（改） | 新增 `get_card_base_url()`：env `CARD_CARD_URL` → `http://127.0.0.1:8890` |
| `scripts/api/api_client.gd`（改） | 构造参数 `base_url := ""`（空则取 user 的 `AppConfig.get_base_url()`，向后兼容）；`post_json`/`get_json` 增加 `timeout := 0.0` 参数（0 用默认 10s）；归一化规则扩展（§5） |
| `scripts/api/card_api.gd`（新，`class_name CardApi extends Node`） | `create_room(max_players) -> Variant`（room dict/ApiError）、`join_room(code)`、`get_room(code)`、`match_wait()`（**单次**长轮询，timeout 30s，返回原始 dict 或 ApiError）、`match_cancel()` |
| `scripts/ws/room_socket.gd`（新，`class_name RoomSocket extends Node`） | `connect_room(token, code)`（连 WS + 发 authenticate 首帧）；信号 `authenticated()`、`state_received(view)`、`events_received(events, version)`、`socket_error(message)`、`closed()`；指令方法 `set_ready(bool)/add_bot()/remove_bot(id)/start_game()`；`poll()` 由宿主每帧调；`close()`；信封解析为 static 纯函数（可单测） |
| `scripts/session.gd`（改） | 新增 `pending_room_code := ""`（跨场景传房间码）与 `pending_player_count := 0`（lobby 人数选择传给 friend_room 建房用） |
| `scenes/room/room.tscn`+`room.gd`（新，功能占位） | 房间号展示（可复制）、玩家列表（名字/准备✓/房主标记/余额）、「准备」toggle、「+机器人」「-机器人」（仅房主）、「开始游戏」（仅房主且人≥3）、「离开房间」（断开 WS 回主页）、断线提示+「重连」、`game_started` → 占位 overlay「对局已开始，对局界面下一期」 |
| `scenes/lobby/lobby.gd`（改） | 快速匹配流程：按钮 loading 态变「取消匹配」、状态「匹配中…(队列第 N 位)」；成桌→存码→切房间页；取消路径处理 `already matched`+`room_code` |
| `scenes/friend_room/friend_room.gd`（改） | 建房→`CardApi.create_room(player_count)`→存码进房页；加入→客户端校验 6 位大写字母数字→`join_room`→进房页；错误显示 status_label |

视觉：房间页沿用现有风格（背景图/主题/TextureButton 悬停反馈同 lobby），结构可被用户随时重新蒙皮——逻辑全在 room.gd。

## 5. ApiClient 归一化扩展

在既有规则（网络失败/401/HTTP200+code≠0/成功）的 401 分支之后新增：

- **HTTP ≥ 400 且 body 为含 `code` 的 JSON → `ApiError{code, message}`**（code 用 body 值，message 优先 body 原文，再套 §6 中文映射）
- 201/200 照旧成功；既有 user 形态行为不变（新增回归用例锁定）

## 6. 错误文案（card 语义中文映射，加进 Endpoints）

`insufficient balance`→「金币不足（需 200 入场费）」；`room not found`→「房间不存在」；`room is full`→「房间已满」；`game already started`→「对局已开始」；`cancel matchmaking first`/`already in a room`→「请先退出当前房间或取消匹配」；`already matched`→「已匹配成功」；`at least 3 players required`→「至少需要 3 名玩家」；`every player must be ready`→「还有玩家未准备」；`account service unavailable`→「账号服务暂不可用」；401 沿用「登录已过期，请重新登录」。

匹配 `dropped.reason`：`insufficient balance`→「金币不足」；`expired`→「匹配超时，请重试」；`joined another room`→「已加入其他房间」；其余→「匹配失败，请重试」。

WS error 帧文案：`unauthorized`→「登录已过期，请重新登录」；`room not found or not joined`→「房间不存在或未加入」；其余→显示原文。

## 7. 数据流

**快速匹配（lobby）**：点「快速匹配」→ 状态「匹配中…」，按钮变「取消匹配」→ 循环 `await CardApi.match_wait()`：`queued` → 更新「队列第 N 位」继续下一轮；`cancelled` → 恢复初始态；`dropped` → 显示 reason 文案并恢复；有 `room_code` → `Session.pending_room_code` 置码 → 切房间页。点「取消匹配」→ `match_cancel()`：`cancelled` 恢复；`already matched` 且带 `room_code` → 直接进房页。匹配期间禁用人数选择与好友同玩按钮（后端 409 约束）。

**建房（friend_room）**：点「创建房间」→ `create_room(player_count)`（3-6 来自主页选择，经 Session 或场景参数传入——**经 `Session.pending_player_count`** 传递）→ 201 → 存码 → 切房间页。

**加入（friend_room）**：输入/回车 → 客户端校验（6 位、`A-Z0-9`，自动转大写去空格）→ `join_room(code)` → 成功存码进房页；失败 status_label 显示文案。

**房间页（room）**：`_ready` 读 `pending_room_code` → `RoomSocket.connect_room(Session.token, code)` → `authenticated` 后清 pending；`state_received` 全量渲染（含 version）；`events_received` 记录事件（本期以随后的 state 重渲染为准，不做增量动画）；`game_started` 在 events 中 → 显示 overlay；断线（`closed`）→ 提示 + 「重连」按钮（重连即重新 connect_room，后端 `Reconnect` 清除代打标记）；「离开房间」→ `close()` → 回主页。

## 8. 测试与验收

**单测（headless，沿用 tests/ 模式）**：
- ApiClient 归一化：card 409 形态 / 201 成功 / 502 / user 200+code≠0 回归
- CardApi 无网络错误分支（连不可达端口 → ApiError network）
- RoomSocket 信封解析（static）：state/events/error 三形态、version 提取、坏 JSON
- 场景接线冒烟（test_scenes.gd 扩展）：room 页节点/回调存在；lobby 匹配按钮态切换函数存在

**live smoke（tests/live_smoke_room.gd，需 user+card+wallet_token 配置）**：
1. 注册/登录拿 token（复用 AuthApi）→ 建房（max_players=3）→ WS authenticate → 收 state（1 玩家）→ `add_bot`×2 → state（3 玩家）→ `set_ready(true)` → `start_game` → 收到 `game_started` 事件（version 推进）
2. 加入不存在房间 → 404「房间不存在」；第二个账号加入满员约束路径（可选）
3. 匹配取消：入队→cancel→cancelled（受 IP/单人限制，若单人无法同时排队则跳过此断言并注明）

**手动走查**：双开两个客户端验证真人建房/加入/准备/开局；拔网线/杀后端看重连提示；金币不足提示。

**验收边界**：`game_started` 后 UI 停留在占位 overlay（WS 保持连接）即视为本期通过。
