class_name Avatars
## 克苏鲁头像映射:编号 1..6 → title/ 下的素材路径(资料设置页与牌桌座席共用)。

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
