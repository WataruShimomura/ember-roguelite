extends RefCounted

const RunState = preload("res://core/run_state.gd")
const BattleEngine = preload("res://core/battle_engine.gd")
const INSTRUCTION_COMMIT = "c2921672a4679ecc9e5c9e439c98278b56960db8"
var catalog
var state
var battle
var reward_rng = RandomNumberGenerator.new()
var battle_start: Dictionary = {}

func _init(content) -> void:
	catalog = content

func new_run(seed_value: int, equipment: Dictionary) -> bool:
	if not catalog.errors.is_empty(): return false
	for id in catalog.party_ids():
		if not equipment.has(id) or equipment[id].size() != 2: return false
		for item in equipment[id]:
			if item != "" and not catalog.data.equipment.has(item): return false
	state = RunState.new()
	state.seed_value = seed_value
	state.loadout = equipment.duplicate(true)
	state.inventory = catalog.data.initial_inventory.duplicate(true)
	var route_rng = RandomNumberGenerator.new()
	route_rng.seed = seed_value ^ 0x1450321
	reward_rng.seed = seed_value ^ 0x2840965
	for pool in catalog.data.route: state.route.append(pool[route_rng.randi_range(0, pool.size() - 1)])
	for id in catalog.party_ids():
		var stats = catalog.equipped_stats(id, state.loadout[id])
		state.party[id] = {"hp": int(stats.MAX_HP), "tp": mini(int(stats.MAX_TP), int(catalog.data.units[id].initial_tp)), "stats": stats}
	state.record("start", {"seed": seed_value, "route": state.route, "party": state.party, "loadout": state.loadout, "inventory": state.inventory})
	battle = null
	return true

func valid(phase: String, revision: int) -> bool:
	return state != null and state.phase == phase and state.revision == revision

func start_battle(revision: int) -> bool:
	if state == null or state.revision != revision or not state.phase in ["ready", "intermission"]: return false
	battle_start = {"party": state.party.duplicate(true), "loadout": state.loadout.duplicate(true), "inventory": state.inventory.duplicate(true)}
	battle = BattleEngine.new(catalog)
	var encounter = catalog.data.encounters[state.route[state.node]]
	var seed_value = (state.seed_value * 1103515245 + (state.node + 1) * 12345) & 0x7fffffff
	battle.start(state.loadout, seed_value, state.party, encounter.enemies, state.inventory)
	state.phase = "battle"
	state.revision += 1
	state.record("battle_start", {"seed": seed_value, "encounter": state.route[state.node], "resources": battle_start})
	return true

func collect_battle(revision: int) -> bool:
	if not valid("battle", revision) or battle.state.phase != "finished": return false
	var snapshot = battle.snapshot()
	for id in catalog.party_ids():
		state.party[id].hp = snapshot.units[id].hp
		state.party[id].tp = snapshot.units[id].tp
	state.inventory = snapshot.inventory.duplicate(true)
	var record = {"encounter": state.route[state.node], "seed": snapshot.seed, "start": battle_start.duplicate(true), "end": {"party": state.party.duplicate(true), "inventory": state.inventory.duplicate(true)}, "result": battle.result(), "events": snapshot.events}
	state.battles.append(record)
	state.record("battle_end", {"battle": state.battles.size() - 1, "party": state.party, "inventory": state.inventory})
	if snapshot.winner != "ally": state.outcome = "defeat"
	elif state.node == state.route.size() - 1: state.outcome = "clear"
	state.phase = "battle_result"
	state.revision += 1
	return true

func continue_result(revision: int) -> bool:
	if not valid("battle_result", revision): return false
	if not state.outcome.is_empty():
		state.phase = "finished"
		state.record("finish", {"outcome": state.outcome, "party": state.party})
	else:
		state.offers.clear()
		for pool in catalog.data.reward_groups: state.offers.append(pool[reward_rng.randi_range(0, pool.size() - 1)])
		state.phase = "reward"
		state.record("reward_offer", {"offers": state.offers})
	state.revision += 1
	return true

func can_add_item(id: String, quantity: int) -> bool:
	if not catalog.data.items.has(id): return false
	var occupied = state.inventory.keys().filter(func(key): return state.inventory[key] > 0).size()
	if state.inventory.get(id, 0) == 0 and occupied >= int(catalog.data.rules.inventory_slots): return false
	return state.inventory.get(id, 0) + quantity <= int(catalog.data.items[id].max_stack)

func restore(hp: int, tp: int, source: String) -> void:
	for id in state.party:
		var unit = state.party[id]
		if unit.hp <= 0: continue
		var before = {"hp": unit.hp, "tp": unit.tp}
		unit.hp = mini(int(unit.stats.MAX_HP), int(unit.hp) + hp)
		unit.tp = mini(int(unit.stats.MAX_TP), int(unit.tp) + tp)
		state.record("restore", {"actor": id, "source": source, "before": before, "after": {"hp": unit.hp, "tp": unit.tp}})

func choose_reward(index: int, revision: int) -> bool:
	if not valid("reward", revision) or index < 0 or index >= state.offers.size(): return false
	var id = state.offers[index]
	var reward = catalog.data.rewards[id]
	if reward.kind == "item" and not can_add_item(reward.item, int(reward.quantity)): return false
	match reward.kind:
		"equipment": state.gear[reward.equipment] = state.gear.get(reward.equipment, 0) + 1
		"item": state.inventory[reward.item] = state.inventory.get(reward.item, 0) + int(reward.quantity)
		"restore": restore(int(reward.hp), int(reward.tp), "reward:" + id)
	state.record("reward", {"reward": id, "definition": reward, "party": state.party, "gear": state.gear, "inventory": state.inventory})
	state.offers.clear()
	state.node += 1
	state.phase = "event" if state.node == 2 else "intermission"
	state.revision += 1
	return true

func choose_event(index: int, revision: int) -> bool:
	if not valid("event", revision) or index < 0 or index >= catalog.data.event.choices.size(): return false
	var choice = catalog.data.event.choices[index]
	if choice.kind == "restore": restore(int(choice.hp), int(choice.tp), "event:" + choice.id)
	elif choice.kind == "equipment":
		for unit in state.party.values():
			if unit.hp > 0: unit.hp = maxi(1, int(unit.hp) - int(choice.hp_cost))
		state.gear[choice.equipment] = state.gear.get(choice.equipment, 0) + 1
	state.record("event", {"choice": choice.id, "party": state.party, "gear": state.gear})
	state.phase = "intermission"
	state.revision += 1
	return true

func equip(actor: String, slot: int, id: String, revision: int) -> bool:
	if state == null or state.revision != revision or not state.phase in ["ready", "intermission"]: return false
	if not state.party.has(actor) or slot < 0 or slot > 1: return false
	if id != "" and (not catalog.data.equipment.has(id) or state.gear.get(id, 0) <= 0): return false
	var previous = state.loadout[actor][slot]
	if previous == id: return false
	if previous != "": state.gear[previous] = state.gear.get(previous, 0) + 1
	if id != "": state.gear[id] -= 1
	state.loadout[actor][slot] = id
	var unit = state.party[actor]
	unit.stats = catalog.equipped_stats(actor, state.loadout[actor])
	unit.hp = mini(int(unit.hp), int(unit.stats.MAX_HP))
	unit.tp = mini(int(unit.tp), int(unit.stats.MAX_TP))
	state.record("equipment", {"actor": actor, "slot": slot, "before": previous, "after": id, "party": state.party, "loadout": state.loadout})
	state.revision += 1
	return true

func snapshot() -> Dictionary:
	return state.snapshot() if state != null else {}

func result() -> Dictionary:
	var result = state.snapshot()
	result.instruction_commit = INSTRUCTION_COMMIT
	result.total = {"damage_dealt": 0, "damage_taken": 0, "healing": 0, "equipment_triggers": 0, "rounds": 0}
	for entry in state.battles:
		for key in result.total: result.total[key] += entry.result[key]
	return result
