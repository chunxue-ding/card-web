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
