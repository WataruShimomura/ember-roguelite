extends RefCounted

var catalog

func _init(content) -> void:
	catalog = content

func cost(unit: Dictionary, skill_id: String) -> Dictionary:
	var base = int(catalog.data.skills[skill_id].cost)
	var total = base
	var sources: Array = [{"source": "skill:" + skill_id, "value": base}]
	if base > 0:
		for effect in catalog.equipment_effects(unit, "cost_reduction"):
			total -= int(effect.value)
			sources.append({"source": effect.source, "value": -int(effect.value)})
	return {"amount": maxi(1, total) if base > 0 else 0, "sources": sources}

func targets(state, actor_id: String, skill_id: String, target_id: String = "") -> Array:
	var actor = state.units[actor_id]
	var mode = catalog.data.skills[skill_id].target
	var opposing = "enemy" if actor.team == "ally" else "ally"
	match mode:
		"self": return [actor_id] if actor.hp > 0 else []
		"all_enemies": return state.alive(opposing)
		"all_allies": return state.alive(actor.team)
		"enemy", "ally", "fallen_ally":
			var team = opposing if mode == "enemy" else actor.team
			if state.units.has(target_id):
				var target = state.units[target_id]
				if target.team == team and ((target.hp == 0) if mode == "fallen_ally" else (target.hp > 0)): return [target_id]
	return []

func power_sources(unit: Dictionary) -> Array:
	var sources: Array = [{"source": "unit:%s:POWER" % unit.id, "operation": "+", "value": catalog.data.units[unit.id].stats.POWER}]
	for effect in catalog.equipment_effects(unit, "stat"):
		if effect.stat == "POWER": sources.append({"source": effect.source, "operation": "+", "value": effect.value})
	for modifier in unit.modifiers:
		if modifier.stat == "POWER": sources.append({"source": modifier.source, "operation": "+", "value": modifier.value})
	return sources

func append_recovery(projected: Dictionary, effects: Array, actor: String, target_id: String, kind: String, raw: int, source: String, credit: int = 0) -> void:
	var target = projected[target_id]
	var field = "tp" if kind == "tp" else "hp"
	var maximum = int(target.stats.MAX_TP if field == "tp" else target.stats.MAX_HP)
	var amount = mini(maxi(0, raw), maximum - int(target[field]))
	if target.hp <= 0 and kind != "revive": return
	target[field] += amount
	effects.append({"kind": kind, "actor": actor, "target": target_id, "amount": amount, "raw": raw, "source": source, "credit": credit, "sources": [{"source": source, "operation": "+", "value": raw}]})

func append_damage(projected: Dictionary, effects: Array, actor_id: String, target_id: String, base: float, sources: Array, source: String, counter_allowed: bool = true, bypass: bool = false, counter_hit: bool = false) -> void:
	var actor = projected[actor_id]
	var target = projected[target_id]
	if target.hp <= 0: return
	var amount = maxf(0, base)
	var trace = sources.duplicate(true)
	if not bypass:
		for reduction in catalog.equipment_effects(target, "damage_multiplier"):
			amount *= reduction.value
			trace.append({"source": reduction.source, "operation": "×", "value": reduction.value, "owner": target_id})
		if target.guard:
			amount *= float(catalog.data.rules.guard_multiplier)
			trace.append({"source": "stance:guard", "operation": "×", "value": catalog.data.rules.guard_multiplier})
	var raw = int(floor(amount))
	var actual = mini(raw, int(target.hp))
	target.hp -= actual
	var credit = maxi(0, int(target.low_water) - int(target.hp)) if target.team == "enemy" else 0
	target.low_water = mini(int(target.low_water), int(target.hp))
	effects.append({"kind": "damage", "actor": actor_id, "target": target_id, "raw": raw, "amount": actual, "credit": credit, "low_after": target.low_water, "source": source, "sources": trace, "counter": counter_hit})
	# A single credit per damage is reused by all siphons; no credit from re-damage.
	if credit > 0 and actor.hp > 0 and actor.team != target.team:
		for kind in ["siphon_hp", "siphon_tp"]:
			for siphon in catalog.equipment_effects(actor, kind):
				append_recovery(projected, effects, actor_id, actor_id, "heal" if kind == "siphon_hp" else "tp", int(floor(credit * float(siphon.value))), siphon.source, credit)
	if counter_hit and actual > 0 and actor.hp > 0:
		for bonus in catalog.growth_effects(actor, "counter_tp"):
			if not bonus.source in actor.growth_used:
				consume_growth(actor, effects, bonus.source)
				append_recovery(projected, effects, actor_id, actor_id, "tp", int(bonus.value), bonus.source)
	if counter_allowed and actual > 0 and target.hp > 0 and actor.hp > 0:
		var counters = catalog.equipment_effects(target, "counter")
		if target.counter_bonus > 0: counters.append({"source": target.counter_source, "value": target.counter_bonus})
		for counter in counters:
			if actor.hp <= 0: break
			append_damage(projected, effects, target_id, actor_id, float(counter.value), [{"source": counter.source, "operation": "+", "value": counter.value}], counter.source, false, false, true)

func consume_growth(unit: Dictionary, effects: Array, source: String) -> void:
	unit.growth_used.append(source)
	effects.append({"kind": "growth_trigger", "actor": unit.id, "target": unit.id, "key": source, "source": source, "sources": []})

func skill_growth(projected: Dictionary, effects: Array, actor: Dictionary, target_id: String, skill: String, order: Array, before: bool) -> void:
	for kind in (["detonate"] if before else ["spread", "counter_stance"]):
		for growth in catalog.growth_effects(actor, kind):
			if growth.skill != skill or actor.hp <= 0: continue
			var target = projected[target_id]
			if kind == "detonate" and target.hp > 0 and target.statuses.has(growth.status):
				target.statuses.erase(growth.status)
				effects.append({"kind": "remove_status", "actor": actor.id, "target": target_id, "status": growth.status, "source": growth.source, "sources": []})
				append_damage(projected, effects, actor.id, target_id, float(growth.damage), [{"source": growth.source, "operation": "+", "value": growth.damage}], growth.source, false)
			elif kind == "spread" and target.hp > 0:
				var remaining = int(growth.targets)
				for id in order:
					if remaining <= 0: break
					if id == target_id or projected[id].team == actor.team or projected[id].hp <= 0: continue
					effects.append({"kind": "status", "actor": actor.id, "target": id, "status": growth.status, "chance": growth.chance, "source": growth.source, "sources": [{"source": growth.source, "operation": "+", "value": growth.chance}]})
					remaining -= 1
			elif kind == "counter_stance":
				actor.counter_bonus = int(growth.value)
				actor.counter_source = growth.source
				effects.append({"kind": "counter_stance", "actor": actor.id, "target": actor.id, "value": growth.value, "source": growth.source, "sources": []})

func calculate(state, actor_id: String, skill_id: String, target_ids: Array) -> Dictionary:
	var projected = state.units.duplicate(true)
	var actor = projected[actor_id]
	var skill = catalog.data.skills[skill_id]
	var payment = cost(actor, skill_id)
	var result = {"actor": actor_id, "skill": skill_id, "targets": target_ids.duplicate(), "cost": payment.amount, "cost_sources": payment.sources, "effects": []}
	actor.tp = maxi(0, int(actor.tp) - int(payment.amount))
	for target_id in target_ids:
		if actor.hp <= 0: break
		var starting_statuses = projected[target_id].statuses.duplicate(true)
		skill_growth(projected, result.effects, actor, target_id, skill_id, state.order, true)
		for definition in skill.effects:
			var recipient = actor_id if definition.get("recipient", "") == "self" else target_id
			var target = projected[recipient]
			if target.hp <= 0 and definition.kind != "revive": continue
			var source = "skill:" + skill_id
			var effect = definition.duplicate(true)
			effect.merge({"actor": actor_id, "target": recipient, "source": source, "sources": []})
			match definition.kind:
				"damage", "heal":
					var sources: Array = [] if definition.get("flat", false) else power_sources(actor)
					var amount = float(definition.get("base", 0))
					for entry in sources: amount += entry.value
					sources.append({"source": source, "operation": "+", "value": definition.get("base", 0)})
					if definition.kind == "damage":
						var bonuses: Array = []
						for bonus in catalog.growth_effects(actor, "burn_bonus"):
							if starting_statuses.has(bonus.status) and not bonus.source in actor.growth_used:
								amount += float(bonus.value)
								sources.append({"source": bonus.source, "operation": "+", "value": bonus.value})
								bonuses.append(bonus)
						var position = result.effects.size()
						append_damage(projected, result.effects, actor_id, recipient, amount, sources, source)
						if result.effects[position].amount > 0:
							for bonus in bonuses: consume_growth(actor, result.effects, bonus.source)
					else:
						append_recovery(projected, result.effects, actor_id, recipient, "heal", int(floor(maxf(0, amount))), source)
						result.effects[-1].sources = sources
				"tp", "revive": append_recovery(projected, result.effects, actor_id, recipient, definition.kind, int(definition.base), source)
				"status":
					effect.sources.append({"source": source, "operation": "+", "value": effect.chance})
					for bonus in catalog.equipment_effects(actor, "status_chance"):
						if bonus.get("status", "") == effect.status:
							effect.chance += bonus.value
							effect.sources.append({"source": bonus.source, "operation": "+", "value": bonus.value})
					effect.chance = clampf(effect.chance, 0, 1)
					result.effects.append(effect)
				"guard":
					target.guard = true
					effect.multiplier = catalog.data.rules.guard_multiplier
					result.effects.append(effect)
				"modifier", "charge": result.effects.append(effect)
		skill_growth(projected, result.effects, actor, target_id, skill_id, state.order, false)
	return result
