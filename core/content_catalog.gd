extends RefCounted

var data: Dictionary

func _init(path: String = "res://data/content.json") -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string(path))

func equipped_stats(id: String, equipment: Array) -> Dictionary:
	var stats = data.units[id].stats.duplicate(true)
	for item in equipment:
		if not data.equipment.has(item):
			continue
		for effect in data.equipment[item].effects:
			if effect.kind == "stat":
				stats[effect.stat] = stats.get(effect.stat, 0) + effect.value
	return stats

func equipment_effects(unit: Dictionary, kind: String) -> Array:
	var found: Array = []
	for slot in range(unit.equipment.size()):
		var id = unit.equipment[slot]
		if not data.equipment.has(id):
			continue
		for effect in data.equipment[id].effects:
			if effect.kind == kind:
				var entry = effect.duplicate(true)
				entry.source = "equipment:%s:%d" % [id, slot]
				found.append(entry)
	return found
