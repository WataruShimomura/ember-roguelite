extends SceneTree

var failures: int = 0
var checks: int = 0
var game
var captured: Dictionary = {}

func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: print("PASS UI: " + message)
	else:
		failures += 1
		printerr("FAIL UI: " + message)

func _initialize() -> void:
	call_deferred("run")

func capture(id: String) -> void:
	if captured.has(id): return
	captured[id] = true
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/artifacts/v02_" + id + ".png")

func key(code: int) -> void:
	var event = InputEventKey.new()
	event.keycode = code; event.pressed = true
	Input.parse_input_event(event)

func auto_command() -> void:
	var view = game.current_view
	var b = game.manager.battle.snapshot()
	var actor = b.actor
	var target = ""
	var enemies = b.order.filter(func(id): return b.units[id].team == "enemy" and b.units[id].hp > 0)
	if enemies.is_empty(): return
	target = enemies[0]
	var allies = b.order.filter(func(id): return b.units[id].team == "ally" and b.units[id].hp > 0)
	allies.sort_custom(func(a, z): return b.units[a].hp < b.units[z].hp)
	var weakest = allies[0]
	view.select_action("attack")
	if actor == "cleric" and b.units[weakest].hp < b.units[weakest].stats.MAX_HP - 22 and b.units[actor].tp >= game.manager.battle.calculator.cost(b.units[actor], "heal").amount:
		view.select_action("heal"); target = weakest
	elif actor == "mage" and b.units[actor].tp >= game.manager.battle.calculator.cost(b.units[actor], "fireball").amount:
		view.select_action("fireball")
	elif actor == "knight" and b.units[actor].tp >= game.manager.battle.calculator.cost(b.units[actor], "strike").amount:
		view.select_action("strike")
	view.selected_target = target
	view.select_action(view.selected_skill, view.selected_item)
	view.confirm.pressed.emit()

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(game.screen == "preparation", "preparation without assets")
	await capture("01_preparation")
	game.current_view.launch.pressed.emit()
	await process_frame
	check(game.screen == "battle" and game.current_view.command_buttons.size() == 4, "three personal commands plus items")
	check(not game.manager.battle.commands("knight").has("guard"), "common guard absent in UI flow")
	await capture("02_battle")
	key(KEY_2); await process_frame
	check(game.current_view.selected_skill == "strike", "keyboard selects skill")
	key(KEY_RIGHT); await process_frame
	check(game.current_view.selected_target == "sentinel", "keyboard selects target")
	key(KEY_D); await process_frame
	check(game.detail.visible, "keyboard opens breakdown")
	await capture("03_breakdown")
	game.detail.hide()
	var stale = game.current_view.confirm
	stale.pressed.emit()
	var revision = game.manager.battle.snapshot().revision
	stale.pressed.emit()
	check(game.manager.battle.snapshot().revision == revision, "stale button cannot double execute")
	await process_frame
	key(KEY_4); await process_frame
	check(game.current_view.items_box.visible, "item picker opens from keyboard")
	game.current_view.item_buttons[1].pressed.emit()
	check(game.current_view.selected_item == "ether", "finite item selectable with mouse signal")
	await capture("04_items")
	game.current_view.confirm.pressed.emit()
	await process_frame
	check(game.manager.battle.snapshot().inventory.ether == 0, "item consumed exactly once")
	var safety: int = 0
	while game.screen != "finished" and safety < 400:
		safety += 1
		match game.screen:
			"battle": auto_command()
			"battle_result":
				await capture("05_battle_result")
				game.current_view.proceed.pressed.emit()
			"reward":
				await capture("06_reward")
				check(game.current_view.choices.size() == 3, "three rewards shown")
				var node = game.current_view.choices[0] if game.manager.snapshot().node == 0 else game.current_view.choices[2]
				var prior = game.manager.snapshot().revision
				node.pressed.emit(); node.pressed.emit()
				check(game.manager.snapshot().revision == prior + 1, "reward duplicate input rejected")
			"event":
				await capture("07_event")
				check(game.current_view.choices.size() >= 2, "finite event has alternatives")
				game.current_view.choices[0].pressed.emit()
			"intermission":
				await capture("08_equipment")
				game.current_view.proceed.pressed.emit()
		await process_frame
	check(game.screen == "finished", "UI reaches adventure result")
	check(game.manager.snapshot().outcome == "clear" and game.manager.snapshot().battles.size() == 4, "four-fight UI clear")
	await capture("09_run_result")
	if OS.get_cmdline_user_args().has("--save-log"):
		check(game.save_run(), "adventure log saved")
		var saved = JSON.parse_string(FileAccess.get_file_as_string("user://last_run.json"))
		var expected = JSON.parse_string(JSON.stringify(game.manager.result()))
		check(saved == expected and saved.instruction_commit == "c2921672a4679ecc9e5c9e439c98278b56960db8", "full history/resources/equipment/seed and instruction SHA exported")
		game.detail.hide()
	game.current_view.proceed.pressed.emit()
	await process_frame
	check(game.screen == "battle" and game.manager.snapshot().battles.is_empty(), "retry starts new adventure")
	game.prepare()
	await process_frame
	check(game.screen == "preparation", "can return to preparation")
	print("UI RESULT: %d checks / %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
