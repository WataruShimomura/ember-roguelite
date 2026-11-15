extends RefCounted

var catalog

func _init(content) -> void:
	catalog = content

func build(state) -> Dictionary:
	var intents: Dictionary = {}
	var allies = state.alive("ally")
	for id in state.alive("enemy"):
		var unit = state.units[id]
		var policy = catalog.data.policies[catalog.data.units[id].policy]
		var skill = str(policy.normal)
		if policy.has("charged") and unit.charged:
			skill = policy.charged
		elif policy.has("charge_every") and state.round % int(policy.charge_every) == int(policy.charge_offset):
			skill = policy.charge
		elif policy.has("alternate_every") and state.round % int(policy.alternate_every) == 0:
			skill = policy.alternate
		var mode = catalog.data.skills[skill].target
		var chosen: Array = []
		match mode:
			"self": chosen = [id]
			"all_enemies": chosen = allies.duplicate()
			_: chosen = [allies[(state.round - 1) % allies.size()]] if not allies.is_empty() else []
		intents[id] = {"actor": id, "skill": skill, "targets": chosen, "done": false}
	return intents
