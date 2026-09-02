class_name Avatars
## 克苏鲁头像映射:编号 1..6 → title/ 下的素材路径(资料设置页与牌桌座席共用)。

const GUEST_PATH := "res://title/克苏鲁游客头像.png"
const BOT_PATH := "res://title/克苏鲁机器人头像.png"

const PATHS := [
	"res://title/克苏鲁Q版头像1 克苏鲁本尊.png",
	"res://title/克苏鲁Q版头像2 深潜者.png",
	"res://title/克苏鲁Q版头像3 古老者.png",
	"res://title/克苏鲁Q版头像3 古老者 1.png",
	"res://title/克苏鲁Q版头像5 奈亚拉托提普.png",
	"res://title/克苏鲁Q版头像6 犹格索托斯.png",
]


static func path_for(avatar: int) -> String:
	if avatar < 1 or avatar > PATHS.size():
		return ""
	return PATHS[avatar - 1]


static func user_path(avatar: int, is_guest: bool) -> String:
	if is_guest:
		return GUEST_PATH
	return path_for(avatar)


static func game_player_path(avatar: int, is_bot: bool) -> String:
	if is_bot:
		return BOT_PATH
	var selected := path_for(avatar)
	# 非游客账号进入大厅前必须完成头像设置，因此牌桌中未设置头像的真人
	# 即为游客；保留该兜底也兼容旧服务端快照。
	return selected if not selected.is_empty() else GUEST_PATH
