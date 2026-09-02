extends SceneTree
## 三人游戏牌桌离线测试：快照映射、牌面显示与排名预测交互。

const Helper = preload("res://tests/test_helper.gd")

var h := Helper.new()
var submitted_rank := 0
var selected_rank := 0
var rematch_count := 0
var quick_match_fired := false
var deal_started_count := 0
var deal_sequence: Array[String] = []
var community_deal_sequence: Array[int] = []


func _initialize() -> void:
	h.check(ProjectSettings.get_setting("display/window/stretch/aspect") == "keep", "game 固定 16:9 逻辑画布避免预览布局漂移")
	var background_import := ConfigFile.new()
	var progress_import := ConfigFile.new()
	h.check(background_import.load("res://game/游戏桌面底图.png.import") == OK and int(background_import.get_value("params", "process/size_limit", 0)) == 2048, "game Web 桌面底图限制导入尺寸降低移动端显存")
	h.check(progress_import.load("res://game/进度报警上图.png.import") == OK and int(progress_import.get_value("params", "process/size_limit", 0)) == 1024, "game 警报图限制导入尺寸降低移动端显存")
	h.check(not GameBoard.should_use_card_perspective(true, true) and GameBoard.should_use_card_perspective(true, false), "game Web 触屏设备禁用高成本透视 Shader")
	var settlement_preview := (load("res://scenes/game/round_settlement.tscn") as PackedScene).instantiate() as Control
	h.check(settlement_preview.visible and (settlement_preview.get_node("Panel/ResultTitle") as TextureRect).texture != null and (settlement_preview.get_node("Panel/Rows/Row1/BestCards/Card1/Image") as TextureRect).texture != null, "game 结算页在 Godot 2D 编辑器中提供完整可调预览")
	settlement_preview.queue_free()
	var scene := load("res://scenes/game/game_board.tscn") as PackedScene
	var board := scene.instantiate() as Control
	var editor_node_count := board.find_children("*", "", true, false).size()
	h.check(board.has_node("Background/RightPlayer") and board.has_node("Background/TopPlayer") and board.has_node("Background/BottomPlayer"), "game 四个玩家座席已固定在场景文件")
	h.check(board.has_node("Background/Vault/MoneyFrame/CoinIcon"), "game 金库组件已固定在场景文件")
	h.check(board.has_node("Background/PredictionPanel/ButtonLayer/Rank3/Artwork"), "game 排名预测组件已固定在场景文件")
	h.check(board.has_node("Background/PredictionPanel/ButtonLayer/Rank4/Artwork"), "game 四人模式第4名按钮已固定在场景文件")
	h.check(board.has_node("Background/DeckPile/TopCard"), "game 离开图标左侧固定显示独立牌堆")
	root.add_child(board)
	await process_frame
	var runtime_node_count := board.find_children("*", "", true, false).size()
	h.check(runtime_node_count == editor_node_count, "game 运行时不再新增布局节点")
	h.check(board.has_node("Background/TutorialHelpButton") and board.has_node("TutorialOverlay/GuidePanel"), "game 新手指引与手动重看入口固定在场景文件")
	board.start_tutorial(true)
	await process_frame
	var tutorial_overlay := board.get_node("TutorialOverlay") as Control
	var tutorial_highlight := board.get_node("TutorialOverlay/Highlight") as Panel
	h.check(tutorial_overlay.visible and tutorial_highlight.size.x > 0.0 and tutorial_highlight.size.y > 0.0, "game 新手指引遮罩会高亮当前目标")
	board.call("_on_tutorial_next_pressed")
	var tutorial_chart := board.get_node("TutorialOverlay/GuidePanel/Margin/VBox/HandRankingChart") as TextureRect
	h.check((board.get_node("TutorialOverlay/GuidePanel/Margin/VBox/Footer/Step") as Label).text == "2 / 8", "game 新手指引支持分步切换")
	h.check(tutorial_chart.visible and tutorial_chart.texture.resource_path.ends_with("德州扑克牌型大小说明图.png"), "game 新手指引包含可随时重看的牌型说明图")
	board.close_tutorial(false)
	h.check(not tutorial_overlay.visible, "game 新手指引可以关闭且测试不会写入完成状态")
	var music_node := root.get_node("Music")
	var music_player := music_node.get("_player") as AudioStreamPlayer
	var game_music := music_player.stream as AudioStreamMP3
	h.check(game_music != null and game_music.resource_path.ends_with("game.mp3") and game_music.loop, "game 场景循环播放 game.mp3 背景音乐")
	var editor_preview_hidden_at_runtime := not (board.get_node("Background/Progress/Slots/Slot1/ResultIcon") as TextureRect).visible
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
	var progress := board.get_node("Background/Progress") as TextureRect
	h.check(progress.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "game 警报进度保持素材原始长宽比")
	h.check(is_equal_approx(progress.size.x / progress.size.y, 3.0), "game 警报进度容器锁定为素材 3:1 比例")
	var progress_slots_node := board.get_node("Background/Progress/Slots") as Control
	var all_progress_slots_are_square := true
	for slot_node in progress_slots_node.get_children():
		var slot := slot_node as Control
		var result_icon := slot.get_node("ResultIcon") as TextureRect
		all_progress_slots_are_square = all_progress_slots_are_square and absf(slot.size.x - slot.size.y) < 0.05
		all_progress_slots_are_square = all_progress_slots_are_square and result_icon.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.check(all_progress_slots_are_square, "game 警报进度七个圆槽等宽等高且结果图标保持正圆")
	h.check(editor_preview_hidden_at_runtime, "game 2D 编辑器圆槽预览标记在运行时自动隐藏")
	h.check(board.get_node("Background/CommunityCards/Card1").custom_minimum_size == Vector2(110, 154), "game 公共牌使用标准扑克牌比例")
	var hidden_card := board.get_node("Background/LeftPlayer/HoleCards/Card1/Image") as TextureRect
	h.check(hidden_card.texture.resource_path.ends_with("back.png"), "game 对手手牌使用卡背")
	h.check((board.get_node("Background/LeftPlayer/HoleCards") as HBoxContainer).get_theme_constant("separation") < 0, "game 对手两张手牌采用德州式重叠排列")
	h.check((board.get_node("Background/BottomPlayer/HoleCards") as HBoxContainer).get_theme_constant("separation") < 0, "game 自己的两张手牌采用德州式重叠排列")
	var left_card_panel := board.get_node("Background/LeftPlayer/HoleCards/Card1") as PanelContainer
	var left_second_panel := board.get_node("Background/LeftPlayer/HoleCards/Card2") as PanelContainer
	h.check(left_card_panel.rotation < 0.0 and left_second_panel.rotation > 0.0, "game 两张手牌向两侧旋转形成扇形")
	var interactive_card := board.get_node("Background/BottomPlayer/HoleCards/Card1/Image") as TextureRect
	h.check(interactive_card.material is ShaderMaterial and interactive_card.mouse_filter == Control.MOUSE_FILTER_STOP, "game 手牌启用 2D 透视悬停材质")
	var interactive_public_card := board.get_node("Background/CommunityCards/Card1/Image") as TextureRect
	h.check(interactive_public_card.material is ShaderMaterial and interactive_public_card.mouse_filter == Control.MOUSE_FILTER_STOP, "game 公共牌启用相同的 2D 透视悬停材质")
	var public_first_panel := board.get_node("Background/CommunityCards/Card1") as PanelContainer
	var public_middle_panel := board.get_node("Background/CommunityCards/Card3") as PanelContainer
	var public_last_panel := board.get_node("Background/CommunityCards/Card5") as PanelContainer
	h.check(public_first_panel.rotation < 0.0 and is_zero_approx(public_middle_panel.rotation) and public_last_panel.rotation > 0.0, "game 五张公共牌向两侧展开形成轻微弧线")
	h.check(public_first_panel.position.y > public_middle_panel.position.y and public_last_panel.position.y > public_middle_panel.position.y, "game 公共牌中间略高、两侧逐步下沉")
	var hover_motion := InputEventMouseMotion.new()
	hover_motion.position = Vector2(interactive_card.size.x, 0.0)
	interactive_card.gui_input.emit(hover_motion)
	h.check(absf(float((interactive_card.material as ShaderMaterial).get_shader_parameter("y_rot"))) > 0.0, "game 鼠标位置会驱动手牌透视角度")
	board.apply_state({
		"status": "playing",
		"phase": "yellow",
		"players": [
			{"id": 2, "name": "对手甲", "balance": 2300, "predictions": [1, 2, 3, 4], "hole_cards": []},
			{"id": 3, "name": "对手乙", "balance": 1780, "predictions": [4, 3, 2, 1], "hole_cards": []},
			{"id": 4, "name": "对手丙", "balance": 2100, "predictions": [2, 4, 1, 3], "hole_cards": []},
			{"id": 1, "name": "本人", "balance": 1950, "chip": 4, "hole_cards": [{"rank": 12, "suit": 3}, {"rank": 11, "suit": 2}]},
		],
	}, 1)
	var top_player := board.get_node("Background/TopPlayer") as Control
	var rank4_button := board.get_node("Background/PredictionPanel/ButtonLayer/Rank4") as TextureButton
	var top_rank4_history := board.get_node("Background/TopPlayer/PredictionHistory/Round2Icon") as TextureRect
	h.check(top_player.visible and top_player.get_node("NameFrame/NameLabel").text == "对手乙", "game 四人模式显示第四位玩家座席")
	h.check(rank4_button.visible and int(board.get("_active_player_count")) == 4, "game 四人模式显示第4名预测按钮")
	h.check(top_rank4_history.visible and top_rank4_history.texture != null, "game 四人玩家历史可显示第4名")
	h.check((board.call("_deal_targets") as Array).size() == 8, "game 四人模式准备两轮共8个发牌目标")
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
	var progress_result_tweens: Dictionary = board.get("_progress_result_tweens")
	h.check(progress_result_tweens.size() == 2 and first_result.scale.x < 1.0 and second_result.modulate.a < 1.0, "game 新胜负标记播放淡入旋转回弹特效")
	var settlement := board.get_node("RoundSettlement") as Control
	h.check(settlement.visible, "game 每轮结束显示独立结算页面")
	var basic_result_title := settlement.get_node("Panel/ResultTitle") as TextureRect
	h.check(basic_result_title.texture is AtlasTexture and (basic_result_title.texture as AtlasTexture).atlas.resource_path.ends_with("结算胜利标题.png"), "game 成功轮次显示胜利结算标题")
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
	var right_info_atlas := right_info.texture as AtlasTexture
	var right_avatar_frame := board.get_node("Background/RightPlayer/AvatarFrame") as TextureRect
	var right_hole_cards := board.get_node("Background/RightPlayer/HoleCards") as HBoxContainer
	h.check(right_info_atlas != null and right_info_atlas.atlas.resource_path.ends_with("个人信息组合镜像.png") and not right_info.flip_h, "game 右侧玩家使用独立镜像组合素材")
	h.check(right_hole_cards.anchor_right < right_avatar_frame.anchor_left, "game 右侧玩家手牌位于头像左侧")
	var top_info := board.get_node("Background/TopPlayer/InfoFrame") as TextureRect
	var top_info_atlas := top_info.texture as AtlasTexture
	var top_avatar_frame := board.get_node("Background/TopPlayer/AvatarFrame") as TextureRect
	var top_hole_cards := board.get_node("Background/TopPlayer/HoleCards") as HBoxContainer
	h.check(top_info_atlas != null and top_info_atlas.atlas.resource_path.ends_with("个人信息组合镜像.png"), "game 右上玩家使用独立镜像组合素材")
	h.check(top_hole_cards.anchor_right < top_avatar_frame.anchor_left, "game 右上玩家手牌位于头像左侧")
	var coin_icon := board.get_node("Background/LeftPlayer/CoinIcon") as TextureRect
	h.check(coin_icon.texture is AtlasTexture, "game 金币圆圈使用主页金币图标")
	var history := board.get_node("Background/LeftPlayer/PredictionHistory") as TextureRect
	var right_history := board.get_node("Background/RightPlayer/PredictionHistory") as TextureRect
	var third_prediction := history.get_node("Round3Icon") as TextureRect
	h.check(history.texture is AtlasTexture and third_prediction.visible and third_prediction.texture is AtlasTexture, "game 玩家四次预测使用按钮图片记录")
	h.check((right_history.get_node("Round1Icon") as TextureRect).visible and (right_history.get_node("Round4Icon") as TextureRect).visible, "game 两位对手的预测历史同时显示")
	var royal_cards := [
		{"rank": 14, "suit": 3}, {"rank": 13, "suit": 3}, {"rank": 12, "suit": 3},
		{"rank": 11, "suit": 3}, {"rank": 10, "suit": 3},
	]
	var full_house_cards := [
		{"rank": 9, "suit": 0}, {"rank": 9, "suit": 1}, {"rank": 9, "suit": 2},
		{"rank": 4, "suit": 0}, {"rank": 4, "suit": 3},
	]
	var pair_cards := [
		{"rank": 7, "suit": 0}, {"rank": 7, "suit": 1}, {"rank": 14, "suit": 2},
		{"rank": 11, "suit": 0}, {"rank": 8, "suit": 3},
	]
	var rich_result_players := [
		{"id": 2, "name": "对手甲", "balance": 2300, "chip": 1, "best_hand": {"category": 8, "tiebreak": [14], "cards": royal_cards}, "hole_cards": []},
		{"id": 3, "name": "对手乙", "balance": 1780, "chip": 3, "best_hand": {"category": 1, "tiebreak": [7, 14, 11, 8], "cards": pair_cards}, "hole_cards": []},
		{"id": 1, "name": "本人", "balance": 1950, "chip": 2, "best_hand": {"category": 6, "tiebreak": [9, 4], "cards": full_house_cards}, "hole_cards": []},
	]
	board.apply_state({"status": "round_complete", "phase": "red", "round_succeeded": true, "host_id": 1, "players": rich_result_players}, 1)
	var result_row1 := settlement.get_node("Panel/Rows/Row1") as Control
	var result_row2 := settlement.get_node("Panel/Rows/Row2") as Control
	h.check(not result_row1.has_node("Balance") and (result_row1.get_node("Name") as Label).horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "game 结算页移除金币并让玩家名称居中")
	h.check((result_row1.get_node("PredictedRank/Label") as Label).text == "1" and (result_row1.get_node("ActualRank/Label") as Label).text == "1", "game 结算页同时显示玩家预测排名与实际排名")
	var result_hand_type := result_row1.get_node("HandType") as Label
	h.check(result_hand_type.text == "皇家同花顺" and result_hand_type.anchor_right < 0.85 and (result_row1.get_node("BestCards/Card5/Image") as TextureRect).texture != null, "game 结算页在牌框内靠左显示牌型名称与完整五张最佳成牌")
	var correct_frame := result_row1.get_node("PredictedRank") as TextureRect
	h.check(correct_frame.texture is AtlasTexture and (correct_frame.texture as AtlasTexture).atlas.resource_path.ends_with("排名圆框金色正确态.png"), "game 猜中排名使用金色正确态")
	rich_result_players[1]["chip"] = 2
	rich_result_players[2]["chip"] = 3
	board.apply_state({"status": "round_complete", "phase": "red", "round_succeeded": false, "host_id": 1, "players": rich_result_players}, 1)
	var failure_title := settlement.get_node("Panel/ResultTitle") as TextureRect
	var wrong_predicted_frame := result_row2.get_node("PredictedRank") as TextureRect
	var wrong_actual_frame := result_row2.get_node("ActualRank") as TextureRect
	h.check((failure_title.texture as AtlasTexture).atlas.resource_path.ends_with("结算失败标题.png"), "game 失败轮次显示失败结算标题")
	h.check((wrong_predicted_frame.texture as AtlasTexture).atlas.resource_path.ends_with("排名圆框紫色预测态.png") and (wrong_actual_frame.texture as AtlasTexture).atlas.resource_path.ends_with("排名圆框红色错误态.png"), "game 猜错时以紫色预测态和红色实际态清楚区分")
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
			{"id": 2, "name": "对手甲", "balance": 2300, "avatar": 2, "chips": [2, 0, 0, 0], "chip": 2, "confirmed": true, "hole_cards": []},
			{"id": 3, "name": "对手乙", "balance": 1780, "hole_cards": []},
			{"id": 1, "name": "本人", "balance": 1950, "chip": 3, "hole_cards": []},
		],
	}, 1)
	var rank_buttons := board.get_node("Background/PredictionPanel/ButtonLayer")
	h.check(rank_buttons.get_node("Rank2").disabled, "game 已确认的排名不可再选")
	h.check(not rank_buttons.get_node("Rank1").disabled and not rank_buttons.get_node("Rank3").disabled, "game 未锁排名保持可选")
	h.check(not rank_buttons.get_node("Rank3").modulate.is_equal_approx(Color.WHITE), "game 本人选择高亮跟随服务端 chip")
	var left_avatar := board.get_node("Background/LeftPlayer/AvatarFrame/AvatarIcon") as TextureRect
	h.check(left_avatar.visible and left_avatar.texture != null, "game 有头像的玩家座席显示头像图")
	h.check(left_avatar.size.x > 0.0 and left_avatar.size.y > 0.0, "game 头像使用场景文件中的可编辑布局")
	h.check(left_avatar.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "game 头像保持比例不拉伸")
	h.check(not board.get_node("Background/LeftPlayer/AvatarFrame/InitialLabel").visible, "game 有头像时隐藏首字母占位")
	var right_avatar := board.get_node("Background/RightPlayer/AvatarFrame/AvatarIcon") as TextureRect
	h.check(right_avatar.visible and right_avatar.texture.resource_path.ends_with("克苏鲁游客头像.png"), "game 未设置头像的游客使用专属头像")
	board.call("_update_seat", board.get_node("Background/RightPlayer"), {"id": -1, "name": "Cultist 1", "is_bot": true, "hole_cards": []}, false, false)
	h.check(right_avatar.visible and right_avatar.texture.resource_path.ends_with("克苏鲁机器人头像.png"), "game 机器人使用专属头像")
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
	h.check(board.get_node("Background/SubmitButton").disabled and "已锁定" in board.get_node("Background/SubmitButton/Label").text, "game 提交预测后按钮显示已锁定并禁止重复提交")
	h.check("等待其他玩家" in board.get_node("Background/StatusLabel").text, "game 锁定预测后显示持续状态反馈")
	h.check(board.get_node("Background/PredictionPanel/ButtonLayer/Rank1").modulate.a < 0.7 and board.get_node("Background/PredictionPanel/ButtonLayer/Rank2").modulate.a == 1.0, "game 锁定后保留所选排名高亮并淡化其他选项")
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
	board.deal_card_duration = 0.01
	board.deal_card_gap = 0.01
	board.deal_started.connect(func() -> void: deal_started_count += 1)
	board.card_dealt.connect(func(seat_name: String, card_index: int) -> void: deal_sequence.append("%s:%d" % [seat_name, card_index]))
	board.arm_new_round_animation()
	var deal_state := {
		"status": "playing",
		"phase": "white",
		"players": [
			{"id": 2, "name": "对手甲", "balance": 2300, "hole_cards": []},
			{"id": 3, "name": "对手乙", "balance": 1780, "hole_cards": []},
			{"id": 1, "name": "本人", "balance": 1950, "hole_cards": [{"rank": 12, "suit": 3}, {"rank": 11, "suit": 2}]},
		],
	}
	board.apply_state(deal_state, 1)
	h.check(not board.get_node("Background/LeftPlayer/HoleCards/Card1/Image").visible, "game 发牌开始时隐藏尚未到达的手牌")
	await create_timer(0.5).timeout
	h.check(deal_sequence == ["LeftPlayer:0", "RightPlayer:0", "BottomPlayer:0", "LeftPlayer:1", "RightPlayer:1", "BottomPlayer:1"], "game 按左、右、自己循环发两轮，每轮一张")
	h.check(board.get_node("Background/BottomPlayer/HoleCards/Card2/Image").visible, "game 两轮发牌结束后显示全部手牌")
	board.apply_state(deal_state, 1)
	await create_timer(0.05).timeout
	h.check(deal_started_count == 1, "game 重复状态快照不会重复播放发牌动画")
	board.community_card_dealt.connect(func(card_index: int) -> void: community_deal_sequence.append(card_index))
	board.arm_community_animation()
	deal_state["phase"] = "yellow"
	deal_state["community_cards"] = [
		{"rank": 2, "suit": 0},
		{"rank": 3, "suit": 1},
		{"rank": 4, "suit": 2},
	]
	board.apply_state(deal_state, 1)
	h.check(not board.get_node("Background/CommunityCards/Card1/Image").visible, "game 新公共牌飞入前隐藏目标牌位")
	await create_timer(0.2).timeout
	h.check(community_deal_sequence == [0, 1, 2], "game 一次新增三张公共牌时从独立牌堆依次发出")
	h.check(board.get_node("Background/CommunityCards/Card3/Image").visible, "game 飞入后的公共牌显示真实牌面")
	h.check(not board.get_node("Background/CommunityCards/Card4/Image").visible, "game 尚未发出的公共牌位置保持空白")
	board.apply_state(deal_state, 1)
	await create_timer(0.05).timeout
	h.check(community_deal_sequence.size() == 3, "game 重复公共牌快照不会重复发牌")
	board.show_events([{"event": "hole_dealt", "player_id": 2}])
	deal_state["phase"] = "white"
	deal_state["community_cards"] = [{"rank": 8, "suit": 3}]
	board.apply_state(deal_state, 1)
	await create_timer(0.3).timeout
	h.check(community_deal_sequence == [0, 1, 2, 0], "game 新一轮从五张重置后第一张公共牌仍播放发牌")
	deal_sequence.clear()
	board.arm_new_round_animation()
	var four_player_deal_state := {
		"status": "playing",
		"phase": "white",
		"players": [
			{"id": 2, "name": "对手甲", "balance": 2300, "hole_cards": []},
			{"id": 3, "name": "对手乙", "balance": 1780, "hole_cards": []},
			{"id": 4, "name": "对手丙", "balance": 2100, "hole_cards": []},
			{"id": 1, "name": "本人", "balance": 1950, "hole_cards": [{"rank": 12, "suit": 3}, {"rank": 11, "suit": 2}]},
		],
	}
	board.apply_state(four_player_deal_state, 1)
	await create_timer(0.6).timeout
	h.check(deal_sequence == ["LeftPlayer:0", "TopPlayer:0", "RightPlayer:0", "BottomPlayer:0", "LeftPlayer:1", "TopPlayer:1", "RightPlayer:1", "BottomPlayer:1"], "game 四人局按左、上、右、自己循环发两轮")
	h.check(board.get_node("Background/TopPlayer/HoleCards/Card2/Image").visible, "game 四人局两轮发牌结束后显示上方玩家手牌")
	board.queue_free()
	h.finish(self)
