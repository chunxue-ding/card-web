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
