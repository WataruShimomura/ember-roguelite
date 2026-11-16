extends Control

const Content = preload("res://core/content_catalog.gd")
const Manager = preload("res://core/run_manager.gd")
const Visuals = preload("res://ui/visual_catalog.gd")
const Preparation = preload("res://ui/preparation_view.gd")
const Battle = preload("res://ui/battle_view.gd")
const Reward = preload("res://ui/reward_view.gd")
const Camp = preload("res://ui/camp_view.gd")
const Results = preload("res://ui/results_view.gd")
const Growth = preload("res://ui/growth_view.gd")
var catalog = Content.new()
var manager = Manager.new(catalog)
var visuals = Visuals.new()
var loadout: Dictionary
var seed_value: int = 42
var preset: String = "burst"
var screen: String = "preparation"
var host: VBoxContainer
var current_view
var detail: AcceptDialog
var last_feedback: Array = []
var feedback_enabled: bool = true
var displayed_battle_seed: int = -1

func _ready() -> void:
	loadout = catalog.data.presets[preset].duplicate(true)
	var backdrop = visuals.texture(visuals.data.get("background", ""))
	if backdrop:
		var image_node = TextureRect.new()
		image_node.texture = backdrop
		image_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(image_node)
	var music_path = visuals.data.get("bgm", "")
	if not music_path.is_empty() and ResourceLoader.exists(music_path):
		var music = AudioStreamPlayer.new()
		music.stream = load(music_path)
		add_child(music)
		music.finished.connect(music.play)
		music.play()
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	host = VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(host)
	detail = AcceptDialog.new()
	detail.title = "EMBER / 計算内訳と記録"
	detail.get_ok_button().text = "戻る [Esc]"
	add_child(detail)
	render()

func start_run() -> void:
	last_feedback.clear()
	displayed_battle_seed = -1
	if not manager.new_run(seed_value, loadout):
		show_text("開始できません", "\n".join(catalog.errors))
		return
	manager.start_battle(manager.snapshot().revision)
	render()

func render() -> void:
	if manager.state != null:
		if manager.snapshot().phase == "battle" and manager.battle.snapshot().phase == "finished":
			manager.collect_battle(manager.snapshot().revision)
		screen = manager.snapshot().phase
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
	var view_type
	match screen:
		"preparation": view_type = Preparation
		"battle": view_type = Battle
		"reward", "event": view_type = Reward
		"growth": view_type = Growth
		"ready", "intermission": view_type = Camp
		_: view_type = Results
	if screen == "battle" and displayed_battle_seed != manager.battle.state.battle_seed:
		displayed_battle_seed = manager.battle.state.battle_seed
		last_feedback = manager.battle.state.events.filter(func(e): return e.type == "tp")
	current_view = view_type.new()
	host.add_child(current_view)
	current_view.configure(self)

func prepare() -> void:
	manager = Manager.new(catalog)
	screen = "preparation"
	render()

func show_text(title_value: String, text_value: String) -> void:
	for child in detail.get_children():
		if child is ScrollContainer:
			detail.remove_child(child)
			child.queue_free()
	detail.title = title_value
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 480)
	detail.add_child(scroll)
	var text_node = Label.new()
	text_node.text = text_value
	text_node.add_theme_font_size_override("font_size", 17)
	text_node.theme = current_view.theme
	scroll.add_child(text_node)
	detail.popup_centered(Vector2i(870, 580))

func show_details(calculation: Dictionary) -> void:
	if not calculation.is_empty(): show_text("計算内訳 / SOURCE TRACE", visuals.breakdown(calculation))

func save_run() -> bool:
	var file = FileAccess.open("user://last_run.json", FileAccess.WRITE)
	if not file:
		show_text("保存できません", "保存先の書き込み権限を確認してください。")
		return false
	file.store_string(JSON.stringify(manager.result(), "\t"))
	file.close()
	show_text("冒険ログを保存", ProjectSettings.globalize_path("user://last_run.json"))
	return true

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not detail.visible and current_view != null:
		if current_view.handle_key(event.keycode): get_viewport().set_input_as_handled()
