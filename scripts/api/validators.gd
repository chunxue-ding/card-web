class_name Validators
## 前置校验，与后端 internal/authx 规则对齐（邮箱正则、密码 ≥ 8 位）

const EMAIL_PATTERN := "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"
const MIN_PASSWORD_LEN := 8


static func valid_email(email: String) -> bool:
	var re := RegEx.new()
	if re.compile(EMAIL_PATTERN) != OK:
		push_error("邮箱正则编译失败")
		return false
	return re.search(email.strip_edges()) != null


static func password_ok(password: String) -> bool:
	return password.length() >= MIN_PASSWORD_LEN
