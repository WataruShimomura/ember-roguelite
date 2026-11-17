extends SceneTree

const Content = preload("res://core/content_catalog.gd")
const Manager = preload("res://core/run_manager.gd")
const BattleEngine = preload("res://core/battle_engine.gd")
const State = preload("res://core/battle_state.gd")
const Policy = preload("res://tests/design_lab_policy.gd")
const Simulator = preload("res://tests/run_simulator.gd")
const Variants = preload("res://lab/design_lab_variants.gd")
const BASE = "c21c5bc4d42ff83602d2f74bd4d5f18c1678eed5"
const INSTRUCTIONS = "3f395875ff4efbab8bbe4e1144f1befd20131226"
const REWARD_TRIALS = ["gear_ring", "gear_ward", "gear_bench", "gear_rest"]
var args = OS.get_cmdline_user_args()
var mode: String = args[0] if not args.is_empty() else "baseline"
var failures: int = 0

func require(condition: bool, detail: String) -> bool:
	if not condition:
		printerr("FAIL: " + detail)
		failures += 1
	return condition

func content_for(candidate: String):
	var catalog = Content.new()
	if candidate in REWARD_TRIALS:
		var variant = "tp" if candidate == "gear_ring" else "gear"
		Variants.apply(variant, catalog)
		catalog.data.reward_groups[0] = ["gear_ring"]
	else:
		Variants.apply(candidate, catalog)
	return catalog

func _initialize() -> void:
	if not require(mode in Variants.MODES or mode in REWARD_TRIALS, "unknown mode"):
		quit(1)
		return
	var catalog = content_for(mode)
	if not require(catalog.errors.is_empty(), str(catalog.errors)):
		quit(1)
		return
	if catalog.data.skills.strike.effects[0].get("pierces_guard", false):
		check_skill_rules(catalog)
	if catalog.data.skills.has("ward"):
		check_gear_rules(catalog)
	var output = {"base": BASE, "instructions": INSTRUCTIONS, "engine": Engine.get_version_info().string, "mode": mode, "rules": catalog.data.rules.tp_recovery, "runs": [], "delay_probe": [], "positions": [], "long_fight": []}
	for seed_value in range(42, 52):
		for preset in ["burst", "sustain"]:
			for style in Policy.NAMES:
				output.runs.append(play(catalog, seed_value, preset, style, output.positions))
		for items in [false, true]:
			for delay in [false, true]:
				output.delay_probe.append(probe(catalog, seed_value, delay, items))
		for preset in ["burst", "sustain"]:
			output.long_fight.append(long_fight(catalog, seed_value, preset))
	output.failures = failures
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	var file = FileAccess.open("res://tests/artifacts/design_lab_%s.json" % mode, FileAccess.WRITE)
	if require(file != null, "write measurements"):
		file.store_string(JSON.stringify(output))
		file.close()
	print("DESIGN LAB %s: %d runs, %d delay probes, %d long fights, %d positions, %d failures" % [mode, output.runs.size(), output.delay_probe.size(), output.long_fight.size(), output.positions.size(), failures])
	quit(0 if failures == 0 else 1)

func check_skill_rules(catalog) -> void:
	var battle = BattleEngine.new(catalog)
	battle.start(catalog.data.presets.burst, 42, {}, ["sentinel"])
	var attack: Dictionary = battle.preview("knight", "attack", "sentinel")
	var strike: Dictionary = battle.preview("knight", "strike", "sentinel")
	require(strike.effects[0].amount < attack.effects[0].amount, "normal wins against exposed target")
	battle.state.units.sentinel.guard = true
	var guarded: Dictionary = battle.preview("knight", "attack", "sentinel")
	var piercing: Dictionary = battle.preview("knight", "strike", "sentinel")
	require(piercing.effects[0].amount == strike.effects[0].amount and guarded.effects[0].amount < piercing.effects[0].amount, "strike trades open damage for bypass")
	var roll_state: int = battle.state.rng.state
	var hp: int = battle.state.units.sentinel.hp
	require(battle.submit("knight", "strike", "sentinel", battle.state.revision), "strike execute")
	require(battle.state.units.sentinel.hp == hp - piercing.effects[0].amount and roll_state == battle.state.rng.state, "strike preview agrees with execution")
	var fire: Dictionary = battle.preview("mage", "fireball", "sentinel")
	require(fire.effects.any(func(effect): return effect.kind == "status" and effect.chance == 1.0), "fireball guaranteed status preview")
	require(battle.submit("mage", "fireball", "sentinel", battle.state.revision), "fireball execute")
	require(battle.state.units.sentinel.statuses.has("burn"), "fireball applies forecast burn")

func check_gear_rules(catalog) -> void:
	var battle = BattleEngine.new(catalog)
	var loadout: Dictionary = catalog.data.presets.burst.duplicate(true)
	loadout.knight = ["ring", "ring"]
	battle.start(loadout, 42, {}, ["warlock"])
	require(battle.commands("knight").count("ward") == 1 and not "ward" in battle.commands("mage"), "equipment grants only one command to wearer")
	var target: String = battle.state.intents.warlock.targets[0]
	var unguarded: int = battle.intent_preview("warlock").calculation.effects[0].amount
	var before: Dictionary = battle.snapshot()
	var ward: Dictionary = battle.preview("knight", "ward", target)
	require(ward.cost == 1 and ward.effects[0].kind == "guard" and battle.snapshot() == before, "ward preview is pure")
	require(battle.submit("knight", "ward", target, battle.state.revision), "submit equipment skill")
	var mitigated: int = battle.intent_preview("warlock").calculation.effects[0].amount
	require(unguarded > mitigated and battle.state.units[target].guard, "ward updates enemy prediction")
	require(not battle.submit("mage", "ward", target, battle.state.revision), "non-wearer input rejected")
	require(battle.submit("mage", "attack", "warlock", battle.state.revision), "advance to forecast")
	require(battle.state.units[target].hp == before.units[target].hp - mitigated, "ward prediction agrees with enemy damage")

func play(catalog, seed_value: int, preset: String, style: String, positions: Array) -> Dictionary:
	var manager = Manager.new(catalog)
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value ^ 0x576db9
	var growth = ["detonate", "ember_hunt"] if preset == "burst" else ["riposte", "counter_order"]
	var details: Array = []
	var current: Dictionary = {}
	var alone_at: int = 0
	require(manager.new_run(seed_value, catalog.data.presets[preset]), "new run")
	for _step in range(700):
		var run = manager.state
		var revision: int = run.revision
		match run.phase:
			"finished": break
			"ready", "intermission":
				equip_reward(manager)
				require(manager.start_battle(run.revision), "start encounter")
				current = {"turns": [], "blocked_skills": {}, "full": 0, "empty": 0, "delay_turns": 0}
				alone_at = 0
			"battle":
				var battle = manager.battle
				var state = battle.state
				if state.phase == "finished":
					require(manager.collect_battle(revision), "collect encounter")
					details.append(measure(run.battles[-1], current, catalog.party_ids(), catalog.data.rules.tp_recovery.pool))
					continue
				var actor: String = state.actor()
				var unit: Dictionary = state.units[actor]
				var alive: Array = state.alive("enemy")
				if alive.size() == 1 and alone_at == 0: alone_at = state.round
				var delaying: bool = style == "delay" and alive.size() == 1 and run.node < 3 and state.round < alone_at + 4
				var options = Policy.options(battle, style, run.route.size() - 1 - run.node)
				if not require(not options.is_empty(), "legal action available"): break
				var action = Policy.choose(options, style, rng, delaying)
				if seed_value == 42 and style == "conditional" and actor in ["knight", "mage"] and state.round <= 3:
					positions.append(compare_position(battle, options, preset, run.node))
				record_turn(current, battle, action, delaying)
				if not require(battle.submit(actor, action.skill, action.target, state.revision, action.item), "submit " + str(action)): break
			"battle_result": require(manager.continue_result(revision), "continue")
			"reward": require(manager.choose_reward(0 if run.node == 0 and mode != "gear_rest" else 2, revision), "reward")
			"growth":
				var index: int = 0 if run.level == 3 else run.growth_options.find(growth[0 if run.level == 2 else 1])
				require(manager.choose_growth(index, revision), "growth")
			"event": require(manager.choose_event(0, revision), "event")
	var state = manager.state
	require(state.phase == "finished", "run step cap reached: %d/%s/%s" % [seed_value, preset, style])
	var history: Array = state.history.filter(func(event): return event.kind in ["reward", "growth", "event", "equipment", "restore", "reward_offer"])
	return {"seed": seed_value, "preset": preset, "policy": style, "route": state.route, "initial_loadout": catalog.data.presets[preset], "outcome": state.outcome, "battles": details, "history": history, "inventory": state.inventory, "party": state.party}

func equip_reward(manager) -> void:
	var run = manager.state
	if mode == "gear_bench" or run.equipment_slots != 3 or run.loadout.knight[2] != "": return
	for item in run.gear:
		if run.gear[item] > 0:
			require(manager.equip("knight", 2, item, run.revision), "equip owned reward")
			return

func record_turn(details: Dictionary, battle, action: Dictionary, delaying: bool) -> void:
	var state = battle.state
	var actor: String = state.actor()
	var unit: Dictionary = state.units[actor]
	details.full += int(unit.tp == unit.stats.MAX_TP)
	details.empty += int(unit.tp == 0)
	details.delay_turns += int(delaying)
	for skill in battle.commands(actor):
		if battle.calculator.cost(unit, skill).amount > unit.tp:
			details.blocked_skills[skill] = details.blocked_skills.get(skill, 0) + 1
	var forecasts: Array = []
	for id in state.intents:
		var intent: Dictionary = state.intents[id]
		if not intent.done and state.units[id].hp > 0: forecasts.append([id, intent.skill, intent.targets])
	var targets = battle.preview(actor, action.skill, action.target).targets
	details.turns.append([state.round, actor, unit.hp, unit.tp, action.skill, targets, action.cost, forecasts, targets.map(func(id): return [state.units[id].hp, state.units[id].statuses.keys(), state.units[id].guard]), action.value, delaying])

func measure(record: Dictionary, details: Dictionary, party_ids: Array, pool_size: int) -> Dictionary:
	var stats = Simulator.battle_stats(record, party_ids)
	stats.merge(details)
	stats.seed = record.seed
	stats.start = record.start
	stats.end = record.end
	stats.result = record.result.duplicate()
	stats.result.erase("actions")
	stats.natural_unused = 0
	stats.entry_overflow = 0
	stats.inventory_used = {}
	stats.equipment_effects = {}
	stats.ward_prevented_hp = 0
	stats.ward_hits = 0
	stats.hp_timeline = []
	var hp: Dictionary = {}
	var warded: Dictionary = {}
	var tp: Dictionary = stats.carried_tp.duplicate()
	for id in party_ids: hp[id] = record.start.party[id].hp
	for event in record.events:
		match event.type:
			"guard": warded[event.target] = event.skill == "ward"
			"guard_expired", "defeat": warded.erase(event.get("target", event.get("actor", "")))
			"tp_pool_discarded": stats.natural_unused += event.amount
			"item": stats.inventory_used[event.item] = stats.inventory_used.get(event.item, 0) + 1
			"equipment": stats.equipment_effects[event.source] = stats.equipment_effects.get(event.source, 0) + 1
			"damage", "heal":
				if hp.has(event.target):
					if event.type == "damage" and warded.get(event.target, false) and event.sources.any(func(source): return source.source == "stance:guard"):
						var unguarded: float = 0
						for source in event.sources:
							if source.operation == "+": unguarded += source.value
							elif source.source != "stance:guard": unguarded = maxf(0, unguarded) * source.value
						stats.ward_prevented_hp += mini(hp[event.target], maxi(0, floori(unguarded))) - event.amount
						stats.ward_hits += 1
					hp[event.target] += event.amount * (-1 if event.type == "damage" else 1)
					stats.hp_timeline.append([event.sequence, event.round, event.target, hp[event.target], event.source])
			"tp":
				require(event.before == tp[event.target], "TP timeline")
				tp[event.target] = event.after
				if event.source == "recovery:entry": stats.entry_overflow += event.requested - event.amount
	require(hp == stats.hp_end and tp == stats.tp_end, "HP/TP accounting")
	require(stats.natural + stats.natural_unused == pool_size * party_ids.size(), "pool accounting")
	return stats

func compare_position(battle, options: Array, preset: String, node: int) -> Dictionary:
	var source = battle.state
	var values: Array = []
	for option in options:
		if option.item != "": continue
		var branch = BattleEngine.new(battle.catalog)
		branch.state = State.new(battle.catalog, {}, source.battle_seed, {}, [], source.inventory)
		for field in ["units", "order", "intents"]:
			branch.state.set(field, source.get(field).duplicate(true))
		for field in ["round", "round_started", "cursor", "phase", "revision"]:
			branch.state.set(field, source.get(field))
		branch.state.rng.state = source.rng.state
		var actor: String = source.actor()
		require(branch.submit(actor, option.skill, option.target, source.revision, option.item), "branch submit")
		# Complete the current round, then inspect the same start-of-next-round horizon.
		while branch.state.phase != "finished" and branch.state.round == source.round:
			var next = Policy.choose(Policy.options(branch, "conditional", 3 - node), "conditional", null, false)
			require(branch.submit(branch.state.actor(), next.skill, next.target, branch.state.revision, next.item), "branch continuation")
		var result: Dictionary = branch.result()
		var party_hp: int = 0
		var party_tp: int = 0
		for id in battle.catalog.party_ids():
			party_hp += branch.state.units[id].hp
			party_tp += branch.state.units[id].tp
		values.append([option.skill, option.target, option.cost, option.value, result.damage_dealt, result.damage_taken, party_hp, party_tp, branch.state.alive("enemy").size(), branch.state.winner, branch.state.inventory.duplicate(true)])
	return {"preset": preset, "node": node, "round": source.round, "seed": source.battle_seed, "rng_state": str(source.rng.state), "actor": source.actor(), "units": source.units.duplicate(true), "order": source.order.duplicate(), "inventory": source.inventory.duplicate(true), "intents": source.intents.duplicate(true), "alternatives": values}

func probe(catalog, seed_value: int, delay: bool, items: bool) -> Dictionary:
	var battle = BattleEngine.new(catalog)
	var party = {"knight": {"tp": 0}, "mage": {"tp": 0}, "cleric": {"tp": 0}}
	battle.start(catalog.data.presets.sustain, seed_value, party, ["sentinel"], {"potion": 2, "ether": 1} if items else {})
	var steps: int = 0
	var turns: Array = []
	while battle.state.phase != "finished" and steps < 90:
		var options = Policy.options(battle, "conditional", 2)
		var action = Policy.choose(options, "conditional", null, delay and battle.state.round <= 4)
		turns.append([battle.state.round, battle.state.actor(), action.skill, action.target])
		if not require(battle.submit(battle.state.actor(), action.skill, action.target, battle.state.revision, action.item), "probe submit"): break
		steps += 1
	var state = battle.state
	require(state.phase == "finished", "probe step cap")
	var natural: int = 0
	for event in state.events:
		if event.type == "tp" and event.source == "recovery:round": natural += event.amount
	return {"seed": seed_value, "delay": delay, "items": items, "turns": turns, "rounds": state.round, "winner": state.winner, "tp": catalog.party_ids().map(func(id): return state.units[id].tp), "hp": catalog.party_ids().map(func(id): return state.units[id].hp), "inventory": state.inventory, "natural": natural, "damage_taken": battle.result().damage_taken}

func long_fight(catalog, seed_value: int, preset: String) -> Dictionary:
	var trial = Content.new()
	trial.data = catalog.data.duplicate(true)
	trial.data.units.boss.stats.MAX_HP *= 2
	var battle = BattleEngine.new(trial)
	battle.start(trial.data.presets[preset], seed_value, {}, ["boss"], {}, [], [{"source": "recovery:entry", "value": trial.data.rules.tp_recovery.entry}])
	var counts = {"normal": 0, "skills": 0, "empty": 0, "natural": 0}
	for _step in range(180):
		var state = battle.state
		if state.phase == "finished": break
		var actor: String = state.actor()
		var action = Policy.choose(Policy.options(battle, "conditional", 0), "conditional", null, false)
		counts.empty += int(state.units[actor].tp == 0)
		counts.normal += int(action.skill == "attack")
		counts.skills += int(action.skill != "attack")
		if not require(battle.submit(actor, action.skill, action.target, state.revision), "long fight submit"): break
	require(battle.state.phase == "finished", "long fight step cap reached")
	for event in battle.state.events:
		if event.type == "tp" and event.source == "recovery:round": counts.natural += event.amount
	require(counts.natural <= int(trial.data.rules.tp_recovery.pool) * 3, "long fight TP ceiling")
	return {"seed": seed_value, "preset": preset, "rounds": battle.state.round, "winner": battle.state.winner, "counts": counts, "hp": trial.party_ids().map(func(id): return battle.state.units[id].hp), "tp": trial.party_ids().map(func(id): return battle.state.units[id].tp)}
