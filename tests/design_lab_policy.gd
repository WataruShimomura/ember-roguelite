extends RefCounted

const NAMES = ["rush", "reserve", "delay", "defense", "synergy", "conditional", "random"]

static func options(battle, style: String, remaining: int) -> Array:
	var state = battle.state
	var actor: String = state.actor()
	var unit: Dictionary = state.units[actor]
	var threats: Dictionary = {}
	for enemy in state.intents:
		var forecast: Dictionary = battle.intent_preview(enemy)
		for effect in forecast.calculation.get("effects", []):
			if effect.kind == "damage" and not effect.counter:
				if not threats.has(enemy): threats[enemy] = {}
				threats[enemy][effect.target] = effect.amount
	var candidates: Array = []
	var skills: Dictionary = {}
	for skill in battle.commands(actor): skills[skill] = ""
	for item in state.inventory:
		if state.inventory[item] > 0: skills[battle.catalog.data.items[item].skill] = item
	for skill in skills:
		if battle.calculator.cost(unit, skill).amount > unit.tp: continue
		for target in battle.legal_targets(actor, skill):
			var calc: Dictionary = battle.preview(actor, skill, target)
			if calc.targets.is_empty(): continue
			var summary = {"damage": 0, "kills": 0, "prevention": 0.0, "heal": 0, "urgent_heal": 0, "tp": 0, "status": 0.0, "retaliation": 0, "buff": 0, "lethal": 0, "new_hp": 0, "revive": 0}
			var defeated: Dictionary = {}
			for effect in calc.effects:
				var recipient: Dictionary = state.units[effect.target]
				var incoming: int = 0
				for enemy in threats:
					if not defeated.has(enemy): incoming += threats[enemy].get(effect.target, 0)
				match effect.kind:
					"damage":
						if recipient.team == "enemy":
							summary.damage += effect.amount
							summary.new_hp += effect.credit
							if effect.low_after == 0 and not defeated.has(effect.target):
								defeated[effect.target] = true
								summary.kills += 1
								for amount in threats.get(effect.target, {}).values(): summary.prevention += amount
						else: summary.retaliation += effect.amount
					"heal":
						summary.heal += effect.amount
						if recipient.hp < 30 or incoming >= recipient.hp: summary.urgent_heal += effect.amount
					"revive": summary.revive += effect.amount
					"tp": summary.tp += effect.amount
					"status":
						if not defeated.has(effect.target) and not recipient.statuses.has(effect.status):
							summary.status += effect.chance * minf(8, recipient.hp)
					"guard":
						var target_turn = state.order.find(effect.target)
						var before_expiry: int = 0
						for enemy in threats:
							var enemy_turn = state.order.find(enemy)
							if defeated.has(enemy): continue
							if target_turn <= state.cursor or enemy_turn < target_turn:
								before_expiry += threats[enemy].get(effect.target, 0)
						if not recipient.guard:
							summary.prevention += before_expiry * (1 - effect.multiplier)
							if before_expiry >= recipient.hp and before_expiry * effect.multiplier < recipient.hp:
								summary.lethal += 1
					"counter_stance":
						if incoming > 0: summary.buff += effect.value
					"modifier":
						if effect.value < 0 and not defeated.has(effect.target):
							for amount in threats.get(effect.target, {}).values():
								summary.prevention += mini(amount, absi(int(effect.value)))
						elif effect.value > 0: summary.buff += effect.value
			var option = {"skill": skill, "target": target, "item": skills[skill], "cost": calc.cost, "value": summary}
			option.score = score(option, style, remaining)
			candidates.append(option)
	return candidates

static func score(option: Dictionary, style: String, remaining: int) -> float:
	var v: Dictionary = option.value
	var item_fee: float = 7 if option.item != "" else 0
	var base: float = v.damage - v.retaliation + v.revive * 1.2 + 12 * v.lethal - item_fee
	match style:
		"rush": return base + 13 * v.kills + .65 * v.prevention + .2 * v.status + .8 * v.urgent_heal + 2 * v.tp - .8 * option.cost
		"reserve": return base + 7 * v.kills + .8 * v.prevention + .45 * v.heal + .7 * v.urgent_heal + 3 * v.tp - (3 + remaining) * option.cost
		"defense": return base + 6 * v.kills + 1.65 * v.prevention + .6 * v.heal + .7 * v.urgent_heal + 2 * v.tp + .9 * v.buff - 2 * option.cost
		"synergy": return base + 6 * v.kills + .7 * v.prevention + 1.35 * v.status + .65 * v.heal + .75 * v.urgent_heal + 3 * v.tp + .55 * v.buff - 2 * option.cost
	return base + 8 * v.kills + v.prevention + .65 * v.status + .55 * v.heal + .85 * v.urgent_heal + 2.7 * v.tp + .45 * v.buff - (2 + .6 * remaining) * option.cost

static func choose(candidates: Array, style: String, rng: RandomNumberGenerator, delay: bool) -> Dictionary:
	if style == "random": return candidates[rng.randi_range(0, candidates.size() - 1)]
	var best: Dictionary = {}
	var best_score: float = -INF
	for option in candidates:
		var rank: float = option.score
		if delay:
			var v: Dictionary = option.value
			rank = -1000 * v.kills - 3 * v.damage - 4 * v.status + v.heal + .5 * v.prevention + 2 * v.tp - 5 * option.cost
			if option.item != "": rank -= 15
		if rank > best_score:
			best_score = rank
			best = option
	return best
