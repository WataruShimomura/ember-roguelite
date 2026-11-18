extends RefCounted

const Catalog = preload("res://combat_core_v1/catalog.gd")
const Battle = preload("res://combat_core_v1/battle.gd")
var seed_value: int
var mode: String
var threshold_enabled: bool
var node: int = 0
var level: int = 1
var phase: String = "ready"
var party: Dictionary
var moves: Dictionary
var gears: Dictionary = {}
var kits: int
var battle
var history: Array = []
var start_state: Dictionary

func _init(seed_number: int = 42, growth_mode: String = "U3", thresholds: bool = true) -> void:
	seed_value = seed_number
	mode = growth_mode
	threshold_enabled = thresholds
	party = Catalog.initial_party()
	moves = Catalog.data.builds.standard.duplicate(true)
	kits = int(Catalog.data.rules.start_kits)

func start() -> bool:
	if phase != "ready": return false
	battle = Battle.new()
	start_state = {"party": party.duplicate(true), "loadout": moves.duplicate(true), "gears": gears.duplicate(), "level": level, "kits": kits}
	battle.start(node, seed_value + node * 997, party, moves, gears, kits, threshold_enabled)
	start_state.enemies = {}
	for id in battle.s.enemies: start_state.enemies[id] = battle.s.units[id].duplicate(true)
	phase = "battle"
	return true

func exchange(actor: String, slot: int, skill: String) -> bool:
	if phase != "ready" or (node > 0 and not mode in ["U2", "U3"]): return false
	if not actor in Catalog.PARTY or slot < 0 or slot >= 4: return false
	if not skill in Catalog.data.allies[actor].skills or skill in moves[actor]: return false
	moves[actor][slot] = skill
	return true

func collect() -> bool:
	if phase != "battle" or battle.s.outcome.is_empty(): return false
	sync_party()
	history.append({"node": node, "seed": battle.s.seed, "start": start_state, "end": party.duplicate(true), "kits_end": kits, "round": battle.s.round, "outcome": battle.s.outcome, "combat_events": battle.events.size(), "events": battle.events})
	phase = "camp" if battle.s.outcome == "clear" and node < Catalog.data.encounters.size() - 1 else "finished"
	return true

func sync_party() -> void:
	for id in Catalog.PARTY:
		var unit: Dictionary = battle.s.units[id]
		party[id].hp = unit.hp
		party[id].tp = unit.tp
	kits = battle.s.kits

func care(actor: String, skill: String, target: String) -> bool:
	if phase != "camp" or not battle.care(actor, skill, target): return false
	sync_party()
	return true

func grow(path: String) -> bool:
	var numeric: bool = mode in ["U1", "U3"]
	var tactics: bool = mode in ["U2", "U3"]
	if phase != "camp" or (tactics and not Catalog.data.growth.paths.has(path)): return false
	var before: Dictionary = party.duplicate(true)
	var previous_moves: Dictionary = moves.duplicate(true)
	if numeric:
		level += 1
		var old: Dictionary = Catalog.data.growth.levels[level - 2]
		var upgrade: Dictionary = Catalog.data.growth.levels[level - 1]
		for id in Catalog.PARTY:
			var hp_gain: int = upgrade.hp - old.hp
			party[id].max += hp_gain
			if party[id].hp > 0: party[id].hp += hp_gain
			party[id].power += int(upgrade.power - old.power)
	var acquired: String = ""
	if tactics:
		moves = Catalog.data.builds[path].duplicate(true)
		acquired = Catalog.data.growth.paths[path].gears[node]
		var owner: String = Catalog.data.gear[acquired].owner
		gears[owner] = acquired
	history[-1].growth = {"path": path if tactics else "", "level": level, "before": before, "after": party.duplicate(true), "gear": acquired, "loadout_before": previous_moves, "loadout_after": moves.duplicate(true)}
	node += 1
	phase = "ready"
	return true
