extends "res://ui/view_base.gd"

var proceed: Button

func build() -> void:
	heading("次の戦いに備える", "次は " + catalog.data.encounters[snapshot.route[snapshot.node]].name + " / 獲得した装備だけを交換できます。")
	party_cards(self, snapshot.party, snapshot.loadout)
	var row = HBoxContainer.new()
	add_child(row)
	for id in catalog.party_ids():
		var card = panel(row)
		card.add_child(label(visuals.unit(id), 22, visuals.color(id)))
		for slot in range(2):
			var keys: Array = [snapshot.loadout[id][slot]]
			if not "" in keys: keys.append("")
			for gear in snapshot.gear:
				if snapshot.gear[gear] > 0 and not gear in keys: keys.append(gear)
			var options = OptionButton.new()
			options.fit_to_longest_item = false; options.custom_minimum_size.y = 44
			for gear in keys: options.add_item(visuals.equipment(gear))
			options.item_selected.connect(func(index):
				if app.manager.equip(id, slot, keys[index], snapshot.revision): app.render())
			card.add_child(options)
			card.add_child(wrapped(visuals.data.equipment.get(snapshot.loadout[id][slot], {}).get("description", "装備なし"), 14))
	var bag: Array[String] = []
	for id in snapshot.gear:
		if snapshot.gear[id] > 0: bag.append("%s ×%d" % [visuals.equipment(id), snapshot.gear[id]])
	add_child(wrapped("予備装備：" + (" / ".join(bag) if not bag.is_empty() else "なし")))
	add_child(wrapped("最大HP・最大TPを増やしても現在値は補充されません。戦闘不能者は蘇生薬でのみ復帰します。"))
	add_child(label("所持品   " + inventory_text(snapshot.inventory), 17, muted))
	proceed = button("次の戦闘へ →", func():
		if app.manager.start_battle(snapshot.revision): app.render(), true)
	add_child(proceed)
