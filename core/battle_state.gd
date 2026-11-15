extends RefCounted

var units: Dictionary = {}
var order: Array = []
var intents: Dictionary = {}
var events: Array = []
var round: int = 1
var cursor: int = 0
var tp: int = 2
var phase: String = "advancing"
var winner: String = ""
var battle_seed: int
var revision: int = 0
var rng = RandomNumberGenerator.new()

func _init(catalog, loadout: Dictionary, seed_value: int) -> void:
	battle_seed = seed_value
	rng.seed = seed_value
	tp = int(catalog.data.rules.initial_tp)
	for id in catalog.data.units:
		var definition = catalog.data.units[id]
		var equipment: Array = loadout.get(id, []).duplicate()
		var stats = catalog.equipped_stats(id, equipment)
		units[id] = {"id": id, "team": definition.team, "stats": stats, "hp": int(stats.MAX_HP), "equipment": equipment, "guard": false, "modifiers": [], "statuses": {}, "charged": false, "acted": false}
		order.append(id)
	order.sort_custom(func(a, b):
		if units[a].stats.SPEED == units[b].stats.SPEED:
			return a < b
		return units[a].stats.SPEED > units[b].stats.SPEED)

func alive(team: String) -> Array:
	return order.filter(func(id): return units[id].team == team and units[id].hp > 0)

func actor() -> String:
	return str(order[cursor]) if cursor < order.size() and winner.is_empty() else ""

func record(type: String, payload: Dictionary = {}) -> void:
	var entry = payload.duplicate(true)
	entry.type = type
	entry.round = round
	entry.sequence = events.size()
	events.append(entry)

func snapshot() -> Dictionary:
	return {"units": units.duplicate(true), "order": order.duplicate(), "intents": intents.duplicate(true), "events": events.duplicate(true), "round": round, "cursor": cursor, "tp": tp, "phase": phase, "winner": winner, "seed": battle_seed, "revision": revision, "actor": actor()}
