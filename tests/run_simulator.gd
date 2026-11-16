extends RefCounted

const Manager = preload("res://core/run_manager.gd")

static func choose_action(battle) -> Dictionary:
	var state = battle.snapshot()
	var actor = state.actor
	var allies = battle.state.alive("ally")
	allies.sort_custom(func(a, b): return state.units[a].hp < state.units[b].hp)
	var weakest = allies[0]
	if state.units[weakest].hp < 30 and state.inventory.get("potion", 0) > 0:
		return {"skill": "item_potion", "target": weakest, "item": "potion"}
	if "heal" in battle.commands(actor) and state.units[weakest].stats.MAX_HP - state.units[weakest].hp > 24 and battle.calculator.cost(state.units[actor], "heal").amount <= state.units[actor].tp:
		return {"skill": "heal", "target": weakest, "item": ""}
	var best = {"skill": "attack", "target": battle.state.alive("enemy")[0], "item": ""}
	var best_score: float = -1e10
	for skill in battle.commands(actor):
		if battle.calculator.cost(state.units[actor], skill).amount > state.units[actor].tp: continue
		for target in battle.legal_targets(actor, skill):
			var preview = battle.preview(actor, skill, target)
			var score = -2.0 * preview.cost
			var incoming = 0
			for intent in state.intents.values():
				if not intent.done and actor in intent.targets and intent.skill not in ["guard", "charge"]: incoming += 1
			for effect in preview.effects:
				match effect.kind:
					"damage": score += effect.amount if state.units[effect.target].team == "enemy" else -effect.amount
					"heal": score += .4 * effect.amount
					"status": score += 6 * effect.chance
					"guard": score += 5 * incoming
					"counter_stance": score += effect.value * .7 * incoming
					"modifier": score += 1
			if score > best_score:
				best_score = score
				best = {"skill": skill, "target": target, "item": ""}
	return best

static func battle_stats(record: Dictionary, party_ids: Array) -> Dictionary:
	var stats = {"encounter": record.encounter, "rounds": record.result.rounds, "carried_tp": {}, "tp_start": {}, "tp_end": {}, "hp_end": {}, "entry": 0, "natural": 0, "absorb": 0, "growth_tp": 0, "item_tp": 0, "spent": 0, "normal": 0, "skills": 0, "items": 0, "commands": {}, "tp_timeline": [], "normal_rate": 0.0}
	for id in party_ids:
		stats.tp_start[id] = record.start.party[id].tp
		stats.carried_tp[id] = record.start.party[id].tp
		stats.tp_end[id] = record.end.party[id].tp
		stats.hp_end[id] = record.end.party[id].hp
	var entering = true
	stats.growth_events = {}
	for event in record.events:
		if event.get("source", "").begins_with("growth:") and event.type in ["remove_status", "counter_stance", "growth_trigger", "status"]:
			stats.growth_events[event.source] = stats.growth_events.get(event.source, 0) + 1
		if event.type == "round": entering = false
		if event.type == "tp":
			stats.tp_timeline.append(event)
			if event.amount < 0: stats.spent -= event.amount
			elif entering:
				stats.entry += event.amount
				stats.tp_start[event.target] += event.amount
			elif event.source == "recovery:round": stats.natural += event.amount
			elif event.source.begins_with("equipment:"): stats.absorb += event.amount
			elif event.source.begins_with("growth:"): stats.growth_tp += event.amount
			elif event.source.begins_with("skill:item_"): stats.item_tp += event.amount
		if event.type == "action" and event.actor in party_ids:
			stats.commands[event.skill] = stats.commands.get(event.skill, 0) + 1
			if event.skill == "attack": stats.normal += 1
			elif event.skill.begins_with("item_"): stats.items += 1
			else: stats.skills += 1
	var actions = stats.normal + stats.skills + stats.items
	stats.normal_rate = float(stats.normal) / actions if actions > 0 else 0.0
	return stats

static func play(catalog, seed_value: int, preset: String, choices: Array) -> Dictionary:
	var run = Manager.new(catalog)
	if not run.new_run(seed_value, catalog.data.presets[preset]): return {"error": "new_run"}
	var steps: int = 0
	while run.state.phase != "finished" and steps < 1000:
		steps += 1
		match run.state.phase:
			"ready", "intermission":
				# Put a legitimately acquired reward into the new third slot if possible.
				if run.state.equipment_slots == 3:
					for id in catalog.party_ids():
						if run.state.loadout[id][2] != "": continue
						for gear in run.state.gear.keys():
							if run.state.gear[gear] > 0:
								run.equip(id, 2, gear, run.state.revision)
								break
				run.start_battle(run.state.revision)
			"battle":
				if run.battle.state.phase == "finished": run.collect_battle(run.state.revision)
				else:
					var action = choose_action(run.battle)
					if not run.battle.submit(run.battle.state.actor(), action.skill, action.target, run.battle.state.revision, action.item): return {"error": "action rejected"}
			"battle_result": run.continue_result(run.state.revision)
			"reward": run.choose_reward(0 if run.state.node == 0 else 2, run.state.revision)
			"growth":
				var index = 0
				if run.state.level != 3:
					var wanted = choices[0] if run.state.level == 2 else choices[1]
					index = run.state.growth_options.find(wanted)
				if not run.choose_growth(index, run.state.revision): return {"error": "growth rejected"}
			"event": run.choose_event(0, run.state.revision)
	var stats: Array = []
	for record in run.state.battles: stats.append(battle_stats(record, catalog.party_ids()))
	return {"run": run, "outcome": run.state.outcome, "stats": stats, "steps": steps}
