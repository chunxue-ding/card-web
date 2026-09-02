class_name RoundSettlement
extends Control
## 每轮摊牌结算：展示团队结果、预测名次、实际名次及每人的五张最佳成牌。

signal continue_requested

const SUIT_TO_ASSET_ROW := {0: 3, 1: 2, 2: 1, 3: 0}
const CATEGORY_NAMES := ["高牌", "一对", "两对", "三条", "顺子", "同花", "葫芦", "四条", "同花顺"]

@onready var panel: TextureRect = $Panel
@onready var result_title: TextureRect = $Panel/ResultTitle
@onready var continue_button: Button = $Panel/ContinueButton
@onready var continue_label: Label = $Panel/ContinueButton/Label
@onready var rows: Array[Control] = [
	$Panel/Rows/Row1,
	$Panel/Rows/Row2,
	$Panel/Rows/Row3,
	$Panel/Rows/Row4,
]

var _success_title: Texture2D
var _failure_title: Texture2D
var _correct_rank: Texture2D
var _predicted_rank: Texture2D
var _wrong_rank: Texture2D


func _ready() -> void:
	_success_title = _cropped_texture("res://game/end/结算胜利标题.png")
	_failure_title = _cropped_texture("res://game/end/结算失败标题.png")
	_correct_rank = _cropped_texture("res://game/end/排名圆框金色正确态.png")
	_predicted_rank = _cropped_texture("res://game/end/排名圆框紫色预测态.png")
	_wrong_rank = _cropped_texture("res://game/end/排名圆框红色错误态.png")
	continue_button.pressed.connect(_on_continue_pressed)


func show_result(view: Dictionary, my_id: int) -> void:
	var was_hidden := not visible
	visible = true
	var succeeded := bool(view.get("round_succeeded", str(view.get("winner", "")) == "gang"))
	result_title.texture = _success_title if succeeded else _failure_title
	var players: Array = view.get("players", [])
	var actual_ranks := _actual_ranks(players)
	for index in rows.size():
		var row := rows[index]
		row.visible = index < players.size()
		if row.visible:
			_render_row(row, players[index] as Dictionary, int(actual_ranks.get(int((players[index] as Dictionary).get("id", 0)), index + 1)), my_id)
	_update_continue(view, my_id)
	if was_hidden:
		modulate.a = 0.0
		panel.scale = Vector2(0.96, 0.96)
		panel.pivot_offset = panel.size * 0.5
		var tween := create_tween().set_parallel(true)
		tween.tween_property(self, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(panel, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_result() -> void:
	visible = false
	continue_button.disabled = false
	modulate = Color.WHITE
	panel.scale = Vector2.ONE


func set_continue_pending() -> void:
	continue_button.disabled = true
	continue_label.text = "提交中…"


func _update_continue(view: Dictionary, my_id: int) -> void:
	var status := str(view.get("status", "round_complete"))
	var mine: Dictionary = {}
	for raw_player in view.get("players", []):
		var player := raw_player as Dictionary
		if int(player.get("id", 0)) == my_id:
			mine = player
			break
	if status == "round_complete":
		if bool(mine.get("next_ready", false)):
			var active_humans := 0
			var ready_humans := 0
			for raw_player in view.get("players", []):
				var player := raw_player as Dictionary
				if not bool(player.get("is_bot", false)) and not bool(player.get("abandoned", false)):
					active_humans += 1
					if bool(player.get("next_ready", false)):
						ready_humans += 1
			continue_label.text = "等待其他玩家 %d/%d" % [ready_humans, active_humans]
			continue_button.disabled = true
		else:
			continue_label.text = "下一轮"
			continue_button.disabled = false
	elif str(view.get("source", "friend")) == "match":
		continue_label.text = "快速匹配"
		continue_button.disabled = false
	elif int(view.get("host_id", 0)) == my_id:
		continue_label.text = "再来一局"
		continue_button.disabled = false
	else:
		continue_label.text = "等待房主再来一局"
		continue_button.disabled = true


func _render_row(row: Control, player: Dictionary, actual_rank: int, my_id: int) -> void:
	var player_id := int(player.get("id", 0))
	var display_name := "You" if player_id == my_id else str(player.get("name", "玩家"))
	(row.get_node("Name") as Label).text = display_name
	var avatar_path := Avatars.game_player_path(int(player.get("avatar", 0)), bool(player.get("is_bot", false)))
	(row.get_node("Avatar") as TextureRect).texture = load(avatar_path) as Texture2D
	var predicted_rank := int(player.get("chip", 0))
	if predicted_rank <= 0:
		var chips: Array = player.get("chips", [])
		if not chips.is_empty():
			predicted_rank = int(chips.back())
	var correct := predicted_rank == actual_rank and predicted_rank > 0
	var predicted_frame := row.get_node("PredictedRank") as TextureRect
	var actual_frame := row.get_node("ActualRank") as TextureRect
	predicted_frame.texture = _correct_rank if correct else _predicted_rank
	actual_frame.texture = _correct_rank if correct else _wrong_rank
	(predicted_frame.get_node("Label") as Label).text = str(predicted_rank) if predicted_rank > 0 else "—"
	(actual_frame.get_node("Label") as Label).text = str(actual_rank)
	var best_hand: Dictionary = player.get("best_hand", {})
	var cards: Array = best_hand.get("cards", [])
	for index in 5:
		var image := row.get_node("BestCards/Card%d/Image" % (index + 1)) as TextureRect
		image.texture = load(_card_asset_path(cards[index] as Dictionary)) as Texture2D if index < cards.size() else null
	(row.get_node("HandType") as Label).text = _hand_name(best_hand)


func _actual_ranks(players: Array) -> Dictionary:
	var ordered: Array[Dictionary] = []
	for raw_player in players:
		ordered.append(raw_player as Dictionary)
	ordered.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var compared := _compare_hands(left.get("best_hand", {}) as Dictionary, right.get("best_hand", {}) as Dictionary)
		if compared != 0:
			# 后端 chip/rank 的语义是从小到大：1 最弱，人数编号最大者最强。
			return compared < 0
		var left_chip := int(left.get("chip", 0))
		var right_chip := int(right.get("chip", 0))
		if left_chip != right_chip:
			return left_chip < right_chip
		return int(left.get("id", 0)) < int(right.get("id", 0))
	)
	var result := {}
	for index in ordered.size():
		result[int(ordered[index].get("id", 0))] = index + 1
	return result


func _compare_hands(left: Dictionary, right: Dictionary) -> int:
	var left_category := int(left.get("category", -1))
	var right_category := int(right.get("category", -1))
	if left_category != right_category:
		return 1 if left_category > right_category else -1
	var left_tiebreak: Array = left.get("tiebreak", [])
	var right_tiebreak: Array = right.get("tiebreak", [])
	for index in maxi(left_tiebreak.size(), right_tiebreak.size()):
		var left_value := int(left_tiebreak[index]) if index < left_tiebreak.size() else 0
		var right_value := int(right_tiebreak[index]) if index < right_tiebreak.size() else 0
		if left_value != right_value:
			return 1 if left_value > right_value else -1
	return 0


func _hand_name(best_hand: Dictionary) -> String:
	var category := int(best_hand.get("category", -1))
	var tiebreak: Array = best_hand.get("tiebreak", [])
	if category == 8 and not tiebreak.is_empty() and int(tiebreak[0]) == 14:
		return "皇家同花顺"
	if category < 0 or category >= CATEGORY_NAMES.size():
		return "未知牌型"
	return CATEGORY_NAMES[category]


func _card_asset_path(card: Dictionary) -> String:
	var rank := int(card.get("rank", 0))
	var suit := int(card.get("suit", 0))
	if rank < 2 or rank > 14 or not SUIT_TO_ASSET_ROW.has(suit):
		return "res://cards/back.png"
	var column := 0 if rank == 14 else rank - 1
	return "res://cards/card_r%d_c%d.png" % [int(SUIT_TO_ASSET_ROW[suit]), column]


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


func _on_continue_pressed() -> void:
	continue_requested.emit()
