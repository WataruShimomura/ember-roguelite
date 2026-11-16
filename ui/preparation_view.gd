extends "res://ui/view_base.gd"

var launch: Button

func build() -> void:
	heading("残り火の旅", "VER.0.3  /  4戦の短い冒険。HPと個別TPを、次の戦いへ。")
	add_child(wrapped("通常戦 → 報酬 → 通常戦 → 報酬 → 祭壇 → 強敵 → 報酬 → 最奥ボス。全滅で冒険終了。", 18))
	var row = HBoxContainer.new()
	add_child(row)
	row.add_child(button("速攻 / 捨身と集中", func(): choose_preset("burst")))
	row.add_child(button("継戦 / 吸収と反撃", func(): choose_preset("sustain")))
	var cards = HBoxContainer.new()
	add_child(cards)
	for id in catalog.party_ids():
		var card = panel(cards, visuals.color(id).darkened(.5))
		card.add_child(label(visuals.unit(id), 25, visuals.color(id)))
		var stats = catalog.equipped_stats(id, app.loadout[id])
		for stat in catalog.data.stats: card.add_child(label("%s   %d" % [visuals.data.stats.get(stat, stat), stats[stat]], 18))
		for slot in range(2):
			var options = OptionButton.new()
			options.fit_to_longest_item = false
			options.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			options.custom_minimum_size.y = 44
			var keys = [""] + catalog.data.equipment.keys()
			for item in keys: options.add_item(visuals.equipment(item))
			options.select(keys.find(app.loadout[id][slot]))
			options.item_selected.connect(func(index):
				app.loadout[id][slot] = keys[index]
				app.render())
			card.add_child(options)
			var item = app.loadout[id][slot]
			card.add_child(wrapped(visuals.data.equipment.get(item, {}).get("description", "装備なし"), 14))
	var info = panel(self)
	info.add_child(wrapped("戦闘開始TP+2 / R2以降は有限プール4から自然回復+1。Lv2・3・4で成長。\n吸収は敵の最低到達HPを更新した分だけ。アイテムは有限で、使用に1手番必要です。", 17))
	var controls = HBoxContainer.new()
	add_child(controls)
	controls.add_child(label("冒険シード", 16, muted))
	var seed_input = SpinBox.new()
	seed_input.min_value = 0; seed_input.max_value = 2147483647; seed_input.value = app.seed_value
	seed_input.custom_minimum_size.x = 180
	seed_input.value_changed.connect(func(value): app.seed_value = int(value))
	controls.add_child(seed_input)
	launch = button("冒険に出る →", app.start_run, true)
	controls.add_child(launch)
	add_child(wrapped("操作：マウス / Tab・Enter。戦闘は 1〜3 コマンド・4 アイテム・←→ 対象・Enter 実行・D 内訳。"))

func choose_preset(id: String) -> void:
	app.preset = id
	app.loadout = catalog.data.presets[id].duplicate(true)
	app.render()
