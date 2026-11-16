extends SceneTree

const Content = preload("res://core/content_catalog.gd")
const Manager = preload("res://core/run_manager.gd")
const Battle = preload("res://core/battle_engine.gd")
const Simulator = preload("res://tests/run_simulator.gd")
var assertions: int = 0
var failures: int = 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var catalog = Content.new()
	check(catalog.errors.is_empty(), "v0.3 content validates")
	var run = Manager.new(catalog)
	run.new_run(42, catalog.data.presets.burst)
	run.state.party.knight.tp = 0
	run.state.party.mage.tp = 4
	run.state.party.cleric.hp = 0
	var revision = run.state.revision
	check(run.start_battle(revision) and not run.start_battle(revision), "entry transition only once")
	var battle = run.battle
	check(battle.state.units.knight.tp == 2 and battle.state.units.mage.tp == 5, "entry +2 and cap")
	check(battle.state.units.cleric.tp == 3, "KO no entry restoration")
	check(battle.state.units.knight.tp_pool == 4, "separate finite battle pool")
	var snapshot = battle.snapshot()
	var random = battle.state.rng.state
	for i in range(20):
		battle.preview("knight", "attack", "warlock")
		battle.begin_round()
	check(battle.snapshot() == snapshot and random == battle.state.rng.state, "R1 re-entry and preview pure")
	battle.state.round = 2
	battle.begin_round()
	check(battle.state.units.knight.tp == 3 and battle.state.units.knight.tp_pool == 3, "R2 restoration spends actual pool")
	check(battle.state.units.mage.tp_pool == 4, "full TP saves pool")
	check(battle.state.units.cleric.tp == 3 and battle.state.units.cleric.tp_pool == 4, "KO no round restore")
	battle.begin_round()
	check(battle.state.units.knight.tp_pool == 3, "same round cannot restore twice")
	for round_value in range(3, 103):
		battle.state.units.knight.tp = 0
		battle.state.round = round_value
		battle.begin_round()
	check(battle.state.units.knight.tp == 0 and battle.state.units.knight.tp_pool == 0, "100-round delay cannot exceed pool")
	var restored = 0
	for event in battle.state.events:
		if event.type == "tp" and event.actor == "knight" and event.source == "recovery:round": restored += event.amount
	check(restored == 4, "logged recovery bounded to capacity")
	for id in battle.state.alive("enemy"): battle.state.units[id].hp = 0
	battle.check_winner()
	check(battle.state.units.mage.tp_pool == 0, "remaining pool discarded on finish")
	check(run.collect_battle(run.state.revision), "end resources imported")
	check(not run.state.party.knight.has("tp_pool"), "pool never enters RunState party")
	# Exercise a fresh battle using the carried TP without invoking future growth yet.
	var next = Battle.new(catalog)
	next.start(run.state.loadout, 1, run.state.party)
	check(next.state.units.knight.tp_pool == 4 and next.state.units.knight.tp == run.state.party.knight.tp, "fresh pool; no hidden entry grant in standalone start")
	check_growth()
	check_edges()
	print("GROWTH RESULT: %d assertions / %d failures" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func fixture(upgrades: Array):
	var battle = Battle.new(Content.new())
	battle.start({"knight":["stone"],"mage":["ember"]}, 42, {}, ["warlock","sentinel"], {}, upgrades)
	return battle

func check_growth() -> void:
	var battle = fixture(["detonate", "ember_hunt"])
	battle.state.units.sentinel.statuses.burn = {"actor":"mage","remaining":2,"source":"test"}
	var snapshot = battle.snapshot()
	var preview = battle.preview("mage", "fireball", "sentinel")
	check(preview.effects[0].kind == "remove_status" and preview.effects[1].source == "growth:detonate", "detonation consumes burn before extra hit")
	check(preview.effects.any(func(e): return e.kind == "damage" and e.sources.any(func(p): return p.source == "growth:ember_hunt")), "first burning strike bonus traced")
	check(battle.snapshot() == snapshot, "growth preview does not consume burn or passive")
	var hp = battle.state.units.sentinel.hp
	battle.execute(preview)
	var expected = preview.effects.filter(func(e): return e.kind == "damage" and e.target == "sentinel").reduce(func(n, e): return n + e.amount, 0)
	check(hp - battle.state.units.sentinel.hp == expected, "growth damage equals actual")
	var again = battle.preview("mage", "fireball", "sentinel")
	check(not again.effects.any(func(e): return e.kind == "growth_trigger"), "passive once per actor per battle")
	battle = fixture(["spread"])
	preview = battle.preview("mage", "fireball", "warlock")
	check(preview.effects.any(func(e): return e.kind == "status" and e.target == "sentinel" and e.source == "growth:spread"), "spread reaches separate living enemy")
	battle.state.units.sentinel.hp = 0
	check(not battle.preview("mage", "fireball", "warlock").effects.any(func(e): return e.source == "growth:spread"), "spread does not target fallen enemy")
	battle = fixture(["riposte", "counter_order"])
	battle.state.units.knight.tp = 0
	battle.execute(battle.preview("knight", "pressure", "warlock"))
	check(battle.state.units.knight.counter_bonus == 10, "personal stance gains extra counter")
	preview = battle.preview("warlock", "attack", "knight")
	check(preview.effects.filter(func(e): return e.kind == "damage" and e.counter).size() == 2, "equipment and growth counters compose without chains")
	check(preview.effects.filter(func(e): return e.kind == "tp" and e.source == "growth:counter_order").size() == 1, "multiple counters grant only one passive TP")
	battle.resolver.apply(battle.state, preview)
	check(battle.state.units.knight.tp == 1, "passive TP grant actual")
	check(not battle.preview("warlock", "attack", "knight").effects.any(func(e): return e.kind == "tp" and e.source == "growth:counter_order"), "counter passive spent")
	var catalog = Content.new()
	var run = Manager.new(catalog)
	run.new_run(42, catalog.data.presets.burst)
	# Complete a real battle, not a synthetic reward transition.
	run.start_battle(run.state.revision)
	while run.battle.state.phase != "finished":
		var action = Simulator.choose_action(run.battle)
		run.battle.submit(run.battle.state.actor(), action.skill, action.target, run.battle.state.revision, action.item)
	run.collect_battle(run.state.revision); run.continue_result(run.state.revision); run.choose_reward(0, run.state.revision)
	check(run.state.level == 2 and run.state.phase == "growth", "normal reward followed by mandatory level choice")
	check(not run.start_battle(run.state.revision), "cannot skip growth")
	var revision = run.state.revision
	check(run.choose_growth(0, revision) and not run.choose_growth(1, revision), "growth selection accepted once")
	for route in [["detonate","ember_hunt"],["riposte","counter_order"],["spread","careful"]]:
		var played = Simulator.play(Content.new(), 42, "sustain" if route[0] == "riposte" else "burst", route)
		check(not played.has("error") and played.outcome == "clear", "four fights complete with growth: " + str(route))
		if played.has("error"): continue
		run = played.run
		check(run.state.level == 4 and run.state.equipment_slots == 3 and run.state.upgrades == route, "one common level, three slots, exactly two choices")
		check(run.state.loadout.values().all(func(slots): return slots.size() == 3), "slot count consistent across party")
		check(not run.choose_growth(0, run.state.revision), "no reselection after completion")
		var repeated = Simulator.play(Content.new(), 42, "sustain" if route[0] == "riposte" else "burst", route)
		check(run.result() == repeated.run.result(), "same seed and choices deterministic with growth")
		run.new_run(42, catalog.data.presets.burst)
		check(run.state.level == 1 and run.state.upgrades.is_empty() and run.state.equipment_slots == 2, "new run removes all growth")

func reach_growth(run) -> void:
	var steps = 0
	while run.state.phase != "growth" and steps < 200:
		steps += 1
		match run.state.phase:
			"ready", "intermission": run.start_battle(run.state.revision)
			"battle":
				if run.battle.state.phase == "finished": run.collect_battle(run.state.revision)
				else:
					var action = Simulator.choose_action(run.battle)
					run.battle.submit(run.battle.state.actor(), action.skill, action.target, run.battle.state.revision, action.item)
			"battle_result": run.continue_result(run.state.revision)
			"reward": run.choose_reward(0, run.state.revision)

func check_edges() -> void:
	var catalog = Content.new()
	catalog.data.rules.tp_recovery.pool = 3
	catalog.data.rules.tp_recovery.round = 2
	var battle = Battle.new(catalog)
	battle.start({}, 42, {"knight": {"hp": 100, "tp": 0}})
	battle.state.round = 2; battle.begin_round()
	check(battle.state.units.knight.tp == 2 and battle.state.units.knight.tp_pool == 1, "configurable rate two, pool three")
	battle.state.round = 3; battle.begin_round()
	check(battle.state.units.knight.tp == 3 and battle.state.units.knight.tp_pool == 0, "partial last pool recovery")
	var run = Manager.new(Content.new())
	run.new_run(42, run.catalog.data.presets.burst)
	run.state.upgrades = ["careful"]
	run.state.party.knight.tp = 0
	run.start_battle(run.state.revision)
	check(run.battle.state.units.knight.tp == 3, "careful adds exactly one entry TP")
	check(run.battle.state.events.any(func(e): return e.type == "tp" and e.actor == "knight" and e.source == "growth:careful" and e.amount == 1), "passive entry grant has source ID")
	var state = run.battle.snapshot()
	for i in range(10): run.battle.begin_round(); run.battle.preview("knight", "attack", "warlock")
	check(state == run.battle.snapshot(), "entry passive cannot replay on redraw/preview")
	run = Manager.new(Content.new()); run.new_run(42, run.catalog.data.presets.burst)
	reach_growth(run); run.choose_growth(0, run.state.revision)
	check(not run.equip("knight", 2, "", run.state.revision), "Lv2 intermission still has only two slots")
	reach_growth(run)
	var gear = run.state.gear.duplicate(true)
	check(not run.equip("knight", 2, "", run.state.revision), "third slot locked before Lv3 confirmation")
	run.choose_growth(0, run.state.revision)
	check(run.state.gear == gear and run.state.loadout.values().all(func(slots): return slots[2] == ""), "slot expansion grants no gear")
	run.choose_event(0, run.state.revision)
	check(not run.equip("knight", 3, "", run.state.revision), "fourth slot rejected")
	for id in run.catalog.data.equipment:
		if run.state.gear.get(id, 0) == 0:
			check(not run.equip("knight", 2, id, run.state.revision), "unowned third-slot gear rejected")
			break
	for id in gear:
		if gear[id] > 0:
			check(run.equip("knight", 2, id, run.state.revision), "owned reward fits third slot")
			check(run.state.gear[id] == gear[id] - 1, "third-slot ownership count conserved")
			break
	battle = fixture(["ember_hunt"])
	battle.state.units.knight.hp = 1
	battle.state.units.warlock.equipment = ["stone"]
	battle.state.units.warlock.statuses.burn = {"actor": "mage", "remaining": 2, "source": "test"}
	var preview = battle.preview("knight", "attack", "warlock")
	battle.resolver.apply(battle.state, preview)
	check(battle.state.units.knight.hp == 0 and "growth:ember_hunt" in battle.state.units.knight.growth_used, "passive right consumed even when counter kills attacker")
	battle.state.units.knight.hp = 10
	check(not battle.preview("knight", "attack", "warlock").effects.any(func(e): return e.kind == "growth_trigger"), "revival cannot repeat first-strike passive")
	var fresh = fixture(["ember_hunt"])
	check(fresh.state.units.knight.growth_used.is_empty(), "new battle resets finite passive rights")
	run = Manager.new(Content.new())
	run.new_run(42, {"knight": ["ring", "crest"], "mage": ["ember", "focus"], "cleric": ["stone", "focus"]})
	run.state.party.knight.tp = 0
	run.start_battle(run.state.revision)
	battle = run.battle
	battle.submit("knight", "attack", "warlock", battle.state.revision)
	check(battle.state.units.knight.tp == 3, "entry then absorption order")
	battle.submit("mage", "item_ether", "knight", battle.state.revision, "ether")
	check(battle.state.units.knight.tp == 5, "finite item clamps after absorption")
	battle.submit("cleric", "attack", "warlock", battle.state.revision)
	check(battle.state.round == 2 and battle.state.units.knight.tp_pool == 4, "full TP at next round does not consume pool")
