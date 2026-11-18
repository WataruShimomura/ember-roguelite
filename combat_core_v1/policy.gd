extends RefCounted

const Catalog = preload("res://combat_core_v1/catalog.gd")
const STYLES = ["rush", "sustain", "counter", "synergy", "reserve", "read", "delay", "random"]

static func incoming(b) -> Dictionary:
	var harm = {"blade":0,"mage":0,"warden":0}
	for id in b.live(b.s.enemies):
		for e in b.intent_preview(id):
			if e.event == "damage" and harm.has(e.target): harm[e.target] += e.amount
	return harm

static func score(a, b, style: String, delaying: bool) -> float:
	var pressure: Dictionary = incoming(b)
	var health: float = 0
	var risk: float = 0
	var deaths: int = 0
	var spent: int = 0
	for id in Catalog.PARTY:
		var old: Dictionary = a.s.units[id]
		var unit: Dictionary = b.s.units[id]
		health += unit.hp - old.hp
		if unit.hp <= 0 and old.hp > 0: deaths += 1
		if unit.hp > 0 and pressure[id] > 0:
			risk += pressure[id] * .33
			risk += 28 if pressure[id] >= unit.hp else maxf(0, 19 - (unit.hp - pressure[id])) * .35
		spent += old.tp - unit.tp
	var dealt: int = 0
	var kills: int = 0
	var conditions: float = 0
	var priority: float = 0
	for id in a.s.enemies:
		var old: Dictionary = a.s.units[id]
		var unit: Dictionary = b.s.units[id]
		var difference: int = old.hp - unit.hp
		dealt += difference
		if old.hp > 0 and unit.hp == 0:
			kills += 1
			if id != "shield": priority += 5
		if unit.hp > 0:
			conditions += float(unit.burn - old.burn) * 3
			if "combo" in b.s.units.blade.moves and (unit.mark > b.s.round) != (old.mark > a.s.round):
				conditions += 6 if unit.mark > b.s.round else -3
			if id == "shield" and old.guard and not unit.guard: conditions += 10 if b.live(b.s.enemies).size() > 1 else 2
		if id == "mender" and unit.heals > 0: priority += difference * .33
	var defense: float = 0
	var reply: float = 0
	for e in b.events:
		match e.event:
			"interrupt": defense += 12
			"mitigation":
				if e.source in ["dampen","convert"]: defense += e.amount * .35
			"damage":
				if e.source == "reply": reply += e.amount
			"rally": conditions += 6
			"gear":
				if e.source == "mail": defense += e.amount * .35
	if delaying: return -4 * dealt - 200 * kills + health * 2 - spent * 1.2 - deaths * 60 - risk
	var kit_fee: int = 12 * (a.s.kits - b.s.kits)
	var base: float = dealt + 16 * kills + priority - 75 * deaths - kit_fee
	match style:
		"rush": return base + 10 * kills + health * .55 - .7 * spent - risk * .7 + .6 * conditions + .65 * defense
		"sustain": return base + 1.37 * health - 1.35 * spent - risk * 1.15 + conditions + defense
		"counter": return base + 1.2 * health - spent - risk * 1.3 + conditions + 1.2 * defense + .45 * reply
		"synergy": return base + health - 1.1 * spent - risk + 1.85 * conditions + .8 * defense
		"reserve": return base + health - (1.8 if a.s.encounter == 2 else 2.9) * spent - risk * 1.2 + conditions + defense
	return base + 1.27 * health - 1.35 * spent - risk * 1.45 + conditions + defense

static func select(b, style: String, delaying: bool = false) -> Dictionary:
	var moves: Array = b.options()
	if moves.is_empty(): return {}
	if style == "random": return moves[posmod(hash([b.s.seed, b.s.revision, style]), moves.size())]
	var best: Dictionary = moves[0]
	var best_value: float = -INF
	for move in moves:
		var branch = b.copy()
		branch.submit(move, b.s.revision)
		var value: float = score(b, branch, style, delaying)
		if value > best_value:
			best = move
			best_value = value
	return best

static func camp(route, style: String) -> void:
	for skill in ["kit","aid","convert"]:
		var owner: String = "mage" if skill == "convert" else "warden"
		var options: Array = route.battle.live(Catalog.PARTY)
		options.sort_custom(func(a, b): return route.party[a].hp < route.party[b].hp)
		for id in options:
			var unit: Dictionary = route.party[id]
			var limit: float = .75 if style in ["sustain","counter","read"] else .55
			if unit.hp <= unit.max * limit and route.care(owner if route.battle.alive(owner) else options[0], skill, id): break
