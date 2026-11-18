extends Control

const Catalog = preload("res://combat_core_v1/catalog.gd")
const Route = preload("res://combat_core_v1/route.gd")
const Fixtures = preload("res://combat_core_v1/fixtures.gd")
const GOLD = Color("efc382")
const BLUE = Color("93c7ef")
const GREEN = Color("86d2b6")
const RED = Color("f3aa96")
const MUTED = Color("aebbd0")
const INTENTS = {"charge":"詠唱","heavy":"大技","strike":"攻撃","heal":"回復","guard":"構え","sweep":"灰の波"}
const MODES = {"U0":"無成長","U1":"数値のみ","U2":"戦術のみ","U3":"両方"}
const BUILDS = {"standard":"標準","assault":"攻撃連携","counter":"防御反撃","sustain":"状態異常・継戦"}
var stage: VBoxContainer
var route
var test_battle
var scenario: String = ""
var build: String = "standard"
var variant: int = 0
var start_tp: int = 18
var seed_value: int = 42
var thresholds: bool = true
var current_skill: String = ""
var choice: Dictionary = {}
var last_events: Array = []
var checkpoint
var generation: int = 0

func _ready() -> void:
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI","Meiryo","Noto Sans CJK JP"])
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 19
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	stage = VBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.add_theme_constant_override("separation", 9)
	scroll.add_child(stage)
	reset("U3")

func reset(mode: String) -> void:
	route = Route.new(seed_value, mode, thresholds)
	test_battle = null
	checkpoint = null
	current_skill = ""
	choice.clear()
	last_events.clear()
	render()

func name_of(id: String) -> String:
	return "全体" if id == "all" else Catalog.names(id)

func skill_name(id: String) -> String:
	return "傷薬" if id == "kit" else Catalog.data.skills[id].name

func line(parent: Node, caption: String, size: int = 19, color: Color = Color("eef1fa")) -> Label:
	var l = Label.new()
	l.text = caption
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

func style(bg: Color, border: Color = Color("34465c")) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.content_margin_left = 11
	box.content_margin_right = 11
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box

func panel(parent: Node, border: Color = Color("34465c")) -> VBoxContainer:
	var frame = PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", style(Color("142032"), border))
	parent.add_child(frame)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	frame.add_child(column)
	return column

func btn(parent: Node, caption: String, callback: Callable, selected: bool = false) -> Button:
	var node = Button.new()
	node.text = caption
	node.custom_minimum_size.y = 39
	node.add_theme_stylebox_override("normal", style(Color("3d3735") if selected else Color("202e43"), GOLD if selected else Color("34465c")))
	node.add_theme_stylebox_override("hover", style(Color("314058"), GOLD))
	node.add_theme_stylebox_override("disabled", style(Color("131d2c")))
	var at: int = generation
	node.pressed.connect(func():
		if at == generation: callback.call())
	parent.add_child(node)
	return node

func select_from(parent: Node, entries: Dictionary, selected: String, callback: Callable) -> void:
	var node = OptionButton.new()
	parent.add_child(node)
	var index: int = 0
	for id in entries:
		node.add_item(entries[id])
		if id == selected: node.select(index)
		index += 1
	var ids: Array = entries.keys()
	node.item_selected.connect(func(i):
		callback.call(ids[i]))

func row(parent: Node) -> HBoxContainer:
	var h = HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	parent.add_child(h)
	return h

func render() -> void:
	generation += 1
	for child in stage.get_children():
		stage.remove_child(child)
		child.queue_free()
	line(stage, "EMBER   /   COMBAT CORE v1", 32, GOLD)
	if test_battle != null:
		if test_battle.s.outcome.is_empty(): combat(test_battle, scenario + "  " + Fixtures.LABELS[scenario])
		else:
			title_result(test_battle)
			var actions = row(stage)
			btn(actions,"同じ局面を再戦",launch)
			btn(actions,"準備へ",func(): reset(route.mode))
		return
	match route.phase:
		"ready": preparation()
		"battle": combat(route.battle, Catalog.data.encounters[route.node].name)
		"camp": camp()
		"finished":
			title_result(route.battle)
			var actions = row(stage)
			btn(actions,"同じシードで再戦",func(): reset(route.mode))

func preparation() -> void:
	line(stage, "出撃準備　Lv%d　SEED %d" % [route.level, seed_value], 24, BLUE)
	if route.node == 0:
		var settings = row(stage)
		line(settings, "成長条件")
		select_from(settings, MODES, route.mode, reset)
		btn(settings,"閾値TP " + ("あり" if thresholds else "なし"),func():
			thresholds = not thresholds
			reset(route.mode))
		line(settings, "シード")
		var seed_input = SpinBox.new()
		seed_input.min_value = 0
		seed_input.max_value = 999999
		seed_input.value = seed_value
		seed_input.value_changed.connect(func(value):
			seed_value = int(value)
			route.seed_value = seed_value)
		settings.add_child(seed_input)
		var test = row(stage)
		line(test, "検証局面")
		var labels = {"":"3戦ルート"}
		for id in Fixtures.IDS: labels[id] = id + " " + Fixtures.LABELS[id]
		select_from(test, labels, scenario, func(id):
			scenario = id
			render())
		if not scenario.is_empty():
			select_from(test, BUILDS, build, func(id): build = id)
			select_from(test, {"0":"TP 0","4":"TP 4","18":"TP 18","30":"TP 30"}, str(start_tp), func(id): start_tp = int(id))
			select_from(test, {"0":"条件A","1":"条件B"}, str(variant), func(id): variant = int(id))
			line(stage,"指定の局面を復元します。F2・F3・F5・F6の条件A/Bで比較状態を切り替えます。",17,MUTED)
			btn(stage,"検証局面を開始",launch,true)
			return
	var encounter: Dictionary = Catalog.data.encounters[route.node]
	var enemies: Array = []
	for id in encounter.enemies:
		enemies.append("%s HP%d" % [name_of(id),encounter.enemies[id].hp])
	line(stage, encounter.name + "　｜　" + "　".join(enemies),22,GOLD)
	line(stage, "候補6種類から各4枠。通常攻撃は別枠。控えの技へ交換できます。",17,MUTED)
	var columns = row(stage)
	for id in Catalog.PARTY:
		var player: Dictionary = route.party[id]
		var box = panel(columns)
		var gear: Dictionary = Catalog.data.gear[route.gears.get(id,"standard")]
		line(box, name_of(id) + "　" + gear.name,22,GREEN)
		line(box, "HP %d/%d　TP %d/30　技威力 %d" % [player.hp,player.max,player.tp,player.power],18)
		line(box, gear.hint,16,MUTED)
		for slot in range(4):
			var skill: String = route.moves[id][slot]
			if route.node == 0 or route.mode in ["U2","U3"]:
				var entries = {skill: skill_name(skill)}
				for candidate in Catalog.data.allies[id].skills:
					if not candidate in route.moves[id]: entries[candidate] = skill_name(candidate)
				select_from(box,entries,skill,func(picked):
					if route.exchange(id,slot,picked): render())
			else: line(box, skill_name(skill))
			line(box, Catalog.data.skills[skill].hint,15,MUTED)
	btn(stage,"戦闘 %d / 3 を開始" % (route.node + 1),launch,true)

func launch() -> void:
	current_skill = ""
	choice.clear()
	last_events.clear()
	checkpoint = null
	if not scenario.is_empty():
		test_battle = Fixtures.make(scenario,seed_value,start_tp,build,thresholds,variant)
	else: route.start()
	render()

func bar(column: VBoxContainer, value: int, maximum: int, tint: Color) -> void:
	var p = ProgressBar.new()
	p.max_value = maximum
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size.y = 6
	p.add_theme_stylebox_override("background",style(Color("222f44")))
	var fill = StyleBoxFlat.new()
	fill.bg_color = tint
	p.add_theme_stylebox_override("fill",fill)
	column.add_child(p)

func unit_card(parent: Node, b, id: String, enemy: bool) -> void:
	var unit: Dictionary = b.s.units[id]
	var highlight: bool = b.actor() == id or choice.get("target","") == id
	var box = panel(parent,GOLD if highlight else Color("34465c"))
	var hp_change: int = 0
	for e in last_events:
		if e.target == id and e.event in ["damage","heal"]: hp_change += e.amount * (-1 if e.event == "damage" else 1)
	var flags: Array[String] = []
	if not b.alive(id): flags.append("戦闘不能")
	if unit.get("guard",false): flags.append("構え・護衛")
	if unit.get("lock",0) > b.s.round: flags.append("再構え不可")
	if unit.get("burn",0) > 0: flags.append("火傷×%d" % unit.burn)
	if unit.get("mark",0) > b.s.round: flags.append("標的")
	if id == "boss": flags.append("防護解除" if b.exposed(id) else "儀式防護")
	if unit.get("stance",{}).size() > 0: flags.append("反撃待ち")
	if unit.get("reward",0) > 0: flags.append("迎撃強化")
	if unit.get("rally",0) > 0: flags.append("結束")
	if b.s.protection.get("target","") == id: flags.append(skill_name(b.s.protection.kind) + "の対象")
	line(box, ("%s%s　 %s" % ["▶ " if b.actor() == id else "",name_of(id)," / ".join(flags)]).strip_edges(),20,RED if enemy else GREEN)
	bar(box,unit.hp,unit.max,RED if enemy else GREEN)
	var change = "  (%+d)" % hp_change if hp_change != 0 else ""
	var extra = "   TP %d/30　%s" % [unit.tp,Catalog.data.gear[unit.gear].name] if not enemy else "　未通過閾値 %s" % " / ".join(unit.cutoffs.map(func(v): return str(v)))
	line(box,"HP %d/%d%s%s" % [unit.hp,unit.max,change,extra],16,MUTED)
	if not enemy: bar(box,unit.tp,30,BLUE)
	if enemy and b.alive(id):
		var intent: Dictionary = b.s.intents[id]
		var notice: String = "行動済み" if intent.done else describe_intent(b,id,intent)
		line(box,notice,17,GOLD)

func describe_intent(b, actor: String, intent: Dictionary) -> String:
	if intent.cancelled: return "失効　" + INTENTS[intent.kind]
	if intent.kind == "guard": return "構えを張る　味方への物理を引き受け"
	if intent.kind == "charge": return "次Rの大技 → %s　基礎%d" % [name_of(intent.target),intent.power]
	var summary: String = event_text(b.intent_preview(actor),5)
	var suffix = "  /  中断無効" if intent.kind == "heavy" and not intent.interruptible else ""
	return INTENTS[intent.kind] + "　" + (summary if not summary.is_empty() else name_of(intent.target)) + suffix

func combat(b, title: String) -> void:
	line(stage,"%s　｜　R%d　Lv%d　SEED %d" % [title,b.s.round,route.level,b.s.seed],22,GOLD)
	var sequence: Array = b.s.order.map(func(id): return ("▶ " if id == b.actor() else "") + name_of(id) if b.alive(id) else "×" + name_of(id))
	line(stage,"固定順　" + "  →  ".join(sequence),18,BLUE)
	var field = row(stage)
	var allies = panel(field)
	var enemies = panel(field)
	for id in Catalog.PARTY: unit_card(allies,b,id,false)
	for id in b.s.enemies: unit_card(enemies,b,id,true)
	var console = panel(stage,Color("6f6149"))
	var actor: String = b.actor()
	line(console,name_of(actor) + " の手番",21,GREEN)
	var commands = row(console)
	for skill in b.commands(actor):
		var cost: int = int(Catalog.data.skills[skill].cost) if skill != "kit" else 0
		var node = btn(commands, skill_name(skill) + (" ×%d" % b.s.kits if skill == "kit" else "  TP%d" % cost),func():
			current_skill = skill
			choice.clear()
			var targets: Array = b.targets(actor,skill)
			if targets.size() == 1: choice = {"actor":actor,"skill":skill,"target":targets[0]}
			render(), current_skill == skill)
		node.disabled = not b.usable(actor,skill) or b.targets(actor,skill).is_empty()
		node.tooltip_text = Catalog.data.skills.get(skill,{}).get("hint","HPを24回復。有限の初期アイテム。")
	if not current_skill.is_empty():
		var targets = row(console)
		for id in b.targets(actor,current_skill):
			btn(targets,name_of(id),func():
				choice = {"actor":actor,"skill":current_skill,"target":id}
				render(),choice.get("target","") == id)
	if not choice.is_empty():
		var details: String = event_text(b.preview(choice),11)
		line(console,"予測　" + (details if not details.is_empty() else "効果なし。支払うTPを確認。"),17,BLUE)
		var confirmation = btn(console,"この行動を実行",func(): submit(b,b.s.revision),true)
		confirmation.size_flags_horizontal = Control.SIZE_SHRINK_END
	if not last_events.is_empty():
		line(stage,"直近　" + event_text(last_events,9),16,MUTED)
	if test_battle != null:
		var tools = row(stage)
		btn(tools,"同じ局面へ戻す",launch)
		btn(tools,"この状態を保存",func():
			checkpoint = b.copy()
			render())
		if checkpoint != null:
			btn(tools,"保存状態を復元",func():
				test_battle = checkpoint.copy()
				current_skill = ""
				choice.clear()
				last_events.clear()
				render())
		btn(tools,"準備へ",func(): reset(route.mode))

func submit(b, revision: int) -> void:
	var idx: int = b.events.size()
	if not b.submit(choice,revision): return
	last_events = b.events.slice(idx)
	current_skill = ""
	choice.clear()
	if test_battle == null and not b.s.outcome.is_empty(): route.collect()
	render()

func event_text(events: Array, limit: int) -> String:
	var text: Array[String] = []
	for e in events:
		match e.event:
			"damage": text.append("%s −%d HP%s" % [name_of(e.target),e.amount,"（反撃）" if e.source == "reply" else ""])
			"heal": text.append("%s +%d HP" % [name_of(e.target),e.amount])
			"tp":
				if e.amount != 0: text.append("%s TP%+d" % [name_of(e.target),e.amount])
			"gear": text.append(Catalog.data.gear[e.source].name + " 発動")
			"redirect": text.append("護衛が引受け" if e.source == "guard" else "%sの予告を%sへ" % [name_of(e.target),name_of(e.actor)])
			"protect": text.append("%sへ%sを予約" % [name_of(e.target),skill_name(e.source)])
			"cover","split": text.append(name_of(e.actor) + ("が庇う" if e.event == "cover" else "と分散"))
			"mitigation":
				if e.amount > 0: text.append("軽減%d%s" % [e.amount,"（儀式防護）" if e.source == "ritual" else ""])
			"interrupt": text.append(name_of(e.target) + " 大技中断")
			"break": text.append(name_of(e.target) + " 構え解除")
			"expose": text.append(("反撃" if e.source == "reply" else skill_name(e.source)) + "で儀式防護解除")
			"cancel": text.append(name_of(e.actor) + " 予告失効")
			"stance": text.append("次の被弾に反撃%d" % e.amount)
			"status": text.append(name_of(e.target) + (" 火傷" if e.source in ["ignite","gear_burn"] else " 標的"))
			"rally": text.append(name_of(e.target) + " 次の攻撃に結束")
	if text.size() > limit: return "　/　".join(text.slice(0,limit)) + "　ほか%d件" % (text.size() - limit)
	return "　/　".join(text)

func title_result(b) -> void:
	line(stage,"戦闘勝利" if b.s.outcome == "clear" else "戦闘不能",29,GOLD)
	var columns = row(stage)
	for id in Catalog.PARTY: unit_card(columns,b,id,false)

func camp() -> void:
	title_result(route.battle)
	var numeric: bool = route.mode in ["U1","U3"]
	var tactical: bool = route.mode in ["U2","U3"]
	var next = Catalog.data.encounters[route.node + 1]
	line(stage,"次の敵　" + next.name,22,BLUE)
	var treatment = panel(stage)
	line(treatment,"戦間治療　｜　戦闘で使わなかった回数とTP・傷薬を消費",18,MUTED)
	for id in Catalog.PARTY:
		var status: Dictionary = route.party[id]
		if status.hp == 0 or status.hp == status.max: continue
		var options = row(treatment)
		line(options,name_of(id)).autowrap_mode = TextServer.AUTOWRAP_OFF
		for option in [["aid","warden"],["convert","mage"],["kit",id]]:
			var skill: String = option[0]
			var owner: String = option[1]
			if route.battle.usable(owner,skill):
				btn(options,skill_name(skill),func():
					if route.care(owner,skill,id): render())
	var growth = panel(stage,Color("6f6149"))
	if numeric:
		var diff: Dictionary = Catalog.data.growth.levels[route.level]
		var before: Dictionary = Catalog.data.growth.levels[route.level - 1]
		line(growth,"Lv%d → Lv%d　最大HP +%d（生存者の現在HPにも）　技威力 +%d" % [route.level,route.level+1,diff.hp-before.hp,diff.power-before.power],21,GOLD)
	else: line(growth,"能力値成長なし",19,MUTED)
	var buttons = row(growth)
	if tactical:
		for path in Catalog.data.growth.paths:
			var definition: Dictionary = Catalog.data.growth.paths[path]
			var gear: Dictionary = Catalog.data.gear[definition.gears[route.node]]
			var option = btn(buttons,definition.name + "  /  " + gear.name,func(): advance_path(path))
			option.tooltip_text = gear.hint
		line(growth,"選ぶと4枠の持込セットと装備が変わります。次の出撃準備で技を調整できます。",17,MUTED)
	else: btn(buttons,"構成を維持して次へ",func(): advance_path("standard"),true)

func advance_path(path: String) -> void:
	if route.grow(path):
		last_events.clear()
		render()
