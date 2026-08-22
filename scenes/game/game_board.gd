class_name GameBoard
extends Control
## 三人牌桌：根据房间 WS 快照渲染牌面、玩家、警报进度与排名预测。

signal exit_requested
signal prediction_submitted(rank: int)
signal rank_selected(rank: int)
signal next_round_requested
signal rematch_requested
signal quick_match_requested

const SUIT_TO_ASSET_ROW := {0: 3, 1: 2, 2: 1, 3: 0}
const CARD_BACK := "res://cards/back.png"
const WIN_MARK := "res://game/胜利标记.png"
const LOSS_MARK := "res://game/失败标记.png"
const PLAYER_INFO_FRAME := "res://game/个人信息组合.png"
const COIN_ICON := "res://homepage/金币图标.png"
const MONEY_FRAME := "res://game/玩家金钱框组件.png"
const PREDICTION_FRAME := "res://game/本轮排名预测背景框.png"
const PLAYER_PREDICTION_HISTORY := "res://game/玩家四轮预测排名区域.png"
const RANK_BUTTON_ASSETS := [
	"res://game/排名预测圆形按钮1.png",
	"res://game/排名预测圆形按钮2.png",
	"res://game/排名预测圆形按钮3.png",
]

@onready var pot_label: Label = $Background/Vault/PotLabel
@onready var phase_label: Label = $Background/Progress/PhaseLabel
@onready var progress_slots: Control = $Background/Progress/Slots
@onready var community_cards: HBoxContainer = $Background/CommunityCards
@onready var prediction_buttons: Array[TextureButton] = [
	$Background/PredictionPanel/RankButtons/Rank1,
	$Background/PredictionPanel/RankButtons/Rank2,
	$Background/PredictionPanel/RankButtons/Rank3,
]
@onready var prediction_panel: PanelContainer = $Background/PredictionPanel
@onready var rank_buttons: HBoxContainer = $Background/PredictionPanel/RankButtons
@onready var submit_button: TextureButton = $Background/SubmitButton
@onready var submit_label: Label = $Background/SubmitButton/Label
@onready var status_label: Label = $Background/StatusLabel

var _selected_rank := 0
var _my_id := 0
var _locked_ranks: Array[int] = []
var _state: Dictionary = {}
var _round_results: Array[bool] = []
var _win_mark_texture: Texture2D
var _loss_mark_texture: Texture2D
var _player_info_texture: Texture2D
var _coin_icon_texture: Texture2D
var _money_frame_texture: Texture2D
var _prediction_frame_texture: Texture2D
var _rank_button_textures: Array[Texture2D] = []
var _player_prediction_history_texture: Texture2D
var _player_prediction_cache: Dictionary = {}
var _current_phase := "white"


func _ready() -> void:
	_win_mark_texture = _cropped_texture(WIN_MARK)
	_loss_mark_texture = _cropped_texture(LOSS_MARK)
	_player_info_texture = _cropped_texture(PLAYER_INFO_FRAME)
	_coin_icon_texture = _cropped_texture(COIN_ICON)
	_money_frame_texture = _cropped_texture(MONEY_FRAME)
	_prediction_frame_texture = _cropped_texture(PREDICTION_FRAME)
	_player_prediction_history_texture = _cropped_texture(PLAYER_PREDICTION_HISTORY)
	for path in RANK_BUTTON_ASSETS:
		_rank_button_textures.append(_cropped_texture(path))
	_configure_prediction_art()
	_configure_vault()
	_setup_player_seats()
	for index in prediction_buttons.size():
		prediction_buttons[index].pressed.connect(_select_rank.bind(index + 1))
	_refresh_prediction_buttons()


func _configure_vault() -> void:
	var vault := $Background/Vault as TextureRect
	var vault_artwork := TextureRect.new()
	vault_artwork.name = "Artwork"
	vault_artwork.texture = vault.texture
	vault_artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vault_artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vault_artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_set_rect(vault_artwork, -0.075, -0.075, 1.075, 1.075)
	vault.texture = null
	vault.add_child(vault_artwork)
	var money_frame := TextureRect.new()
	money_frame.name = "MoneyFrame"
	money_frame.texture = _money_frame_texture
	money_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	money_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	money_frame.stretch_mode = TextureRect.STRETCH_SCALE
	_set_rect(money_frame, 0.265, 0.62, 0.669, 0.80)
	vault.add_child(money_frame)

	pot_label.reparent(money_frame)
	_set_rect(pot_label, 0.32, 0.18, 0.94, 0.82)
	pot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var coin := TextureRect.new()
	coin.name = "CoinIcon"
	coin.texture = _coin_icon_texture
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_SCALE
	_set_rect(coin, 0.075, 0.20, 0.285, 0.80)
	money_frame.add_child(coin)


func _configure_prediction_art() -> void:
	prediction_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	prediction_panel.get_node("Title").visible = false
	var artwork := TextureRect.new()
	artwork.name = "Artwork"
	artwork.texture = _prediction_frame_texture
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_SCALE
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prediction_panel.add_child(artwork)
	prediction_panel.move_child(artwork, 0)
	var button_layer := Control.new()
	button_layer.name = "ButtonLayer"
	button_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prediction_panel.add_child(button_layer)
	rank_buttons.visible = false
	var button_rects := [
		Rect2(0.17368, 0.30591, 0.17836, 0.54009),
		Rect2(0.41416, 0.30802, 0.17635, 0.53376),
		Rect2(0.64930, 0.30591, 0.17702, 0.54009),
	]
	for index in prediction_buttons.size():
		var button := prediction_buttons[index]
		button.reparent(button_layer)
		button.custom_minimum_size = Vector2.ZERO
		var button_rect := button_rects[index] as Rect2
		_set_rect(button, button_rect.position.x, button_rect.position.y, button_rect.end.x, button_rect.end.y)
		button.texture_normal = null
		button.texture_hover = null
		button.texture_pressed = null
		button.get_node("Label").visible = false
		var button_art := TextureRect.new()
		button_art.name = "Artwork"
		button_art.texture = _rank_button_textures[index]
		button_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		button_art.stretch_mode = TextureRect.STRETCH_SCALE
		button_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(button_art)


func _setup_player_seats() -> void:
	var left := $Background/LeftPlayer as Control
	_configure_player_info(left, false)
	_set_rect(left, 0.063, 0.447, 0.318, 0.717)
	var left_cards := left.get_node("HoleCards") as Control
	left_cards.anchor_left = 0.68
	left_cards.anchor_top = 0.155
	left_cards.anchor_right = 0.98
	left_cards.anchor_bottom = 0.587
	for card_slot in left_cards.get_children():
		(card_slot as Control).custom_minimum_size = Vector2(90, 126)
	var right := left.duplicate() as Control
	right.name = "RightPlayer"
	_set_rect(right, 0.59, 0.452, 0.845, 0.722)
	_configure_player_info(right, true)
	var right_state := right.get_node("StateLabel") as Control
	right_state.anchor_left = 0.68
	right_state.anchor_right = 0.92
	var right_prediction := right.get_node("PredictionLabel") as Control
	right_prediction.anchor_left = 0.68
	right_prediction.anchor_right = 0.92
	var right_cards := right.get_node("HoleCards") as Control
	right_cards.anchor_left = 0.28
	right_cards.anchor_right = 0.58
	$Background.add_child(right)

	var bottom := left.duplicate() as Control
	bottom.name = "BottomPlayer"
	_set_rect(bottom, 0.331, 0.747, 0.611, 1.017)
	_configure_player_info(bottom, false, true)
	var bottom_cards := bottom.get_node("HoleCards") as Control
	bottom_cards.anchor_left = 0.29
	bottom_cards.anchor_top = -0.567
	bottom_cards.anchor_right = 0.89
	bottom_cards.anchor_bottom = 0.153
	bottom_cards.add_theme_constant_override("separation", 24)
	for card_slot in bottom_cards.get_children():
		(card_slot as Control).custom_minimum_size = Vector2(150, 210)
	_set_rect(bottom.get_node("StateLabel"), 0.72, 0.22, 1.15, 0.34)
	_set_rect(bottom.get_node("PredictionLabel"), 0.72, 0.38, 1.15, 0.50)
	$Background.add_child(bottom)


func _configure_player_info(seat: Control, right_side: bool, bottom := false) -> void:
	var info := seat.get_node_or_null("InfoFrame") as TextureRect
	if info == null:
		info = TextureRect.new()
		info.name = "InfoFrame"
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		info.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		seat.add_child(info)
		seat.move_child(info, 0)
	info.texture = _player_info_texture
	info.flip_h = false
	var coin_icon := seat.get_node_or_null("CoinIcon") as TextureRect
	if coin_icon == null:
		coin_icon = TextureRect.new()
		coin_icon.name = "CoinIcon"
		coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		seat.add_child(coin_icon)
	coin_icon.texture = _coin_icon_texture

	var frame_left := 0.70 if right_side else (0.007 if bottom else 0.011)
	var top := 0.21 if bottom else 0.11
	var frame_right := frame_left + 0.60
	var bottom_edge := top + 0.455
	_set_rect(info, frame_left, top, frame_right, bottom_edge)

	var avatar := seat.get_node("AvatarFrame") as TextureRect
	var name_frame := seat.get_node("NameFrame") as TextureRect
	var money := seat.get_node("MoneyFrame") as TextureRect
	avatar.texture = null
	name_frame.texture = null
	money.texture = null
	_set_rect(avatar, frame_left, top, frame_left + 0.27, bottom_edge)
	_set_rect(name_frame, frame_left + 0.235, top + 0.075, frame_right - 0.035, top + 0.255)
	_set_rect(money, frame_left + 0.27, top + 0.28, frame_left + 0.52, bottom_edge)
	var coin_center_x := frame_left + 0.288
	var coin_center_y := top + 0.369
	_set_rect(coin_icon, coin_center_x - 0.042, coin_center_y - 0.075, coin_center_x + 0.042, coin_center_y + 0.075)
	_set_rect(avatar.get_node("InitialLabel"), 0.0, 0.0, 1.0, 1.0)
	_set_rect(name_frame.get_node("NameLabel"), 0.0, 0.0, 1.0, 1.0)
	_set_rect(money.get_node("MoneyLabel"), 0.0, 0.0, 1.0, 1.0)
	_configure_prediction_history(seat, right_side, bottom)


func _configure_prediction_history(seat: Control, right_side: bool, bottom: bool) -> void:
	seat.get_node("StateLabel").visible = false
	seat.get_node("PredictionLabel").visible = false
	var history := seat.get_node_or_null("PredictionHistory") as TextureRect
	if history == null:
		history = TextureRect.new()
		history.name = "PredictionHistory"
		history.texture = _player_prediction_history_texture
		history.mouse_filter = Control.MOUSE_FILTER_IGNORE
		history.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		history.stretch_mode = TextureRect.STRETCH_SCALE
		seat.add_child(history)
		var centers := [0.1924, 0.3983, 0.6039, 0.8076]
		for index in 4:
			var value := Label.new()
			value.name = "Round%d" % (index + 1)
			value.visible = false
			value.mouse_filter = Control.MOUSE_FILTER_IGNORE
			value.add_theme_color_override("font_color", Color(0.95, 0.76, 0.43, 1.0))
			value.add_theme_font_size_override("font_size", 20)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_set_rect(value, centers[index] - 0.055, 0.53, centers[index] + 0.055, 0.76)
			history.add_child(value)
			var result_icon := TextureRect.new()
			result_icon.name = "Round%dIcon" % (index + 1)
			result_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			result_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			result_icon.stretch_mode = TextureRect.STRETCH_SCALE
			_set_rect(result_icon, centers[index] - 0.072, 0.428, centers[index] + 0.072, 0.816)
			history.add_child(result_icon)
	if bottom:
		_set_rect(history, 0.6525, 0.22, 1.2075, 0.60)
	elif right_side:
		_set_rect(history, 0.585, 0.61, 1.195, 0.99)
	else:
		_set_rect(history, 0.005, 0.61, 0.615, 0.99)


func _set_rect(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


func apply_state(view: Dictionary, my_id: int) -> void:
	_state = view
	pot_label.text = _format_number(int(view.get("pot", 0)))
	var phase := str(view.get("phase", "white"))
	var phase_changed := phase != _current_phase
	_current_phase = phase
	if phase_changed:
		_selected_rank = 0
		_refresh_prediction_buttons()
	phase_label.text = {"white": "白色阶段", "yellow": "黄色阶段", "orange": "橙色阶段", "red": "红色阶段"}.get(phase, "警报进度")
	_update_progress(int(view.get("vaults", 0)), int(view.get("alarms", 0)), phase)
	_update_cards(community_cards, view.get("community_cards", []), false)
	var status := str(view.get("status", "playing"))
	var reveal_hole_cards := status == "round_complete" or status == "finished"

	var players: Array = view.get("players", [])
	var mine: Dictionary = {}
	var others: Array[Dictionary] = []
	for raw_player in players:
		var player := raw_player as Dictionary
		if int(player.get("id", 0)) == my_id:
			mine = player
		else:
			others.append(player)
	_update_seat($Background/LeftPlayer, others[0] if others.size() > 0 else {}, false, reveal_hole_cards)
	_update_seat($Background/RightPlayer, others[1] if others.size() > 1 else {}, false, reveal_hole_cards)
	_update_seat($Background/BottomPlayer, mine, true, reveal_hole_cards)

	_my_id = my_id
	_locked_ranks.clear()
	for raw_player in players:
		var player := raw_player as Dictionary
		if int(player.get("id", 0)) != my_id and bool(player.get("confirmed", false)):
			var locked_rank := int(player.get("chip", 0))
			if locked_rank > 0:
				_locked_ranks.append(locked_rank)
	_selected_rank = int(mine.get("chip", 0))
	_refresh_prediction_buttons()

	if status == "round_complete":
		if bool(mine.get("next_ready", false)):
			var active_humans := 0
			var votes := 0
			for raw_player in players:
				var pl := raw_player as Dictionary
				if not bool(pl.get("is_bot", false)) and not bool(pl.get("abandoned", false)):
					active_humans += 1
					if bool(pl.get("next_ready", false)):
						votes += 1
			submit_label.text = "等待其他玩家 %d/%d" % [votes, active_humans]
		else:
			submit_label.text = "下一轮"
		status_label.text = "本轮成功" if bool(view.get("round_succeeded", false)) else "本轮失败"
	elif status == "finished":
		if str(view.get("source", "friend")) == "match":
			submit_label.text = "快速匹配"
		else:
			submit_label.text = "再来一局" if int(view.get("host_id", 0)) == my_id else "等待房主再来一局"
		status_label.text = "帮派获胜" if str(view.get("winner", "")) == "gang" else "警报方获胜"
	else:
		submit_label.text = "提交预测"
		status_label.text = ""


func show_events(events: Array) -> void:
	for event in events:
		var event_data := event as Dictionary
		match str(event_data.get("event", "")):
			"chip_claimed":
				_cache_claimed_chip(int(event_data.get("player_id", 0)), int(event_data.get("rank", 0)))
			"phase_changed":
				status_label.text = "进入下一阶段"
			"round_settled":
				var total := int(event_data.get("vaults", 0)) + int(event_data.get("alarms", 0))
				if _round_results.size() < total:
					_round_results.append(bool(event_data.get("succeeded", false)))
				_render_progress_results()
				status_label.text = "本轮结算完成"
			"game_over":
				status_label.text = "整局结算完成"


func _cache_claimed_chip(player_id: int, rank: int) -> void:
	if player_id == 0 or rank < 1 or rank > 3:
		return
	var values: Array = [0, 0, 0, 0]
	if _player_prediction_cache.has(player_id):
		values = (_player_prediction_cache[player_id] as Array).duplicate()
	var phase_index := int({"white": 0, "yellow": 1, "orange": 2, "red": 3}.get(_current_phase, 0))
	values[phase_index] = rank
	_player_prediction_cache[player_id] = values


func _update_seat(seat: Control, player: Dictionary, is_me: bool, reveal_hole_cards: bool) -> void:
	var empty := player.is_empty()
	seat.visible = not empty
	if empty:
		return
	var name := str(player.get("name", "玩家"))
	seat.get_node("NameFrame/NameLabel").text = "You" if is_me else name
	seat.get_node("AvatarFrame/InitialLabel").text = name.left(1).to_upper()
	seat.get_node("MoneyFrame/MoneyLabel").text = _format_number(int(player.get("balance", 0)))
	var state_text := "已确认" if bool(player.get("confirmed", false)) else "预测排名"
	if str(_state.get("status", "")) == "round_complete":
		state_text = "已继续" if bool(player.get("next_ready", false)) else "看牌中"
	seat.get_node("StateLabel").text = state_text
	_update_prediction_history(seat, player)
	_update_cards(seat.get_node("HoleCards"), player.get("hole_cards", []), not is_me and not reveal_hole_cards)


func _update_prediction_history(seat: Control, player: Dictionary) -> void:
	var player_id := int(player.get("id", 0))
	var values: Array = [0, 0, 0, 0]
	var from_server := false
	for key in ["predictions", "prediction_history", "chips"]:
		var raw: Variant = player.get(key, null)
		if raw is Array:
			for index in mini(4, raw.size()):
				values[index] = int(raw[index])
			from_server = true
			break
	if not from_server and _player_prediction_cache.has(player_id):
		var cached := _player_prediction_cache[player_id] as Array
		for index in 4:
			if int(values[index]) <= 0:
				values[index] = int(cached[index])
	var phase_index := int({"white": 0, "yellow": 1, "orange": 2, "red": 3}.get(_current_phase, 0))
	var current_chip := int(player.get("chip", 0))
	if current_chip > 0:
		values[phase_index] = current_chip
	_player_prediction_cache[player_id] = values.duplicate()
	var history := seat.get_node("PredictionHistory") as TextureRect
	for index in 4:
		var value := int(values[index])
		var icon := history.get_node("Round%dIcon" % (index + 1)) as TextureRect
		icon.visible = value >= 1 and value <= 3
		icon.texture = _rank_button_textures[value - 1] if icon.visible else null


func _update_cards(container: Container, cards: Array, hidden: bool) -> void:
	var slots := container.get_children()
	for index in slots.size():
		var slot := slots[index] as PanelContainer
		var label := slot.get_node("Label") as Label
		label.visible = false
		var image := slot.get_node_or_null("Image") as TextureRect
		if image == null:
			image = TextureRect.new()
			image.name = "Image"
			image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_SCALE
			slot.add_child(image)
			slot.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		if index < cards.size() and not hidden:
			image.texture = load(_card_asset_path(cards[index] as Dictionary)) as Texture2D
		else:
			image.texture = load(CARD_BACK) as Texture2D


func _update_progress(vaults: int, alarms: int, _phase: String) -> void:
	var settled_rounds := clampi(vaults + alarms, 0, progress_slots.get_child_count())
	if _round_results.size() != settled_rounds:
		_round_results.clear()
		for _round in vaults:
			_round_results.append(true)
		for _round in alarms:
			_round_results.append(false)
	_render_progress_results()


func _render_progress_results() -> void:
	for index in progress_slots.get_child_count():
		var slot := progress_slots.get_child(index) as Label
		slot.text = ""
		var icon := slot.get_node_or_null("ResultIcon") as TextureRect
		if icon == null:
			icon = TextureRect.new()
			icon.name = "ResultIcon"
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_SCALE
			slot.add_child(icon)
		icon.visible = index < _round_results.size()
		if icon.visible:
			icon.texture = _win_mark_texture if _round_results[index] else _loss_mark_texture


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


func _select_rank(rank: int) -> void:
	if rank == _selected_rank or rank in _locked_ranks:
		return
	_selected_rank = rank
	_refresh_prediction_buttons()
	rank_selected.emit(rank)


func _refresh_prediction_buttons() -> void:
	for index in prediction_buttons.size():
		var button := prediction_buttons[index]
		var rank := index + 1
		var locked := rank in _locked_ranks
		button.disabled = locked
		if locked:
			button.modulate = Color(0.45, 0.42, 0.38, 0.55)
		else:
			button.modulate = Color(1.28, 1.12, 1.42, 1.0) if rank == _selected_rank else Color.WHITE
		button.scale = Vector2.ONE


func _on_submit_pressed() -> void:
	match str(_state.get("status", "playing")):
		"round_complete":
			next_round_requested.emit()
		"finished":
			if str(_state.get("source", "friend")) == "match":
				quick_match_requested.emit()
			elif int(_state.get("host_id", 0)) == _my_id:
				rematch_requested.emit()
		_:
			if _selected_rank == 0:
				status_label.text = "请先选择预测排名"
				return
			prediction_submitted.emit(_selected_rank)
			status_label.text = "排名预测已提交"


func _card_asset_path(card: Dictionary) -> String:
	var rank := int(card.get("rank", 0))
	var suit := int(card.get("suit", 0))
	if rank < 2 or rank > 14 or not SUIT_TO_ASSET_ROW.has(suit):
		return CARD_BACK
	var column := 0 if rank == 14 else rank - 1
	return "res://cards/card_r%d_c%d.png" % [int(SUIT_TO_ASSET_ROW[suit]), column]


func _format_number(value: int) -> String:
	var digits := str(value)
	var formatted := ""
	while digits.length() > 3:
		formatted = ",%s%s" % [digits.right(3), formatted]
		digits = digits.left(-3)
	return digits + formatted


func _on_exit_pressed() -> void:
	exit_requested.emit()
