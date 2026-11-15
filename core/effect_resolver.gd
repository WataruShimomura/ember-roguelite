extends RefCounted

var catalog
const MAX_EFFECTS = 128

func _init(content) -> void:
	catalog = content

func equipment_event(state, source: Dictionary, fallback_owner: String) -> void:
	if str(source.source).begins_with("equipment:"):
		state.record("equipment", {"actor": source.get("owner", fallback_owner), "source": source.source, "trigger": source.get("trigger", "effect"), "value": source.value})

func apply(state, calculation: Dictionary) -> void:
	# A finite flat effect list: effects never recursively issue actions.
	assert(calculation.effects.size() <= MAX_EFFECTS)
	for effect in calculation.effects:
		var target = state.units[effect.target]
		if target.hp <= 0:
			continue
		for source in effect.sources:
			equipment_event(state, source, calculation.actor)
		var event = {"actor": calculation.actor, "target": effect.target, "skill": calculation.skill, "source": effect.source, "sources": effect.sources}
		match effect.kind:
			"damage", "heal":
				var amount = int(effect.amount)
				target.hp = clampi(int(target.hp) + (amount if effect.kind == "heal" else -amount), 0, int(target.stats.MAX_HP))
				event.amount = amount
				event.raw = effect.raw
				state.record(effect.kind, event)
				if target.hp == 0:
					state.record("defeat", {"target": effect.target})
			"guard":
				target.guard = true
				event.multiplier = effect.multiplier
				state.record("guard", event)
			"modifier":
				# Refresh a modifier from the same skill; different skills compose.
				target.modifiers = target.modifiers.filter(func(m): return m.source != effect.source)
				target.modifiers.append({"source": effect.source, "stat": effect.stat, "value": effect.value, "instance": state.events.size()})
				event.stat = effect.stat
				event.value = effect.value
				state.record("modifier", event)
			"status":
				var roll = state.rng.randf()
				event.status = effect.status
				event.chance = effect.chance
				event.roll = roll
				event.success = roll < effect.chance
				if event.success:
					var definition = catalog.data.statuses[effect.status]
					target.statuses[effect.status] = {"remaining": int(definition.duration), "actor": calculation.actor, "source": effect.source}
					event.duration = definition.duration
					event.timing = definition.timing
				state.record("status", event)
			"charge":
				target.charged = true
				state.record("charge", event)

func round_end(state) -> void:
	for id in state.order:
		var unit = state.units[id]
		if unit.hp <= 0:
			continue
		for status_id in unit.statuses.keys():
			var definition = catalog.data.statuses[status_id]
			if definition.timing != "round_end":
				continue
			var status = unit.statuses[status_id]
			var amount = mini(int(definition.damage), int(unit.hp))
			unit.hp -= amount
			state.record("damage", {"actor": status.actor, "target": id, "skill": status_id, "source": "status:" + status_id, "sources": [{"source": "status:" + status_id, "operation": "+", "value": definition.damage}], "amount": amount, "raw": definition.damage})
			status.remaining -= 1
			state.record("status_tick", {"target": id, "status": status_id, "remaining": status.remaining, "amount": amount, "timing": definition.timing})
			if unit.hp == 0:
				state.record("defeat", {"target": id})
			if status.remaining <= 0:
				unit.statuses.erase(status_id)
				state.record("status_expired", {"target": id, "status": status_id})
