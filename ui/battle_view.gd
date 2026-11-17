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
var unit_panels: Dictionary = {}
var pool_labels: Dictionary = {}
var hp_gauges: Dictionary = {}
var tp_gauges: Dictionary = {}

func build() -> void:
	add_theme_constant_override("separation", 9)
	engine = app.manager.battle
	battle = engine.snapshot()
	actor = battle.actor
	revision = battle.revision
	commands = engine.commands(actor)
	var subtitle = "共通Lv%d   戦闘 %d / 4   ROUND %02d   SEED %d   /   即時実行" % [snapshot.level, snapshot.node + 1, battle.round, snapshot.seed]
	if app.lab_mode != "baseline": subtitle += "   /   Design Lab " + app.lab_mode
	heading(catalog.data.encounters[snapshot.route[snapshot.node]].name, subtitle)
	var order: Array[String] = []
	for id in battle.order:
		order.append(("▶ " if id == actor else ("✓ " if battle.units[id].acted else "")) + visuals.unit(id))
	add_child(label("固定行動順   " + " → ".join(order), 16, accent))
	var upgrades: Array[String] = []
	for id in snapshot.upgrades: upgrades.append(visuals.growth_name(id))
	add_child(label("選択成長：" + (" / ".join(upgrades) if not upgrades.is_empty() else "Lv2で選択"), 14, Color("ca95de")))
	var field = HBoxContainer.new()
	field.custom_minimum_size.y = 318
	add_child(field)
	var allies = VBoxContainer.new(); allies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_child(allies)
	allies.add_child(label("PARTY / 味方陣営", 14, muted))
	var crossing = VBoxContainer.new()
	crossing.custom_minimum_size.x = 70
	crossing.alignment = BoxContainer.ALIGNMENT_CENTER
	field.add_child(crossing)
	crossing.add_child(label("対峙", 20, accent))
	crossing.add_child(label("→ ←", 22, muted))
	var enemies = VBoxContainer.new(); enemies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_child(enemies)
	enemies.add_child(label("THREATS / 敵陣営・行動予告", 14, muted))
	for id in battle.order:
		unit_card(allies if battle.units[id].team == "ally" else enemies, id)
	var console = panel(self, accent.darkened(.5))
	console.add_child(label(visuals.unit(actor) + " の手番", 22, visuals.color(actor)))
	var row = HBoxContainer.new()
	console.add_child(row)
	for index in range(commands.size()):
		var skill = commands[index]
		var payment = engine.calculator.cost(battle.units[actor], skill)
		var transformations = snapshot.upgrades.filter(func(id):
			var growth = catalog.data.growth.options[id]
			return growth.get("unit", "") == actor and growth.get("skill", "") == skill)
		var node = button("%d  %s%s  TP%d" % [index + 1, visuals.skill(skill), " ★" if not transformations.is_empty() else "", payment.amount], func(): select_action(skill))
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		node.disabled = payment.amount > battle.units[actor].tp
		node.tooltip_text = "本人のTPが不足しています" if node.disabled else "予測を確認して実行"
		var hint: String = visuals.data.get("skill_hints", {}).get(skill, "")
		if not hint.is_empty(): node.tooltip_text += "\n" + hint
		for id in transformations: node.tooltip_text += "\n" + visuals.data.growth[id].description
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
	preview.custom_minimum_size.y = 40
	preview.max_lines_visible = 3
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
	log_panel.get_parent().name = "RecentEvents"
	log_panel.add_child(label("所持品   " + inventory_text(battle.inventory), 14, muted))
	var events = app.last_feedback if app.feedback_enabled else []
	var recent: Array[String] = []
	for event in events.slice(maxi(0, events.size() - 4)):
		var feedback = visuals.feedback(event)
		if not feedback.text.is_empty(): recent.append(feedback.text)
	log_panel.add_child(wrapped("直近：" + "  /  ".join(recent) if not recent.is_empty() else "次の行動を選択できます。", 14))
	var actions = HBoxContainer.new()
	log_panel.add_child(actions)
	var log_button = button("全ログと計算根拠", func(): app.show_text("戦闘記録", "\n".join(battle.events.map(func(e): return visuals.event_text(e)))))
	log_button.custom_minimum_size.y = 30
	actions.add_child(log_button)
	var feedback_button = button("変化強調 " + ("ON" if app.feedback_enabled else "OFF"), func():
		app.feedback_enabled = not app.feedback_enabled
		app.render())
	feedback_button.custom_minimum_size.y = 30
	actions.add_child(feedback_button)

func unit_card(parent: Node, id: String) -> void:
	var unit = battle.units[id]
	var card = panel(parent, accent if id == actor else visuals.color(id).darkened(.7))
	card.add_theme_constant_override("separation", 3)
	unit_panels[id] = card.get_parent()
	var card_style = style(Color("111925"), visuals.color(id).darkened(.7))
	card_style.content_margin_top = 5
	card_style.content_margin_bottom = 5
	unit_panels[id].add_theme_stylebox_override("panel", card_style)
	var row = HBoxContainer.new()
	card.add_child(row)
	var badge = PanelContainer.new()
	badge.custom_minimum_size = Vector2(58, 64)
	badge.add_theme_stylebox_override("panel", style(visuals.color(id).darkened(.85), visuals.color(id).darkened(.4)))
	row.add_child(badge)
	var texture = visuals.texture(visuals.data.units.get(id, {}).get("portrait", ""))
	if texture:
		var image_node = TextureRect.new()
		image_node.texture = texture
		image_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.add_child(image_node)
	else:
		var glyph = label(visuals.data.units[id].glyph, 26, visuals.color(id))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_child(glyph)
	var body = VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 3)
	row.add_child(body)
	var states: Array[String] = []
	if unit.hp <= 0: states.append("戦闘不能")
	if unit.guard: states.append("構え中")
	for status in unit.statuses: states.append("%s%d" % [visuals.data.statuses[status], unit.statuses[status].remaining])
	for modifier in unit.modifiers: states.append("%s%+d" % [visuals.data.stats[modifier.stat], modifier.value])
	body.add_child(label(("▶ " if id == actor else "") + visuals.unit(id) + "  " + " / ".join(states), 18, visuals.color(id)))
	var hp = ProgressBar.new(); hp.max_value = unit.stats.MAX_HP; hp.value = unit.hp; hp.show_percentage = false; hp.custom_minimum_size.y = 5
	body.add_child(hp); hp_gauges[id] = hp
	if unit.team == "ally":
		var recovery = catalog.data.rules.tp_recovery
		var text = "HP %d/%d   TP %d/%d" % [unit.hp, unit.stats.MAX_HP, unit.tp, unit.stats.MAX_TP]
		if recovery.enabled and recovery.pool > 0: text += "   自然 残%d" % unit.tp_pool
		var resources = label(text, 15)
		if recovery.enabled and recovery.pool > 0:
			resources.tooltip_text = "R2以降、ラウンド開始に最大%dTP。実回復分だけ自然プールを消費。" % recovery.round
		elif recovery.enabled:
			resources.tooltip_text = "開始時にTP+%d（上限まで）。ラウンド開始時の自然回復はありません。" % recovery.entry
		body.add_child(resources); pool_labels[id] = resources
		var tp = ProgressBar.new(); tp.max_value = unit.stats.MAX_TP; tp.value = unit.tp; tp.show_percentage = false; tp.custom_minimum_size.y = 5
		var fill = StyleBoxFlat.new(); fill.bg_color = Color("82b9ec"); fill.set_corner_radius_all(3)
		tp.add_theme_stylebox_override("fill", fill)
		body.add_child(tp); tp_gauges[id] = tp
	else:
		body.add_child(label("HP %d/%d / 最低到達%d" % [unit.hp, unit.stats.MAX_HP, unit.low_water], 14))
	var change_label = label("", 12, muted)
	change_label.custom_minimum_size.y = 16
	card.add_child(change_label)
	if app.feedback_enabled:
		var changes = app.last_feedback.filter(func(e): return e.get("target", "") == id and e.type in ["damage", "heal", "tp", "status"] and e.get("amount", 1) != 0)
		if not changes.is_empty():
			var latest = visuals.feedback(changes[-1])
			change_label.text = latest.text
			change_label.add_theme_color_override("font_color", latest.color)
	if unit.team == "enemy" and unit.hp > 0:
		var predicted = engine.intent_preview(id)
		var text_value = "行動済み" if predicted.intent.get("done", true) else (visuals.skill(predicted.intent.skill) + " / " + visuals.describe(predicted.calculation).replace("\n", " / "))
		var node = button(text_value, func(): app.show_details(predicted.calculation))
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node.custom_minimum_size.y = 34
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
	var header: String = visuals.data.get("skill_hints", {}).get(skill, "")
	if not item.is_empty(): header = "%sを1個消費・1手番使用" % visuals.data.items[item]
	preview.text = (header + "\n" if not header.is_empty() else "") + visuals.describe(calculation)
	confirm.disabled = calculation.targets.is_empty()
	for id in unit_panels:
		var border = accent if id == actor else (Color("82b9ec") if id == selected_target else visuals.color(id).darkened(.7))
		var box = style(Color("111925"), border, 2 if id == actor or id == selected_target else 1)
		box.content_margin_top = 5
		box.content_margin_bottom = 5
		unit_panels[id].add_theme_stylebox_override("panel", box)

func commit() -> void:
	var from = engine.state.events.size()
	if engine.submit(actor, selected_skill, selected_target, revision, selected_item):
		app.last_feedback = engine.state.events.slice(from).filter(func(e): return e.type in ["damage", "heal", "tp", "status", "growth_trigger", "counter_stance", "remove_status"])
		app.render()

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
