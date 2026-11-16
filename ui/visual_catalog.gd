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
	if calculation.is_empty(): return "予告は無効になりました"
	var lines: Array[String] = []
	for effect in calculation.effects:
		var target = unit(effect.target)
		match effect.kind:
			"damage": lines.append("%s −%d HP%s" % [target, effect.amount, " / 反撃" if effect.counter else ""])
			"heal", "revive": lines.append("%s +%d HP%s" % [target, effect.amount, " / 吸収" if effect.get("credit", 0) > 0 else ""])
			"tp": lines.append("%s +%d TP / %s" % [target, effect.amount, "吸収" if effect.get("credit", 0) > 0 else "回復"])
			"guard": lines.append("%s 構え ×%.2f / 次の自身の手番まで" % [target, effect.multiplier])
			"modifier": lines.append("%s %s %+d / 次の行動まで" % [target, data.stats.get(effect.stat, effect.stat), effect.value])
			"status": lines.append("%s 火傷 %d%%（生存時）" % [target, roundi(effect.chance * 100)])
			"charge": lines.append("次ラウンドに全体大技。撃破・牽制・吸収/反撃で備える")
	return "\n".join(lines)

func breakdown(calculation: Dictionary) -> String:
	var lines: Array[String] = ["%s / %s" % [unit(calculation.actor), skill(calculation.skill)], "本人TP消費 %d（有料スキルは最低1）" % calculation.cost]
	for source in calculation.cost_sources: lines.append("  %s %+d" % [source.source, source.value])
	for effect in calculation.effects:
		lines.append("\n[%s] %s / %s" % [unit(effect.target), effect.kind, effect.source])
		for source in effect.sources: lines.append("  %s  %s %s" % [source.source, source.operation, str(source.value)])
		if effect.has("raw"): lines.append("  floor → %d / 実反映 %d" % [effect.raw, effect.amount])
		if effect.has("credit"): lines.append("  共通の新規削減HPクレジット: %d" % effect.credit)
		if effect.kind == "damage": lines.append("  最低到達HP → %d / 反撃の再連鎖なし" % effect.low_after)
		if effect.has("chance"): lines.append("  成功率 %d%% / 抽選は実行時のみ" % roundi(effect.chance * 100))
		if effect.kind == "status":
			var status = content.statuses[effect.status]
			lines.append("  ラウンド終了時 %dダメージ ×%d回" % [status.damage, status.duration])
		if effect.kind == "modifier": lines.append("  %s %+d / 次の行動まで" % [effect.stat, effect.value])
	lines.append("\n吸収: 実ダメージで敵の最低到達HPを更新した差分 × 各装備の比率を個別にfloor。\n再び削った回復HPは対象外。HP/TPの不足量で上限適用。")
	return "\n".join(lines)

func event_text(event: Dictionary) -> String:
	var prefix = "R%02d  " % event.round
	match event.type:
		"action": return prefix + "%s / %s → %s" % [unit(event.actor), skill(event.skill), ", ".join(event.targets.map(func(id): return unit(id)))]
		"damage": return prefix + "%s −%d HP ← %s / 新規削減%d" % [unit(event.target), event.amount, event.source, event.credit]
		"heal": return prefix + "%s +%d HP / %s / クレジット%d" % [unit(event.target), event.amount, event.source, event.get("credit", 0)]
		"tp": return prefix + "%s TP %d → %d / %s / クレジット%d" % [unit(event.target), event.before, event.after, event.source, event.credit]
		"status": return prefix + "%s 火傷%d%% → %s / 抽選%.4f" % [unit(event.target), roundi(event.chance * 100), "成功" if event.success else "失敗", event.roll]
		"equipment": return prefix + "%s / %s = %s" % [unit(event.actor), event.source, str(event.value)]
		"item": return prefix + "%s / %s 残%d" % [unit(event.actor), data.items[event.item], event.remaining]
		"charge": return prefix + "%s が全体大技を準備" % unit(event.actor)
		"guard": return prefix + "%s 構え ×%.2f" % [unit(event.target), event.multiplier]
		"cancel": return prefix + "%s 予告中止（対象戦闘不能）" % unit(event.actor)
		"defeat": return prefix + unit(event.target) + " 戦闘不能"
		_: return prefix + str(event)

func reward_name(reward: Dictionary) -> String:
	match reward.kind:
		"equipment": return equipment(reward.equipment)
		"item": return data.items[reward.item] + " ×%d" % reward.quantity
		_: return "小休息"

func reward_description(reward: Dictionary) -> String:
	match reward.kind:
		"equipment": return data.equipment[reward.equipment].description + "。次の準備画面で装備可能。"
		"item": return "有限の回復資源。戦闘中に1手番を使って使用。"
		_: return "生存者全員 HP+%d / TP+%d。上限まで。蘇生なし。" % [reward.hp, reward.tp]

func run_event_text(event: Dictionary) -> String:
	var prefix = "戦闘%d / " % (event.node + 1)
	match event.kind:
		"reward": return prefix + "報酬: " + reward_name(event.definition)
		"event": return prefix + "祭壇: " + event.choice
		"equipment": return prefix + "%s / %s → %s" % [unit(event.actor), equipment(event.before), equipment(event.after)]
		"restore": return prefix + "%s HP %d→%d / TP %d→%d [%s]" % [unit(event.actor), event.before.hp, event.after.hp, event.before.tp, event.after.tp, event.source]
		_: return prefix + event.kind
