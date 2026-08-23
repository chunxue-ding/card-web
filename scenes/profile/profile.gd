extends Control
## 首次登录的资料设置页:昵称 + 克苏鲁头像(6 选 1),保存后进大厅。

const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"

@onready var name_input: LineEdit = $Background/Center/VBox/NameInput
@onready var avatar_grid: GridContainer = $Background/Center/VBox/AvatarGrid
@onready var error_label: Label = $Background/Center/VBox/ErrorLabel
@onready var save_button: Button = $Background/Center/VBox/SaveButton

var _selected_avatar := 0


func _ready() -> void:
	Music.play_ambient()
	name_input.text = str(Session.user.get("name", ""))
	for index in Avatars.PATHS.size():
		var button := avatar_grid.get_node("Avatar%d" % (index + 1)) as TextureButton
		button.texture_normal = load(Avatars.PATHS[index])
		button.pressed.connect(_select_avatar.bind(index + 1))
	_refresh()


func _select_avatar(avatar: int) -> void:
	_selected_avatar = avatar
	_refresh()


func _refresh() -> void:
	for index in Avatars.PATHS.size():
		var button := avatar_grid.get_node("Avatar%d" % (index + 1)) as TextureButton
		var selected := index + 1 == _selected_avatar
		button.modulate = Color(1.3, 1.15, 1.45, 1.0) if selected else Color.WHITE
		button.pivot_offset = button.size / 2.0
		button.scale = Vector2.ONE * (1.08 if selected else 1.0)


func _on_save_pressed() -> void:
	var nickname := name_input.text.strip_edges()
	if nickname.is_empty() or nickname.length() > 24:
		error_label.text = "昵称需要 1-24 个字符"
		return
	if _selected_avatar == 0:
		error_label.text = "请选择一个头像"
		return
	error_label.text = ""
	save_button.disabled = true
	var err: ApiError = await Session.update_profile(nickname, _selected_avatar)
	if not is_inside_tree():
		return
	save_button.disabled = false
	if err != null:
		error_label.text = err.message
		return
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		push_error("无法进入主页：%s" % error_string(error))
