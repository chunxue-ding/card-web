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
	var res: Variant = await api.match_wait("fake-token", 4)
	h.check(res is ApiError and res.is_network_error, "card 不可达 match_wait → 网络错误")
	var room: Variant = await api.create_room("fake-token", 3)
	h.check(room is ApiError and room.is_network_error, "card 不可达 create_room → 网络错误")
	OS.set_environment("CARD_CARD_URL", "")
	h.finish(self)
