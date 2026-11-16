extends VBoxContainer

var app
var catalog
var visuals
var snapshot: Dictionary
var accent = Color("e4b978")
var muted = Color("8d9aae")

func configure(application) -> void:
	app = application
	catalog = app.catalog
	visuals = app.visuals
	snapshot = app.manager.snapshot()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)
	setup_theme()
	build()

func build() -> void:
	pass

func handle_key(_key: int) -> bool:
	return false

func heading(title: String, subtitle: String) -> void:
	add_child(label("E M B E R   /   " + title, 30, accent))
	add_child(wrapped(subtitle, 15, muted))
	add_child(HSeparator.new())

func party_cards(parent: Node, party: Dictionary, loadout: Dictionary) -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)
	for id in catalog.party_ids():
		var card = panel(row, visuals.color(id).darkened(.5))
		card.add_child(label(visuals.unit(id), 23, visuals.color(id)))
		var u = party[id]
		card.add_child(label("HP %d / %d   TP %d / %d" % [u.hp, u.stats.MAX_HP, u.tp, u.stats.MAX_TP], 18))
		for item in loadout[id]:
			card.add_child(wrapped(visuals.equipment(item), 14, muted))

func inventory_text(items: Dictionary) -> String:
	var values: Array[String] = []
	for id in items: values.append("%s ×%d" % [visuals.data.items.get(id, id), items[id]])
	return " / ".join(values)

func style(bg: Color, border: Color = Color("2c384b"), width: int = 1) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(9)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

func setup_theme() -> void:
	var t = Theme.new()
	t.default_font_size = 17
	var font_path = visuals.data.get("font", "")
	if not font_path.is_empty() and ResourceLoader.exists(font_path):
		t.default_font = load(font_path)
	else:
		var system_font = SystemFont.new()
		system_font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "Noto Sans CJK JP"])
		t.default_font = system_font
	t.set_color("font_color", "Label", Color("dce3ef"))
	t.set_stylebox("panel", "PanelContainer", style(Color("111925")))
	t.set_stylebox("normal", "Button", style(Color("1a2534")))
	t.set_stylebox("hover", "Button", style(Color("2c394b"), accent))
	t.set_stylebox("pressed", "Button", style(Color("4a3b29"), accent))
	t.set_stylebox("focus", "Button", style(Color(0, 0, 0, 0), accent, 2))
	t.set_stylebox("disabled", "Button", style(Color("101722"), Color("1f2836")))
	t.set_color("font_color", "Button", Color("e4e9f0"))
	t.set_color("font_disabled_color", "Button", Color("586578"))
	t.set_stylebox("normal", "OptionButton", style(Color("1a2534")))
	t.set_stylebox("hover", "OptionButton", style(Color("2c394b"), accent))
	var bar_background = style(Color("253042"), Color("253042"), 0)
	var bar_fill = style(Color("71bfa6"), Color("71bfa6"), 0)
	for box in [bar_background, bar_fill]:
		box.content_margin_left = 0
		box.content_margin_right = 0
		box.content_margin_top = 0
		box.content_margin_bottom = 0
	t.set_stylebox("background", "ProgressBar", bar_background)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 14)
	theme = t

func label(text_value: String, size: int = 17, tint: Color = Color("dce3ef")) -> Label:
	var node = Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", tint)
	return node

func wrapped(text_value: String, size: int = 16, tint: Color = Color("a8b5c8")) -> Label:
	var node = label(text_value, size, tint)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node

func button(text_value: String, callback: Callable, prominent: bool = false) -> Button:
	var node = Button.new()
	node.text = text_value
	node.custom_minimum_size.y = 46
	if prominent:
		node.add_theme_stylebox_override("normal", style(Color("473a2b"), accent))
		node.add_theme_color_override("font_color", accent)
	node.pressed.connect(callback)
	return node

func panel(parent: Node, tint: Color = Color("2c384b")) -> VBoxContainer:
	var outer = PanelContainer.new()
	outer.add_theme_stylebox_override("panel", style(Color("111925"), tint))
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(outer)
	var box = VBoxContainer.new()
	outer.add_child(box)
	return box
