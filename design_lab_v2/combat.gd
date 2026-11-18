extends RefCounted

const ALLIES = ["blade", "mage", "warden"]
const ENEMIES = ["shield", "oracle"]
static var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://design_lab_v2/content.json"))
var s: Dictionary
var mode: String

func setup(seed_value: int, encounter: int, reward: String, carried: Dictionary) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + encounter * 997
	s = {"round": 1, "tick": 0, "units": {}, "intents": {}, "events": [], "shared": carried.get("shared", 18), "kills": [], "outcome": "", "ward": {}, "encounter": encounter, "reward": reward}
	for id in ALLIES + ENEMIES:
		var maximum: int = int(data.units[id].hp)
		if id in ENEMIES: maximum += encounter * 16 + rng.randi_range(-3, 3)
		s.units[id] = {"max": maximum, "hp": carried.get("hp", {}).get(id, maximum), "stock": carried.get("stock", {}).get(id, 2) if id in ALLIES else 0, "ready": 0, "turn": 0, "mark": false, "burn": 0, "guard": false, "reply": false}

func copy():
	var branch = get_script().new()
	branch.s = s.duplicate(true)
	return branch

func alive(id: String) -> bool:
	return s.units[id].hp > 0

func live(ids: Array) -> Array:
	return ids.filter(func(id): return alive(id))

func carry() -> Dictionary:
	var result = {"hp": {}, "stock": {}, "shared": s.shared}
	for id in ALLIES:
		result.hp[id] = s.units[id].hp
		result.stock[id] = s.units[id].stock
	return result

func commands(actor: String) -> Array:
	var moves: Array = data.units[actor].moves.duplicate()
	if mode == "plan" and data.units[actor].has("plan_extra"):
		moves.append(data.units[actor].plan_extra)
	var reward: Dictionary = data.rewards[s.reward]
	if actor == "warden" and reward.has("replace"):
		moves[moves.find(reward.replace)] = reward.move
	return moves

func targets(actor: String, move: String) -> Array:
	match data.moves[move].target:
		"enemy": return live(ENEMIES)
		"all": return ["all"] if not live(ENEMIES).is_empty() else []
		"ally": return live(ALLIES)
		"other": return live(ALLIES).filter(func(id): return id != actor)
		_: return [actor]

func cost(move: String) -> int:
	return int(data.moves[move][mode])

func options(actor: String, budget: int) -> Array:
	var found: Array = []
	if actor.is_empty() or not alive(actor): return found
	for move in commands(actor):
		if cost(move) <= budget:
			for id in targets(actor, move): found.append({"actor": actor, "move": move, "target": id})
	return found

func record(event: String, actor: String, target: String, amount: int = 0, detail: String = "") -> void:
	s.events.append({"event": event, "actor": actor, "target": target, "amount": amount, "detail": detail, "round": s.round, "tick": s.tick})

func damage(actor: String, target: String, power: int, source: String, bypass: bool = false) -> int:
	if not alive(target): return 0
	var unit: Dictionary = s.units[target]
	var raw: int = power if bypass or not unit.guard else power / 2
	var actual: int = mini(raw, unit.hp)
	unit.hp -= actual
	record("damage", actor, target, actual, source)
	if not alive(target):
		record("ko", actor, target)
		if mode == "plan" and target in ENEMIES and not target in s.kills:
			s.kills.append(target)
			var credit: int = mini(3, 24 - s.shared)
			s.shared += credit
			record("supply", actor, target, credit)
	status()
	return actual

func status() -> void:
	if live(ENEMIES).is_empty(): s.outcome = "clear"
	elif live(ALLIES).is_empty(): s.outcome = "defeat"

func start_actor(actor: String) -> void:
	s.units[actor].reply = false
	if s.ward.get("owner", "") == actor: s.ward.clear()

func action(a: Dictionary) -> void:
	var actor: String = a.actor
	var target: String = a.target
	var move: String = a.move
	start_actor(actor)
	if target != "all" and not alive(target):
		record("fizzle", actor, target, 0, move)
		return
	var payment: int = cost(move)
	if mode == "plan": s.shared -= payment
	else: s.units[actor].stock -= payment
	record("action", actor, target, payment, move)
	var power: int = data.moves[move].get("power", 0)
	match move:
		"rush", "spear": damage(actor, target, power, move)
		"spread":
			for id in live(ENEMIES): damage(actor, id, power, move)
		"mark":
			damage(actor, target, power, move)
			if alive(target): s.units[target].mark = true
		"follow":
			if s.units[target].mark:
				power += 12
				s.units[target].mark = false
				record("combo", actor, target, 12)
			damage(actor, target, power, move)
		"burn":
			damage(actor, target, power, move)
			if alive(target): s.units[target].burn = 2
		"break":
			damage(actor, target, power, move)
			var intent: Dictionary = s.intents.get(target, {})
			if alive(target) and intent.get("move", "") == "heavy" and not intent.shifted:
				intent.shifted = true
				if mode == "clock": intent.due += 2
				record("interrupt", actor, target, 2 if mode == "clock" else 0, move)
		"riposte": s.units[actor].reply = true
		"dampen":
			var intent: Dictionary = s.intents.get(target, {})
			if intent.get("move", "") in ["heavy", "strike"]:
				var reduced: int = mini(intent.power, power)
				intent.power -= reduced
				record("dampen", actor, target, reduced)
		"lure":
			var intent: Dictionary = s.intents.get(target, {})
			if intent.get("move", "") in ["heavy", "strike"]:
				intent.target = actor
				s.units[actor].reply = true
				record("redirect", actor, target, 0, move)
		"cover": s.ward = {"owner": actor, "target": target}
		"heal": heal(actor, target, power, move)

func heal(actor: String, target: String, power: int, source: String) -> void:
	var unit: Dictionary = s.units[target]
	var actual: int = mini(power, unit.max - unit.hp)
	unit.hp += actual
	record("heal", actor, target, actual, source)

func make_intent(enemy: String, due: int) -> Dictionary:
	var turn: int = s.units[enemy].turn
	var candidates: Array = live(ALLIES)
	var target: String = candidates[(turn + 1) % candidates.size()]
	if enemy == "shield":
		if turn % 2 == 0: return {"move": "guard", "target": enemy, "due": due, "shifted": false, "power": 0}
		return {"move": "strike", "target": target, "due": due, "shifted": false, "power": 12 + 3 * s.encounter}
	if turn == 1: return {"move": "mend", "target": enemy, "due": due, "shifted": false, "power": 14}
	return {"move": "heavy", "target": target, "due": due, "shifted": false, "power": 26 + 4 * s.encounter}

func enemy_action(enemy: String) -> void:
	var intent: Dictionary = s.intents[enemy]
	var unit: Dictionary = s.units[enemy]
	unit.turn += 1
	if unit.burn > 0:
		unit.burn -= 1
		damage("mage", enemy, 5, "burn_tick", true)
	if not alive(enemy):
		record("cancel", enemy, intent.target, 0, intent.move)
		return
	var target: String = intent.target
	match intent.move:
		"guard":
			unit.guard = true
			record("enemy", enemy, enemy, 0, "guard")
		"mend": heal(enemy, enemy, intent.power, "mend")
		"heavy", "strike":
			unit.guard = false
			if (mode == "plan" and intent.shifted) or not alive(target):
				record("cancel", enemy, target, 0, intent.move)
				return
			var power: int = intent.power
			if s.ward.get("target", "") == target and alive(s.ward.owner):
				target = s.ward.owner
				var prevented: int = mini(power, 8)
				power -= prevented
				s.ward.clear()
				record("cover", target, intent.target, prevented)
			var dealt: int = damage(enemy, target, power, intent.move)
			if dealt > 0 and alive(target) and s.units[target].reply:
				s.units[target].reply = false
				damage(target, enemy, 9, "reply")
