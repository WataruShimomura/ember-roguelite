extends RefCounted

var catalog
var calculator
const MAX_EFFECTS = 128

func _init(content) -> void:
	catalog = content
	calculator = preload("res://core/action_calculator.gd").new(content)

func equipment_event(state, source: Dictionary, owner: String) -> void:
	if str(source.source).begins_with("equipment:"):
		state.record("equipment", {"actor": source.get("owner", owner), "source": source.source, "value": source.value})

func change_tp(state, target_id: String, delta: int, source: String, credit: int = 0) -> void:
	var unit = state.units[target_id]
	var before = int(unit.tp)
	unit.tp = clampi(before + delta, 0, int(unit.stats.MAX_TP))
	state.record("tp", {"actor": target_id, "target": target_id, "source": source, "before": before, "after": unit.tp, "amount": unit.tp - before, "requested": delta, "credit": credit})

func apply(state, calculation: Dictionary) -> void:
	assert(calculation.effects.size() <= MAX_EFFECTS, "Effect budget exceeded")
	for effect in calculation.effects:
		var target = state.units[effect.target]
		if target.hp <= 0 and effect.kind != "revive": continue
		var seen: Array = []
		for source in effect.sources:
			if not source.source in seen:
				equipment_event(state, source, effect.actor)
				seen.append(source.source)
		var event = effect.duplicate(true)
		event.skill = calculation.skill
		match effect.kind:
			"damage":
				event.amount = mini(int(effect.amount), int(target.hp))
				target.hp -= event.amount
				target.low_water = mini(int(target.low_water), int(target.hp))
				state.record("damage", event)
				if target.hp == 0: state.record("defeat", {"target": effect.target})
			"heal", "revive":
				event.amount = mini(int(effect.amount), int(target.stats.MAX_HP - target.hp))
				target.hp += event.amount
				state.record("heal", event)
			"tp": change_tp(state, effect.target, int(effect.amount), effect.source, int(effect.get("credit", 0)))
			"guard":
				target.guard = true
				state.record("guard", event)
			"modifier":
				target.modifiers = target.modifiers.filter(func(m): return m.source != effect.source)
				target.modifiers.append({"source": effect.source, "stat": effect.stat, "value": effect.value, "instance": state.events.size()})
				state.record("modifier", event)
			"status":
				event.roll = state.rng.randf()
				event.success = event.roll < effect.chance
				if event.success:
					var definition = catalog.data.statuses[effect.status]
					target.statuses[effect.status] = {"remaining": int(definition.duration), "actor": effect.actor, "source": effect.source}
					event.duration = definition.duration
					event.timing = definition.timing
				state.record("status", event)
			"charge":
				target.charged = true
				state.record("charge", event)

func round_end(state) -> void:
	for id in state.order:
		var unit = state.units[id]
		if unit.hp <= 0: continue
		for status_id in unit.statuses.keys():
			if unit.hp <= 0: break
			var definition = catalog.data.statuses[status_id]
			if definition.timing != "round_end": continue
			var status = unit.statuses[status_id]
			var effects: Array = []
			var source = "status:" + status_id
			calculator.append_damage(state.units.duplicate(true), effects, status.actor, id, float(definition.damage), [{"source": source, "operation": "+", "value": definition.damage}], source, false, definition.get("ignores_guard", false))
			apply(state, {"skill": status_id, "effects": effects})
			status.remaining -= 1
			state.record("status_tick", {"target": id, "status": status_id, "remaining": status.remaining, "timing": definition.timing})
			if status.remaining <= 0:
				unit.statuses.erase(status_id)
				state.record("status_expired", {"target": id, "status": status_id})
