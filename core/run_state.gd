extends RefCounted

var seed_value: int
var revision: int = 0
var phase: String = "ready"
var node: int = 0
var route: Array = []
var party: Dictionary = {}
var loadout: Dictionary = {}
var inventory: Dictionary = {}
var gear: Dictionary = {}
var offers: Array = []
var battles: Array = []
var history: Array = []
var outcome: String = ""

func record(kind: String, payload: Dictionary = {}) -> void:
	var event = payload.duplicate(true)
	event.kind = kind
	event.node = node
	event.sequence = history.size()
	history.append(event)

func snapshot() -> Dictionary:
	return {"seed": seed_value, "revision": revision, "phase": phase, "node": node, "route": route.duplicate(), "party": party.duplicate(true), "loadout": loadout.duplicate(true), "inventory": inventory.duplicate(true), "gear": gear.duplicate(true), "offers": offers.duplicate(), "battles": battles.duplicate(true), "history": history.duplicate(true), "outcome": outcome}
