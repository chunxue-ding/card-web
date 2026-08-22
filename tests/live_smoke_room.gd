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
