extends SceneTree

var failures: int = 0
var game

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS UI: " + message)
	else:
		failures += 1
		printerr("FAIL UI: " + message)

func _initialize() -> void:
	call_deferred("run")

func capture(name_value: String) -> void:
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/artifacts/" + name_value + ".png")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(game.screen == "loadout", "loadout opens without assets")
	await capture("01_loadout")
	game.start_battle()
	await process_frame
	check(game.screen == "battle" and game.command_buttons.size() == 4, "four command buttons and battle")
	check(game.target_buttons.size() == 2, "two enemy targets")
	await capture("02_battle")
	game.select_skill("strike")
	check(game.current_calculation.effects[0].raw == 26, "UI shows equipment-adjusted preview")
	game.show_details(game.current_calculation)
	await process_frame
	check(game.detail.visible, "detail dialog opens")
	await capture("03_breakdown")
	game.detail.hide()
	var stale_button = game.confirm_button
	stale_button.pressed.emit()
	var revision = game.engine.state.revision
	stale_button.pressed.emit()
	check(game.engine.state.revision == revision, "duplicate button signal rejected")
	await process_frame
	check(game.battle_snapshot.actor == "mage", "next actor displayed")
	check(game.command_buttons[1].disabled, "unaffordable skill disabled")
	game.select_skill("guard")
	check(game.target_buttons.is_empty(), "self action requires no target selection")
	var key = InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	check(game.selected_skill == "attack", "keyboard selects command")
	key = InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	check(game.selected_target == "sentinel", "keyboard selects target")
	game.select_skill("guard")
	game.commit(game.battle_snapshot.actor, game.selection_revision)
	await process_frame
	var safety: int = 0
	while game.screen == "battle" and safety < 100:
		safety += 1
		game.select_skill("attack")
		game.commit(game.battle_snapshot.actor, game.selection_revision)
		await process_frame
	check(game.screen == "result", "battle reaches result via UI")
	await capture("04_result")
	if OS.get_cmdline_user_args().has("--save-log"):
		game.save_log()
		check(FileAccess.file_exists("user://last_battle.json"), "JSON log saved")
		var saved = JSON.parse_string(FileAccess.get_file_as_string("user://last_battle.json"))
		var expected = JSON.parse_string(JSON.stringify(game.engine.result()))
		check(saved.result == expected, "saved result matches displayed result")
		game.detail.hide()
	game.start_battle()
	await process_frame
	check(game.engine.state.tp == 2 and game.engine.state.round == 1, "retry resets battle")
	game.show_loadout()
	await process_frame
	check(game.screen == "loadout", "return to loadout")
	print("UI RESULT: %d failures" % failures)
	game.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
