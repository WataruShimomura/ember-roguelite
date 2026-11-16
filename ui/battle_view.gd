extends "res://ui/view_base.gd"

var engine
var battle: Dictionary
var selected_skill: String = "attack"
var selected_target: String = ""
var selected_item: String = ""
var calculation: Dictionary = {}
var command_buttons: Array = []
var target_buttons: Array = []
var item_buttons: Array = []
var targets_box: HBoxContainer
var items_box: HBoxContainer
var preview: Label
var confirm: Button
var commands: Array
var revision: int
var actor: String

func build() -> void:
	engine = app.manager.battle
	battle = engine.snapshot()
	actor = battle.actor
	revision = battle.revision
	commands = engine.commands(actor)
	heading(catalog.data.encounters[snapshot.route[snapshot.node]].name, "戦闘 %d / 4   ROUND %02d   SEED %d   /   個別TP・即時実行" % [snapshot.node + 1, battle.round, snapshot.seed])
	var order: Array[String] = []
	for id in battle.order:
		order.append(("▶ " if id == actor else ("✓ " if battle.units[id].acted else "")) + visuals.unit(id))
	add_child(label("固定行動順   " + " → ".join(order), 16, accent))
	var units_row = HBoxContainer.new()
	units_row.custom_minimum_size.y = 300
	add_child(units_row)
	for id in battle.order.filter(func(key): return battle.units[key].team == "ally") + battle.order.filter(func(key): return battle.units[key].team == "enemy"):
		unit_card(units_row, id)
	var console = panel(self, accent.darkened(.5))
	console.add_child(label(visuals.unit(actor) + " の手番", 22, visuals.color(actor)))
	var row = HBoxContainer.new()
	console.add_child(row)
	for index in range(commands.size()):
		var skill = commands[index]
		var payment = engine.calculator.cost(battle.units[actor], skill)
		var node = button("%d  %s  TP%d" % [index + 1, visuals.skill(skill), payment.amount], func(): select_action(skill))
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.disabled = payment.amount > battle.units[actor].tp
		node.tooltip_text = "本人のTPが不足しています" if node.disabled else "予測を確認して実行"
		row.add_child(node)
		command_buttons.append(node)
	var item_button = button("4  アイテム", toggle_items)
	item_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(item_button)
	command_buttons.append(item_button)
	items_box = HBoxContainer.new()
	items_box.visible = false
	console.add_child(items_box)
	for id in catalog.data.items:
		var item_node = button("%s ×%d" % [visuals.data.items[id], battle.inventory.get(id, 0)], func(): select_item(id))
		item_node.disabled = battle.inventory.get(id, 0) <= 0
		items_box.add_child(item_node)
		item_buttons.append(item_node)
	targets_box = HBoxContainer.new()
	console.add_child(targets_box)
	preview = wrapped("", 15, Color("e0e7f1"))
	preview.custom_minimum_size.y = 54
	console.add_child(preview)
	var controls = HBoxContainer.new()
	console.add_child(controls)
	controls.add_child(button("計算内訳 [D]", func(): app.show_details(calculation)))
	controls.add_child(label("1〜3 選択 / ←→ 対象 / Enter 実行", 14, muted))
	var space = Control.new(); space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(space)
	confirm = button("実行する [Enter] →", commit, true)
	controls.add_child(confirm)
	select_action("attack")
	var log_panel = panel(self)
	log_panel.add_child(label("所持品   " + inventory_text(battle.inventory), 14, muted))
	var events = battle.events.filter(func(e): return e.type in ["action", "damage", "heal", "tp", "item", "cancel"])
	for event in events.slice(maxi(0, events.size() - 3)):
		log_panel.add_child(wrapped(visuals.event_text(event), 14, muted))
	log_panel.add_child(button("この戦闘の全ログ", func(): app.show_text("戦闘記録", "\n".join(battle.events.map(func(e): return visuals.event_text(e))))))

func unit_card(parent: Node, id: String) -> void:
	var unit = battle.units[id]
	var card = panel(parent, accent if id == actor else visuals.color(id).darkened(.7))
	var texture = visuals.texture(visuals.data.units.get(id, {}).get("portrait", ""))
	if texture:
		var image_node = TextureRect.new()
		image_node.texture = texture
		image_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image_node.custom_minimum_size.y = 44
		card.add_child(image_node)
	card.add_child(label(visuals.unit(id), 22, visuals.color(id)))
	card.add_child(label("HP %d / %d" % [unit.hp, unit.stats.MAX_HP], 17))
	var hp = ProgressBar.new(); hp.max_value = unit.stats.MAX_HP; hp.value = unit.hp; hp.show_percentage = false; hp.custom_minimum_size.y = 7
	card.add_child(hp)
	if unit.team == "ally": card.add_child(label("TP %d / %d" % [unit.tp, unit.stats.MAX_TP], 20, accent))
	else: card.add_child(label("最低到達HP %d" % unit.low_water, 13, muted))
	var states: Array[String] = []
	if unit.hp <= 0: states.append("戦闘不能")
	if unit.guard: states.append("構え中 ×0.5")
	for status in unit.statuses: states.append("%s 残%d" % [visuals.data.statuses[status], unit.statuses[status].remaining])
	for modifier in unit.modifiers: states.append("%s %+d" % [visuals.data.stats[modifier.stat], modifier.value])
	card.add_child(wrapped(" / ".join(states) if not states.is_empty() else "状態異常なし", 13, muted))
	if unit.team == "enemy" and unit.hp > 0:
		var predicted = engine.intent_preview(id)
		var text_value = "行動済み" if predicted.intent.get("done", true) else (visuals.skill(predicted.intent.skill) + "\n" + visuals.describe(predicted.calculation))
		var node = button(text_value, func(): app.show_details(predicted.calculation))
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node.add_theme_font_size_override("font_size", 13)
		card.add_child(node)

func toggle_items() -> void:
	items_box.visible = not items_box.visible

func select_item(id: String) -> void:
	if battle.inventory.get(id, 0) <= 0: return
	items_box.visible = true
	select_action(catalog.data.items[id].skill, id)

func select_action(skill: String, item: String = "") -> void:
	if engine.calculator.cost(battle.units[actor], skill).amount > battle.units[actor].tp: return
	selected_skill = skill
	selected_item = item
	var legal = engine.legal_targets(actor, skill)
	if not selected_target in legal: selected_target = str(legal[0]) if not legal.is_empty() else ""
	for child in targets_box.get_children():
		targets_box.remove_child(child); child.queue_free()
	target_buttons.clear()
	var mode = catalog.data.skills[skill].target
	if mode in ["enemy", "ally", "fallen_ally"]:
		targets_box.add_child(label("対象", 14, muted))
		for id in legal:
			var node = button(("● " if id == selected_target else "○ ") + visuals.unit(id), func():
				selected_target = id
				select_action(selected_skill, selected_item))
			targets_box.add_child(node); target_buttons.append(node)
	else: targets_box.add_child(label("対象：自動選択 / 全体または自分", 14, muted))
	for index in range(commands.size()):
		command_buttons[index].add_theme_stylebox_override("normal", style(Color("443726") if commands[index] == skill else Color("1a2534"), accent if commands[index] == skill else Color("2c384b")))
	calculation = engine.preview(actor, skill, selected_target)
	preview.text = ("%sを1個消費・1手番使用\n" % visuals.data.items[item] if not item.is_empty() else "") + visuals.describe(calculation)
	confirm.disabled = calculation.targets.is_empty()

func commit() -> void:
	if engine.submit(actor, selected_skill, selected_target, revision, selected_item): app.render()

func handle_key(key: int) -> bool:
	if key >= KEY_1 and key <= KEY_3: select_action(commands[key - KEY_1])
	elif key == KEY_4: toggle_items()
	elif key in [KEY_LEFT, KEY_RIGHT]:
		var targets = engine.legal_targets(actor, selected_skill)
		if not targets.is_empty():
			selected_target = targets[posmod(targets.find(selected_target) + (1 if key == KEY_RIGHT else -1), targets.size())]
			select_action(selected_skill, selected_item)
	elif key in [KEY_ENTER, KEY_KP_ENTER]: commit()
	elif key == KEY_D: app.show_details(calculation)
	elif key == KEY_ESCAPE: select_action("attack"); items_box.visible = false
	else: return false
	return true
