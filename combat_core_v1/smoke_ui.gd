extends SceneTree

const Policy = preload("res://combat_core_v1/policy.gd")
var view
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: print("PASS UI: " + message)
	else:
		failures += 1
		printerr("FAIL UI: " + message)

func button(caption: String, prefix: bool = false) -> Button:
	for node in view.find_children("*","Button",true,false):
		if not node.disabled and (node.text.begins_with(caption) if prefix else node.text == caption): return node
	return null

func press(caption: String, prefix: bool = false) -> bool:
	var node = button(caption,prefix)
	if node == null:
		check(false,"missing button " + caption)
		return false
	node.pressed.emit()
	return true

func select_item(caption: String, prefix: bool = false) -> bool:
	for node in view.find_children("*","OptionButton",true,false):
		for i in range(node.item_count):
			var label: String = node.get_item_text(i)
			if label.begins_with(caption) if prefix else label == caption:
				node.select(i)
				node.item_selected.emit(i)
				return true
	check(false,"missing list entry " + caption)
	return false

func capture(id: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://tests/artifacts/combat_core_%s.png" % id) == OK,"capture " + id)

func prepare_move(a: Dictionary) -> bool:
	if not press(view.skill_name(a.skill) + " ",true): return false
	var target: String = view.name_of(a.target)
	return press(target)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	view = load("res://combat_core_v1/main.tscn").instantiate()
	root.add_child(view)
	await process_frame
	check(view.find_children("*","OptionButton",true,false).size() >= 14,"six candidates and four slots in preparation")
	select_item("返し刃")
	check("riposte" in view.route.moves.blade,"slot selector exchanges a skill")
	select_item("無成長")
	check(view.route.mode == "U0" and view.route.level == 1,"growth comparison can be selected")
	select_item("両方")
	await capture("preparation")
	select_item("F1 ",true)
	press("検証局面を開始")
	var b = view.test_battle
	var snapshot: Dictionary = b.s.duplicate(true)
	press("この状態を保存")
	prepare_move({"skill":"taunt","target":"caster"})
	check(b.s == snapshot and not view.choice.is_empty(),"target preview leaves state untouched")
	await capture("forecast")
	var commit = button("この行動を実行")
	if commit != null:
		check(commit.get_global_rect().end.y <= view.size.y - 16,"action button is visible without scrolling")
		commit.pressed.emit()
		var revision: int = b.s.revision
		commit.pressed.emit()
		check(b.s.revision == revision and b.s.intents.caster.target == "blade","stale button rejected, announced target updated")
	else: check(false,"confirmation exists")
	press("保存状態を復元")
	check(view.test_battle.s == snapshot,"restore the same fixture and state")
	press("準備へ")
	select_item("3戦ルート")
	press("戦闘 1 / 3 を開始")
	var growth: int = 0
	for _step in range(180):
		if view.route.phase == "finished": break
		if view.route.phase == "camp":
			await capture("growth_%d" % (growth + 1))
			var before: int = view.route.party.blade.max
			press("防御反撃  /",true)
			growth += 1
			check(view.route.level == growth + 1 and view.route.party.blade.max > before,"level and max HP increased")
			check("counter" in view.route.moves.warden and view.route.gears.warden == "mail","tactical reward changes skills and equipment")
		if view.route.phase == "ready":
			if not press("戦闘 %d / 3 を開始" % (view.route.node + 1)): break
			if view.route.node == 2: await capture("boss")
		if view.route.phase == "battle":
			b = view.route.battle
			var a: Dictionary = Policy.select(b,"read")
			if not prepare_move(a) or not press("この行動を実行"): break
		await process_frame
	check(growth == 2 and view.route.phase == "finished" and view.route.history.size() == 3,"three playable encounters with two growth selections")
	check(view.route.history[-1].outcome == "clear" and view.route.level == 3,"U3 UI route clears the boss")
	await capture("result")
	press("同じシードで再戦")
	check(view.route.node == 0 and view.route.gears.is_empty() and view.route.level == 1,"retry clears growth and equipment state")
	print("UI RESULT: %d checks / %d failures" % [checks,failures])
	view.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
