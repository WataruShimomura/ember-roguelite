extends Control

const Catalog = preload("res://combat_core_v2/catalog.gd")
const Route = preload("res://combat_core_v2/route.gd")
const Fixtures = preload("res://combat_core_v2/fixtures.gd")
const GOLD = Color("efc382")
const BLUE = Color("93c7ef")
const GREEN = Color("86d2b6")
const RED = Color("f3aa96")
const MUTED = Color("aebbd0")
const INTENTS = {"charge":"詠唱","heavy":"大技","strike":"攻撃","heal":"回復","guard":"構え","sweep":"灰の波"}
const MODES = {"U0":"無成長","U1":"数値のみ","U2":"戦術のみ","U3":"両方"}
var stage: VBoxContainer
var route
var test_battle
var scenario: String = ""
var test_gear: String = "standard"
var change: Dictionary = {}
var reward_choice: String = ""
var detail_label: Label
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
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
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
	change.clear()
	reward_choice = ""
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
	node.custom_minimum_size.y = 32
	node.add_theme_stylebox_override("normal", style(Color("3d3735") if selected else Color("202e43"), GOLD if selected else Color("34465c")))
	node.add_theme_stylebox_override("hover", style(Color("314058"), GOLD))
	node.add_theme_stylebox_override("focus", style(Color(0,0,0,0), GOLD))
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
	line(stage, "EMBER   /   COMBAT CORE v2", 32, GOLD)
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
		"result": result_screen()
		"level": level_screen()
		"reward": reward_screen()
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
			select_from(test, {"standard":"装備なし","glove":"爆裂の手袋","seal":"破勢の印","mail":"返礼の鎧"}, test_gear, func(id): test_gear = id)
			select_from(test, {"0":"TP 0","4":"TP 4","18":"TP 18","30":"TP 30"}, str(start_tp), func(id): start_tp = int(id))
			select_from(test, {"0":"条件A","1":"条件B"}, str(variant), func(id): variant = int(id))
			line(stage,"指定の局面を復元します。F2・F3・F5・F6の条件A/Bで比較状態を切り替えます。",17,MUTED)
			btn(stage,"検証局面を開始",launch,true)
			return
	loadout_panel()

func launch() -> void:
	current_skill = ""
	choice.clear()
	last_events.clear()
	checkpoint = null
	if not scenario.is_empty():
		test_battle = Fixtures.make(scenario,seed_value,start_tp,test_gear,thresholds,variant)
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
	if unit.get("guard",false): flags.append("構え・護衛" if unit.escort else "構え")
	if unit.get("lock",0) > b.s.round: flags.append("再構え不可")
	var burn: Dictionary = unit.get("burn",{})
	if not burn.is_empty(): flags.append("火傷%d（%d×%d・%s）" % [burn.ticks,burn.power,burn.ticks,name_of(burn.actor)])
	if unit.get("mark",0) > b.s.round: flags.append("標的")
	if unit.get("brace",0) > 0: flags.append("耐衝%d" % unit.brace)
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
	if intent.kind == "guard": return "構え：物理半減" + ("・護衛" if b.s.units[actor].escort else "")
	if intent.kind == "charge": return "次Rの大技 → %s　基礎%d" % [name_of(intent.target),intent.power]
	var summary: String = event_text(b.intent_preview(actor),5)
	return INTENTS[intent.kind] + "　" + (summary if not summary.is_empty() else name_of(intent.target))

func combat(b, title: String) -> void:
	line(stage,"%s　｜　R%d　Lv%d　SEED %d" % [title,b.s.round,route.level,b.s.seed],22,GOLD)
	var sequence: Array = b.s.order.map(func(id): return ("▶ " if id == b.actor() else "") + name_of(id) if b.alive(id) else "×" + name_of(id))
	line(stage,"固定順　" + "  →  ".join(sequence),18,BLUE)
	var field = row(stage)
	var allies = panel(field)
	var enemies = panel(field)
	for id in Catalog.PARTY: unit_card(allies,b,id,false)
	for id in b.s.enemies: unit_card(enemies,b,id,true)
	command_panel(b)

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
			"gear": text.append(Catalog.data.gear[e.source].name + "：" + Catalog.data.gear[e.source].hint)
			"redirect": text.append("護衛が引受け" if e.source == "guard" else "%sの予告を%sへ" % [name_of(e.target),name_of(e.actor)])
			"protect": text.append("%sへ%sを予約" % [name_of(e.target),skill_name(e.source)])
			"cover","split": text.append(name_of(e.actor) + ("が庇う" if e.event == "cover" else "と分散"))
			"mitigation":
				if e.amount > 0: text.append("軽減%d" % e.amount)
			"interrupt": text.append(name_of(e.target) + " 大技中断")
			"break": text.append(name_of(e.target) + " 構え解除")
			"burn_apply": text.append("%s → %s 火傷%d×%d" % [name_of(e.actor),name_of(e.target),e.get("power",6),e.amount])
			"burn_extend": text.append("%sの火傷を延長 → %d回" % [name_of(e.target),e.amount])
			"burn_consume": text.append("%s 火傷%d回→0、打点+%d" % [name_of(e.target),e.ticks,e.amount])
			"burn_expire": text.append("%sの火傷が失効" % name_of(e.target))
			"brace": text.append("%sの次撃−%d" % [name_of(e.target),e.amount])
			"cancel": text.append(name_of(e.actor) + " 予告失効")
			"stance": text.append("次の被弾に反撃%d" % e.amount)
			"status": text.append(name_of(e.target) + " 標的")
			"rally": text.append(name_of(e.target) + " 次の攻撃に結束")
	if text.size() > limit: return "　/　".join(text.slice(0,limit)) + "　ほか%d件" % (text.size() - limit)
	return "　/　".join(text)

func title_result(b) -> void:
	line(stage,"戦闘勝利" if b.s.outcome == "clear" else "戦闘不能",29,GOLD)
	var columns = row(stage)
	for id in Catalog.PARTY: unit_card(columns,b,id,false)

func loadout_panel() -> void:
	var encounter: Dictionary = Catalog.data.encounters[route.node]
	line(stage,"出撃準備　/　" + encounter.name,22,GOLD)
	var enemies: Array = []
	for id in encounter.enemies: enemies.append("%s HP%d" % [name_of(id),encounter.enemies[id].hp])
	line(stage,"敵　" + "　".join(enemies) + "　｜　各人4枠、装備1枠",17,MUTED)
	var columns = row(stage)
	for id in Catalog.PARTY:
		var box = panel(columns)
		var u: Dictionary = route.party[id]
		var equipped: String = route.gears.get(id,"standard")
		line(box,"%s　HP %d/%d　TP %d" % [name_of(id),u.hp,u.max,u.tp],20,GREEN)
		line(box,"装着中　" + Catalog.data.gear[equipped].name,17,GOLD)
		var equipment = {"standard":"装備なし"}
		for g in route.owned:
			if Catalog.data.gear[g].owner == id: equipment[g] = Catalog.data.gear[g].name
		line(box,"所持　" + (" / ".join(equipment.values().slice(1)) if equipment.size() > 1 else "なし"),16)
		if route.configurable():
			select_from(box,equipment,equipped,func(picked): request_change(id,-1,equipped,picked))
		for slot in range(4):
			var skill: String = route.moves[id][slot]
			if route.configurable():
				var options = {skill:"%d  %s" % [slot+1,skill_name(skill)]}
				for candidate in route.known[id]:
					if not candidate in route.moves[id]: options[candidate] = skill_name(candidate) + "（控え）"
				select_from(box,options,skill,func(picked): request_change(id,slot,skill,picked))
			else: line(box,"%d  %s" % [slot+1,skill_name(skill)],17)
		var candidates: Array = []
		for skill in Catalog.data.allies[id].skills:
			var state = "未習得" if not skill in route.known[id] else ("持込" if skill in route.moves[id] else "控え")
			candidates.append("%s［%s］" % [skill_name(skill),state])
		line(box," / ".join(candidates),16,MUTED)
		btn(box,"6候補の効果を見る",func(): show_candidates(id))
	if not change.is_empty(): confirm_change()
	var footer = row(stage)
	line(footer,"傷薬 %d/%d　戦間：手番なし" % [route.kits,Catalog.data.rules.max_kits],17,BLUE).autowrap_mode = TextServer.AUTOWRAP_OFF
	for id in Catalog.PARTY:
		var unit: Dictionary = route.party[id]
		if route.kits > 0 and 0 < unit.hp and unit.hp < unit.max:
			var amount: int = mini(unit.max-unit.hp,int(Catalog.data.rules.kit_hp))
			btn(footer,"%s HP+%d" % [name_of(id),amount],func():
				if route.care(id): render())
	btn(footer,"戦闘 %d / 3 を開始" % (route.node+1),launch,true).disabled = not change.is_empty()

func show_candidates(id: String) -> void:
	var details = AcceptDialog.new()
	details.title = name_of(id) + "の技"
	var descriptions: Array = []
	for skill in Catalog.data.allies[id].skills:
		var state = "未習得" if not skill in route.known[id] else ("持込" if skill in route.moves[id] else "控え")
		descriptions.append("%s［%s］ TP%d\n%s" % [skill_name(skill),state,Catalog.data.skills[skill].cost,Catalog.data.skills[skill].hint])
	details.dialog_text = "\n\n".join(descriptions)
	add_child(details)
	details.confirmed.connect(details.queue_free)
	details.canceled.connect(details.queue_free)
	details.popup_centered(Vector2i(650,420))

func request_change(actor: String, slot: int, previous: String, picked: String) -> void:
	if previous == picked: return
	change = {"actor":actor,"slot":slot,"before":previous,"item":picked}
	render()

func confirm_change() -> void:
	var box = panel(stage,GOLD)
	var equipment: bool = change.slot == -1
	var defs: Dictionary = Catalog.data.gear if equipment else Catalog.data.skills
	line(box,"%s　%s → %s" % [name_of(change.actor),defs[change.before].name,defs[change.item].name],20,GOLD)
	line(box,"外す効果　" + defs[change.before].hint + "\n加える効果　" + defs[change.item].hint,17)
	if not equipment: line(box,"装着効果　" + Catalog.data.gear[route.gears.get(change.actor,"standard")].hint,16,MUTED)
	var buttons = row(box)
	btn(buttons,"変更を確定",func():
		if equipment: route.equip(change.actor,change.item)
		else: route.exchange(change.actor,change.slot,change.item)
		change.clear()
		render(),true)
	btn(buttons,"元の構成に戻す",func():
		change.clear()
		render())

func command_panel(b) -> void:
	var console = panel(stage,GOLD)
	var actor: String = b.actor()
	line(console,"%s の手番　｜　傷薬 %d　戦闘中1手" % [name_of(actor),b.s.kits],19,GREEN)
	var boxes = row(console)
	var list = panel(boxes)
	var detail = panel(boxes)
	list.custom_minimum_size.x = 473
	detail.custom_minimum_size.x = 356
	detail_label = line(detail,"Tabで移動、Enterで選択。対象と予測を確認して実行。",17,BLUE)
	for skill in b.commands(actor):
		var definition: Dictionary = Catalog.data.skills.get(skill,{})
		var reason: String = unavailable(b,actor,skill)
		var entry = row(list)
		var node = btn(entry,skill_name(skill) + (" ×%d" % b.s.kits if skill == "kit" else " TP%d" % definition.cost),func():
			if not reason.is_empty(): return
			current_skill = skill
			choice.clear()
			var options: Array = b.targets(actor,skill)
			if options.size() == 1: choice = {"actor":actor,"skill":skill,"target":options[0]}
			render(),current_skill == skill)
		node.custom_minimum_size.x = 145
		if reason != "": node.modulate = Color("a0a6b2")
		var note = definition.get("hint","生存者のHPを回復。")
		line(entry,note if reason == "" else reason,16,MUTED).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var inspect = func(): detail_label.text = skill_details(b,actor,skill)
		node.mouse_entered.connect(inspect)
		node.focus_entered.connect(inspect)
	if current_skill != "":
		detail_label.text = skill_details(b,actor,current_skill)
		var options = row(detail)
		for id in b.targets(actor,current_skill):
			btn(options,name_of(id),func():
				choice = {"actor":actor,"skill":current_skill,"target":id}
				render(),choice.get("target","") == id)
	if not choice.is_empty():
		var model = b.project(choice)
		line(detail,"予測　%s → %s\n%s" % [skill_name(choice.skill),name_of(choice.target),event_text(model.events,18)],17,BLUE)
		var reason: String = inactive_reason(choice.skill,model.events)
		if reason != "": line(detail,reason,16,MUTED)
		var pending: Array = []
		for id in model.live(model.s.enemies):
			var intent: Dictionary = model.s.intents[id]
			if not intent.done and intent.kind in ["heavy","sweep","strike"]:
				pending.append(name_of(id) + " " + describe_intent(model,id,intent))
		if not pending.is_empty(): line(detail,"攻撃予告　" + " / ".join(pending),16,GOLD)
		btn(detail,"この行動を実行",func(): submit(b,b.s.revision),true).size_flags_horizontal = Control.SIZE_SHRINK_END

func unavailable(b, actor: String, skill: String) -> String:
	if skill == "kit" and b.s.kits == 0: return "在庫なし"
	if not b.usable(actor,skill): return "TP不足"
	if b.targets(actor,skill).is_empty(): return "有効対象なし（傷薬は欠損HPが必要）"
	return ""

func skill_details(b, actor: String, skill: String) -> String:
	if skill == "kit": return "傷薬　最大%d HP。TP0、在庫1消費。満タン・戦闘不能者は対象外。\n%s" % [Catalog.data.rules.kit_hp,unavailable(b,actor,skill)]
	var d: Dictionary = Catalog.data.skills[skill]
	var gear: Dictionary = Catalog.data.gear[b.s.units[actor].gear]
	var scope: String = {"enemy":"敵1体","enemies":"敵全体","ally":"味方1人","other":"自分以外","self":"自分"}[d.target]
	var power = " 基礎威力%d%+d。" % [b.s.units[actor].power,d.get("power",0)] if skill in ["attack","slashes","break","interrupt","combo","mark","ignite","detonate","wave","relay","thrust"] else ""
	var rules = {"ignite":"周期末に6×2。残り総量の大きい方で上書き。","detonate":"回数×威力を加算、残りは0。","break":"物理半減の構えを解除。次周期まで再発動不可。","mark":"連携撃で消費。付与周期と次周期に有効。","dampen":"予告−9。1予告に1回。","cover":"次の自分の手番まで。1回だけ被害58%。","split":"単体被害を等分。奇数の残りは衛士。","counter":"軽減12、実被害を受け生存時に16反撃と火傷。","brace":"次撃−12。対象の次手で失効。"}
	return "%s　TP%d　%s%s\n%s %s\n装着 %s　%s %s" % [d.name,d.cost,scope,power,d.hint,rules.get(skill,""),gear.name,gear.hint,unavailable(b,actor,skill)]

func inactive_reason(skill: String, events: Array) -> String:
	var types = {"detonate":"burn_consume","slashes":"burn_extend","break":"break","interrupt":"interrupt","taunt":"redirect","dampen":"mitigation","combo":"combo","relay":"burn_apply"}
	if not types.has(skill) or events.any(func(e): return e.event == types[skill] and e.source != "guard"): return ""
	var hints = {"detonate":"着弾先に火傷がない","slashes":"着弾先が撃破済み、火傷なし、または残り2回","break":"着弾先に構えも構え予告もない","interrupt":"着弾先に未実行の詠唱大技がない","taunt":"移せる単体予告がない","dampen":"攻撃予告がないか、既に弱体済み","combo":"着弾先に標的がない","relay":"別敵に火傷がないか、着弾先の火傷の方が強い"}
	return "追加効果なし　" + hints[skill]

func result_screen() -> void:
	line(stage,"結果 / 第%d戦" % (route.node+1),24,BLUE)
	title_result(route.battle)
	var damage: int = 0
	var healing: int = 0
	for e in route.battle.events:
		if e.target in Catalog.PARTY:
			if e.event == "damage": damage += e.amount
			if e.event == "heal": healing += e.amount
	line(stage,"被害計 %d　回復計 %d　傷薬 %d。勝利時の自動補給なし。" % [damage,healing,route.kits],19)
	var onward = route.battle.s.outcome == "clear" and route.node < 2
	btn(stage,"レベル確認へ（次に報酬）" if onward else "冒険結果へ",func():
		if route.proceed(): render(),true)

func level_screen() -> void:
	var numeric: bool = route.mode in ["U1","U3"]
	var hp_gain: int = 0
	var power_gain: int = 0
	if numeric:
		var old: Dictionary = Catalog.data.growth.levels[route.level-1]
		var next: Dictionary = Catalog.data.growth.levels[route.level]
		hp_gain = int(next.hp-old.hp)
		power_gain = int(next.power-old.power)
	line(stage,"レベル確認　Lv%d → Lv%d" % [route.level,route.level+int(numeric)],26,GOLD)
	line(stage,"数値成長は自動。生存者の現在HPにも最大HPの増分を加算。TPは維持。" if numeric else "この比較条件は能力値の増加なし。",19)
	for id in Catalog.PARTY:
		var u: Dictionary = route.party[id]
		line(stage,"%s　最大HP %d → %d　HP %d → %d　威力 %d → %d" % [name_of(id),u.max,u.max+hp_gain,u.hp,u.hp+(hp_gain if u.hp>0 else 0),u.power,u.power+power_gain],20)
	btn(stage,"適用して報酬選択へ",func():
		if route.level_up():
			reward_choice = ""
			render(),true)

func reward_screen() -> void:
	line(stage,"報酬 / 次の報酬を1つ選ぶ",26,GOLD)
	line(stage,"選ばなかった報酬は残りません。獲得後に準備で装着・持込を変更。",18,MUTED)
	if route.offers().is_empty(): line(stage,"この比較条件は報酬なし。",18)
	for id in route.offers():
		var reward: Dictionary = Catalog.data.rewards[id]
		var box = panel(stage,GOLD if id == reward_choice else Color("34465c"))
		var reason: String = route.reward_reason(id)
		var category: String = {"gear":"装備","skill":"習得","kit":"回復品"}[reward.type]
		btn(box,category+"　"+reward.name + ("［"+reason+"］" if reason != "" else ""),func():
			reward_choice = id
			render(),id == reward_choice).disabled = reason != ""
		line(box,reward_details(reward),17)
	var actions = row(stage)
	if reward_choice != "":
		btn(actions,"獲得を確定　"+Catalog.data.rewards[reward_choice].name,func(): finish_reward(reward_choice),true)
	btn(actions,"見送って出撃準備へ",func(): finish_reward(""))

func reward_details(reward: Dictionary) -> String:
	match reward.type:
		"kit": return "所持 %d/%d → %d/%d。最大%d HP。戦闘中1手、戦間は手番なし。" % [route.kits,Catalog.data.rules.max_kits,mini(route.kits+1,int(Catalog.data.rules.max_kits)),Catalog.data.rules.max_kits,Catalog.data.rules.kit_hp]
		"gear":
			var gear: Dictionary = Catalog.data.gear[reward.item]
			return "%s専用。装着中：%s。1枠で競合。%s" % [name_of(gear.owner),Catalog.data.gear[route.gears.get(gear.owner,"standard")].name,gear.hint]
		_: return "%sが習得。持込4枠は維持。%s" % [name_of(reward.owner),Catalog.data.skills[reward.item].hint]

func finish_reward(id: String) -> void:
	if route.take(id):
		reward_choice = ""
		last_events.clear()
		render()
