extends "res://design_lab_v2/combat.gd"

func _init() -> void:
	mode = "plan"

func start(seed_value: int, encounter: int = 0, reward: String = "base", carried: Dictionary = {}) -> void:
	setup(seed_value, encounter, reward, carried)
	status()
	if s.outcome.is_empty(): begin_round()

func begin_round() -> void:
	# Both intents are public for the entire planning phase.
	s.intents.clear()
	for id in live(ENEMIES): s.intents[id] = make_intent(id, s.round)

func submit(plan: Array, complete: bool = true) -> bool:
	if s.outcome != "": return false
	var remaining: Array = live(ALLIES)
	var budget: int = s.shared
	for a in plan:
		if not a.actor in remaining or not a in options(a.actor, budget): return false
		remaining.erase(a.actor)
		budget -= cost(a.move)
	if complete and not remaining.is_empty(): return false
	for a in plan:
		action(a)
		if s.outcome != "": return true
	if not complete: return true
	for id in ["oracle", "shield"]:
		if alive(id): enemy_action(id)
		elif s.intents.has(id): record("cancel", id, s.intents[id].target, 0, s.intents[id].move)
		if s.outcome != "": return true
	s.round += 1
	begin_round()
	return true
