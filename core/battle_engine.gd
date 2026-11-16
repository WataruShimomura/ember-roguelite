extends RefCounted

const State = preload("res://core/battle_state.gd")
const Calculator = preload("res://core/action_calculator.gd")
const Resolver = preload("res://core/effect_resolver.gd")
const Policy = preload("res://core/enemy_intent_policy.gd")
const Results = preload("res://core/result_aggregator.gd")

var catalog
var state
var calculator
var resolver
var policy

func _init(content) -> void:
	catalog = content
	calculator = Calculator.new(content)
	resolver = Resolver.new(content)
	policy = Policy.new(content)

func start(loadout: Dictionary, seed_value: int = 20261115, party: Dictionary = {}, enemies: Array = ["warlock", "sentinel"], inventory: Dictionary = {}) -> void:
	assert(catalog.errors.is_empty(), "Invalid content definitions")
	state = State.new(catalog, loadout, seed_value, party, enemies, inventory)
	state.record("start", {"seed": seed_value, "order": state.order.duplicate()})
	for id in state.order:
		for effect in catalog.equipment_effects(state.units[id], "stat"):
			resolver.equipment_event(state, effect, id)
	if not check_winner():
		begin_round()
		advance()

func begin_round() -> void:
	state.cursor = 0
	for unit in state.units.values():
		unit.acted = false
	state.intents = policy.build(state)
	state.record("round", {"intents": state.intents.duplicate(true)})

func commands(actor_id: String) -> Array:
	return ["attack"] + catalog.data.units[actor_id].skills

func legal_targets(actor_id: String, skill_id: String) -> Array:
	var mode = catalog.data.skills[skill_id].target
	if mode == "self" or mode.begins_with("all_"):
		return calculator.targets(state, actor_id, skill_id)
	if mode == "fallen_ally":
		return state.order.filter(func(id): return state.units[id].team == state.units[actor_id].team and state.units[id].hp == 0)
	var team = state.units[actor_id].team
	if mode == "enemy":
		team = "enemy" if team == "ally" else "ally"
	return state.alive(team)

func preview(actor_id: String, skill_id: String, target_id: String = "") -> Dictionary:
	if not state.units.has(actor_id) or not catalog.data.skills.has(skill_id):
		return {}
	return calculator.calculate(state, actor_id, skill_id, calculator.targets(state, actor_id, skill_id, target_id))

func intent_preview(id: String) -> Dictionary:
	if not state.intents.has(id):
		return {"active": false, "intent": {}, "calculation": {}}
	var intent = state.intents[id]
	var targets = intent.targets.filter(func(target): return state.units[target].hp > 0)
	var active = state.units[id].hp > 0 and not intent.done and not targets.is_empty()
	var result = calculator.calculate(state, id, intent.skill, targets) if active else {}
	return {"active": active, "intent": intent.duplicate(true), "calculation": result}

func submit(actor_id: String, skill_id: String, target_id: String, expected_revision: int, item_id: String = "") -> bool:
	if state.phase != "input" or state.revision != expected_revision or state.actor() != actor_id:
		return false
	if state.units[actor_id].team != "ally" or state.units[actor_id].hp <= 0:
		return false
	if item_id.is_empty():
		if not commands(actor_id).has(skill_id): return false
	elif not catalog.data.items.has(item_id) or catalog.data.items[item_id].skill != skill_id or state.inventory.get(item_id, 0) <= 0:
		return false
	var calculation = preview(actor_id, skill_id, target_id)
	if calculation.targets.is_empty() or calculation.cost > state.units[actor_id].tp:
		return false
	state.phase = "resolving"
	if not item_id.is_empty():
		state.inventory[item_id] -= 1
		state.record("item", {"actor": actor_id, "item": item_id, "remaining": state.inventory[item_id]})
	execute(calculation)
	state.cursor += 1
	state.revision += 1
	advance()
	return true

func execute(calculation: Dictionary) -> void:
	var actor = state.units[calculation.actor]
	var expiring = actor.modifiers.duplicate(true)
	state.record("action", {"actor": calculation.actor, "skill": calculation.skill, "targets": calculation.targets.duplicate(), "calculation": calculation.duplicate(true)})
	if calculation.cost > 0:
		resolver.change_tp(state, calculation.actor, -calculation.cost, "skill:" + calculation.skill)
		for source in calculation.cost_sources: resolver.equipment_event(state, source, calculation.actor)
	resolver.apply(state, calculation)
	for modifier in expiring:
		# Only consume modifiers present before this action, including an existing self buff.
		var index = actor.modifiers.find(modifier)
		if index >= 0:
			actor.modifiers.remove_at(index)
			state.record("modifier_expired", {"actor": calculation.actor, "source": modifier.source})
	if catalog.data.skills[calculation.skill].get("consumes_charge", false):
		actor.charged = false
	actor.acted = true
	check_winner()

func check_winner() -> bool:
	if state.alive("ally").is_empty():
		state.winner = "enemy"
	elif state.alive("enemy").is_empty():
		state.winner = "ally"
	if not state.winner.is_empty():
		state.phase = "finished"
		state.record("finish", {"winner": state.winner})
		return true
	return false

func advance() -> void:
	while state.winner.is_empty():
		if state.cursor >= state.order.size():
			resolver.round_end(state)
			if check_winner():
				return
			state.round += 1
			begin_round()
		var id = state.actor()
		var unit = state.units[id]
		if unit.hp <= 0:
			state.record("skip", {"actor": id})
			state.cursor += 1
			continue
		if unit.guard:
			unit.guard = false
			state.record("guard_expired", {"actor": id})
		if unit.team == "ally":
			state.phase = "input"
			return
		state.phase = "resolving"
		var intent = state.intents[id]
		var targets = intent.targets.filter(func(target): return state.units[target].hp > 0)
		intent.done = true
		if targets.is_empty():
			unit.acted = true
			unit.modifiers.clear()
			state.record("cancel", {"actor": id, "skill": intent.skill, "targets": intent.targets.duplicate(), "reason": "target_defeated"})
		else:
			execute(calculator.calculate(state, id, intent.skill, targets))
		state.cursor += 1

func snapshot() -> Dictionary:
	return state.snapshot()

func result() -> Dictionary:
	return Results.aggregate(state)
