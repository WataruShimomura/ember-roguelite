extends Control

const Content = preload("res://core/content_catalog.gd")
const BattleEngine = preload("res://core/battle_engine.gd")
const Visuals = preload("res://ui/visual_catalog.gd")

var catalog = Content.new()
var visuals = Visuals.new()
var engine = BattleEngine.new(catalog)
var loadout = {"knight": ["ring", "boots"], "mage": ["ember", "ring"], "cleric": ["crest", "stone"]}
var seed_value: int = 20261115
var screen: String = "loadout"
var selected_skill: String = "attack"
var selected_target: String = ""
var root: VBoxContainer
var detail: AcceptDialog
var command_buttons: Array = []
var target_buttons: Array = []
var confirm_button: Button
var preview_label: Label
var battle_snapshot: Dictionary = {}
var current_calculation: Dictionary = {}
var selection_revision: int = -1
var accent = Color("e4b978")
var muted = Color("8d9aae")

func _ready() -> void:
	setup_theme()
	var backdrop = visuals.texture(visuals.data.get("background", ""))
	if backdrop:
		var background = TextureRect.new()
		background.texture = backdrop
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(background)
	var music_path = visuals.data.get("bgm", "")
	if not music_path.is_empty() and ResourceLoader.exists(music_path):
		var music = AudioStreamPlayer.new()
		music.stream = load(music_path)
		add_child(music)
		music.finished.connect(music.play)
		music.play()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	root = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 18)
	scroll.add_child(root)
	detail = AcceptDialog.new()
	detail.title = "計算内訳 / SOURCE TRACE"
	detail.min_size = Vector2i(800, 560)
	detail.get_ok_button().text = "戻る  [Esc]"
	add_child(detail)
	show_loadout()

func style(bg: Color, border: Color = Color("2c384b"), width: int = 1) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(9)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

func setup_theme() -> void:
	var t = Theme.new()
	t.default_font_size = 17
	var font_path = visuals.data.get("font", "")
	if not font_path.is_empty() and ResourceLoader.exists(font_path):
		t.default_font = load(font_path)
	else:
		var system_font = SystemFont.new()
		system_font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "Noto Sans CJK JP"])
		t.default_font = system_font
	t.set_color("font_color", "Label", Color("dce3ef"))
	t.set_stylebox("panel", "PanelContainer", style(Color("111925")))
	t.set_stylebox("normal", "Button", style(Color("1a2534")))
	t.set_stylebox("hover", "Button", style(Color("2c394b"), accent))
	t.set_stylebox("pressed", "Button", style(Color("4a3b29"), accent))
	t.set_stylebox("focus", "Button", style(Color(0, 0, 0, 0), accent, 2))
	t.set_stylebox("disabled", "Button", style(Color("101722"), Color("1f2836")))
	t.set_color("font_color", "Button", Color("e4e9f0"))
	t.set_color("font_disabled_color", "Button", Color("586578"))
	t.set_stylebox("normal", "OptionButton", style(Color("1a2534")))
	t.set_stylebox("hover", "OptionButton", style(Color("2c394b"), accent))
	var bar_background = style(Color("253042"), Color("253042"), 0)
	var bar_fill = style(Color("71bfa6"), Color("71bfa6"), 0)
	for box in [bar_background, bar_fill]:
		box.content_margin_left = 0
		box.content_margin_right = 0
		box.content_margin_top = 0
		box.content_margin_bottom = 0
	t.set_stylebox("background", "ProgressBar", bar_background)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 14)
	theme = t

func label(text_value: String, size: int = 17, tint: Color = Color("dce3ef")) -> Label:
	var node = Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", tint)
	return node

func wrapped(text_value: String, size: int = 16, tint: Color = Color("a8b5c8")) -> Label:
	var node = label(text_value, size, tint)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

func button(text_value: String, callback: Callable, prominent: bool = false) -> Button:
	var node = Button.new()
	node.text = text_value
	node.custom_minimum_size.y = 46
	if prominent:
		node.add_theme_stylebox_override("normal", style(Color("473a2b"), accent))
		node.add_theme_color_override("font_color", accent)
	node.pressed.connect(callback)
	return node

func panel(parent: Node, tint: Color = Color("2c384b")) -> VBoxContainer:
	var outer = PanelContainer.new()
	outer.add_theme_stylebox_override("panel", style(Color("111925"), tint))
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(outer)
	var box = VBoxContainer.new()
	outer.add_child(box)
	return box

func clear_view() -> void:
	for node in root.get_children():
		root.remove_child(node)
		node.queue_free()
	command_buttons.clear()
	target_buttons.clear()
	confirm_button = null

func header(section: String, description: String) -> void:
	var row = HBoxContainer.new()
	root.add_child(row)
	var title_box = VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_box)
	title_box.add_child(label("E M B E R   /   戦闘試験場", 30, accent))
	title_box.add_child(label(description, 15, muted))
	row.add_child(label(section + "   /   VER.0.1", 15, muted))
	root.add_child(HSeparator.new())

func show_loadout() -> void:
	screen = "loadout"
	clear_view()
	header("01  出撃準備", "灰の向こうを読む。予告を見極め、共有TPで戦局を変える。")
	root.add_child(label("3人の装備を整える", 25))
	root.add_child(wrapped("各2枠。同じ装備を複数人で使用できます。素早さは出撃時に行動順を固定し、戦闘中は変化しません。"))
	var columns = HBoxContainer.new()
	root.add_child(columns)
	for id in ["knight", "mage", "cleric"]:
		var card = panel(columns, visuals.color(id).darkened(0.55))
		identity(card, id)
		var stats = catalog.equipped_stats(id, loadout[id])
		for stat in catalog.data.stats:
			card.add_child(label("%s     %s" % [visuals.data.stats.get(stat, stat), str(stats.get(stat, 0))], 18))
		card.add_child(HSeparator.new())
		for slot in range(2):
			card.add_child(label("装備スロット %d" % (slot + 1), 14, muted))
			var options = OptionButton.new()
			options.fit_to_longest_item = false
			options.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			options.custom_minimum_size.y = 45
			options.add_item("装備なし")
			var keys = [""] + catalog.data.equipment.keys()
			for item in catalog.data.equipment:
				options.add_item(visuals.equipment(item) + " / " + visuals.data.equipment[item].description)
			options.select(keys.find(loadout[id][slot]))
			options.item_selected.connect(func(index):
				loadout[id][slot] = keys[index]
				show_loadout())
			card.add_child(options)
		card.add_child(wrapped(" / ".join(catalog.data.units[id].skills.map(func(skill): return visuals.skill(skill))), 15, visuals.color(id)))
	var bottom = panel(root)
	bottom.add_child(label("BUILD PRESETS", 14, accent))
	var preset_row = HBoxContainer.new()
	bottom.add_child(preset_row)
	preset_row.add_child(button("攻勢 / 火傷とTP循環", func():
		loadout = {"knight": ["ring", "boots"], "mage": ["ember", "ring"], "cleric": ["crest", "stone"]}
		show_loadout()))
	preset_row.add_child(button("持久 / HPと防御", func():
		loadout = {"knight": ["amulet", "stone"], "mage": ["amulet", "stone"], "cleric": ["crest", "stone"]}
		show_loadout()))
	bottom.add_child(wrapped("敵術士は詠唱の次ラウンドに全体攻撃。牽制で効果量を下げるか、防御で被害を抑えるか、撃破して止めるか。"))
	var actions = HBoxContainer.new()
	root.add_child(actions)
	actions.add_child(label("再現用シード", 16, muted))
	var seed_input = SpinBox.new()
	seed_input.min_value = 0
	seed_input.max_value = 2147483647
	seed_input.value = seed_value
	seed_input.custom_minimum_size.x = 190
	seed_input.value_changed.connect(func(value): seed_value = int(value))
	actions.add_child(seed_input)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(button("出撃する  →", start_battle, true))
	root.add_child(label("操作：マウス / Tabで移動・Enterで決定。戦闘中は 1〜4・←→・Enter。", 15, muted))

func identity(parent: Node, id: String) -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)
	var portrait = visuals.texture(visuals.data.units[id].get("portrait", ""))
	if portrait:
		var image_node = TextureRect.new()
		image_node.texture = portrait
		image_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image_node.custom_minimum_size = Vector2(60, 60)
		row.add_child(image_node)
	else:
		var badge = PanelContainer.new()
		badge.custom_minimum_size = Vector2(56, 60)
		badge.add_theme_stylebox_override("panel", style(visuals.color(id).darkened(0.85), visuals.color(id).darkened(0.4)))
		var glyph = label(visuals.data.units[id].glyph, 26, visuals.color(id))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_child(glyph)
		row.add_child(badge)
	var text_box = VBoxContainer.new()
	row.add_child(text_box)
	text_box.add_child(label(visuals.unit(id), 23, visuals.color(id)))
	text_box.add_child(label(visuals.data.units[id].subtitle, 12, muted))

func start_battle() -> void:
	engine.start(loadout, seed_value)
	selected_skill = "attack"
	selected_target = ""
	show_battle()

func show_battle() -> void:
	if engine.state.phase == "finished":
		show_result()
		return
	screen = "battle"
	clear_view()
	battle_snapshot = engine.snapshot()
	selection_revision = battle_snapshot.revision
	header("02  戦闘", "ROUND %02d   /   SEED %d   /   時間制限なし・即時解決" % [battle_snapshot.round, battle_snapshot.seed])
	var top = HBoxContainer.new()
	root.add_child(top)
	var order_box = panel(top)
	order_box.add_child(label("固定行動順  /  SPEED", 13, muted))
	var order_row = HBoxContainer.new()
	order_box.add_child(order_row)
	for id in battle_snapshot.order:
		var unit = battle_snapshot.units[id]
		var text_value = "%s %d" % [visuals.unit(id), unit.stats.SPEED]
		if id == battle_snapshot.actor:
			text_value = "▶ " + text_value
		elif unit.acted:
			text_value = "✓ " + text_value
		order_row.add_child(label(text_value, 16, accent if id == battle_snapshot.actor else (muted if unit.acted or unit.hp == 0 else visuals.color(id))))
	var tp_box = panel(top, accent.darkened(0.45))
	tp_box.get_parent().size_flags_horizontal = Control.SIZE_SHRINK_END
	tp_box.add_child(label("共有 TACTICAL POINTS", 13, muted))
	tp_box.add_child(label("%s   %d / %d" % ["●".repeat(battle_snapshot.tp) + "○".repeat(int(catalog.data.rules.max_tp) - battle_snapshot.tp), battle_snapshot.tp, catalog.data.rules.max_tp], 22, accent))
	var sides = HBoxContainer.new()
	sides.custom_minimum_size.y = 330
	root.add_child(sides)
	var allies = VBoxContainer.new()
	allies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.add_child(allies)
	allies.add_child(label("PARTY  /  味方", 14, muted))
	var ally_row = HBoxContainer.new()
	allies.add_child(ally_row)
	for id in ["knight", "mage", "cleric"]:
		unit_card(ally_row, id)
	var enemies = VBoxContainer.new()
	enemies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.add_child(enemies)
	enemies.add_child(label("THREATS  /  敵と行動予告", 14, muted))
	var enemy_row = HBoxContainer.new()
	enemies.add_child(enemy_row)
	for id in ["warlock", "sentinel"]:
		unit_card(enemy_row, id)
	var console = panel(root, accent.darkened(0.4))
	console.add_child(label("%s の手番  /  COMMAND" % visuals.unit(battle_snapshot.actor), 21, accent))
	var command_row = HBoxContainer.new()
	console.add_child(command_row)
	var commands = engine.commands(battle_snapshot.actor)
	if not commands.has(selected_skill):
		selected_skill = "attack"
	for index in range(commands.size()):
		var skill = commands[index]
		var cost = int(catalog.data.skills[skill].cost)
		var command_button = button("%d   %s   %s" % [index + 1, visuals.skill(skill), "TP %d" % cost if cost > 0 else ("TP +%d" % engine.preview(battle_snapshot.actor, skill).tp_gain if skill == "attack" else "TP ±0")], func(): select_skill(skill))
		command_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		command_button.disabled = cost > battle_snapshot.tp
		command_button.tooltip_text = "共有TPが不足しています" if command_button.disabled else "選択して対象と予測を確認"
		command_row.add_child(command_button)
		command_buttons.append(command_button)
	var target_row = HBoxContainer.new()
	target_row.name = "Targets"
	console.add_child(target_row)
	preview_label = wrapped("", 16, Color("e0e7f1"))
	console.add_child(preview_label)
	var controls = HBoxContainer.new()
	console.add_child(controls)
	controls.add_child(button("計算内訳  [D]", func(): show_details(current_calculation)))
	controls.add_child(label("1〜4 コマンド  /  ←→ 対象  /  Enter 確定", 14, muted))
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)
	var revision = selection_revision
	var actor = battle_snapshot.actor
	confirm_button = button("実行する  [Enter]  →", func(): commit(actor, revision), true)
	controls.add_child(confirm_button)
	select_skill(selected_skill)
	var recent = panel(root)
	recent.add_child(label("BATTLE LOG  /  直近の履歴", 13, muted))
	var events = battle_snapshot.events.filter(func(event): return ["action", "damage", "heal", "tp", "status", "charge", "cancel"].has(event.type))
	for event in events.slice(maxi(0, events.size() - 4)):
		recent.add_child(label(visuals.event_text(event), 14, muted))

func unit_card(parent: Node, id: String) -> void:
	var unit = battle_snapshot.units[id]
	var box = panel(parent, accent if id == battle_snapshot.actor else Color("2c384b"))
	identity(box, id)
	box.add_child(label("HP   %d / %d" % [unit.hp, unit.stats.MAX_HP], 18, Color("dfaaa4") if unit.hp < unit.stats.MAX_HP * 0.3 else Color("dce3ef")))
	var bar = ProgressBar.new()
	bar.max_value = unit.stats.MAX_HP
	bar.value = unit.hp
	bar.show_percentage = false
	bar.custom_minimum_size.y = 7
	box.add_child(bar)
	var conditions: Array[String] = []
	if unit.hp == 0:
		conditions.append("戦闘不能")
	if unit.guard:
		conditions.append("防御中")
	if unit.charged:
		conditions.append("詠唱完了")
	for status in unit.statuses:
		conditions.append("%s %d回" % [visuals.data.statuses.get(status, status), unit.statuses[status].remaining])
	for modifier in unit.modifiers:
		conditions.append("%s %+d" % [visuals.data.stats.get(modifier.stat, modifier.stat), modifier.value])
	box.add_child(wrapped(" / ".join(conditions) if not conditions.is_empty() else "状態異常なし", 13, muted))
	if unit.team == "enemy":
		if unit.hp <= 0:
			box.add_child(label("予告解除 / 戦闘不能", 14, muted))
			return
		var preview = engine.intent_preview(id)
		var intent = preview.intent
		var text_value = visuals.skill(intent.skill)
		if intent.done:
			text_value += " / 行動済み"
		elif not preview.active:
			text_value += " / 中止（戦闘不能）"
		else:
			text_value += "\n" + visuals.describe(preview.calculation)
		var intent_button = button(text_value, func():
			if not preview.calculation.is_empty(): show_details(preview.calculation))
		intent_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		intent_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		intent_button.add_theme_font_size_override("font_size", 14)
		box.add_child(intent_button)
	else:
		var stats_text: Array[String] = []
		for stat in catalog.data.stats:
			if stat != "MAX_HP":
				stats_text.append("%s %s" % [visuals.data.stats.get(stat, stat), str(unit.stats.get(stat, 0))])
		box.add_child(wrapped(" / ".join(stats_text), 13, muted))

func select_skill(skill: String) -> void:
	if screen != "battle" or catalog.data.skills[skill].cost > battle_snapshot.tp:
		return
	selected_skill = skill
	var actor = battle_snapshot.actor
	var legal = engine.legal_targets(actor, skill)
	if not legal.has(selected_target):
		selected_target = str(legal[0]) if not legal.is_empty() else ""
	for index in range(command_buttons.size()):
		var selected = engine.commands(actor)[index] == skill
		command_buttons[index].add_theme_stylebox_override("normal", style(Color("443726") if selected else Color("1a2534"), accent if selected else Color("2c384b")))
	var target_row = root.find_child("Targets", true, false)
	for node in target_row.get_children():
		target_row.remove_child(node)
		node.queue_free()
	target_buttons.clear()
	var mode = catalog.data.skills[skill].target
	if mode in ["enemy", "ally"]:
		target_row.add_child(label("対象", 15, muted))
		for id in legal:
			var target_button = button(("● " if id == selected_target else "○ ") + visuals.unit(id), func():
				selected_target = id
				select_skill(selected_skill))
			target_row.add_child(target_button)
			target_buttons.append(target_button)
	else:
		target_row.add_child(label("対象：" + ("自分" if mode == "self" else "全体 / 追加の対象選択は不要"), 15, muted))
	current_calculation = engine.preview(actor, skill, selected_target)
	preview_label.text = visuals.describe(current_calculation)
	confirm_button.disabled = current_calculation.targets.is_empty()

func commit(actor: String, revision: int) -> void:
	if screen != "battle":
		return
	if engine.submit(actor, selected_skill, selected_target, revision):
		selected_skill = "attack"
		selected_target = ""
		show_battle()

func show_details(calculation: Dictionary) -> void:
	if calculation.is_empty():
		return
	detail.dialog_text = ""
	for child in detail.get_children():
		if child is ScrollContainer:
			detail.remove_child(child)
			child.queue_free()
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 480)
	detail.add_child(scroll)
	var content = label(visuals.breakdown(calculation), 17)
	content.text += "\n数値内訳は予測と実行で共有。確率判定だけ実行時に抽選。"
	scroll.add_child(content)
	detail.popup_centered(Vector2i(850, 600))

func show_result() -> void:
	screen = "result"
	clear_view()
	var result = engine.result()
	header("03  リザルト", "SEED %d   /   ログから集計した戦闘記録" % result.seed)
	root.add_child(label("VICTORY  /  勝利" if result.winner == "ally" else "DEFEAT  /  敗北", 38, accent if result.winner == "ally" else Color("e68c87")))
	root.add_child(label("%d ラウンドを経過。装備と行動を振り返り、次の戦術を試そう。" % result.rounds, 17, muted))
	var summary = HBoxContainer.new()
	root.add_child(summary)
	for entry in [["与ダメージ", result.damage_dealt], ["被ダメージ", result.damage_taken], ["実回復量", result.healing], ["装備効果発動", result.equipment_triggers]]:
		var box = panel(summary)
		box.add_child(label(entry[0], 15, muted))
		box.add_child(label(str(entry[1]), 32, accent))
	var unit_row = HBoxContainer.new()
	root.add_child(unit_row)
	for id in ["knight", "mage", "cleric"]:
		var box = panel(unit_row)
		var stats = result.units[id]
		box.add_child(label(visuals.unit(id), 21, visuals.color(id)))
		box.add_child(label("行動 %d / 与ダメージ %d / 被ダメージ %d\n回復 %d / 装備効果 %d" % [stats.actions, stats.damage, stats.taken, stats.healing, stats.equipment], 16))
	var actions = HBoxContainer.new()
	root.add_child(actions)
	actions.add_child(button("同じ装備・シードで再戦  →", start_battle, true))
	actions.add_child(button("装備を変更する", show_loadout))
	actions.add_child(button("JSONログを保存", save_log))
	root.add_child(label("行動履歴・計算根拠・TP変動", 21))
	var tabs = TabContainer.new()
	tabs.custom_minimum_size.y = 310
	root.add_child(tabs)
	for mode in ["行動履歴", "全イベント"]:
		var history_scroll = ScrollContainer.new()
		history_scroll.name = mode
		tabs.add_child(history_scroll)
		var history = VBoxContainer.new()
		history.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		history_scroll.add_child(history)
		for event in engine.snapshot().events:
			if mode == "行動履歴" and event.type != "action":
				continue
			if event.type == "action":
				var row = button(visuals.event_text(event) + "  /  内訳を見る", func(): show_details(event.calculation))
				row.alignment = HORIZONTAL_ALIGNMENT_LEFT
				row.add_theme_font_size_override("font_size", 15)
				history.add_child(row)
			else:
				history.add_child(wrapped(visuals.event_text(event), 14, muted))

func save_log() -> void:
	for child in detail.get_children():
		if child is ScrollContainer:
			detail.remove_child(child)
			child.queue_free()
	var file = FileAccess.open("user://last_battle.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"result": engine.result(), "events": engine.snapshot().events, "loadout": loadout}, "\t"))
		file.close()
		detail.dialog_text = "保存先：" + ProjectSettings.globalize_path("user://last_battle.json")
	else:
		detail.dialog_text = "ログの保存先を開けませんでした。書き込み権限をご確認ください。"
	detail.popup_centered()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or detail.visible:
		return
	if screen != "battle":
		return
	var key = event.keycode
	if key >= KEY_1 and key <= KEY_4:
		select_skill(engine.commands(battle_snapshot.actor)[key - KEY_1])
	elif key == KEY_LEFT or key == KEY_RIGHT:
		var targets = engine.legal_targets(battle_snapshot.actor, selected_skill)
		if not targets.is_empty():
			var index = targets.find(selected_target)
			selected_target = targets[posmod(index + (1 if key == KEY_RIGHT else -1), targets.size())]
			select_skill(selected_skill)
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		commit(battle_snapshot.actor, selection_revision)
	elif key == KEY_D:
		show_details(current_calculation)
	elif key == KEY_ESCAPE:
		select_skill("attack")
	else:
		return
	get_viewport().set_input_as_handled()
