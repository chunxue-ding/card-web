extends SceneTree
## 三人游戏牌桌离线测试：快照映射、牌面显示与排名预测交互。

const Helper = preload("res://tests/test_helper.gd")

var h := Helper.new()
var submitted_rank := 0
var selected_rank := 0
var rematch_count := 0
var quick_match_fired := false


func _initialize() -> void:
	var scene := load("res://scenes/game/game_board.tscn") as PackedScene
	var board := scene.instantiate() as Control
	root.add_child(board)
	await process_frame
	board.apply_state({
		"status": "playing",
		"phase": "yellow",
		"pot": 3600,
		"vaults": 1,
		"alarms": 1,
		"community_cards": [{"rank": 14, "suit": 3}],
		"players": [
			{"id": 2, "name": "对手甲", "balance": 2300, "predictions": [2, 1, 3, 2], "hole_cards": []},
			{"id": 3, "name": "对手乙", "balance": 1780, "predictions": [1, 3, 2, 3], "hole_cards": []},
			{"id": 1, "name": "本人", "balance": 1950, "hole_cards": [{"rank": 12, "suit": 3}, {"rank": 11, "suit": 2}]},
		],
	}, 1)
	h.check(board.get_node("Background/Vault/MoneyFrame/PotLabel").text == "3,600", "game 奖池金额映射")
	h.check(board.get_node("Background/Vault/MoneyFrame/CoinIcon").texture is AtlasTexture, "game 金库金额框使用主页金币图标")
	h.check(board.get_node("Background/Vault/Artwork").anchor_left < 0.0, "game 金库主体独立放大")
	var public_card := board.get_node("Background/CommunityCards/Card1/Image") as TextureRect
	h.check(public_card.texture.resource_path.ends_with("card_r0_c0.png"), "game 公共牌映射真实牌面")
	h.check(not board.get_node("Background/Progress/PhaseLabel").visible, "game 隐藏阶段文字说明")
	h.check(board.get_node("Background/CommunityCards/Card1").custom_minimum_size == Vector2(110, 154), "game 公共牌使用标准扑克牌比例")
	var hidden_card := board.get_node("Background/LeftPlayer/HoleCards/Card1/Image") as TextureRect
	h.check(hidden_card.texture.resource_path.ends_with("back.png"), "game 对手手牌使用卡背")
	board.apply_state({
		"status": "round_complete",
		"phase": "red",
		"round_succeeded": true,
		"vaults": 1,
		"alarms": 1,
		"community_cards": [
			{"rank": 2, "suit": 0}, {"rank": 3, "suit": 1}, {"rank": 4, "suit": 2},
			{"rank": 5, "suit": 3}, {"rank": 6, "suit": 0},
		],
		"players": [
			{"id": 2, "name": "对手甲", "balance": 2300, "predictions": [2, 1, 3, 2], "hole_cards": [{"rank": 10, "suit": 0}, {"rank": 9, "suit": 1}]},
			{"id": 3, "name": "对手乙", "balance": 1780, "predictions": [1, 3, 2, 3], "hole_cards": [{"rank": 8, "suit": 2}, {"rank": 7, "suit": 3}]},
			{"id": 1, "name": "本人", "balance": 1950, "hole_cards": [{"rank": 12, "suit": 3}, {"rank": 11, "suit": 2}]},
		],
	}, 1)
	var revealed_left_card := board.get_node("Background/LeftPlayer/HoleCards/Card1/Image") as TextureRect
	var revealed_right_card := board.get_node("Background/RightPlayer/HoleCards/Card1/Image") as TextureRect
	h.check(not revealed_left_card.texture.resource_path.ends_with("back.png") and not revealed_right_card.texture.resource_path.ends_with("back.png"), "game 当轮结算后翻开两位对手手牌")
	var first_result := board.get_node("Background/Progress/Slots/Slot1/ResultIcon") as TextureRect
	var second_result := board.get_node("Background/Progress/Slots/Slot2/ResultIcon") as TextureRect
	h.check(first_result.visible and first_result.texture != null, "game 胜利图标填入进度圆槽")
	h.check(second_result.visible and second_result.texture != null, "game 失败图标填入进度圆槽")
	board.show_events([{"event": "round_settled", "succeeded": true, "vaults": 2, "alarms": 1}])
	var third_result := board.get_node("Background/Progress/Slots/Slot3/ResultIcon") as TextureRect
	var third_atlas := third_result.texture as AtlasTexture
	h.check(third_result.visible and third_atlas.atlas.resource_path.ends_with("胜利标记.png"), "game 新一轮结果按顺序追加")
	h.check(board.get_node("Background/BottomPlayer/NameFrame/NameLabel").text == "You", "game 本人固定在底部")
	h.check(board.get_node("Background/LeftPlayer/NameFrame/NameLabel").text == "对手甲", "game 对手固定在左侧")
	h.check(board.theme != null and board.theme.default_font.has_char("中".unicode_at(0)), "game 全场景默认字体包含中文字形")
	var left_name_frame := board.get_node("Background/LeftPlayer/NameFrame") as TextureRect
	h.check(left_name_frame.anchor_left < 0.25 and left_name_frame.anchor_right < 0.58, "game 用户名区域向左对齐")
	var left_info := board.get_node("Background/LeftPlayer/InfoFrame") as TextureRect
	var right_info := board.get_node("Background/RightPlayer/InfoFrame") as TextureRect
	h.check(left_info.texture is AtlasTexture and not left_info.flip_h, "game 玩家信息使用裁剪后的组合素材")
	h.check(not right_info.flip_h and right_info.anchor_left > 0.69, "game 右侧玩家信息保持参考图方向")
	var coin_icon := board.get_node("Background/LeftPlayer/CoinIcon") as TextureRect
	h.check(coin_icon.texture is AtlasTexture, "game 金币圆圈使用主页金币图标")
	var history := board.get_node("Background/LeftPlayer/PredictionHistory") as TextureRect
	var right_history := board.get_node("Background/RightPlayer/PredictionHistory") as TextureRect
	var third_prediction := history.get_node("Round3Icon") as TextureRect
	h.check(history.texture is AtlasTexture and third_prediction.visible and third_prediction.texture is AtlasTexture, "game 玩家四次预测使用按钮图片记录")
	h.check((right_history.get_node("Round1Icon") as TextureRect).visible and (right_history.get_node("Round4Icon") as TextureRect).visible, "game 两位对手的预测历史同时显示")
	board.apply_state({
		"status": "playing",
		"phase": "white",
		"players": [
			{"id": 4, "name": "事件对手甲", "balance": 2300, "hole_cards": []},
			{"id": 5, "name": "事件对手乙", "balance": 1780, "hole_cards": []},
			{"id": 1, "name": "本人", "balance": 1950, "hole_cards": []},
		],
	}, 1)
	board.show_events([
		{"event": "chip_claimed", "player_id": 4, "rank": 1},
		{"event": "chip_claimed", "player_id": 5, "rank": 2},
		{"event": "phase_changed", "from": "white", "to": "yellow"},
	])
	board.apply_state({
		"status": "playing",
		"phase": "yellow",
		"players": [
			{"id": 4, "name": "事件对手甲", "balance": 2300, "hole_cards": []},
			{"id": 5, "name": "事件对手乙", "balance": 1780, "hole_cards": []},
			{"id": 1, "name": "本人", "balance": 1950, "hole_cards": []},
		],
	}, 1)
	h.check((history.get_node("Round1Icon") as TextureRect).visible and (right_history.get_node("Round1Icon") as TextureRect).visible, "game 事件中的两位对手预测均写入轮次历史")
	board.apply_state({
		"status": "playing",
		"phase": "orange",
		"players": [
			{"id": 2, "name": "对手甲", "balance": 2300, "chips": [3, 0, 0, 0], "hole_cards": []},
			{"id": 3, "name": "对手乙", "balance": 1780, "hole_cards": []},
			{"id": 1, "name": "本人", "balance": 1950, "hole_cards": []},
		],
	}, 1)
	h.check(history.get_node("Round1Icon").visible, "game 服务端预测历史按阶段显示")
	h.check(not history.get_node("Round3Icon").visible, "game 服务端历史不被本地缓存补齐")
	board.apply_state({
		"status": "playing",
		"phase": "orange",
		"players": [
			{"id": 2, "name": "对手甲", "balance": 2300, "chips": [2, 0, 0, 0], "chip": 2, "confirmed": true, "hole_cards": []},
			{"id": 3, "name": "对手乙", "balance": 1780, "hole_cards": []},
			{"id": 1, "name": "本人", "balance": 1950, "chip": 3, "hole_cards": []},
		],
	}, 1)
	var rank_buttons := board.get_node("Background/PredictionPanel/ButtonLayer")
	h.check(rank_buttons.get_node("Rank2").disabled, "game 已确认的排名不可再选")
	h.check(not rank_buttons.get_node("Rank1").disabled and not rank_buttons.get_node("Rank3").disabled, "game 未锁排名保持可选")
	h.check(not rank_buttons.get_node("Rank3").modulate.is_equal_approx(Color.WHITE), "game 本人选择高亮跟随服务端 chip")
	board.apply_state({
		"status": "playing",
		"phase": "white",
		"players": [
			{"id": 2, "name": "对手甲", "balance": 2300, "chips": [0, 0, 0, 0], "hole_cards": []},
			{"id": 3, "name": "对手乙", "balance": 1780, "hole_cards": []},
			{"id": 1, "name": "本人", "balance": 1950, "hole_cards": []},
		],
	}, 1)
	h.check(not history.get_node("Round1Icon").visible, "game 新一轮预测历史清空")
	var submit := board.get_node("Background/SubmitButton") as TextureButton
	h.check(is_equal_approx(submit.anchor_left, 0.75) and is_equal_approx(submit.anchor_bottom, 0.96), "game 提交预测按钮放大并定位右下角")
	var prediction_art := board.get_node("Background/PredictionPanel/Artwork") as TextureRect
	h.check(prediction_art.texture is AtlasTexture, "game 排名预测使用裁剪后的新背景素材")
	h.check(not board.get_node("Background/PredictionPanel/ButtonLayer/Rank1/Label").visible, "game 排名按钮使用新数字素材")
	var rank_art := board.get_node("Background/PredictionPanel/ButtonLayer/Rank1/Artwork") as TextureRect
	h.check(rank_art.stretch_mode == TextureRect.STRETCH_SCALE, "game 排名按钮跟随背景响应式对齐")
	board.prediction_submitted.connect(func(rank: int) -> void: submitted_rank = rank)
	board.rank_selected.connect(func(rank: int) -> void: selected_rank = rank)
	board.get_node("Background/PredictionPanel/ButtonLayer/Rank2").pressed.emit()
	h.check(selected_rank == 2, "game 选择即上报排名")
	board.get_node("Background/SubmitButton").pressed.emit()
	h.check(submitted_rank == 2, "game 提交所选预测排名")
	var finished_players := [
		{"id": 2, "name": "对手甲", "balance": 2300, "hole_cards": []},
		{"id": 3, "name": "对手乙", "balance": 1780, "hole_cards": []},
		{"id": 1, "name": "本人", "balance": 1950, "hole_cards": []},
	]
	board.apply_state({"status": "finished", "phase": "red", "winner": "gang", "host_id": 1, "players": finished_players}, 1)
	h.check(board.get_node("Background/SubmitButton/Label").text == "再来一局", "game 房主结算页显示再来一局")
	board.rematch_requested.connect(func() -> void: rematch_count += 1)
	board.get_node("Background/SubmitButton").pressed.emit()
	h.check(rematch_count == 1, "game 房主提交触发再来一局")
	board.apply_state({"status": "finished", "phase": "red", "winner": "gang", "host_id": 2, "players": finished_players}, 1)
	h.check(board.get_node("Background/SubmitButton/Label").text == "等待房主再来一局", "game 非房主等待再来一局")
	board.get_node("Background/SubmitButton").pressed.emit()
	h.check(rematch_count == 1, "game 非房主不触发再来一局")
	board.apply_state({"status": "round_complete", "phase": "red", "host_id": 1, "players": finished_players}, 1)
	h.check(board.get_node("Background/SubmitButton/Label").text == "下一轮", "game 轮结算页显示下一轮")
	h.check(board.get_node("Background/LeftPlayer/StateLabel").text == "看牌中", "game 未确认玩家显示看牌中")
	var voting_players := [
		{"id": 2, "name": "对手甲", "balance": 2300, "next_ready": true, "hole_cards": []},
		{"id": 3, "name": "对手乙", "balance": 1780, "hole_cards": []},
		{"id": 1, "name": "本人", "balance": 1950, "next_ready": true, "hole_cards": []},
	]
	board.apply_state({"status": "round_complete", "phase": "red", "host_id": 1, "players": voting_players}, 1)
	h.check(board.get_node("Background/SubmitButton/Label").text == "等待其他玩家 2/3", "game 已投票显示等待进度")
	h.check(board.get_node("Background/LeftPlayer/StateLabel").text == "已继续", "game 已确认玩家显示已继续")
	board.apply_state({"status": "finished", "phase": "red", "winner": "gang", "source": "match", "host_id": 1, "players": finished_players}, 1)
	h.check(board.get_node("Background/SubmitButton/Label").text == "快速匹配", "game 匹配桌结算页显示快速匹配")
	board.quick_match_requested.connect(func() -> void: quick_match_fired = true)
	board.get_node("Background/SubmitButton").pressed.emit()
	h.check(quick_match_fired, "game 匹配桌提交触发快速匹配")
	board.queue_free()
	h.finish(self)
