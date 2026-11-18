extends RefCounted

const Catalog = preload("res://combat_core_v1/catalog.gd")
const Effects = preload("res://combat_core_v1/effects.gd")
const PARTY = Catalog.PARTY
const DATA = Catalog
var s: Dictionary
var events: Array = []

func start(encounter: int, seed_value: int, party: Dictionary, loadout: Dictionary, gears: Dictionary, kits: int, thresholds: bool, fixture: Dictionary = {}) -> void:
	s = {"encounter": encounter, "seed": seed_value, "round": 1, "cursor": 0, "revision": 0, "order": [], "units": {}, "enemies": [], "intents": {}, "outcome": "", "kits": kits, "thresholds": thresholds, "care": {}, "protection": {}, "locked": fixture.get("intents", {}).duplicate(true)}
	events.clear()
	for id in PARTY:
		var unit: Dictionary = party[id].duplicate(true)
		unit.merge({"speed": int(Catalog.data.allies[id].speed), "moves": loadout[id].duplicate(), "gear": gears.get(id, "standard"), "stance": {}, "rally": 0, "reward": 0})
		unit.hp = clampi(unit.hp, 0, unit.max)
		unit.tp = clampi(unit.tp, 0, int(Catalog.data.rules.max_tp))
		unit.merge(fixture.get("allies", {}).get(id, {}), true)
		s.units[id] = unit
		s.order.append(id)
		s.care[id] = int(Catalog.data.rules.heal_limit)
	var enemies: Dictionary = fixture.get("enemies", Catalog.data.encounters[encounter].enemies)
	for id in enemies:
		var stats: Dictionary = enemies[id].duplicate(true)
		var max_hp: int = int(stats.hp)
		var hp: int = int(stats.get("current", max_hp))
		var cutoffs: Array = []
		for percent in Catalog.data.rules.thresholds:
			var cutoff: int = floori(max_hp * float(percent) / 100)
			if hp > cutoff: cutoffs.append(cutoff)
		stats.merge({"hp": hp, "max": max_hp, "speed": int(Catalog.data.enemies[id].speed), "cutoffs": cutoffs, "mark": 0, "burn": 0, "guard": id == "shield", "lock": 0, "charged": "", "heals": int(stats.get("limit", 0)), "exposed_until": 0}, true)
		stats.merge(fixture.get("states", {}).get(id, {}), true)
		s.units[id] = stats
		s.enemies.append(id)
		s.order.append(id)
	s.order.sort_custom(func(a, b):
		var left: int = s.units[a].speed
		var right: int = s.units[b].speed
		return a < b if left == right else left > right)
	finish()
	if s.outcome.is_empty():
		forecast()
		advance()

func copy():
	var branch = get_script().new()
	branch.s = s.duplicate(true)
	return branch

func actor() -> String:
	return s.order[s.cursor] if s.outcome.is_empty() and s.cursor < s.order.size() else ""

func live(ids: Array) -> Array:
	return ids.filter(func(id): return alive(id))

func alive(id: String) -> bool:
	return s.units.has(id) and s.units[id].hp > 0

func record(event: String, actor_id: String, target: String, amount: int = 0, source: String = "") -> void:
	events.append({"event": event, "actor": actor_id, "target": target, "amount": amount, "source": source, "round": s.round})

func finish() -> bool:
	if live(PARTY).is_empty(): s.outcome = "defeat"
	elif live(s.enemies).is_empty(): s.outcome = "clear"
	return not s.outcome.is_empty()

func targets(actor_id: String, skill: String) -> Array:
	match Catalog.data.skills.get(skill, {}).get("target", "ally"):
		"self": return [actor_id]
		"enemy": return live(s.enemies)
		"enemies": return ["all"] if not live(s.enemies).is_empty() else []
		"other": return live(PARTY).filter(func(id): return id != actor_id)
		_: return live(PARTY)

func commands(actor_id: String) -> Array:
	var moves: Array = ["attack"] + s.units[actor_id].moves
	if s.kits > 0: moves.append("kit")
	return moves

func usable(actor_id: String, skill: String) -> bool:
	if not actor_id in PARTY or not alive(actor_id) or not skill in commands(actor_id): return false
	if skill == "kit": return s.kits > 0
	if skill in ["aid", "convert"] and s.care[actor_id] <= 0: return false
	return s.units[actor_id].tp >= int(Catalog.data.skills[skill].cost)

func legal(move: Dictionary) -> bool:
	return s.outcome.is_empty() and move.actor == actor() and usable(move.actor, move.skill) and move.target in targets(move.actor, move.skill)

func options() -> Array:
	var who: String = actor()
	var result: Array = []
	if who.is_empty(): return result
	for skill in commands(who):
		if usable(who, skill):
			for target in targets(who, skill): result.append({"actor": who, "skill": skill, "target": target})
	return result

func preview(move: Dictionary) -> Array:
	if not legal(move): return []
	var branch = copy()
	Effects.perform(branch, move)
	return branch.events

func submit(move: Dictionary, revision: int) -> bool:
	if revision != s.revision or not legal(move): return false
	Effects.perform(self, move)
	s.cursor += 1
	s.revision += 1
	advance()
	return true

func care(actor_id: String, skill: String, target: String) -> bool:
	if s.outcome != "clear" or not target in live(PARTY) or s.units[target].hp == s.units[target].max:
		return false
	if not skill in ["aid", "convert", "kit"] or not usable(actor_id, skill): return false
	Effects.treatment(self, actor_id, skill, target)
	return true

func fixed_target(id: String, round_number: int) -> String:
	var members: Array = live(PARTY)
	return members[posmod(hash([s.seed, round_number, id]), members.size())]

func forecast() -> void:
	s.intents.clear()
	for id in live(s.enemies):
		var unit: Dictionary = s.units[id]
		var intent = {"kind": "strike", "target": fixed_target(id, s.round), "power": int(unit.hit), "done": false, "cancelled": false, "softened": false, "interruptible": false, "bonus": 0}
		match Catalog.data.enemies[id].role:
			"shield":
				if s.round % 2 == 1 and s.round >= unit.lock:
					intent.merge({"kind": "guard", "target": id, "power": 0}, true)
			"caster", "boss":
				var boss: bool = id == "boss"
				match (s.round - 1) % (4 if boss else 3):
					0:
						intent.merge({"kind": "charge", "target": "mage" if alive("mage") else fixed_target(id, s.round + 1), "power": int(unit.heavy)}, true)
					1:
						if not unit.charged.is_empty():
							var backlash: bool = boss and s.round % 8 == 6
							intent.merge({"kind": "heavy", "target": unit.charged, "power": int(unit.heavy), "interruptible": not backlash, "bonus": 10 if boss else 0}, true)
					2:
						if boss: intent.merge({"kind": "sweep", "target": "all", "power": int(unit.sweep) + posmod(hash(s.seed), 7) - 3, "ritual": true}, true)
			"mender":
				var allies: Array = live(s.enemies)
				allies.sort_custom(func(a, b):
					var left: int = s.units[a].max - s.units[a].hp
					var right: int = s.units[b].max - s.units[b].hp
					return a < b if left == right else left > right)
				if unit.heals > 0 and s.units[allies[0]].max - s.units[allies[0]].hp >= 12:
					intent.merge({"kind": "heal", "target": allies[0], "power": int(unit.heal)}, true)
		if s.round == 1 and s.locked.has(id): intent.merge(s.locked[id], true)
		s.intents[id] = intent
	record("forecast", "", "", 0, str(s.intents))

func intent_power(intent: Dictionary) -> int:
	var strength: int = int(intent.power) + (int(intent.bonus) if alive("shield") and s.units.shield.guard else 0)
	if intent.get("ritual", false) and exposed("boss"): strength -= int(Catalog.data.rules.ritual_sweep_relief)
	return maxi(0, strength)

func exposed(id: String) -> bool:
	var unit: Dictionary = s.units[id]
	return unit.exposed_until > s.round or (unit.burn > 0 and unit.mark > s.round)

func intent_preview(id: String) -> Array:
	if not alive(id) or not s.intents.has(id) or s.intents[id].done: return []
	var branch = copy()
	Effects.enemy_action(branch, id)
	return branch.events

func advance() -> void:
	while not finish():
		if s.cursor == s.order.size():
			for id in live(s.enemies):
				if s.units[id].burn > 0:
					s.units[id].burn -= 1
					Effects.damage(self, "mage", id, int(Catalog.data.rules.burn_damage), "burn", false)
			if finish(): return
			s.round += 1
			s.cursor = 0
			forecast()
		var id: String = actor()
		if alive(id):
			if id in PARTY:
				s.units[id].stance.clear()
				if s.protection.get("owner", "") == id: s.protection.clear()
				return
			Effects.enemy_action(self, id)
		s.cursor += 1
