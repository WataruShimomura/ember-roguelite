extends Control

const Plan = preload("res://design_lab_v2/plan.gd")
const ClockRules = preload("res://design_lab_v2/clock.gd")
const MINT = Color("91d7c5")
const GOLD = Color("f0c580")
const SUBTLE = Color("aab9cf")
const DANGER = Color("ffab91")

@export_enum("plan", "clock") var mode: String = "plan"
var game
var host: VBoxContainer
var queue: Array = []
var pending: Dictionary = {}
var selected_actor: String = ""
var selected_move: String = ""
var preview_label: Label
var highlight_target: String = ""
var generation: int = 0
var last_events: Array = []
var seed_value: int = 42

func _ready() -> void:
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "Noto Sans CJK JP"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 20
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 30)
	add_child(margin)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	host = VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_theme_constant_override("separation", 12)
	scroll.add_child(host)
	start()

func start(reward: String = "base", encounter: int = 0, carry: Dictionary = {}) -> void:
	game = Plan.new() if mode == "plan" else ClockRules.new()
	game.start(seed_value, encounter, reward, carry)
	queue.clear()
	pending.clear()
	last_events.clear()
	selected_actor = ""
	selected_move = ""
	highlight_target = ""
	render()

func line(parent: Node, value: String, size: int = 20, color: Color = Color("edf2fa")) -> Label:
	var text = Label.new()
	text.text = value
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", size)
	text.add_theme_color_override("font_color", color)
	parent.add_child(text)
	return text

func button(parent: Node, value: String, callback: Callable, tint: Color = Color("26354b")) -> Button:
	var control = Button.new()
	control.text = value
	control.custom_minimum_size = Vector2(92, 43)
	var palette = {"normal": tint, "hover": tint.lightened(.16), "pressed": tint.lightened(.24), "focus": tint.lightened(.08)}
	for entry in palette:
		var box = StyleBoxFlat.new()
		box.bg_color = palette[entry]
		box.set_corner_radius_all(6)
		box.content_margin_left = 13
		box.content_margin_right = 13
		control.add_theme_stylebox_override(entry, box)
	var stamp: int = generation
	control.pressed.connect(func():
		if stamp == generation: callback.call())
	parent.add_child(control)
	return control

func panel(parent: Node, border: Color = Color("354b65")) -> VBoxContainer:
	var frame = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color("142032")
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	frame.add_child(column)
	return column

func title(id: String) -> String:
	return game.data.units.get(id, {}).get("name", "敵全体" if id == "all" else id)

func move_name(id: String) -> String:
	return game.data.moves.get(id, {}).get("name", {"heavy": "大技", "strike": "攻撃", "mend": "自己回復", "guard": "構え"}.get(id, id))

func timeline() -> void:
	var entries: Array = []
	for id in ["oracle", "shield"] + game.ALLIES:
		if not game.alive(id): continue
		var foe: bool = id in game.ENEMIES
		var due: int = game.s.intents[id].due if foe else game.s.units[id].ready
		entries.append({"id": id, "foe": foe, "due": due, "order": entries.size()})
	entries.sort_custom(func(a, b):
		return a.order < b.order if a.due == b.due else a.due < b.due)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	host.add_child(row)
	for entry in entries:
		var tile = panel(row, GOLD if entry.id == selected_actor else Color("354b65"))
		var caption = title(entry.id)
		if entry.foe: caption += "・" + move_name(game.s.intents[entry.id].move)
		line(tile, "t%02d   %s" % [entry.due, caption], 17, DANGER if entry.foe else MINT)

func card(parent: Node, id: String, foe: bool) -> void:
	var unit: Dictionary = game.s.units[id]
	var box = panel(parent, GOLD if id == selected_actor or id == highlight_target else Color("354b65"))
	var status_text: Array[String] = []
	if unit.guard: status_text.append("構え")
	if unit.mark: status_text.append("刻印")
	if unit.burn > 0: status_text.append("燃焼×%d" % unit.burn)
	if unit.reply: status_text.append("反撃待ち")
	var status_suffix = "   " + " / ".join(status_text) if not status_text.is_empty() else ""
	line(box, title(id) + status_suffix, 24, DANGER if foe else MINT)
	var bar = ProgressBar.new()
	bar.max_value = unit.max
	bar.value = unit.hp
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	var fill = StyleBoxFlat.new()
	fill.bg_color = (DANGER if foe else MINT)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	var suffix = "   携行印 %d　次手 t%d" % [unit.stock, unit.ready] if mode == "clock" and not foe and unit.hp > 0 else ""
	line(box, "HP %d / %d%s" % [unit.hp, unit.max, suffix], 17, SUBTLE)
	if foe and unit.hp > 0 and game.s.intents.has(id):
		var intent: Dictionary = game.s.intents[id]
		var payload = ""
		match intent.move:
			"heavy", "strike": payload = " → %s　%dダメージ" % [title(intent.target), intent.power]
			"mend": payload = " +%d HP（1回限り）" % intent.power
		line(box, "%s%s%s%s" % ["t%d  " % intent.due if mode == "clock" else "", move_name(intent.move), payload, "  /  妨害済み" if intent.shifted else ""], 19, GOLD)

func render() -> void:
	generation += 1
	for node in host.get_children():
		host.remove_child(node)
		node.queue_free()
	var active = game.live(game.ALLIES).filter(func(id): return not queue.any(func(a): return a.actor == id))
	if game.s.outcome.is_empty():
		if mode == "clock": selected_actor = game.actor()
		elif not selected_actor in active: selected_actor = active[0] if not active.is_empty() else ""
	else: selected_actor = ""
	line(host, "EMBER   /   " + ("三手を組むラウンド" if mode == "plan" else "予告までのタイムライン"), 36, GOLD)
	var flow = "ラウンド %d　共有補給 %d / 24　先に味方、次に詠唱士→盾兵" % [game.s.round, game.s.shared]
	if mode == "clock": flow = "現在 t%d　同刻は敵優先　技の硬直で次手が変化" % game.s.tick
	line(host, "戦闘 %d / 2　%s　　%s" % [game.s.encounter + 1, game.data.rewards[game.s.reward].name, flow], 20, SUBTLE)
	if mode == "clock" and game.s.outcome.is_empty(): timeline()
	var board = HBoxContainer.new()
	board.add_theme_constant_override("separation", 18)
	host.add_child(board)
	var party = panel(board)
	var enemies = panel(board)
	line(party, "味方", 17, MINT)
	line(enemies, "敵の予告（軽減前）", 17, DANGER)
	for id in game.ALLIES: card(party, id, false)
	for id in ["oracle", "shield"]: card(enemies, id, true)
	if not game.s.outcome.is_empty():
		show_result()
		return
	var tray = panel(host, Color("695b45"))
	if mode == "plan":
		var labels: Array = queue.map(func(a): return "%s %s → %s" % [title(a.actor), move_name(a.move), title(a.target)])
		var order = HBoxContainer.new()
		tray.add_child(order)
		var sequence = line(order, "計画　" + ("味方を選び、実行順に行動を置く" if labels.is_empty() else "  →  ".join(labels)), 19, GOLD)
		sequence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not queue.is_empty():
			var undo = button(order, "最後の手を戻す", func():
				selected_actor = queue.pop_back().actor
				selected_move = ""
				render())
			undo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var actors = HBoxContainer.new()
		tray.add_child(actors)
		for id in active:
			button(actors, title(id), func(): pick_actor(id), Color("4b494b") if selected_actor == id else Color("26354b"))
	else:
		line(tray, title(selected_actor) + " の手番", 22, MINT)
	if not selected_actor.is_empty():
		var budget = game.s.units[selected_actor].stock if mode == "clock" else game.s.shared
		if mode == "plan":
			for a in queue: budget -= game.cost(a.move)
		var commands = HBoxContainer.new()
		tray.add_child(commands)
		for move in game.commands(selected_actor):
			var caption = "%s　%d%s" % [move_name(move), game.cost(move), "印" if mode == "clock" else "補給"]
			if mode == "clock": caption += " / +%d刻" % game.data.moves[move].delay
			var node = button(commands, caption, func(): pick_move(move), Color("4b494b") if move == selected_move else Color("26354b"))
			node.disabled = game.cost(move) > budget or game.targets(selected_actor, move).is_empty()
			node.tooltip_text = game.data.moves[move].description
		if not selected_move.is_empty():
			line(tray, game.data.moves[selected_move].description, 17, SUBTLE)
			var targets = HBoxContainer.new()
			tray.add_child(targets)
			for target in game.targets(selected_actor, selected_move):
				button(targets, title(target), func(): pick_target(target), Color("4b494b") if target == highlight_target else Color("26354b"))
	preview_label = line(tray, preview(), 19, MINT)
	var commit = HBoxContainer.new()
	tray.add_child(commit)
	if mode == "plan" and active.is_empty(): button(commit, "ラウンドを確定", execute, Color("465e6a"))
	if mode == "clock" and not pending.is_empty(): button(commit, "行動を実行", execute, Color("465e6a"))
	if not last_events.is_empty(): line(host, "直近　" + event_text(last_events, 6), 17, SUBTLE)

func pick_actor(id: String) -> void:
	selected_actor = id
	selected_move = ""
	render()

func pick_move(id: String) -> void:
	selected_move = id
	highlight_target = ""
	pending.clear()
	render()

func pick_target(id: String) -> void:
	var a = {"actor": selected_actor, "move": selected_move, "target": id}
	if mode == "plan":
		queue.append(a)
		selected_move = ""
	else: pending = a
	highlight_target = id
	render()

func preview() -> String:
	var branch = game.copy()
	var complete = queue.size() == game.live(game.ALLIES).size()
	if mode == "plan":
		if queue.is_empty() or not branch.submit(queue, complete): return ""
	elif pending.is_empty() or not branch.submit(pending): return ""
	var changed = branch.s.events.slice(game.s.events.size())
	var scope = "配置済みの手" if mode == "plan" and not complete else ("次の入力まで" if mode == "clock" else "ラウンド終了まで")
	var end = "次 t%d" % branch.s.tick if mode == "clock" else "補給 %d→%d" % [game.s.shared, branch.s.shared]
	if not branch.s.outcome.is_empty(): end = "決着"
	return "%sの予測　%s　｜　%s" % [scope, end, event_text(changed, 9)]

func event_text(events: Array, limit: int) -> String:
	var parts: Array[String] = []
	for e in events:
		match e.event:
			"damage": parts.append("%s −%d HP%s" % [title(e.target), e.amount, "（反撃）" if e.detail == "reply" else ""])
			"heal": parts.append("%s +%d HP" % [title(e.target), e.amount])
			"interrupt": parts.append("%s 大技%s" % [title(e.target), "を+2刻" if e.amount > 0 else "を阻止"])
			"redirect": parts.append("%sの予告を%sへ" % [title(e.target), title(e.actor)])
			"cover": parts.append("%sが庇う" % title(e.actor))
			"dampen": parts.append("%sの予告 −%d" % [title(e.target), e.amount])
			"cancel": parts.append("%sの%s失効" % [title(e.actor), move_name(e.detail)])
			"fizzle": parts.append("%sの%s空振り" % [title(e.actor), move_name(e.detail)])
			"enemy": parts.append("%sが%s" % [title(e.actor), move_name(e.detail)])
			"supply": parts.append("補給 +%d" % e.amount)
	if parts.size() > limit: return "　/　".join(parts.slice(0, limit)) + "　ほか%d件" % (parts.size() - limit)
	return "　/　".join(parts) if not parts.is_empty() else "HP変化なし"

func execute() -> void:
	var before: int = game.s.events.size()
	var accepted: bool = game.submit(queue) if mode == "plan" else game.submit(pending)
	if not accepted: return
	last_events = game.s.events.slice(before)
	queue.clear()
	pending.clear()
	selected_move = ""
	highlight_target = ""
	render()

func show_result() -> void:
	var result = panel(host)
	line(result, "戦闘勝利" if game.s.outcome == "clear" else "全滅", 28, GOLD)
	var rewards = game.s.outcome == "clear" and game.s.encounter == 0
	if rewards: line(result, "HPと資源を引き継ぎ、強化された2体へ。衛士の携行技を1枠交換できます。", 18, SUBTLE)
	var actions = HBoxContainer.new()
	result.add_child(actions)
	if rewards:
		for id in ["base", "lure", "medic"]:
			var reward: Dictionary = game.data.rewards[id]
			var choice: String = reward.name if id == "base" else "%s → %s" % [move_name(reward.replace), move_name(reward.move)]
			button(actions, choice, func(): start(id, 1, game.carry()))
	button(actions, "最初から", func(): start())
