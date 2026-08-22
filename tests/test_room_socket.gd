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
