extends RefCounted

const POLICIES = ["rush", "sustain", "reserve", "delay", "adaptive"]

static func evaluate(before, after, style: String, delaying: bool) -> float:
	var hp_loss: int = 0
	var danger: int = 0
	var deaths: int = 0
	var enemy_loss: int = 0
	var kills: int = 0
	var setup: int = 0
	var stock_cost: int = before.s.shared - after.s.shared
	for id in before.ALLIES:
		var old: Dictionary = before.s.units[id]
		var current: Dictionary = after.s.units[id]
		hp_loss += old.hp - current.hp
		stock_cost += old.stock - current.stock
		if old.hp > 0 and current.hp == 0: deaths += 1
		if current.hp > 0 and current.hp < 30: danger += maxi(0, mini(30, old.hp) - current.hp)
	for id in before.ENEMIES:
		var old: Dictionary = before.s.units[id]
		var current: Dictionary = after.s.units[id]
		enemy_loss += old.hp - current.hp
		if old.hp > 0 and current.hp == 0: kills += 1
		if current.hp > 0: setup += (int(current.mark) - int(old.mark)) * 4 + (current.burn - old.burn) * 2
	var interrupted: int = 0
	var redirects: int = 0
	for index in range(before.s.events.size(), after.s.events.size()):
		var event: Dictionary = after.s.events[index]
		if event.event == "interrupt": interrupted += 1
		if event.event == "redirect": redirects += 1
	if delaying: return -30 * kills - 3 * enemy_loss - hp_loss * .45 - stock_cost * 3
	var tactical: float = setup + 5 * interrupted + redirects
	var base: float = enemy_loss + 12 * kills - 65 * deaths - danger * .35 + tactical
	match style:
		"rush": return base + 7 * kills - .45 * hp_loss - stock_cost
		"sustain": return base - 1.35 * hp_loss - stock_cost * 1.7
		"reserve": return base - .70 * hp_loss - stock_cost * 4.0
	return base - .95 * hp_loss - stock_cost * 2.0

static func rank(entries: Array) -> void:
	entries.sort_custom(func(a, b):
		if is_equal_approx(a.score, b.score): return a.order < b.order
		return a.score > b.score)

static func proposals(game, style: String, delaying: bool) -> Array:
	if game.mode == "clock":
		var actor: String = game.actor()
		var entries: Array = []
		for a in game.options(actor, game.s.units[actor].stock):
			var branch = game.copy()
			branch.submit(a)
			var tempo: float = .7 * (int(game.data.moves[a.move].delay) - 2)
			entries.append({"input": a, "score": evaluate(game, branch, style, delaying) - tempo, "order": entries.size()})
		rank(entries)
		return entries

	# Retain several promising partial plans and all their legal continuations.
	var beam: Array = [{"input": []}]
	var living: Array = game.live(game.ALLIES)
	for depth in range(living.size()):
		var entries: Array = []
		for entry in beam:
			var reserved: int = 0
			var selected: Array = []
			for a in entry.input:
				selected.append(a.actor)
				reserved += game.cost(a.move)
			for actor in living:
				if actor in selected: continue
				for a in game.options(actor, game.s.shared - reserved):
					var plan: Array = entry.input + [a]
					var branch = game.copy()
					branch.submit(plan, depth == living.size() - 1)
					entries.append({"input": plan, "score": evaluate(game, branch, style, delaying), "order": entries.size()})
		rank(entries)
		beam = entries.slice(0, 6)
	return beam
