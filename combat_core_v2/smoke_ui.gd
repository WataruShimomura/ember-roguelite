extends SceneTree

const Policy = preload("res://combat_core_v2/policy.gd")
var view
var count: int = 0
var failures: int = 0
var tag: String

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, title: String) -> void:
	count += 1
	if not ok:
		failures += 1
		printerr("FAIL UI: " + title)

func find_button(caption: String, prefix: bool = false) -> Button:
	for node in view.find_children("*","Button",true,false):
		if not node.disabled and (node.text.begins_with(caption) if prefix else node.text == caption): return node
	return null

func press(caption: String, prefix: bool = false) -> bool:
	var button = find_button(caption,prefix)
	if button == null:
		check(false,"button " + caption)
		return false
	button.pressed.emit()
	return true

func choose(caption: String, prefix: bool = false) -> bool:
	for node in view.find_children("*","OptionButton",true,false):
		for i in range(node.item_count):
			var item: String = node.get_item_text(i)
			if item.begins_with(caption) if prefix else item == caption:
				node.select(i)
				node.item_selected.emit(i)
				return true
	check(false,"choice " + caption)
	return false

func text_contains(value: String) -> bool:
	return view.find_children("*","Label",true,false).any(func(node): return value in node.text)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var image = root.get_texture().get_image()
	check("%dx%d" % [image.get_width(),image.get_height()] == tag,"native capture resolution")
	check(image.save_png("res://tests/artifacts/v2_%s_%s.png" % [tag,name]) == OK,"capture " + name)

func visible(button: Button) -> bool:
	return button != null and button.get_global_rect().end.y <= view.size.y and button.get_global_rect().end.x <= view.size.x

func setup_action(input: Dictionary) -> bool:
	var skill: String = view.skill_name(input.skill)
	if not press(skill + " ",true): return false
	return press(view.name_of(input.target))

func key(code: int) -> void:
	var e = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	tag = "%dx%d" % [root.size.x,root.size.y]
	view = load("res://combat_core_v2/main.tscn").instantiate()
	root.add_child(view)
	await process_frame
	check(text_contains("未習得") and text_contains("持込") and text_contains("装着中") and text_contains("所持"),"learned, equipped and owned are distinguished")
	await capture("preparation")
	choose("F1 ",true)
	press("検証局面を開始")
	var battle = view.test_battle
	var state: Dictionary = battle.s.duplicate(true)
	var taunt = find_button("挑発 ",true)
	check(taunt != null,"foreshadowed threat has a selectable response")
	if taunt != null:
		taunt.grab_focus()
		await process_frame
		check(view.detail_label.text.begins_with("挑発"),"keyboard focus opens detail")
		key(KEY_ENTER)
		await process_frame
		check(view.current_skill == "taunt","keyboard activates skill")
	press("詠唱士")
	check(battle.s == state and text_contains("予測") and text_contains("攻撃予告"),"target projection is pure and shows updated threat")
	await capture("forecast")
	var execute = find_button("この行動を実行")
	check(visible(execute),"confirm fits initial viewport")
	if execute != null:
		execute.pressed.emit()
		var revision: int = battle.s.revision
		execute.pressed.emit()
		check(battle.s.revision == revision and battle.s.intents.caster.target == "blade","one action and redirected forecast")
	press("準備へ")
	choose("F3 ",true)
	press("検証局面を開始")
	var sequence: Array = [
		{"skill":"break","target":"shield"},{"skill":"ignite","target":"caster"},
		{"skill":"counter","target":"warden"},{"skill":"slashes","target":"caster"},
	]
	for input in sequence:
		if setup_action(input): press("この行動を実行")
	check(text_contains("火傷2"),"current burn and its updated duration visible")
	var burst_button = find_button("爆ぜ火 ",true)
	if burst_button != null: burst_button.mouse_entered.emit()
	check(view.detail_label.text.begins_with("爆ぜ火"),"mouse inspection reaches same detail")
	setup_action({"skill":"detonate","target":"caster"})
	check(text_contains("火傷2回→0、打点+12"),"exact burn consumption preview")
	await capture("burn")
	press("この行動を実行")
	check(text_contains("打点+12"),"same burn consumption in execution")
	press("準備へ")
	choose("3戦ルート")
	press("戦闘 1 / 3 を開始")
	for i in range(45):
		if view.route.phase != "battle": break
		var move: Dictionary = Policy.select(view.route.battle,"read")
		if not setup_action(move) or not press("この行動を実行"): break
		await process_frame
	check(view.route.phase == "result" and text_contains("被害計"),"battle result separate")
	await capture("result")
	press("レベル確認へ（次に報酬）")
	check(text_contains("100 → 110") and view.route.level == 1,"level before/after before applying")
	await capture("level")
	press("適用して報酬選択へ")
	check(view.route.level == 2 and text_contains("次の報酬"),"level applies before distinct reward screen")
	press("装備　導火の指輪")
	check(not "fuse" in view.route.owned and view.route.gears.is_empty(),"reward selection is still pending")
	await capture("reward")
	var grant = find_button("獲得を確定　導火の指輪")
	if grant != null:
		grant.pressed.emit()
		grant.pressed.emit()
	check(view.route.owned.count("fuse") == 1 and view.route.gears.is_empty(),"one reward added without equipping")
	choose("導火の指輪")
	check(view.route.gears.is_empty() and text_contains("装備なし → 導火の指輪"),"loadout before/after awaits approval")
	await capture("exchange")
	press("変更を確定")
	check(view.route.gears.get("mage","") == "fuse","owned gear equips after separate confirmation")
	print("V2 UI %s: %d checks / %d failures" % [tag,count,failures])
	quit(0 if failures == 0 else 1)
