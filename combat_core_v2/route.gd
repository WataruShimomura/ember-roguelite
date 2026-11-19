extends RefCounted

const Catalog = preload("res://combat_core_v2/catalog.gd")
const Battle = preload("res://combat_core_v2/battle.gd")
var seed_value: int
var mode: String
var threshold_enabled: bool
var node: int = 0
var level: int = 1
var phase: String = "ready"
var party: Dictionary
var moves: Dictionary
var known: Dictionary
var owned: Array
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
	moves = Catalog.data.initial_loadout.duplicate(true)
	known = Catalog.data.initial_known.duplicate(true)
	owned = Catalog.data.initial_owned.duplicate()
	kits = int(Catalog.data.rules.start_kits)

func records() -> Dictionary:
	return {"party":party.duplicate(true),"loadout":moves.duplicate(true),"known":known.duplicate(true),"owned":owned.duplicate(),"gears":gears.duplicate(),"level":level,"kits":kits}

func start() -> bool:
	if phase != "ready": return false
	battle = Battle.new()
	start_state = records()
	battle.start(node, seed_value + node * 997, party, moves, gears, kits, threshold_enabled)
	start_state.enemies = {}
	for id in battle.s.enemies: start_state.enemies[id] = battle.s.units[id].duplicate(true)
	phase = "battle"
	return true

func configurable() -> bool:
	return phase == "ready" and (node == 0 or mode in ["U2","U3"])

func exchange(actor: String, slot: int, skill: String) -> bool:
	if not configurable() or not actor in Catalog.PARTY or slot < 0 or slot >= 4: return false
	if not skill in known[actor] or skill in moves[actor]: return false
	moves[actor][slot] = skill
	return true

func equip(actor: String, gear: String) -> bool:
	if not configurable() or not actor in Catalog.PARTY: return false
	if gear != "standard" and (not gear in owned or Catalog.data.gear[gear].owner != actor): return false
	if gear == "standard": gears.erase(actor)
	else: gears[actor] = gear
	return true

func collect() -> bool:
	if phase != "battle" or battle.s.outcome.is_empty(): return false
	for id in Catalog.PARTY:
		party[id].hp = battle.s.units[id].hp
		party[id].tp = battle.s.units[id].tp
	kits = battle.s.kits
	history.append({"node":node,"seed":battle.s.seed,"start":start_state,"end":records(),"round":battle.s.round,"outcome":battle.s.outcome,"events":battle.events})
	phase = "result"
	return true

func proceed() -> bool:
	if phase != "result": return false
	phase = "level" if battle.s.outcome == "clear" and node + 1 < Catalog.data.encounters.size() else "finished"
	return true

func level_up() -> bool:
	if phase != "level": return false
	var before: Dictionary = records()
	if mode in ["U1","U3"]:
		var old: Dictionary = Catalog.data.growth.levels[level - 1]
		var upgrade: Dictionary = Catalog.data.growth.levels[level]
		level += 1
		for id in Catalog.PARTY:
			var hp_gain: int = upgrade.hp - old.hp
			party[id].max += hp_gain
			if party[id].hp > 0: party[id].hp += hp_gain
			party[id].power += int(upgrade.power - old.power)
	history[-1].growth = {"before":before,"after":records()}
	phase = "reward"
	return true

func offers() -> Array:
	return Catalog.data.offers[node] if mode in ["U2","U3"] else []

func reward_reason(id: String) -> String:
	if not id in offers(): return "今回の提示外"
	var reward: Dictionary = Catalog.data.rewards[id]
	match reward.type:
		"kit": return "所持上限" if kits >= int(Catalog.data.rules.max_kits) else ""
		"gear": return "所持済み" if reward.item in owned else ""
		_: return "習得済み" if reward.item in known[reward.owner] else ""

func take(id: String) -> bool:
	if phase != "reward" or (id != "" and not reward_reason(id).is_empty()): return false
	if id != "":
		var reward: Dictionary = Catalog.data.rewards[id]
		match reward.type:
			"kit": kits += 1
			"gear": owned.append(reward.item)
			"skill": known[reward.owner].append(reward.item)
	history[-1].reward = {"id":id,"after":records()}
	node += 1
	phase = "ready"
	return true

func care(target: String) -> bool:
	if phase != "ready" or kits <= 0 or not target in Catalog.PARTY: return false
	var unit: Dictionary = party[target]
	if unit.hp == 0 or unit.hp == unit.max: return false
	var gain: int = mini(unit.max - unit.hp,int(Catalog.data.rules.kit_hp))
	unit.hp += gain
	kits -= 1
	if not history.is_empty():
		if not history[-1].has("camp_items"): history[-1].camp_items = []
		history[-1].camp_items.append({"target":target,"hp":gain})
	return true
