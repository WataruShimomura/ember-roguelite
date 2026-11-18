extends SceneTree

const Policy = preload("res://design_lab_v2/policy.gd")
var view
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition: print("PASS UI: " + description)
	else:
		failures += 1
		printerr("FAIL UI: " + description)

func find_button(caption: String, prefix: bool = false) -> Button:
	var buttons = view.find_children("*", "Button", true, false)
	# The target row follows the party selector if their names are equal.
	buttons.reverse()
	for node in buttons:
		if (node.text.begins_with(caption) if prefix else node.text == caption) and not node.disabled:
			return node
	return null

func press(caption: String, prefix: bool = false) -> bool:
	var node = find_button(caption, prefix)
	if node == null:
		check(false, "enabled button " + caption)
		return false
	node.pressed.emit()
	return true

func draft(a: Dictionary) -> bool:
	if view.mode == "plan" and view.selected_actor != a.actor and not press(view.title(a.actor)): return false
	return press(view.move_name(a.move) + "　", true) and press(view.title(a.target))

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://tests/artifacts/lab_v2_%s_%s.png" % [view.mode, name]) == OK, "captured " + name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	for mode in ["plan", "clock"]:
		view = load("res://design_lab_v2/%s.tscn" % mode).instantiate()
		root.add_child(view)
		await process_frame
		check(view.game.s.intents.oracle.target == "mage" and view.game.s.intents.oracle.power == 26, mode + " visible scenario matches fixture")
		var starting: Dictionary = view.game.s.duplicate(true)
		var commit_label = "ラウンドを確定" if mode == "plan" else "行動を実行"
		if mode == "plan":
			draft({"actor": "mage", "move": "mark", "target": "oracle"})
			check(view.queue.size() == 1 and view.game.s == starting, "draft is pure")
			press("最後の手を戻す")
			check(view.queue.is_empty() and view.game.s == starting, "undo is pure")
			draft({"actor": "mage", "move": "mark", "target": "oracle"})
			draft({"actor": "blade", "move": "follow", "target": "oracle"})
			draft({"actor": "warden", "move": "cover", "target": "mage"})
			check("衛士が庇う" in view.preview_label.text and "−17 HP" in view.preview_label.text, "full plan previews combo and cover")
		else:
			draft({"actor": "blade", "move": "break", "target": "oracle"})
			check("+2刻" in view.preview_label.text and view.game.s == starting, "timeline preview shows delay without writing state")
		await capture("preview")
		var old_button = find_button(commit_label)
		if old_button == null:
			check(false, "commit button")
		else:
			var predicted = view.game.copy()
			check(old_button.get_global_rect().end.y <= view.size.y - 16, "commit is visible without scrolling")
			predicted.submit(view.queue if mode == "plan" else view.pending)
			old_button.pressed.emit()
			var actual: Dictionary = view.game.s.duplicate(true)
			old_button.pressed.emit()
			check(actual == predicted.s and view.game.s == actual, "preview matches committed action and stale button is rejected")
		await capture("executed")
		var picked: bool = false
		for _step in range(80):
			if view.game.s.outcome != "":
				if view.game.s.encounter == 1 or view.game.s.outcome != "clear": break
				var carried: Dictionary = view.game.carry()
				press("槍撃 → 返し槍")
				picked = true
				check(view.game.carry() == carried and "lure" in view.game.commands("warden"), "reward replaces skill and preserves resources")
				await capture("reward")
			var a = Policy.proposals(view.game, "adaptive", false)[0].input
			if mode == "plan":
				for action in a:
					if not draft(action): break
			else: draft(a)
			if not press(commit_label): break
			await process_frame
		check(picked and view.game.s.encounter == 1 and view.game.s.outcome != "", mode + " reaches second battle result")
		view.queue_free()
		await process_frame
	print("UI RESULT: %d checks / %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
