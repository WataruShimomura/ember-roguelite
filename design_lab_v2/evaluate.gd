extends SceneTree

const Plan = preload("res://design_lab_v2/plan.gd")
const ClockRules = preload("res://design_lab_v2/clock.gd")
const Policy = preload("res://design_lab_v2/policy.gd")
const SEEDS = [42, 43, 44, 45, 46, 47, 48, 49, 50, 51]
const REWARDS = ["base", "lure", "medic"]
var checks: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var output = {"base": "c21c5bc4d42ff83602d2f74bd4d5f18c1678eed5", "instructions": "365669f0427999df3c564066d4c02d99c8ae043a", "design": "ffcc5b61ecefde264f6a3524feb57cd82635d4a7", "engine": Engine.get_version_info().string, "runs": [], "positions": [], "stall": []}
	for rules in [Plan, ClockRules]:
		check_boundaries(rules)
		output.positions.append_array(positions(rules))
		output.stall.append(stall(rules))
		for seed_value in SEEDS:
			for style in Policy.POLICIES:
				for gear in REWARDS:
					output.runs.append(play(rules, seed_value, style, gear))
		print("RESULT ", rules.resource_path, " finished")
	output.checks = checks
	output.failures = failures
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	var file = FileAccess.open("res://tests/artifacts/design_lab_v2.json", FileAccess.WRITE)
	if file == null:
		printerr("FAIL: could not save measurements")
		quit(1)
		return
	file.store_string(JSON.stringify(output))
	file.close()
	print("DESIGN LAB V2: %d runs / %d positions / %d checks / %d failures" % [output.runs.size(), output.positions.size(), checks, failures])
	quit(0 if failures == 0 else 1)

func choice(actor: String, move: String, target: String) -> Dictionary:
	return {"actor": actor, "move": move, "target": target}

func empty() -> Dictionary:
	return {"shared": 0, "stock": {"blade": 0, "mage": 0, "warden": 0}}

func check_boundaries(rules) -> void:
	var game = rules.new()
	game.start(42)
	var before: Dictionary = game.s.duplicate(true)
	var a = choice("blade", "break", "oracle")
	var b = choice("mage", "mark", "oracle")
	var c = choice("warden", "cover", "mage")
	var via = game.copy()
	if game.mode == "plan":
		check(not game.submit([a, a, c]) and game.s == before, "duplicate actor rejected atomically")
		check(via.submit([a, b, c]) and game.s == before, "pure full-plan preview")
		check(game.submit([a, b, c]) and game.s == via.s, "plan prediction equals execution")
		check(game.s.events.any(func(e): return e.event == "cancel" and e.detail == "heavy"), "plan break cancels heavy")
		var sequence = game.copy()
		var reverse = game.copy()
		var follow = choice("blade", "follow", "shield")
		var mark = choice("mage", "mark", "shield")
		check(sequence.submit([mark, follow, c]) and reverse.submit([follow, mark, c]), "both orders legal")
		check(reverse.s.units.shield.hp - sequence.s.units.shield.hp == 6, "ordered mark changes guarded hit by six")
	else:
		check(not game.submit(b) and game.s == before, "out of order actor rejected atomically")
		check(via.submit(a) and game.s == before, "pure clock preview")
		check(game.submit(a) and game.s == via.s, "clock prediction equals execution")
		check(game.s.intents.oracle.due == 5 and game.s.intents.oracle.shifted, "clock break shifts heavy by two")
		check(game.submit(b) and game.submit(c), "intervening support is legal")
		check(game.s.units.mage.hp == 54 and game.s.tick == 3, "mage acts again before shifted forecast")
		check(game.submit(b), "advance to the next blade input")
		var repeat = game.copy()
		check(repeat.submit(a) and repeat.s.events.filter(func(e): return e.event == "interrupt").size() == 1, "same forecast cannot be delayed twice")
		check(game.submit(choice("blade", "rush", "oracle")), "advance to the shifted tick")
		check(game.s.tick >= 5 and game.s.units.warden.hp == 60 and game.s.units.warden.stock == 2, "cover receives exact announced hit less eight")

	game.start(42, 0, "base", empty())
	for id in game.ALLIES:
		var options: Array = game.options(id, 0)
		var moves: Array = []
		for option in options:
			if not option.move in moves: moves.append(option.move)
		check(moves.size() >= 2, "multiple free skills for " + id)
	var attack = choice("blade", "rush", "oracle")
	if game.mode == "plan":
		check(not game.submit([a, b, c]), "cannot spend future kill credit during drafting")
		check(game.submit([attack, b, choice("warden", "riposte", "warden")]), "zero-supply plan resolves")
	else: check(game.submit(attack), "zero-stock clock action resolves")

	game.start(42, 0, "lure")
	check("lure" in game.commands("warden") and not "spear" in game.commands("warden"), "reward changes verb")
	for id in game.ALLIES:
		game.s.units[id].hp = 1000
	game.s.units.oracle.max = 500
	game.s.units.oracle.hp = 480
	game.s.units.shield.hp = 500
	# Keep both enemies alive to exercise the one-use self-heal and repeated forecasts.
	for i in range(16):
		if game.mode == "plan":
			game.submit([choice("blade", "rush", "shield"), choice("mage", "mark", "shield"), choice("warden", "lure", "oracle")])
		else:
			var actor: String = game.actor()
			var move: String = {"blade": "rush", "mage": "mark", "warden": "lure"}[actor]
			game.submit(choice(actor, move, "oracle" if actor == "warden" else "shield"))
	var healed: Array = game.s.events.filter(func(e): return e.event == "heal" and e.detail == "mend")
	check(healed.size() == 1 and healed[0].amount == 14, "exactly one finite +14 enemy heal")
	check(game.s.events.any(func(e): return e.event == "damage" and e.detail == "reply"), "reward resolves actual counter")
	check(game.s.events.filter(func(e): return e.event == "supply").is_empty(), "healing, time and counters cannot mint supply without a kill")
	game.start(42, 0, "base", {"hp": {"blade": 1, "mage": 0, "warden": 0}})
	var accepted: bool = game.submit([attack]) if game.mode == "plan" else game.submit(attack)
	check(accepted and game.s.outcome == "defeat", "last knockout ends before another intent")
	check(not (game.submit([attack]) if game.mode == "plan" else game.submit(attack)), "terminal input rejected")

func measure(game, start: Dictionary, choices: Array) -> Dictionary:
	var counts: Dictionary = {}
	var counters: int = 0
	var incoming: int = 0
	var heavy_hits: int = 0
	var suppressions: int = 0
	var healing: int = 0
	var spent: int = 0
	var heals: int = 0
	for event in game.s.events:
		match event.event:
			"action":
				counts[event.detail] = counts.get(event.detail, 0) + 1
				spent += event.amount
			"damage":
				if event.target in game.ALLIES:
					incoming += event.amount
					if event.detail == "heavy": heavy_hits += 1
				if event.detail == "reply": counters += event.amount
			"interrupt", "cover", "redirect", "dampen": suppressions += 1
			"heal":
				if event.target in game.ALLIES: healing += event.amount
				else: heals += 1
	var result = game.carry()
	check(heals <= 1 and game.s.kills.size() <= 2, "finite rewards and heals")
	if game.mode == "plan":
		var earned: int = 0
		for event in game.s.events:
			if event.event == "supply": earned += event.amount
		check(result.shared == start.shared - spent + earned and earned <= 6, "plan supply identity")
	else:
		check(result.stock.values().reduce(func(n, v): return n + v, 0) == start.stock.values().reduce(func(n, v): return n + v, 0) - spent, "clock stock identity")
	return {"start": start, "end": result, "outcome": game.s.outcome, "round": game.s.round, "tick": game.s.tick, "choices": choices, "counts": counts, "enemy_heals": heals, "damage_taken": incoming, "heavy_hits": heavy_hits, "counter_damage": counters, "forecast_responses": suppressions, "healing": healing, "spent": spent}

func play(rules, seed_value: int, style: String, gear: String) -> Dictionary:
	var game = rules.new()
	var summary = {"seed": seed_value, "style": style, "gear": gear, "mode": game.mode, "battles": []}
	var carry: Dictionary = {}
	for encounter in range(2):
		game.start(seed_value, encounter, gear if encounter == 1 else "base", carry)
		var start: Dictionary = game.carry()
		if encounter == 1: check(start == carry, "exact HP and resources carried")
		var choices: Array = []
		var delay_uses: int = 0
		for step in range(90):
			if game.s.outcome != "": break
			var delaying: bool = style == "delay" and game.live(game.ENEMIES).size() == 1 and delay_uses < (3 if game.mode == "plan" else 9)
			if delaying: delay_uses += 1
			var options = Policy.proposals(game, style, delaying)
			if options.is_empty():
				check(false, "valid option available")
				break
			var entry: Dictionary = options[0]
			var actor: String = game.actor() if game.mode == "clock" else ""
			var resources: int = game.s.shared if game.mode == "plan" else game.s.units[actor].stock
			choices.append([game.s.round, game.s.tick, resources, entry.input, delaying])
			if not game.submit(entry.input):
				check(false, "policy submits legal inputs")
				break
		check(game.s.outcome != "", "run reaches outcome before step cap")
		summary.battles.append(measure(game, start, choices))
		carry = game.carry()
		if game.s.outcome != "clear": break
	return summary

func positions(rules) -> Array:
	var results: Array = []
	for setting in ["open", "scarce", "gear"]:
		var game = rules.new()
		var carried = empty() if setting == "scarce" else {}
		carried.hp = {"mage": 22} if setting != "open" else {}
		game.start(42, 0, "lure" if setting == "gear" else "base", carried)
		var options = Policy.proposals(game, "adaptive", false)
		if game.mode == "plan":
			var support = "lure" if setting == "gear" else "cover"
			options.append({"input": [choice("mage", "mark", "oracle"), choice("blade", "follow", "oracle"), choice("warden", support if setting != "scarce" else "riposte", "oracle" if setting == "gear" else ("warden" if setting == "scarce" else "mage"))]})
			if setting == "open":
				options.append({"input": [choice("blade", "break", "oracle"), choice("mage", "mark", "oracle"), choice("warden", "spear", "oracle")]})
		var output = {"mode": game.mode, "setting": setting, "units": game.s.units.duplicate(true), "intents": game.s.intents.duplicate(true), "alternatives": []}
		var explored: Array = []
		for entry in options:
			if entry.input in explored: continue
			explored.append(entry.input)
			var branch = game.copy()
			if not branch.submit(entry.input):
				check(false, "counterfactual input legal")
				continue
			var first: Dictionary = measure(branch, game.carry(), [])
			for i in range(2):
				if branch.s.outcome != "": break
				branch.submit(Policy.proposals(branch, "adaptive", false)[0].input)
			output.alternatives.append({"input": entry.input, "next_input": first, "after_three_inputs": measure(branch, game.carry(), [])})
		results.append(output)
	return results

func stall(rules) -> Dictionary:
	var original = rules.new()
	original.start(42)
	original.s.units.oracle.hp = 0
	original.s.units.shield.hp = 5
	original.s.units.shield.guard = true
	var result = {"mode": original.mode, "end": {}}
	for wait in [false, true]:
		var game = original.copy()
		var inputs: Array = []
		if wait:
			for step in range(3 if game.mode == "plan" else 9):
				if game.s.outcome != "": break
				var input = Policy.proposals(game, "adaptive", true)[0].input
				inputs.append(input)
				game.submit(input)
		for step in range(20):
			if game.s.outcome != "": break
			var input = Policy.proposals(game, "adaptive", false)[0].input
			inputs.append(input)
			game.submit(input)
		check(game.s.outcome == "clear", "low HP delay probe terminates")
		result.end["delay" if wait else "immediate"] = measure(game, original.carry(), inputs)
	check(result.end.delay.end.shared <= result.end.immediate.end.shared and result.end.delay.end.stock == result.end.immediate.end.stock, "no extra carry resource from stalling")
	return result
