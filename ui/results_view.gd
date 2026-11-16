extends "res://ui/view_base.gd"

var proceed: Button

func build() -> void:
	var finished = snapshot.phase == "finished"
	var entry = snapshot.battles[-1]
	var result = app.manager.result().total if finished else entry.result
	var title = ("冒険クリア" if snapshot.outcome == "clear" else "冒険終了 / 全滅") if finished else ("戦闘勝利" if entry.result.winner == "ally" else "戦闘敗北")
	heading(title, "SEED %d / 戦闘 %d / イベントログから集計した結果" % [snapshot.seed, snapshot.battles.size()])
	var totals = HBoxContainer.new()
	add_child(totals)
	for value in [["ラウンド", result.rounds], ["与ダメージ", result.damage_dealt], ["被ダメージ", result.damage_taken], ["回復", result.healing], ["装備寄与", result.equipment_triggers]]:
		var card = panel(totals)
		card.add_child(label(value[0], 14, muted)); card.add_child(label(str(value[1]), 27, accent))
	party_cards(self, snapshot.party, snapshot.loadout)
	var controls = HBoxContainer.new()
	add_child(controls)
	if finished:
		proceed = button("同じ初期装備・シードで再挑戦 →", app.start_run, true)
		controls.add_child(proceed)
		controls.add_child(button("出撃準備に戻る", app.prepare))
		controls.add_child(button("冒険ログJSONを保存", app.save_run))
	else:
		proceed = button("冒険リザルトへ →" if not snapshot.outcome.is_empty() else "報酬を選ぶ →", func():
			if app.manager.continue_result(snapshot.revision): app.render(), true)
		controls.add_child(proceed)
	var tabs = TabContainer.new()
	tabs.custom_minimum_size.y = 320
	add_child(tabs)
	var fights = snapshot.battles if finished else [entry]
	for index in range(fights.size()):
		var fight = fights[index]
		var scroll = ScrollContainer.new(); scroll.name = "戦闘%d" % (index + 1 if finished else snapshot.node + 1)
		tabs.add_child(scroll)
		var body = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(body)
		body.add_child(label(catalog.data.encounters[fight.encounter].name, 20, accent))
		for id in catalog.party_ids():
			var before = fight.start.party[id]; var after = fight.end.party[id]
			body.add_child(label("%s   HP %d → %d   /   TP %d → %d" % [visuals.unit(id), before.hp, after.hp, before.tp, after.tp], 16))
		body.add_child(button("全イベント・TP・吸収を見る", func(): app.show_text("戦闘イベント", "\n".join(fight.events.map(func(e): return visuals.event_text(e))))))
		for event in fight.events:
			if event.type == "action":
				var node = button(visuals.event_text(event) + " / 内訳", func(): app.show_details(event.calculation))
				node.alignment = HORIZONTAL_ALIGNMENT_LEFT
				node.add_theme_font_size_override("font_size", 14)
				body.add_child(node)
	if finished:
		var scroll = ScrollContainer.new(); scroll.name = "報酬・装備・イベント"
		tabs.add_child(scroll)
		var body = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(body)
		for event in snapshot.history:
			body.add_child(wrapped(visuals.run_event_text(event), 15))
