extends "res://ui/view_base.gd"

var choices: Array = []

func build() -> void:
	heading("共通Lv%d / パーティの成長" % snapshot.level, "通常報酬は取得済みです。この成長を確定してから、冒険を続けます。")
	party_cards(self, snapshot.party, snapshot.loadout)
	var definition = catalog.data.growth.levels[str(snapshot.level)]
	var row = HBoxContainer.new()
	add_child(row)
	var options: Array = snapshot.growth_options if definition.kind == "choice" else ["equipment_slots"]
	for index in range(options.size()):
		var id = options[index]
		var card = panel(row, Color("80619a"))
		card.add_child(label("Lv%d → 成長 %d" % [snapshot.level, index + 1], 15, muted))
		var title = "全員の装備枠 2 → %d" % definition.slots if definition.kind == "slots" else visuals.growth_name(id)
		var description = "3人全員に空の装備枠を1つ追加します。装備は自動付与されません。獲得済みの予備装備を次の準備画面で装着できます。" if definition.kind == "slots" else visuals.data.growth[id].description
		card.add_child(label(title, 23, Color("ca95de")))
		card.add_child(wrapped(description, 18))
		var node = button("%d  この成長を確定 →" % (index + 1), func(): choose(index), true)
		card.add_child(node)
		choices.append(node)
	add_child(wrapped("成長はこの冒険だけで有効。選択は一度きりで、経験値稼ぎはありません。", 15))

func choose(index: int) -> void:
	if app.manager.choose_growth(index, snapshot.revision): app.render()

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key < KEY_1 + choices.size():
		choose(key - KEY_1)
		return true
	return false
