extends SceneTree

var failures: int = 0
var checks: int = 0
var game
var captured: Dictionary = {}
var equipped_third: bool = false
var checked_growth_marker: bool = false
var checked_ward: bool = false

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
		root.get_texture().get_image().save_png("res://tests/artifacts/v03_" + id + ".png")

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
	if game.lab_mode == "gear":
		game.catalog.data.reward_groups[0] = ["gear_ring"]
	await capture("01_preparation")
	game.current_view.launch.pressed.emit()
	await process_frame
	check(game.screen == "battle" and game.current_view.command_buttons.size() == 4, "three personal commands plus items")
	check(not game.manager.battle.commands("knight").has("guard"), "common guard absent in UI flow")
	check(game.current_view.pool_labels.size() == 3 and game.current_view.tp_gauges.size() == 3, "personal TP gauges and pools visible")
	check(game.current_view.unit_panels.knight.global_position.x < game.current_view.unit_panels.warlock.global_position.x, "party and enemies occupy opposing sides")
	var before_redraw = game.manager.battle.snapshot()
	game.render(); await process_frame
	check(before_redraw == game.manager.battle.snapshot(), "redraw does not restore TP or pool")
	check(game.current_view.confirm.get_global_rect().end.y <= game.size.y - 12, "execute button visible without scrolling")
	check(game.current_view.find_child("RecentEvents", true, false).get_global_rect().end.y <= game.size.y, "recent feedback visible without scrolling")
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
	check(not game.last_feedback.is_empty(), "immediate feedback has actual events")
	await capture("feedback")
	var safety: int = 0
	while game.screen != "finished" and safety < 400:
		safety += 1
		match game.screen:
			"battle":
				if game.lab_mode == "gear" and not checked_ward and "ward" in game.current_view.commands:
					checked_ward = true
					key(KEY_5); await process_frame
					check(game.current_view.selected_skill == "ward", "gear shortcut selects ward")
					var target = game.manager.battle.state.intents.values()[0].targets[0]
					game.current_view.selected_target = target
					game.current_view.select_action("ward")
					check(game.current_view.calculation.effects[0].kind == "guard" and game.current_view.calculation.targets == [target], "ward preview shows chosen ally")
					await capture("lab_ward")
					game.current_view.confirm.pressed.emit()
					check(game.manager.battle.state.events.any(func(event): return event.type == "guard" and event.skill == "ward" and event.target == target), "ward executes via command button")
					await process_frame
					continue
				if game.manager.snapshot().level == 4: await capture("boss_hud")
				if game.manager.snapshot().level >= 2 and game.manager.battle.state.actor() == "mage" and not checked_growth_marker:
					checked_growth_marker = true
					check("★" in game.current_view.command_buttons[1].text, "changed skill marked on command")
					game.current_view.select_action("fireball")
					await capture("growth_skill")
				if game.last_feedback.any(func(e): return str(e.get("source", "")).begins_with("growth:")): await capture("growth_feedback")
				auto_command()
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
			"growth":
				var level = game.manager.snapshot().level
				await capture("growth_lv%d" % level)
				var prior = game.manager.snapshot().revision
				var node = game.current_view.choices[1] if level == 2 else game.current_view.choices[0]
				node.pressed.emit(); node.pressed.emit()
				check(game.manager.snapshot().revision == prior + 1, "level choice/slot growth applies once")
				if level == 3: check(game.manager.snapshot().equipment_slots == 3, "third slot unlocks on growth screen")
			"event":
				await capture("07_event")
				check(game.current_view.choices.size() >= 2, "finite event has alternatives")
				game.current_view.choices[0].pressed.emit()
			"intermission":
				if game.manager.snapshot().equipment_slots == 3:
					await capture("third_slot")
					var options = game.current_view.find_children("*", "OptionButton", true, false)
					check(options.size() == 9, "camp renders three owned slots per party member")
					if not equipped_third and options[2].item_count > 1:
						options[2].item_selected.emit(1)
						equipped_third = true
						check(game.manager.snapshot().loadout.knight[2] != "", "owned reward equipped through third-slot UI")
				await capture("08_equipment")
				game.current_view.proceed.pressed.emit()
		await process_frame
	check(game.screen == "finished", "UI reaches adventure result")
	if game.lab_mode == "gear": check(checked_ward, "acquired gear grants a battle command")
	check(game.manager.snapshot().outcome == "clear" and game.manager.snapshot().battles.size() == 4, "four-fight UI clear")
	await capture("09_run_result")
	if OS.get_cmdline_user_args().has("--save-log"):
		check(game.save_run(), "adventure log saved")
		var saved = JSON.parse_string(FileAccess.get_file_as_string("user://last_run.json"))
		var expected = JSON.parse_string(JSON.stringify(game.manager.result()))
		check(saved == expected and saved.instruction_commit == "33122df11cb0e04332968c47a8515cef415542c8", "full history/resources/equipment/seed and instruction SHA exported")
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
