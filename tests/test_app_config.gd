extends SceneTree
## AppConfig 行为单测：env 覆盖优先；native 无 env 时用默认值
## （web 同源分支依赖浏览器环境，由部署后的 /browse 验证覆盖）
## 运行：/Users/dn/bin/godot --headless --script res://tests/test_app_config.gd

const Helper = preload("res://tests/test_helper.gd")
const AppConfig = preload("res://scripts/config/app_config.gd")

var h := Helper.new()


func _initialize() -> void:
	OS.set_environment("CARD_API_URL", "http://override.test:9000")
	OS.set_environment("CARD_CARD_URL", "http://card-override.test:9001")
	h.check(AppConfig.get_base_url() == "http://override.test:9000", "CARD_API_URL 覆盖生效")
	h.check(AppConfig.get_card_base_url() == "http://card-override.test:9001", "CARD_CARD_URL 覆盖生效")
	OS.set_environment("CARD_API_URL", "")
	OS.set_environment("CARD_CARD_URL", "")
	h.check(AppConfig.get_base_url() == "http://127.0.0.1:8888", "无 env 时 user 默认地址")
	h.check(AppConfig.get_card_base_url() == "http://127.0.0.1:8890", "无 env 时 card 默认地址")
	h.finish(self)
