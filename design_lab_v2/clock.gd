extends "res://design_lab_v2/combat.gd"

func _init() -> void:
	mode = "clock"

func start(seed_value: int, encounter: int = 0, reward: String = "base", carried: Dictionary = {}) -> void:
	setup(seed_value, encounter, reward, carried)
	status()
	if not s.outcome.is_empty(): return
	for i in range(ALLIES.size()): s.units[ALLIES[i]].ready = i
	s.intents.oracle = make_intent("oracle", 3)
	s.intents.shield = make_intent("shield", 4)
	advance()

func actor() -> String:
	var order: Array = live(ALLIES)
	order.sort_custom(func(a, b):
		if s.units[a].ready == s.units[b].ready: return ALLIES.find(a) < ALLIES.find(b)
		return s.units[a].ready < s.units[b].ready)
	return order[0] if not order.is_empty() else ""

func submit(a: Dictionary) -> bool:
	if s.outcome != "" or a.actor != actor() or not a in options(a.actor, s.units[a.actor].stock):
		return false
	var delay: int = data.moves[a.move].delay
	s.units[a.actor].ready = s.tick + delay
	action(a)
	advance()
	return true

func advance() -> void:
	while s.outcome == "":
		var next: String = actor()
		var due: int = s.units[next].ready
		var enemy: String = ""
		for id in ["oracle", "shield"]:
			if alive(id) and s.intents[id].due <= due:
				if enemy == "" or s.intents[id].due < due:
					due = s.intents[id].due
					enemy = id
		s.tick = due
		if enemy.is_empty(): return
		enemy_action(enemy)
		if not s.outcome.is_empty(): return
		if alive(enemy): s.intents[enemy] = make_intent(enemy, due + (6 if enemy == "oracle" else 5))
