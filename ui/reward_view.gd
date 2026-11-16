extends "res://ui/view_base.gd"

var choices: Array = []

func build() -> void:
	var is_event = snapshot.phase == "event"
	heading(catalog.data.event.name if is_event else "戦利品を選ぶ", "一度だけの選択。HP・TP・装備・アイテムは次の戦闘へ引き継ぎます。")
	party_cards(self, snapshot.party, snapshot.loadout)
	add_child(label("所持品   " + inventory_text(snapshot.inventory), 16, muted))
	var row = HBoxContainer.new()
	add_child(row)
	var count = catalog.data.event.choices.size() if is_event else snapshot.offers.size()
	for index in range(count):
		var card = panel(row)
		var description: String
		var title: String
		var allowed = true
		if is_event:
			title = catalog.data.event.choices[index].name
			description = catalog.data.event.choices[index].description
		else:
			var reward = catalog.data.rewards[snapshot.offers[index]]
			title = visuals.reward_name(reward)
			description = visuals.reward_description(reward)
			if reward.kind == "item": allowed = app.manager.can_add_item(reward.item, int(reward.quantity))
		card.add_child(label(title, 24, accent))
		card.add_child(wrapped(description, 18))
		var node = button("%d  選ぶ →" % (index + 1), func(): choose(index), true)
		node.disabled = not allowed
		if not allowed: card.add_child(wrapped("所持上限のため選べません。別の報酬を選択してください。", 14))
		card.add_child(node)
		choices.append(node)

func choose(index: int) -> void:
	var accepted = app.manager.choose_event(index, snapshot.revision) if snapshot.phase == "event" else app.manager.choose_reward(index, snapshot.revision)
	if accepted: app.render()

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key < KEY_1 + choices.size():
		if not choices[key - KEY_1].disabled: choose(key - KEY_1)
		return true
	return false
