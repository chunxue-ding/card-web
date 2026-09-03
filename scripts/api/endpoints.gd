class_name Endpoints
## API 路径与错误码，与 user 后端 api/user.api、internal/errs/errs.go 对齐

const LOGIN := "/api/v1/auth/login"
const REGISTER := "/api/v1/auth/register"
const GUEST_LOGIN := "/api/v1/auth/guest-login"
const LOGOUT := "/api/v1/auth/logout"
const ME := "/api/v1/users/me"
const UPDATE_ME := "/api/v1/users/me"

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


# ---- card 服务（:8890）----
const CARD_ROOMS := "/api/v1/rooms"
const CARD_ROOM_JOIN := "/api/v1/rooms/%s/join"
const CARD_ROOM_GET := "/api/v1/rooms/%s"
const CARD_MATCH := "/api/v1/match"
const CARD_MATCH_CANCEL := "/api/v1/match/cancel"
const CARD_MATCH_CONFIRM := "/api/v1/match/confirm"
const CARD_MATCH_DECLINE := "/api/v1/match/decline"
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
		"confirm timeout":
			return "确认超时，本次匹配已取消"
		"declined":
			return "有玩家拒绝，本次匹配已取消"
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
	if "chip is already submitted" in error:
		return "该排名已被其他玩家锁定"
	if "claim a chip first" in error:
		return "该排名已被其他玩家抢先选择"
	match error:
		"unauthorized":
			return "登录已过期，请重新登录"
		"room not found or not joined":
			return "房间不存在或未加入"
		_:
			return error
