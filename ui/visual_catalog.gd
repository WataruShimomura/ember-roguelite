extends RefCounted

var data: Dictionary
var content: Dictionary

func _init() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://data/visuals.json"))
	content = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))

func unit(id: String) -> String:
	return data.units.get(id, {}).get("name", id)

func skill(id: String) -> String:
	return data.skills.get(id, data.statuses.get(id, id))

func equipment(id: String) -> String:
	return data.equipment.get(id, {}).get("name", "装備なし")

func color(id: String) -> Color:
	return Color(data.units.get(id, {}).get("color", "#d6b885"))

func texture(path: String):
	return load(path) if not path.is_empty() and ResourceLoader.exists(path) else null

func describe(calculation: Dictionary) -> String:
	if calculation.is_empty():
		return "予告は無効になりました"
	var lines: Array[String] = []
	for effect in calculation.effects:
		var target = unit(effect.target)
		match effect.kind:
			"damage": lines.append("%s → %d ダメージ（計算値 %d）" % [target, effect.amount, effect.raw])
			"heal": lines.append("%s → %d HP回復" % [target, effect.amount])
			"guard": lines.append("%s → 被ダメージ ×%.2f / 次の自身の手番まで" % [target, effect.multiplier])
			"modifier": lines.append("%s → %s %+d / 次の行動まで" % [target, data.stats.get(effect.stat, effect.stat), effect.value])
			"status":
				var definition = content.statuses[effect.status]
				lines.append("%s → 生存時 %s %d%% / ラウンド終了に%dダメージ ×%d回" % [target, data.statuses.get(effect.status, effect.status), roundi(effect.chance * 100), definition.damage, definition.duration])
			"charge": lines.append("次ラウンドに全体大技。撃破・牽制・防御で備えよう")
	return "\n".join(lines)

func breakdown(calculation: Dictionary) -> String:
	var lines: Array[String] = ["%s / %s" % [unit(calculation.actor), skill(calculation.skill)], "TP消費 %d / 獲得予定 +%d（上限まで）" % [calculation.cost, calculation.tp_gain], ""]
	for effect in calculation.effects:
		lines.append("[%s] %s" % [unit(effect.target), effect.kind])
		for source in effect.sources:
			lines.append("  %s  %s %s" % [source.source, source.operation, str(source.value)])
		if effect.has("raw"):
			lines.append("  最後にfloor → %d / HP上限適用後 %d" % [effect.raw, effect.amount])
		if effect.has("chance"):
			lines.append("  0〜100%%に制限 → %d%%" % roundi(effect.chance * 100))
		if effect.kind == "modifier":
			lines.append("  %s: %s %+d" % [effect.source, effect.stat, effect.value])
		lines.append("")
	for source in calculation.tp_sources:
		lines.append("TP: %s %+d" % [source.source, source.value])
	return "\n".join(lines)

func event_text(event: Dictionary) -> String:
	var prefix = "R%02d  " % event.round
	match event.type:
		"action": return prefix + "%s / %s → %s" % [unit(event.actor), skill(event.skill), ", ".join(event.targets.map(func(id): return unit(id)))]
		"damage": return prefix + "%s −%d HP ← %s" % [unit(event.target), event.amount, event.source]
		"heal": return prefix + "%s +%d HP" % [unit(event.target), event.amount]
		"tp": return prefix + "共有TP %d → %d（要求 %+d）" % [event.before, event.after, event.requested]
		"status": return prefix + "%s / 火傷 %d%% → %s（抽選 %.4f）" % [unit(event.target), roundi(event.chance * 100), "成功" if event.success else "失敗", event.roll]
		"equipment": return prefix + "%s / %s / %s = %s" % [unit(event.actor), event.source, event.get("trigger", "effect"), str(event.value)]
		"charge": return prefix + "%s が次ラウンドの全体大技を準備" % unit(event.actor)
		"guard": return prefix + "%s / 防御 ×%.2f" % [unit(event.actor), event.multiplier]
		"modifier": return prefix + "%s / %s %+d [%s]" % [unit(event.target), data.stats.get(event.stat, event.stat), event.value, event.source]
		"cancel": return prefix + "%s / 対象が戦闘不能のため予告を中止" % unit(event.actor)
		"round": return prefix + "ラウンド開始・敵行動を公開"
		"defeat": return prefix + "%s 戦闘不能" % unit(event.target)
		"finish": return prefix + ("勝利" if event.winner == "ally" else "敗北")
		_: return prefix + event.type + " / " + str(event)
