extends Control
## 非游客首次登录资料设置页：用户名 + 六选一头像，保存后进入主页。

const LOBBY_SCENE := "res://scenes/lobby/lobby.tscn"
const PANEL_FRAME := "res://profile/档案设置面板底框.png"
const AVATAR_FRAME := "res://profile/圆形头像选择框底框.png"
const NAME_FRAME := "res://profile/用户名输入框底框无文字.png"
const CONFIRM_FRAME := "res://profile/确认按钮底框无文字.png"

@onready var panel_frame: TextureRect = $Background/Center/PanelFrame
@onready var name_frame: TextureRect = $Background/Center/VBox/NameInputFrame
@onready var name_input: LineEdit = $Background/Center/VBox/NameInput
@onready var avatar_grid: GridContainer = $Background/Center/VBox/AvatarGrid
@onready var save_frame: TextureRect = $Background/Center/VBox/SaveFrame
@onready var error_label: Label = $Background/Center/VBox/ErrorLabel
@onready var save_button: Button = $Background/Center/VBox/SaveButton

var _selected_avatar := 1
var _hovered_avatar := 0


func _ready() -> void:
	Music.play_ambient()
	panel_frame.texture = _cropped_texture(PANEL_FRAME)
	name_frame.texture = _cropped_texture(NAME_FRAME)
	save_frame.texture = _cropped_texture(CONFIRM_FRAME)
	var current_avatar := int(Session.user.get("avatar", 0))
	_selected_avatar = current_avatar if current_avatar >= 1 and current_avatar <= Avatars.PATHS.size() else 1
	name_input.text = str(Session.user.get("name", ""))
	var avatar_frame_texture := _cropped_texture(AVATAR_FRAME)
	for index in Avatars.PATHS.size():
		var number := index + 1
		var button := avatar_grid.get_node("Avatar%d" % number) as TextureButton
		button.texture_normal = avatar_frame_texture
		button.texture_hover = avatar_frame_texture
		button.texture_pressed = avatar_frame_texture
		button.pressed.connect(_select_avatar.bind(number))
		button.mouse_entered.connect(_set_avatar_hover.bind(number, true))
		button.mouse_exited.connect(_set_avatar_hover.bind(number, false))
		var icon := TextureRect.new()
		icon.name = "AvatarIcon"
		icon.texture = _cropped_texture(Avatars.PATHS[index])
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_set_rect(icon, 0.105, 0.105, 0.895, 0.895)
		button.add_child(icon)
	name_input.text_submitted.connect(func(_text: String) -> void: _on_save_pressed())
	save_button.mouse_entered.connect(_set_save_hover.bind(true))
	save_button.mouse_exited.connect(_set_save_hover.bind(false))
	await get_tree().process_frame
	_refresh()


func _select_avatar(avatar: int) -> void:
	_selected_avatar = avatar
	error_label.text = ""
	_refresh()


func _set_avatar_hover(avatar: int, hovered: bool) -> void:
	_hovered_avatar = avatar if hovered else (0 if _hovered_avatar == avatar else _hovered_avatar)
	_refresh()


func _set_save_hover(hovered: bool) -> void:
	if not save_button.disabled:
		save_frame.modulate = Color(1.16, 1.08, 1.2, 1.0) if hovered else Color.WHITE


func _refresh() -> void:
	for index in Avatars.PATHS.size():
		var number := index + 1
		var button := avatar_grid.get_node("Avatar%d" % number) as TextureButton
		var selected := number == _selected_avatar
		var hovered := number == _hovered_avatar
		button.modulate = Color(1.22, 0.9, 1.35, 1.0) if selected else (Color(1.1, 1.06, 1.14, 1.0) if hovered else Color.WHITE)
		button.pivot_offset = button.size * 0.5
		button.scale = Vector2.ONE * (1.065 if selected else (1.035 if hovered else 1.0))
		button.z_index = 2 if selected else (1 if hovered else 0)


func _on_save_pressed() -> void:
	if save_button.disabled:
		return
	var nickname := name_input.text.strip_edges()
	if nickname.is_empty() or nickname.length() > 24:
		error_label.text = "用户名需要 1-24 个字符"
		name_input.grab_focus()
		return
	if _selected_avatar < 1 or _selected_avatar > Avatars.PATHS.size():
		error_label.text = "请选择一个头像"
		return
	error_label.text = ""
	save_button.disabled = true
	save_button.text = "保存中…"
	save_frame.modulate = Color(0.7, 0.7, 0.7, 0.8)
	var err: ApiError = await Session.update_profile(nickname, _selected_avatar)
	if not is_inside_tree():
		return
	save_button.disabled = false
	save_button.text = "确认"
	save_frame.modulate = Color.WHITE
	if err != null:
		error_label.text = err.message
		return
	var error := get_tree().change_scene_to_file(LOBBY_SCENE)
	if error != OK:
		push_error("无法进入主页：%s" % error_string(error))


func _cropped_texture(path: String) -> Texture2D:
	var source := load(path) as Texture2D
	if source == null:
		return null
	var used_rect := source.get_image().get_used_rect()
	if used_rect.size == Vector2i.ZERO:
		return source
	var cropped := AtlasTexture.new()
	cropped.atlas = source
	cropped.region = Rect2(used_rect)
	return cropped


func _set_rect(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
