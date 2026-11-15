extends RefCounted

static func aggregate(state) -> Dictionary:
	var result = {"winner": state.winner, "rounds": state.round, "seed": state.battle_seed, "damage_dealt": 0, "damage_taken": 0, "healing": 0, "equipment_triggers": 0, "units": {}, "actions": []}
	for id in state.order:
		result.units[id] = {"damage": 0, "taken": 0, "healing": 0, "equipment": 0, "actions": 0}
	for event in state.events:
		match event.type:
			"action":
				result.actions.append(event)
				result.units[event.actor].actions += 1
			"damage":
				result.units[event.actor].damage += event.amount
				result.units[event.target].taken += event.amount
				if state.units[event.actor].team == "ally":
					result.damage_dealt += event.amount
				if state.units[event.target].team == "ally":
					result.damage_taken += event.amount
			"heal":
				result.units[event.actor].healing += event.amount
				result.healing += event.amount
			"equipment":
				result.units[event.actor].equipment += 1
				result.equipment_triggers += 1
	return result
