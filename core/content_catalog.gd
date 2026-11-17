extends RefCounted

var data: Dictionary = {}
var errors: Array[String] = []
const EFFECT_KINDS = ["damage", "heal", "tp", "revive", "guard", "modifier", "status", "charge"]
const EQUIPMENT_KINDS = ["stat", "siphon_hp", "siphon_tp", "damage_multiplier", "counter", "cost_reduction", "status_chance"]

func _init(path: String = "res://data/content.json") -> void:
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		errors.append("Invalid JSON at %s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		push_error("ContentCatalog: " + errors[0])
		return
	data = parser.data
	validate()
	for error in errors: push_error("ContentCatalog: " + error)

func validate() -> Array[String]:
	errors.clear()
	for section in ["stats", "rules", "units", "skills", "equipment", "statuses", "policies", "items", "route", "encounters", "rewards", "reward_groups", "event", "presets", "initial_inventory"]:
		if not data.has(section): errors.append("Missing section: " + section)
	if not errors.is_empty(): return errors
	for id in data.skills:
		var skill = data.skills[id]
		if not skill.get("target", "") in ["self", "enemy", "ally", "fallen_ally", "all_enemies", "all_allies"]: errors.append("Invalid target: " + id)
		if skill.get("cost", -1) < 0: errors.append("Invalid cost: " + id)
		for effect in skill.get("effects", []):
			if not effect.get("kind", "") in EFFECT_KINDS: errors.append("Unknown effect: " + id)
			if effect.get("kind") == "status" and not data.statuses.has(effect.get("status", "")): errors.append("Unknown status: " + id)
			if effect.has("pierces_guard") and (effect.kind != "damage" or not effect.pierces_guard is bool): errors.append("Invalid guard piercing: " + id)
	for id in data.equipment:
		for effect in data.equipment[id].get("effects", []):
			if not effect.get("kind", "") in EQUIPMENT_KINDS: errors.append("Unknown equipment effect: " + id)
			if effect.get("kind") == "stat" and not effect.get("stat", "") in data.stats: errors.append("Unknown stat: " + id)
			if effect.get("kind") == "damage_multiplier" and (effect.get("value", -1) < 0 or effect.get("value", 2) > 1): errors.append("Invalid multiplier: " + id)
	for id in data.units:
		var unit = data.units[id]
		for stat in data.stats:
			if not unit.get("stats", {}).has(stat): errors.append("Missing unit stat: " + id + ":" + stat)
		for skill in unit.get("skills", []):
			if not data.skills.has(skill): errors.append("Unknown skill: " + id)
			elif unit.team == "ally" and data.skills[skill].get("enemy_only", false): errors.append("Enemy-only skill assigned to ally: " + id)
		if unit.stats.get("MAX_HP", 0) <= 0 or unit.stats.get("MAX_TP", -1) < 0: errors.append("Invalid resource maximum: " + id)
		if unit.team == "enemy" and not data.policies.has(unit.get("policy", "")): errors.append("Unknown policy: " + id)
	for id in data.policies:
		for field in ["normal", "alternate", "charge", "charged"]:
			if data.policies[id].has(field) and not data.skills.has(data.policies[id][field]): errors.append("Unknown policy skill: " + id)
	for id in data.items:
		if not data.skills.has(data.items[id].get("skill", "")): errors.append("Unknown item skill: " + id)
	for id in data.encounters:
		var seen: Array = []
		for enemy in data.encounters[id].get("enemies", []):
			if not data.units.has(enemy) or enemy in seen: errors.append("Unknown/duplicate enemy: " + id)
			elif data.units[enemy].team != "enemy": errors.append("Encounter contains ally: " + id)
			seen.append(enemy)
	for pool in data.route:
		for id in pool:
			if not data.encounters.has(id): errors.append("Unknown encounter: " + id)
	for id in data.rewards:
		var reward = data.rewards[id]
		if not reward.get("kind", "") in ["equipment", "item", "restore"]: errors.append("Unknown reward kind: " + id)
		if reward.get("kind") == "equipment" and not data.equipment.has(reward.get("equipment", "")): errors.append("Unknown reward equipment: " + id)
		if reward.get("kind") == "item" and not data.items.has(reward.get("item", "")): errors.append("Unknown reward item: " + id)
	for pool in data.reward_groups:
		for id in pool:
			if not data.rewards.has(id): errors.append("Unknown reward: " + id)
		if pool.is_empty(): errors.append("Empty reward pool")
	if data.reward_groups.size() != 3: errors.append("Exactly three reward groups required")
	for pool in data.route:
		if pool.is_empty(): errors.append("Empty encounter pool")
	for id in data.statuses:
		var status = data.statuses[id]
		if status.get("timing", "") != "round_end" or status.get("duration", 0) < 1 or status.get("damage", -1) < 0: errors.append("Invalid status: " + id)
	for preset in data.presets:
		for id in party_ids():
			var slots = data.presets[preset].get(id, [])
			if slots.size() != 2: errors.append("Preset needs two slots: " + preset)
			for gear in slots:
				if gear != "" and not data.equipment.has(gear): errors.append("Unknown preset gear: " + preset)
	for id in data.initial_inventory:
		if not data.items.has(id) or data.initial_inventory[id] < 0: errors.append("Invalid initial item: " + id)
		elif data.initial_inventory[id] > data.items[id].max_stack: errors.append("Initial item stack exceeds maximum: " + id)
	for choice in data.event.get("choices", []):
		if not choice.get("kind", "") in ["restore", "equipment"]: errors.append("Invalid event effect")
		elif choice.kind == "equipment" and not data.equipment.has(choice.get("equipment", "")): errors.append("Invalid event equipment")
	if data.event.get("choices", []).size() < 2: errors.append("Event needs at least two choices")
	var recovery = data.rules.get("tp_recovery", {})
	for field in ["entry", "pool", "round"]:
		if not recovery.get(field, null) is float and not recovery.get(field, null) is int: errors.append("Invalid TP recovery field: " + field)
		elif recovery[field] < 0 or int(recovery[field]) != recovery[field]: errors.append("Recovery requires nonnegative integers: " + field)
	if not data.has("growth"):
		errors.append("Missing growth definitions")
	else:
		for level in ["2", "3", "4"]:
			if not data.growth.levels.has(level): errors.append("Missing growth level: " + level)
			else:
				var step = data.growth.levels[level]
				if not step.kind in ["choice", "slots"]: errors.append("Unknown growth step: " + level)
				if step.kind == "choice" and step.get("options", []).size() < 2: errors.append("Growth needs alternatives: " + level)
				if step.kind == "slots" and step.get("slots", 0) < 3: errors.append("Growth needs expanded slots: " + level)
				for id in data.growth.levels[level].get("options", []):
					if not data.growth.options.has(id): errors.append("Unknown growth choice: " + id)
		for id in data.growth.options:
			var growth = data.growth.options[id]
			if not growth.get("kind", "") in ["spread", "detonate", "counter_stance", "counter_tp", "burn_bonus", "entry_bonus"]: errors.append("Unknown growth kind: " + id)
			if growth.has("skill") and not data.skills.has(growth.skill): errors.append("Unknown growth skill: " + id)
			if growth.has("unit") and not growth.unit in party_ids(): errors.append("Unknown growth unit: " + id)
			if growth.has("status") and not data.statuses.has(growth.status): errors.append("Unknown growth status: " + id)
	return errors.duplicate()

func growth_effects(unit: Dictionary, kind: String) -> Array:
	var found: Array = []
	for id in unit.get("growth", []):
		var definition = data.growth.options[id]
		if definition.kind == kind and (not definition.has("unit") or definition.unit == unit.id):
			var effect = definition.duplicate(true)
			effect.source = "growth:" + id
			found.append(effect)
	return found

func party_ids() -> Array:
	return data.units.keys().filter(func(id): return data.units[id].team == "ally")

func equipped_stats(id: String, equipment: Array) -> Dictionary:
	var stats = data.units[id].stats.duplicate(true)
	for item in equipment:
		if item == "":
			continue
		assert(data.equipment.has(item), "Unknown equipment: " + str(item))
		for effect in data.equipment[item].effects:
			if effect.kind == "stat":
				stats[effect.stat] = stats.get(effect.stat, 0) + effect.value
	return stats

func equipment_effects(unit: Dictionary, kind: String) -> Array:
	var found: Array = []
	for slot in range(unit.equipment.size()):
		var id = unit.equipment[slot]
		if id == "":
			continue
		assert(data.equipment.has(id), "Unknown equipment: " + str(id))
		for effect in data.equipment[id].effects:
			if effect.kind == kind:
				var entry = effect.duplicate(true)
				entry.source = "equipment:%s:%d" % [id, slot]
				found.append(entry)
	return found
