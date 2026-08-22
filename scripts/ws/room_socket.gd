class_name RoomSocket
extends Node
## 房间 WebSocket 封装（card :8890）：authenticate 首帧、state/events/error 信封分发、指令发送。
## 宿主需每帧调 poll()；断线经 closed 信号通知，重连即重新 connect_room（后端会清除代打标记）。

signal authenticated
signal state_received(view: Dictionary)
signal events_received(events: Array, version: int)
signal socket_error(message: String)
signal closed

const CONNECT_FAIL_MESSAGE := "无法连接房间服务"

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
	if _peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_peer.close()
	_peer = WebSocketPeer.new()
	if _peer.connect_to_url(_ws_base_url() + Endpoints.CARD_WS_PATH) != OK:
		socket_error.emit(CONNECT_FAIL_MESSAGE)
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
			socket_error.emit(CONNECT_FAIL_MESSAGE)


func set_ready(ready: bool) -> void:
	_send_json({"type": "set_ready", "ready": ready})


func is_authed() -> bool:
	return _authed


func add_bot() -> void:
	_send_json({"type": "add_bot"})


func remove_bot(player_id: int) -> void:
	_send_json({"type": "remove_bot", "player_id": player_id})


func start_game() -> void:
	_send_json({"type": "start_game"})


func claim_chip(rank: int) -> void:
	_send_json({"type": "claim_chip", "rank": rank})


func confirm_phase() -> void:
	_send_json({"type": "confirm_phase"})


func next_round() -> void:
	_send_json({"type": "next_round"})


func rematch() -> void:
	_send_json({"type": "rematch"})


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
