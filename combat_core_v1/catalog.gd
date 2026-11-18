extends RefCounted

const PARTY = ["blade", "mage", "warden"]
const MODES = ["U0", "U1", "U2", "U3"]
static var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat_core_v1/content.json"))

static func initial_party(level: int = 1) -> Dictionary:
	var party: Dictionary = {}
	var growth: Dictionary = data.growth.levels[level - 1]
	for id in PARTY:
		var unit: Dictionary = data.allies[id]
		party[id] = {"hp": int(unit.hp + growth.hp), "max": int(unit.hp + growth.hp), "power": int(unit.power + growth.power), "tp": int(data.rules.start_tp)}
	return party

static func names(id: String) -> String:
	if id in PARTY: return data.allies[id].name
	return data.enemies.get(id, {}).get("name", id)
