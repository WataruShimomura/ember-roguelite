extends RefCounted

var catalog

func _init(content) -> void:
	catalog = content

func targets(state, actor_id: String, skill_id: String, target_id: String = "") -> Array:
	var actor = state.units[actor_id]
	var mode = catalog.data.skills[skill_id].target
	var opposing = "enemy" if actor.team == "ally" else "ally"
	match mode:
		"self": return [actor_id] if actor.hp > 0 else []
		"all_enemies": return state.alive(opposing)
		"all_allies": return state.alive(actor.team)
		"enemy", "ally":
			var team = opposing if mode == "enemy" else actor.team
			if state.units.has(target_id) and state.units[target_id].team == team and state.units[target_id].hp > 0:
				return [target_id]
	return []

func power_sources(unit: Dictionary) -> Array:
	var sources: Array = [{"source": "unit:%s:POWER" % unit.id, "operation": "+", "value": catalog.data.units[unit.id].stats.POWER}]
	for effect in catalog.equipment_effects(unit, "stat"):
		if effect.stat == "POWER":
			sources.append({"source": effect.source, "operation": "+", "value": effect.value})
	for modifier in unit.modifiers:
		if modifier.stat == "POWER":
			sources.append({"source": modifier.source, "operation": "+", "value": modifier.value})
	return sources

func guard_info(unit: Dictionary) -> Dictionary:
	var multiplier = float(catalog.data.rules.guard_multiplier)
	var source = "command:guard"
	for effect in catalog.equipment_effects(unit, "guard_multiplier"):
		if float(effect.value) < multiplier:
			multiplier = float(effect.value)
			source = effect.source
	return {"value": multiplier, "source": source}

func calculate(state, actor_id: String, skill_id: String, target_ids: Array) -> Dictionary:
	var actor = state.units[actor_id]
	var skill = catalog.data.skills[skill_id]
	var result = {"actor": actor_id, "skill": skill_id, "targets": target_ids.duplicate(), "cost": int(skill.cost) if actor.team == "ally" else 0, "tp_gain": 0, "tp_sources": [], "effects": []}
	if skill.has("tp_gain") and actor.team == "ally":
		result.tp_gain = int(skill.tp_gain)
		result.tp_sources.append({"source": "skill:" + skill_id, "value": int(skill.tp_gain)})
		for effect in catalog.equipment_effects(actor, "tp_gain"):
			result.tp_gain += int(effect.value)
			result.tp_sources.append({"source": effect.source, "value": int(effect.value)})
	for target_id in target_ids:
		var target = state.units[target_id]
		for definition in skill.effects:
			var effect = definition.duplicate(true)
			effect.target = target_id
			effect.source = "skill:" + skill_id
			effect.sources = []
			match effect.kind:
				"damage", "heal":
					var sources = power_sources(actor)
					var amount: float = 0
					for source in sources:
						amount += float(source.value)
						source.owner = actor_id
						source.trigger = "power"
					sources.append({"source": effect.source, "operation": "+", "value": definition.get("base", 0)})
					amount = maxf(0, amount + float(definition.get("base", 0)))
					if effect.kind == "damage" and target.guard:
						var guard = guard_info(target)
						amount *= guard.value
						sources.append({"source": guard.source, "operation": "×", "value": guard.value, "owner": target_id, "trigger": "guard"})
					effect.raw = int(floor(amount))
					effect.amount = mini(effect.raw, int(target.hp)) if effect.kind == "damage" else mini(effect.raw, int(target.stats.MAX_HP - target.hp))
					effect.sources = sources
				"status":
					effect.sources.append({"source": effect.source, "operation": "+", "value": effect.chance})
					for bonus in catalog.equipment_effects(actor, "status_chance"):
						if bonus.get("status", "") == effect.status:
							effect.chance += bonus.value
							effect.sources.append({"source": bonus.source, "operation": "+", "value": bonus.value, "owner": actor_id, "trigger": "status_chance"})
					effect.chance = clampf(effect.chance, 0, 1)
				"guard":
					var guard = guard_info(actor)
					effect.multiplier = guard.value
					effect.sources.append({"source": guard.source, "operation": "×", "value": guard.value})
			result.effects.append(effect)
	return result
