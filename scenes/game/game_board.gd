class_name GameBoard
extends Control
## 三/四人牌桌：根据房间 WS 快照渲染牌面、玩家、警报进度与排名预测。

signal exit_requested
signal prediction_submitted(rank: int)
signal rank_selected(rank: int)
signal next_round_requested
signal rematch_requested
signal quick_match_requested
signal deal_started
signal card_dealt(seat_name: String, card_index: int)
signal community_card_dealt(card_index: int)

const SUIT_TO_ASSET_ROW := {0: 3, 1: 2, 2: 1, 3: 0}
const CARD_BACK := "res://cards/back.png"
const CARD_PERSPECTIVE_SHADER := preload("res://scenes/game/card_perspective.gdshader")
const WIN_MARK := "res://game/胜利标记.png"
const LOSS_MARK := "res://game/失败标记.png"
const PREDICTION_PANEL_3 := "res://game/本轮排名预测背景框.png"
const PREDICTION_PANEL_4 := "res://game/本轮排名预测背景框 4人版.png"
const TUTORIAL_CFG_PATH := "user://tutorial.cfg"
const TUTORIAL_STEPS := [
	{
		"title": "这是你的手牌",
		"body": "每轮你会收到两张只有自己可见的手牌。其他玩家的手牌会在本轮结算时翻开。",
		"target": NodePath("Background/BottomPlayer/HoleCards"),
	},
	{
		"title": "牌型从大到小",
		"body": "皇家同花顺最大，高牌最小；牌型相同时再比较组成牌型的点数。",
		"target": NodePath("Background/CommunityCards"),
		"show_chart": true,
	},
	{
		"title": "观察公共牌",
		"body": "一轮共有四次预测：翻牌前、前三张公共牌发出后、第四张发出后，以及第五张发出后。",
		"target": NodePath("Background/CommunityCards"),
	},
	{
		"title": "选择预测排名",
		"body": "根据手牌和当前公共牌，预测自己最终会排第几名。1 代表牌最小，三人局的 3、四人局的 4 代表牌最大。",
		"target": NodePath("Background/PredictionPanel"),
	},
	{
		"title": "提交并锁定",
		"body": "选好排名后点击提交预测。锁定后本次预测不能修改，需要等待其他玩家完成选择。",
		"target": NodePath("Background/SubmitButton"),
	},
	{
		"title": "警报进度",
		"body": "每轮结算后，胜利或失败标记会依次填入圆槽，方便观察整场对局进度。",
		"target": NodePath("Background/Progress"),
	},
	{
		"title": "关注金库",
		"body": "这里显示当前金库金额。结合牌面、对手选择和风险决定你的排名预测。",
		"target": NodePath("Background/Vault"),
	},
	{
		"title": "回顾四次预测",
		"body": "每位玩家下方会记录本轮四个阶段的预测。现在可以开始你的第一局了。",
		"target": NodePath("Background/BottomPlayer/PredictionHistory"),
	},
]
const RANK_BUTTON_ASSETS := [
	"res://game/排名预测圆形按钮1.png",
	"res://game/排名预测圆形按钮2.png",
	"res://game/排名预测圆形按钮3.png",
	"res://game/排名预测圆形按钮4.png",
]

@export_range(0.05, 1.0, 0.01) var deal_card_duration := 0.38
@export_range(0.0, 0.5, 0.01) var deal_card_gap := 0.08
@export_range(0.15, 0.8, 0.01) var progress_result_effect_duration := 0.34

@onready var pot_label: Label = $Background/Vault/MoneyFrame/PotLabel
@onready var phase_label: Label = $Background/Progress/PhaseLabel
@onready var progress_slots: Control = $Background/Progress/Slots
@onready var community_cards: HBoxContainer = $Background/CommunityCards
@onready var prediction_panel_artwork: TextureRect = $Background/PredictionPanel/Artwork
@onready var prediction_buttons: Array[TextureButton] = [
	$Background/PredictionPanel/ButtonLayer/Rank1,
	$Background/PredictionPanel/ButtonLayer/Rank2,
	$Background/PredictionPanel/ButtonLayer/Rank3,
	$Background/PredictionPanel/ButtonLayer/Rank4,
]
@onready var submit_button: TextureButton = $Background/SubmitButton
@onready var submit_label: Label = $Background/SubmitButton/Label
@onready var status_label: Label = $Background/StatusLabel
@onready var deal_animation_layer: Control = $Background/DealAnimationLayer
@onready var round_settlement: Control = $RoundSettlement
@onready var tutorial_help_button: Button = $Background/TutorialHelpButton
@onready var tutorial_overlay: Control = $TutorialOverlay
@onready var tutorial_highlight: Panel = $TutorialOverlay/Highlight
@onready var tutorial_guide_panel: PanelContainer = $TutorialOverlay/GuidePanel
@onready var tutorial_title: Label = $TutorialOverlay/GuidePanel/Margin/VBox/Title
@onready var tutorial_body: Label = $TutorialOverlay/GuidePanel/Margin/VBox/Body
@onready var tutorial_chart: TextureRect = $TutorialOverlay/GuidePanel/Margin/VBox/HandRankingChart
@onready var tutorial_step_label: Label = $TutorialOverlay/GuidePanel/Margin/VBox/Footer/Step
@onready var tutorial_previous_button: Button = $TutorialOverlay/GuidePanel/Margin/VBox/Footer/Previous
@onready var tutorial_next_button: Button = $TutorialOverlay/GuidePanel/Margin/VBox/Footer/Next

var _selected_rank := 0
var _my_id := 0
var _locked_ranks: Array[int] = []
var _state: Dictionary = {}
var _round_results: Array[bool] = []
var _win_mark_texture: Texture2D
var _loss_mark_texture: Texture2D
var _rank_button_textures: Array[Texture2D] = []
var _prediction_panel_textures: Array[Texture2D] = []
var _player_prediction_cache: Dictionary = {}
var _active_player_count := 3
var _current_phase := "white"
var _deal_animation_pending := false
var _dealing := false
var _dealt_slot_count := 0
var _deal_generation := 0
var _community_animation_pending := false
var _known_community_count := 0
var _pending_community_cards: Array[int] = []
var _community_dealing := false
var _active_community_card := -1
var _card_hover_tweens: Dictionary = {}
var _progress_result_tweens: Dictionary = {}
var _prediction_submit_pending := false
var _prediction_locked := false
var _tutorial_step := 0
var _tutorial_auto_checked := false


func _ready() -> void:
	_win_mark_texture = _cropped_texture(WIN_MARK)
	_loss_mark_texture = _cropped_texture(LOSS_MARK)
	# 场景文件中的七个胜利标记只用于 Godot 2D 编辑器对位；
	# 游戏启动后立刻按真实结算数据重新控制显隐。
	_render_progress_results()
	_prediction_panel_textures = [
		_cropped_texture(PREDICTION_PANEL_3),
		_cropped_texture(PREDICTION_PANEL_4),
	]
	for path in RANK_BUTTON_ASSETS:
		_rank_button_textures.append(_cropped_texture(path))
	for index in prediction_buttons.size():
		prediction_buttons[index].pressed.connect(_select_rank.bind(index + 1))
	_setup_card_interactions()
	for seat in _all_player_seats():
		var hand := seat.get_node("HoleCards") as HBoxContainer
		hand.sort_children.connect(_apply_hole_card_fan)
	community_cards.sort_children.connect(_apply_community_card_spread)
	call_deferred("_apply_hole_card_fan")
	call_deferred("_apply_community_card_spread")
	_configure_player_count(3)
	_refresh_prediction_buttons()
	tutorial_help_button.pressed.connect(start_tutorial.bind(true))
	$TutorialOverlay/GuidePanel/Margin/VBox/Footer/Skip.pressed.connect(_on_tutorial_skip_pressed)
	tutorial_previous_button.pressed.connect(_on_tutorial_previous_pressed)
	tutorial_next_button.pressed.connect(_on_tutorial_next_pressed)
	tutorial_overlay.resized.connect(_layout_tutorial)
	round_settlement.continue_requested.connect(_on_round_settlement_continue_requested)
	var music := get_node_or_null("/root/Music")
	if music != null:
		music.call("play_game")


func _exit_tree() -> void:
	var music := get_node_or_null("/root/Music")
	if music != null:
		music.call("stop")


func _all_player_seats() -> Array[Control]:
	return [
		$Background/LeftPlayer,
		$Background/TopPlayer,
		$Background/RightPlayer,
		$Background/BottomPlayer,
	]


func _deal_seats() -> Array[Control]:
	if _active_player_count == 4:
		return [
			$Background/LeftPlayer,
			$Background/TopPlayer,
			$Background/RightPlayer,
			$Background/BottomPlayer,
		]
	return [
		$Background/LeftPlayer,
		$Background/RightPlayer,
		$Background/BottomPlayer,
	]


func _configure_player_count(count: int) -> void:
	_active_player_count = clampi(count, 3, 4)
	$Background/TopPlayer.visible = _active_player_count == 4
	var panel := $Background/PredictionPanel as PanelContainer
	if _active_player_count == 4:
		panel.anchor_left = 0.37
		panel.anchor_right = 0.63
		prediction_panel_artwork.texture = _prediction_panel_textures[1]
	else:
		panel.anchor_left = 0.38
		panel.anchor_right = 0.62
		prediction_panel_artwork.texture = _prediction_panel_textures[0]

	var layouts_3 := [
		Rect2(0.17368, 0.30591, 0.17836, 0.54009),
		Rect2(0.41416, 0.30802, 0.17635, 0.53376),
		Rect2(0.6493, 0.30591, 0.17702, 0.54009),
	]
	var layouts_4 := [
		Rect2(0.100, 0.324, 0.158, 0.522),
		Rect2(0.310, 0.324, 0.158, 0.522),
		Rect2(0.525, 0.324, 0.158, 0.522),
		Rect2(0.742, 0.324, 0.158, 0.522),
	]
	var layouts: Array = layouts_4 if _active_player_count == 4 else layouts_3
	for index in prediction_buttons.size():
		var button := prediction_buttons[index]
		button.visible = index < _active_player_count
		if button.visible:
			var rect := layouts[index] as Rect2
			button.anchor_left = rect.position.x
			button.anchor_top = rect.position.y
			button.anchor_right = rect.end.x
			button.anchor_bottom = rect.end.y


# 布局节点已固定在 game_board.tscn；这里以下只负责根据服务端状态更新内容。

func arm_new_round_animation() -> void:
	if not _dealing:
		_deal_animation_pending = true
	_community_animation_pending = true


func arm_community_animation() -> void:
	_community_animation_pending = true

func apply_state(view: Dictionary, my_id: int) -> void:
	_state = view
	pot_label.text = _format_number(int(view.get("pot", 0)))
	var phase := str(view.get("phase", "white"))
	var phase_changed := phase != _current_phase
	_current_phase = phase
	if phase_changed:
		_selected_rank = 0
		_prediction_submit_pending = false
		_prediction_locked = false
		_refresh_prediction_buttons()
	phase_label.text = {"white": "白色阶段", "yellow": "黄色阶段", "orange": "橙色阶段", "red": "红色阶段"}.get(phase, "警报进度")
	_update_progress(int(view.get("vaults", 0)), int(view.get("alarms", 0)), phase)
	var public_cards: Array = view.get("community_cards", [])
	var public_card_count := mini(public_cards.size(), community_cards.get_child_count())
	if public_card_count < _known_community_count:
		_pending_community_cards.clear()
		_active_community_card = -1
		_community_dealing = false
		_known_community_count = 0
	_update_community_cards(public_cards)
	if _community_animation_pending and public_card_count > _known_community_count:
		for index in range(_known_community_count, public_card_count):
			if index not in _pending_community_cards:
				_pending_community_cards.append(index)
		_community_animation_pending = false
	_known_community_count = public_card_count
	_apply_community_deal_visibility()
	var status := str(view.get("status", "playing"))
	if status == "playing" and not _tutorial_auto_checked:
		_tutorial_auto_checked = true
		call_deferred("_maybe_show_tutorial")
	var reveal_hole_cards := status == "round_complete" or status == "finished"

	var players: Array = view.get("players", [])
	_configure_player_count(clampi(players.size(), 3, 4))
	var mine: Dictionary = {}
	var others: Array[Dictionary] = []
	for raw_player in players:
		var player := raw_player as Dictionary
		if int(player.get("id", 0)) == my_id:
			mine = player
		else:
			others.append(player)
	_update_seat($Background/LeftPlayer, others[0] if others.size() > 0 else {}, false, reveal_hole_cards)
	_update_seat($Background/TopPlayer, others[1] if others.size() > 2 else {}, false, reveal_hole_cards)
	_update_seat($Background/RightPlayer, others[2] if others.size() > 2 else (others[1] if others.size() > 1 else {}), false, reveal_hole_cards)
	_update_seat($Background/BottomPlayer, mine, true, reveal_hole_cards)
	if _dealing:
		_apply_deal_visibility()
	elif _deal_animation_pending and status == "playing" and players.size() >= 3:
		_deal_animation_pending = false
		_start_deal_animation()
	_start_pending_community_deal()

	_my_id = my_id
	_locked_ranks.clear()
	for raw_player in players:
		var player := raw_player as Dictionary
		if int(player.get("id", 0)) != my_id and bool(player.get("confirmed", false)):
			var locked_rank := int(player.get("chip", 0))
			if locked_rank > 0:
				_locked_ranks.append(locked_rank)
	_selected_rank = int(mine.get("chip", 0))
	if status == "playing":
		var confirmed_by_server := bool(mine.get("confirmed", false))
		if confirmed_by_server:
			_prediction_submit_pending = false
		_prediction_locked = confirmed_by_server or _prediction_submit_pending
	else:
		_prediction_submit_pending = false
		_prediction_locked = false
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
		if _prediction_locked and _selected_rank > 0:
			submit_label.text = "已锁定 · 第%d名" % _selected_rank
			status_label.text = "预测已锁定，等待其他玩家"
		else:
			submit_label.text = "提交预测"
			status_label.text = ""
	submit_button.disabled = status != "playing" or _prediction_locked
	if status in ["round_complete", "finished"]:
		if tutorial_overlay.visible:
			close_tutorial(false)
		round_settlement.show_result(view, my_id)
	else:
		round_settlement.hide_result()


func show_events(events: Array) -> void:
	for event in events:
		var event_data := event as Dictionary
		match str(event_data.get("event", "")):
			"game_started", "hole_dealt":
				arm_new_round_animation()
			"chip_claimed":
				_cache_claimed_chip(int(event_data.get("player_id", 0)), int(event_data.get("rank", 0)))
			"phase_changed":
				arm_community_animation()
				status_label.text = "进入下一阶段"
			"round_settled":
				var total := int(event_data.get("vaults", 0)) + int(event_data.get("alarms", 0))
				if _round_results.size() < total:
					_round_results.append(bool(event_data.get("succeeded", false)))
				_render_progress_results()
				status_label.text = "本轮结算完成"
			"game_over":
				status_label.text = "整局结算完成"


func _start_deal_animation() -> void:
	_dealing = true
	_dealt_slot_count = 0
	_deal_generation += 1
	_clear_flying_cards()
	_apply_deal_visibility()
	deal_started.emit()
	_play_deal_animation(_deal_generation)


func _play_deal_animation(generation: int) -> void:
	var targets := _deal_targets()
	var deal_seats := _deal_seats()
	if targets.size() != deal_seats.size() * 2:
		_finish_deal_animation(generation)
		return
	var origin_image := $Background/DeckPile/TopCard as TextureRect
	var layer_inverse := deal_animation_layer.get_global_transform().affine_inverse()
	var origin_center := origin_image.get_global_rect().get_center()
	var origin_local := layer_inverse * origin_center
	var card_back := load(CARD_BACK) as Texture2D
	for index in targets.size():
		if generation != _deal_generation or not is_instance_valid(deal_animation_layer):
			return
		var target := targets[index] as TextureRect
		var flying_card := TextureRect.new()
		flying_card.name = "FlyingCard%d" % (index + 1)
		flying_card.texture = card_back
		flying_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flying_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		flying_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deal_animation_layer.add_child(flying_card)
		await _animate_flying_card(flying_card, origin_local, target, index)
		if generation != _deal_generation:
			if is_instance_valid(flying_card):
				flying_card.queue_free()
			return
		_dealt_slot_count = index + 1
		_apply_deal_visibility()
		_play_landing_bounce(target)
		var seat := target.get_parent().get_parent().get_parent() as Control
		card_dealt.emit(seat.name, index / deal_seats.size())
		flying_card.queue_free()
		if deal_card_gap > 0.0 and index < targets.size() - 1:
			await get_tree().create_timer(deal_card_gap).timeout
	_finish_deal_animation(generation)


func _deal_targets() -> Array[TextureRect]:
	var seats := _deal_seats()
	var targets: Array[TextureRect] = []
	for card_index in 2:
		for seat in seats:
			targets.append(seat.get_node("HoleCards/Card%d/Image" % (card_index + 1)) as TextureRect)
	return targets


func _apply_deal_visibility() -> void:
	var targets := _deal_targets()
	for index in targets.size():
		targets[index].visible = not _dealing or index < _dealt_slot_count


func _finish_deal_animation(generation: int) -> void:
	if generation != _deal_generation:
		return
	_dealing = false
	_dealt_slot_count = _deal_targets().size()
	_apply_deal_visibility()
	_clear_flying_cards()
	_start_pending_community_deal()


func _clear_flying_cards() -> void:
	for child in deal_animation_layer.get_children():
		child.queue_free()


func _start_pending_community_deal() -> void:
	if _dealing or _community_dealing or _pending_community_cards.is_empty():
		return
	_community_dealing = true
	_play_community_deal_animation()


func _play_community_deal_animation() -> void:
	var card_back := load(CARD_BACK) as Texture2D
	while not _pending_community_cards.is_empty():
		var card_index: int = _pending_community_cards.pop_front()
		_active_community_card = card_index
		_apply_community_deal_visibility()
		var target := community_cards.get_child(card_index).get_node("Image") as TextureRect
		var layer_inverse := deal_animation_layer.get_global_transform().affine_inverse()
		var origin := $Background/DeckPile/TopCard as TextureRect
		var origin_local := layer_inverse * origin.get_global_rect().get_center()
		var flying_card := TextureRect.new()
		flying_card.name = "FlyingCommunityCard%d" % (card_index + 1)
		flying_card.texture = card_back
		flying_card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flying_card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		flying_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deal_animation_layer.add_child(flying_card)
		await _animate_flying_card(flying_card, origin_local, target, card_index)
		_active_community_card = -1
		target.visible = true
		_play_landing_bounce(target)
		community_card_dealt.emit(card_index)
		flying_card.queue_free()
		if deal_card_gap > 0.0 and not _pending_community_cards.is_empty():
			await get_tree().create_timer(deal_card_gap).timeout
	_community_dealing = false
	_apply_community_deal_visibility()


func _animate_flying_card(
	flying_card: TextureRect,
	origin_local: Vector2,
	target: TextureRect,
	variation: int
) -> void:
	var layer_inverse := deal_animation_layer.get_global_transform().affine_inverse()
	var target_frame := target.get_parent() as Control
	var target_global_center := target_frame.get_global_transform() * (target_frame.size * 0.5)
	var target_center := layer_inverse * target_global_center
	var target_size := target_frame.size
	var start_size := target_size * 0.62
	var distance := origin_local.distance_to(target_center)
	var curve_height := clampf(distance * 0.16, 65.0, 180.0)
	var curve_control := origin_local.lerp(target_center, 0.46) + Vector2(0.0, -curve_height)
	var start_rotation := deg_to_rad(-11.0 if variation % 2 == 0 else 11.0)
	var sway_rotation := deg_to_rad(4.0 if variation % 2 == 0 else -4.0)
	flying_card.position = origin_local - start_size * 0.5
	flying_card.size = start_size
	flying_card.pivot_offset = start_size * 0.5
	flying_card.rotation = start_rotation
	flying_card.modulate.a = 0.88
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(
		func(progress: float) -> void:
			if not is_instance_valid(flying_card):
				return
			var inverse_progress := 1.0 - progress
			var center := (
				origin_local * inverse_progress * inverse_progress
				+ curve_control * 2.0 * inverse_progress * progress
				+ target_center * progress * progress
			)
			var current_size := start_size.lerp(target_size, progress)
			flying_card.size = current_size
			flying_card.pivot_offset = current_size * 0.5
			flying_card.position = center - current_size * 0.5
			flying_card.rotation = lerpf(start_rotation, 0.0, progress) + sin(progress * PI) * sway_rotation
			flying_card.modulate.a = lerpf(0.88, 1.0, progress),
		0.0,
		1.0,
		deal_card_duration
	)
	await tween.finished


func _play_landing_bounce(target: TextureRect) -> void:
	target.pivot_offset = target.size * 0.5
	target.scale = Vector2(0.94, 0.94)
	var landing := create_tween()
	landing.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	landing.tween_property(target, "scale", Vector2.ONE, 0.14)


func _setup_card_interactions() -> void:
	var interactive_cards: Array[TextureRect] = []
	for seat in _all_player_seats():
		for card_index in 2:
			interactive_cards.append(seat.get_node("HoleCards/Card%d/Image" % (card_index + 1)) as TextureRect)
	for slot in community_cards.get_children():
		interactive_cards.append(slot.get_node("Image") as TextureRect)
	var perspective_enabled := should_use_card_perspective(
		OS.has_feature("web"),
		DisplayServer.is_touchscreen_available()
	)
	for card in interactive_cards:
		if perspective_enabled:
			var material := ShaderMaterial.new()
			material.shader = CARD_PERSPECTIVE_SHADER
			material.set_shader_parameter("rect_size", card.size)
			material.set_shader_parameter("x_rot", 0.0)
			material.set_shader_parameter("y_rot", 0.0)
			material.set_shader_parameter("fov", 70.0)
			material.set_shader_parameter("inset", 0.12)
			card.material = material
		else:
			card.material = null
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.resized.connect(_sync_card_shader_size.bind(card))
		card.mouse_entered.connect(_on_card_mouse_entered.bind(card))
		card.mouse_exited.connect(_on_card_mouse_exited.bind(card))
		card.gui_input.connect(_on_card_gui_input.bind(card))


static func should_use_card_perspective(is_web: bool, is_touchscreen: bool) -> bool:
	# WebKit/mobile WebGL is memory constrained. Touch devices retain the safe
	# scale feedback but skip the per-card perspective shader.
	return not (is_web and is_touchscreen)


func _apply_hole_card_fan() -> void:
	for seat in _all_player_seats():
		var first := seat.get_node("HoleCards/Card1") as PanelContainer
		var second := seat.get_node("HoleCards/Card2") as PanelContainer
		var angle := deg_to_rad(3.0 if seat.name == "BottomPlayer" else 4.0)
		first.pivot_offset = Vector2(first.size.x * 0.5, first.size.y)
		second.pivot_offset = Vector2(second.size.x * 0.5, second.size.y)
		first.rotation = -angle
		second.rotation = angle


func _apply_community_card_spread() -> void:
	var angles := [-2.8, -1.4, 0.0, 1.4, 2.8]
	var vertical_offsets := [11.0, 4.0, 0.0, 4.0, 11.0]
	for index in community_cards.get_child_count():
		var card := community_cards.get_child(index) as PanelContainer
		card.pivot_offset = Vector2(card.size.x * 0.5, card.size.y)
		card.rotation = deg_to_rad(float(angles[index]))
		card.position.y = (community_cards.size.y - card.size.y) * 0.5 + float(vertical_offsets[index])


func _sync_card_shader_size(card: TextureRect) -> void:
	var material := card.material as ShaderMaterial
	if material != null:
		material.set_shader_parameter("rect_size", card.size)


func _on_card_mouse_entered(card: TextureRect) -> void:
	card.z_index = 20
	_tween_card_scale(card, Vector2(1.035, 1.035), 0.12)


func _on_card_mouse_exited(card: TextureRect) -> void:
	card.z_index = 0
	_tween_card_scale(card, Vector2.ONE, 0.16)
	var material := card.material as ShaderMaterial
	if material == null:
		return
	var start_x := float(material.get_shader_parameter("x_rot"))
	var start_y := float(material.get_shader_parameter("y_rot"))
	var reset := create_tween()
	reset.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	reset.tween_method(
		func(progress: float) -> void:
			if not is_instance_valid(material):
				return
			material.set_shader_parameter("x_rot", lerpf(start_x, 0.0, progress))
			material.set_shader_parameter("y_rot", lerpf(start_y, 0.0, progress)),
		0.0,
		1.0,
		0.18
	)


func _on_card_gui_input(event: InputEvent, card: TextureRect) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_on_card_mouse_entered(card)
		else:
			_on_card_mouse_exited(card)
		card.accept_event()
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			card.accept_event()
		return
	if not event is InputEventMouseMotion or card.size.x <= 0.0 or card.size.y <= 0.0:
		return
	var mouse_event := event as InputEventMouseMotion
	var normalized := mouse_event.position / card.size
	var material := card.material as ShaderMaterial
	if material == null:
		return
	var target_y := clampf((normalized.x - 0.5) * 16.0, -8.0, 8.0)
	var target_x := clampf((0.5 - normalized.y) * 14.0, -7.0, 7.0)
	var current_y := float(material.get_shader_parameter("y_rot"))
	var current_x := float(material.get_shader_parameter("x_rot"))
	material.set_shader_parameter("y_rot", lerpf(current_y, target_y, 0.42))
	material.set_shader_parameter("x_rot", lerpf(current_x, target_x, 0.42))


func _tween_card_scale(card: TextureRect, target_scale: Vector2, duration: float) -> void:
	var key := card.get_instance_id()
	if _card_hover_tweens.has(key):
		var previous := _card_hover_tweens[key] as Tween
		if previous != null and previous.is_valid():
			previous.kill()
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", target_scale, duration)
	_card_hover_tweens[key] = tween


func _apply_community_deal_visibility() -> void:
	for index in community_cards.get_child_count():
		var image := community_cards.get_child(index).get_node("Image") as TextureRect
		if index >= _known_community_count:
			image.visible = false
		elif index == _active_community_card or index in _pending_community_cards:
			image.visible = false
		else:
			image.visible = true


func _cache_claimed_chip(player_id: int, rank: int) -> void:
	if player_id == 0 or rank < 1 or rank > _active_player_count:
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
	seat.get_node("MoneyFrame/MoneyLabel").text = _format_number(int(player.get("balance", 0)))
	var initial := seat.get_node("AvatarFrame/InitialLabel") as Label
	initial.text = name.left(1).to_upper()
	var avatar_id := int(player.get("avatar", 0))
	var icon := seat.get_node("AvatarFrame/AvatarIcon") as TextureRect
	var avatar_path := Avatars.game_player_path(avatar_id, bool(player.get("is_bot", false)))
	if not avatar_path.is_empty():
		icon.texture = load(avatar_path)
		icon.visible = true
		initial.visible = false
	else:
		icon.texture = null
		icon.visible = false
		initial.visible = true
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
		icon.visible = value >= 1 and value <= _active_player_count
		icon.texture = _rank_button_textures[value - 1] if icon.visible else null


func _update_cards(container: Container, cards: Array, hidden: bool) -> void:
	var slots := container.get_children()
	for index in slots.size():
		var slot := slots[index] as PanelContainer
		var label := slot.get_node("Label") as Label
		label.visible = false
		var image := slot.get_node("Image") as TextureRect
		if index < cards.size() and not hidden:
			image.texture = load(_card_asset_path(cards[index] as Dictionary)) as Texture2D
		else:
			image.texture = load(CARD_BACK) as Texture2D


func _update_community_cards(cards: Array) -> void:
	var slots := community_cards.get_children()
	for index in slots.size():
		var slot := slots[index] as PanelContainer
		(slot.get_node("Label") as Label).visible = false
		var image := slot.get_node("Image") as TextureRect
		if index < cards.size():
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
		var icon := slot.get_node("ResultIcon") as TextureRect
		var should_show := index < _round_results.size()
		var was_visible := icon.visible
		if not should_show:
			icon.visible = false
			_reset_progress_result_icon(icon)
			continue
		var succeeded := _round_results[index]
		icon.texture = _win_mark_texture if succeeded else _loss_mark_texture
		icon.visible = true
		if not was_visible:
			_animate_progress_result_icon(icon, succeeded)


func _animate_progress_result_icon(icon: TextureRect, succeeded: bool) -> void:
	_reset_progress_result_icon(icon)
	icon.pivot_offset = icon.size * 0.5
	icon.scale = Vector2.ONE * 0.28
	icon.rotation = deg_to_rad(-12.0 if succeeded else 12.0)
	icon.modulate = Color(1.25, 1.08, 0.62, 0.0) if succeeded else Color(1.08, 0.72, 1.28, 0.0)

	var tween := create_tween()
	_progress_result_tweens[icon] = tween
	var pop_duration := progress_result_effect_duration * 0.68
	tween.set_parallel(true)
	tween.tween_property(icon, "scale", Vector2.ONE * 1.16, pop_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "rotation", 0.0, pop_duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(icon, "modulate", Color.WHITE, pop_duration * 0.72).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.set_parallel(false)
	tween.tween_property(icon, "scale", Vector2.ONE, progress_result_effect_duration - pop_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_on_progress_result_effect_finished.bind(icon, tween))


func _reset_progress_result_icon(icon: TextureRect) -> void:
	var running := _progress_result_tweens.get(icon) as Tween
	if running != null and running.is_valid():
		running.kill()
	_progress_result_tweens.erase(icon)
	icon.scale = Vector2.ONE
	icon.rotation = 0.0
	icon.modulate = Color.WHITE


func _on_progress_result_effect_finished(icon: TextureRect, tween: Tween) -> void:
	if _progress_result_tweens.get(icon) == tween:
		_progress_result_tweens.erase(icon)


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


func _maybe_show_tutorial() -> void:
	var config := ConfigFile.new()
	var completed := config.load(TUTORIAL_CFG_PATH) == OK and bool(config.get_value("game", _tutorial_storage_key(), false))
	if not completed:
		start_tutorial(false)


func start_tutorial(_force := true) -> void:
	_tutorial_step = 0
	tutorial_overlay.visible = true
	_show_tutorial_step()


func close_tutorial(mark_completed := false) -> void:
	tutorial_overlay.visible = false
	if mark_completed:
		var config := ConfigFile.new()
		config.load(TUTORIAL_CFG_PATH)
		config.set_value("game", _tutorial_storage_key(), true)
		var error := config.save(TUTORIAL_CFG_PATH)
		if error != OK:
			push_warning("无法保存新手引导状态：%s" % error_string(error))


func _tutorial_storage_key() -> String:
	var session := get_node_or_null("/root/Session")
	if session != null:
		var session_user: Dictionary = session.get("user") as Dictionary
		var user_id := int(session_user.get("id", 0))
		if user_id != 0:
			return "completed_user_%d" % user_id
	return "completed_device"


func _show_tutorial_step() -> void:
	if not tutorial_overlay.visible or TUTORIAL_STEPS.is_empty():
		return
	_tutorial_step = clampi(_tutorial_step, 0, TUTORIAL_STEPS.size() - 1)
	var step: Dictionary = TUTORIAL_STEPS[_tutorial_step]
	tutorial_title.text = str(step["title"])
	tutorial_body.text = str(step["body"])
	var show_chart := bool(step.get("show_chart", false))
	tutorial_body.visible = not show_chart
	tutorial_chart.visible = show_chart
	tutorial_step_label.text = "%d / %d" % [_tutorial_step + 1, TUTORIAL_STEPS.size()]
	tutorial_previous_button.disabled = _tutorial_step == 0
	tutorial_next_button.text = "开始游戏" if _tutorial_step == TUTORIAL_STEPS.size() - 1 else "下一步"
	_layout_tutorial()


func _layout_tutorial() -> void:
	if not tutorial_overlay.visible or _tutorial_step >= TUTORIAL_STEPS.size():
		return
	var step: Dictionary = TUTORIAL_STEPS[_tutorial_step]
	var show_chart := bool(step.get("show_chart", false))
	var target := get_node_or_null(step["target"] as NodePath) as Control
	if target == null:
		return
	var overlay_rect := tutorial_overlay.get_global_rect()
	var target_rect := target.get_global_rect()
	var padding := 18.0
	var focus := Rect2(target_rect.position - overlay_rect.position - Vector2.ONE * padding, target_rect.size + Vector2.ONE * padding * 2.0)
	focus.position.x = clampf(focus.position.x, 8.0, tutorial_overlay.size.x - 16.0)
	focus.position.y = clampf(focus.position.y, 8.0, tutorial_overlay.size.y - 16.0)
	focus.size.x = minf(focus.size.x, tutorial_overlay.size.x - focus.position.x - 8.0)
	focus.size.y = minf(focus.size.y, tutorial_overlay.size.y - focus.position.y - 8.0)
	tutorial_highlight.visible = not show_chart
	tutorial_highlight.position = focus.position
	tutorial_highlight.size = focus.size

	var dim_top := $TutorialOverlay/DimTop as ColorRect
	var dim_bottom := $TutorialOverlay/DimBottom as ColorRect
	var dim_left := $TutorialOverlay/DimLeft as ColorRect
	var dim_right := $TutorialOverlay/DimRight as ColorRect
	if show_chart:
		dim_top.position = Vector2.ZERO
		dim_top.size = tutorial_overlay.size
		for dim in [dim_bottom, dim_left, dim_right]:
			dim.size = Vector2.ZERO
	else:
		dim_top.position = Vector2.ZERO
		dim_top.size = Vector2(tutorial_overlay.size.x, focus.position.y)
		dim_bottom.position = Vector2(0.0, focus.end.y)
		dim_bottom.size = Vector2(tutorial_overlay.size.x, maxf(0.0, tutorial_overlay.size.y - focus.end.y))
		dim_left.position = Vector2(0.0, focus.position.y)
		dim_left.size = Vector2(focus.position.x, focus.size.y)
		dim_right.position = Vector2(focus.end.x, focus.position.y)
		dim_right.size = Vector2(maxf(0.0, tutorial_overlay.size.x - focus.end.x), focus.size.y)

	var guide_width := minf(640.0 if show_chart else 660.0, tutorial_overlay.size.x - 32.0)
	var guide_height := minf(1040.0, tutorial_overlay.size.y - 24.0) if show_chart else 252.0
	var guide_x := (tutorial_overlay.size.x - guide_width) * 0.5
	var target_center_y := focus.position.y + focus.size.y * 0.5
	var guide_y := (tutorial_overlay.size.y - guide_height) * 0.5 if show_chart else (tutorial_overlay.size.y - guide_height - 32.0 if target_center_y < tutorial_overlay.size.y * 0.52 else 32.0)
	tutorial_guide_panel.set_anchor(SIDE_LEFT, 0.0)
	tutorial_guide_panel.set_anchor(SIDE_TOP, 0.0)
	tutorial_guide_panel.set_anchor(SIDE_RIGHT, 0.0)
	tutorial_guide_panel.set_anchor(SIDE_BOTTOM, 0.0)
	tutorial_guide_panel.offset_left = guide_x
	tutorial_guide_panel.offset_top = guide_y
	tutorial_guide_panel.offset_right = guide_x + guide_width
	tutorial_guide_panel.offset_bottom = guide_y + guide_height


func _on_tutorial_previous_pressed() -> void:
	if _tutorial_step <= 0:
		return
	_tutorial_step -= 1
	_show_tutorial_step()


func _on_tutorial_next_pressed() -> void:
	if _tutorial_step >= TUTORIAL_STEPS.size() - 1:
		close_tutorial(true)
		return
	_tutorial_step += 1
	_show_tutorial_step()


func _on_tutorial_skip_pressed() -> void:
	close_tutorial(true)


func _select_rank(rank: int) -> void:
	if _prediction_locked or rank == _selected_rank or rank in _locked_ranks:
		return
	_selected_rank = rank
	_refresh_prediction_buttons()
	rank_selected.emit(rank)


func _refresh_prediction_buttons() -> void:
	for index in prediction_buttons.size():
		var button := prediction_buttons[index]
		var rank := index + 1
		var locked := rank in _locked_ranks
		button.disabled = locked or _prediction_locked
		if _prediction_locked:
			button.modulate = Color(1.28, 1.12, 1.42, 1.0) if rank == _selected_rank else Color(0.38, 0.35, 0.42, 0.58)
		elif locked:
			button.modulate = Color(0.45, 0.42, 0.38, 0.55)
		else:
			button.modulate = Color(1.28, 1.12, 1.42, 1.0) if rank == _selected_rank else Color.WHITE
		button.scale = Vector2.ONE


func reject_pending_prediction(message: String) -> bool:
	if not _prediction_submit_pending:
		return false
	_prediction_submit_pending = false
	_prediction_locked = false
	_selected_rank = 0
	_refresh_prediction_buttons()
	submit_button.disabled = str(_state.get("status", "playing")) != "playing"
	submit_label.text = "提交预测"
	status_label.text = "%s，请重新选择" % message
	return true


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
			if _prediction_locked:
				return
			if _selected_rank == 0:
				status_label.text = "请先选择预测排名"
				return
			_prediction_submit_pending = true
			_prediction_locked = true
			_refresh_prediction_buttons()
			submit_button.disabled = true
			submit_label.text = "已锁定 · 第%d名" % _selected_rank
			status_label.text = "预测已锁定，等待其他玩家"
			prediction_submitted.emit(_selected_rank)


func _on_round_settlement_continue_requested() -> void:
	round_settlement.set_continue_pending()
	_on_submit_pressed()


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
