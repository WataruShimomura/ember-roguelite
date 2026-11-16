extends SceneTree

const Content = preload("res://core/content_catalog.gd")
const BattleEngine = preload("res://core/battle_engine.gd")
const RunManager = preload("res://core/run_manager.gd")
var failures: int = 0
var assertions: int = 0
var groups: int = 0
var summaries: Array = []

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func group(title: String) -> void:
	groups += 1
	print("TEST %02d  %s" % [groups, title])

func fresh(loadout: Dictionary = {}, party: Dictionary = {}, inventory: Dictionary = {}):
	var b = BattleEngine.new(Content.new())
	b.start(loadout, 42, party, ["warlock", "sentinel"], inventory)
	return b

func act(b, skill: String = "attack", target: String = "warlock", item: String = "") -> bool:
	return b.submit(b.state.actor(), skill, target, b.state.revision, item)

func raw_damage(b, target: String, value: int, actor: String = "knight") -> Array:
	var effects: Array = []
	b.calculator.append_damage(b.state.units.duplicate(true), effects, actor, target, value, [{"source":"test","operation":"+","value":value}], "test")
	b.resolver.apply(b.state, {"skill":"attack","effects":effects})
	return effects

func play_battle(b, mode: String = "burst") -> void:
	var safety: int = 0
	while b.state.phase != "finished" and safety < 500:
		safety += 1
		var actor = b.state.actor()
		var target = str(b.state.alive("enemy")[0])
		var skill = "attack"
		var item = ""
		var allies = b.state.alive("ally")
		allies.sort_custom(func(a, z): return b.state.units[a].hp < b.state.units[z].hp)
		var weakest = allies[0]
		if b.state.units[weakest].hp < 30 and b.state.inventory.get("potion", 0) > 0:
			skill = "item_potion"; item = "potion"; target = weakest
		elif actor == "cleric" and b.state.units[weakest].hp < b.state.units[weakest].stats.MAX_HP - 22 and b.state.units[actor].tp >= b.calculator.cost(b.state.units[actor], "heal").amount:
			skill = "heal"; target = weakest
		elif mode == "burst" and actor == "mage" and b.state.units[actor].tp >= b.calculator.cost(b.state.units[actor], "fireball").amount:
			skill = "fireball"
		elif actor == "knight" and b.state.units[actor].tp >= b.calculator.cost(b.state.units[actor], "pressure").amount:
			if mode == "sustain" and b.state.intents.values().any(func(i): return i.skill == "nova"):
				skill = "pressure"
			elif mode == "burst": skill = "strike"
			if b.state.units[actor].tp < b.calculator.cost(b.state.units[actor], skill).amount: skill = "attack"
		var ok = act(b, skill, target, item)
		check(ok, "automated action accepted")
		if not ok: break
	check(b.state.phase == "finished", "battle terminates")

func play_run(seed_value: int, mode: String = "burst"):
	var r = RunManager.new(Content.new())
	r.new_run(seed_value, r.catalog.data.presets[mode])
	var safety: int = 0
	while r.state.phase != "finished" and safety < 40:
		safety += 1
		match r.state.phase:
			"ready", "intermission": check(r.start_battle(r.state.revision), "start run battle")
			"battle":
				play_battle(r.battle, mode)
				check(r.collect_battle(r.state.revision), "collect battle exactly once")
			"battle_result": check(r.continue_result(r.state.revision), "continue result")
			"reward": check(r.choose_reward(2, r.state.revision), "select finite recovery reward")
			"event": check(r.choose_event(0, r.state.revision), "finite event")
	check(r.state.phase == "finished", "run ends")
	return r

func _initialize() -> void:
	group("definitions validate and unknown IDs/effect types report errors")
	var c = Content.new()
	check(c.errors.is_empty(), "all definitions valid")
	c.data.skills.attack.effects[0].kind = "unknown"
	check(c.validate().any(func(e): return "Unknown effect" in e), "unknown effect rejected")
	c = Content.new()
	c.data.units.knight.skills.append("missing")
	check(not c.validate().is_empty(), "invalid skill reference rejected")

	group("fixed order, ties, one action per round and stale input")
	var b = fresh()
	check(b.state.order == ["knight", "mage", "warlock", "cleric", "sentinel"], "descending SPEED")
	check(not b.submit("mage", "attack", "warlock", 0), "foreign actor rejected")
	check(not act(b, "wave"), "foreign skill rejected")
	check(act(b), "action accepted")
	check(not b.submit("knight", "attack", "warlock", 0), "double input rejected")
	act(b); act(b)
	check(b.state.round == 2, "round wraps")
	check(b.state.events.filter(func(e): return e.type == "action" and e.round == 1).size() == 5, "once per unit")
	c = Content.new(); c.data.units.mage.stats.SPEED = 18
	b = BattleEngine.new(c); b.start({})
	check(b.state.order.slice(0, 2) == ["knight", "mage"], "stable ID tie")

	group("personal TP, no common guard and no free attack TP")
	b = fresh()
	check(b.state.units.knight.tp == 3 and b.state.units.mage.tp == 3, "initial personal TP")
	check(not b.commands("knight").has("guard") and not b.commands("mage").has("guard"), "no common guard")
	check(not act(b, "guard"), "guard cannot be submitted")
	act(b, "strike")
	check(b.state.units.knight.tp == 1 and b.state.units.mage.tp == 3, "only actor pays")
	act(b)
	check(b.state.units.mage.tp == 3, "ordinary attack generates no unconditional TP")
	b = fresh({}, {"knight":{"hp":100,"tp":0}})
	var before = b.snapshot()
	check(not act(b, "strike") and b.snapshot() == before, "insufficient TP has no side effects")
	check(act(b), "TP zero normal attack works")

	group("preview purity and exact logged execution")
	b = fresh({"knight":["chalice","crest"]}, {"knight":{"hp":40,"tp":1}})
	var snapshot = b.snapshot(); var rng = b.state.rng.state; var definitions = b.catalog.data.duplicate(true)
	var p = b.preview("knight", "attack", "warlock")
	for i in range(40):
		b.preview("knight", "attack", "warlock"); b.intent_preview("warlock")
	check(b.snapshot() == snapshot and b.state.rng.state == rng and b.catalog.data == definitions, "preview changes no state/RNG/definitions")
	act(b)
	var logged = b.state.events.filter(func(e): return e.type == "action")[0]
	check(logged.calculation == p, "same calculation used by execution")
	check(b.state.units.warlock.hp == 50 - p.effects[0].amount, "predicted actual damage")
	check(b.state.units.knight.hp == 44, "predicted HP siphon")
	b = fresh({"knight":["crest","focus"]}, {"knight":{"hp":100,"tp":5}})
	p = b.preview("knight", "strike", "warlock")
	act(b, "strike")
	check(b.state.units.knight.tp == 5 and p.cost == 1 and p.effects[-1].amount == 1, "TP siphon projected after own cost, cap matches execution")

	group("low-water 100->60 / heal80->50 / ->20 and overkill")
	b = fresh({"knight":["chalice","crest"]}, {"knight":{"hp":10,"tp":0}})
	b.state.units.sentinel.hp = 100; b.state.units.sentinel.low_water = 100
	var effects = raw_damage(b, "sentinel", 40)
	check(effects[0].credit == 40 and b.state.units.knight.hp == 22 and b.state.units.knight.tp == 2, "40 credit feeds HP and TP")
	b.state.units.sentinel.hp = 80
	effects = raw_damage(b, "sentinel", 30)
	check(effects[0].credit == 10 and b.state.units.sentinel.low_water == 50, "re-healed HP earns no second credit")
	effects = raw_damage(b, "sentinel", 30)
	check(effects[0].credit == 30 and b.state.units.sentinel.low_water == 20, "new 30 credit")
	b.state.units.sentinel.hp = 1; b.state.units.sentinel.low_water = 1
	effects = raw_damage(b, "sentinel", 999)
	check(effects[0].amount == 1 and effects[0].credit == 1, "overkill limited to one real HP")

	group("multiple siphons reuse single credit and floor separately")
	b = fresh({"knight":["chalice","chalice"]}, {"knight":{"hp":10,"tp":0}})
	var e = raw_damage(b, "sentinel", 19)
	check(e.size() == 3 and e[1].credit == 19 and e[2].credit == 19, "both reference same credit")
	check(e[1].amount == 5 and e[2].amount == 5 and b.state.units.knight.hp == 20, "floor per effect")

	group("enemy healing and HP/TP conversion cannot create infinite resources")
	b = fresh({"knight":["chalice","crest"]}, {"knight":{"hp":10,"tp":0}})
	raw_damage(b, "sentinel", 20)
	var hp = b.state.units.knight.hp; var tp = b.state.units.knight.tp
	for i in range(100):
		b.state.units.sentinel.hp += 20
		var repeated = raw_damage(b, "sentinel", 20)
		check(repeated[0].credit == 0, "no healed-HP credit")
	check(b.state.units.knight.hp == hp and b.state.units.knight.tp == tp, "100 heal/re-damage cycles yield no resources")
	b.state.units.sentinel.hp = 1; b.state.units.sentinel.low_water = 0
	e = raw_damage(b, "sentinel", 1)
	check(e[0].credit == 0, "resurrected/reused enemy identity does not reset low-water")
	check(b.catalog.data.skills.heal.cost > 0 and b.calculator.cost(b.state.units.knight, "heal").amount >= 1, "HP recovery never becomes zero TP")

	group("counter prevention and defensive skill timing")
	b = fresh({"knight":["stone","stone"], "warlock":["stone"]})
	p = b.preview("warlock", "attack", "knight")
	var damage = p.effects.filter(func(f): return f.kind == "damage")
	check(damage.size() == 3, "two counters only; no recursive counter on counter")
	check(damage[0].raw == 7, "multiplicative mitigation floor")
	b.resolver.apply(b.state, p)
	check(b.state.units.knight.hp == 93, "counter calculation applies exact incoming damage")
	b = fresh()
	act(b, "pressure")
	check(b.state.units.knight.guard, "knight individual skill creates stance")
	p = b.intent_preview("warlock").calculation
	check(p.effects[0].raw == 4, "pressure + stance updates intent")
	act(b); act(b)
	check(not b.state.units.knight.guard, "stance expires at next own turn")

	group("burn budget, fixed seed and expiry")
	var rolls: Array = []
	for i in range(2):
		b = fresh({"mage":["ember"]})
		act(b)
		p = b.preview("mage", "fireball", "sentinel")
		check(is_equal_approx(p.effects[-1].chance, .75), "burn chance includes equipment")
		act(b, "fireball", "sentinel")
		rolls.append(b.state.events.filter(func(x): return x.type == "status"))
	check(rolls[0] == rolls[1], "fixed seed repeats status rolls")
	b = fresh({"knight":["chalice","crest"]}, {"knight":{"hp":10,"tp":0}})
	b.state.units.sentinel.statuses.burn = {"remaining":2,"actor":"knight","source":"skill:fireball"}
	b.resolver.round_end(b.state); b.resolver.round_end(b.state)
	check(b.state.units.sentinel.hp == 67 and b.state.units.sentinel.statuses.is_empty(), "burn 4 x 2 then expiry")
	check(b.state.units.sentinel.low_water == 67 and b.state.units.knight.hp == 12, "DoT consumes same finite credit with per-tick floor")

	group("finite items, revive and stale use")
	b = fresh({}, {"mage":{"hp":0,"tp":1}}, {"potion":1,"ether":1,"revive":1})
	check(not act(b, "item_potion", "mage", "potion"), "ordinary healing cannot resurrect")
	check(act(b, "item_revive", "mage", "revive"), "explicit revive accepted")
	check(b.state.units.mage.hp == 25 and b.state.inventory.revive == 0 and b.state.actor() == "mage", "revive consumes item and user turn")
	check(not act(b, "item_revive", "mage", "revive"), "empty item rejected")
	check(act(b, "item_ether", "knight", "ether"), "TP item usable on another ally")
	check(b.state.units.knight.tp == 5 and b.state.units.mage.tp == 1, "TP caps per recipient; other TP unchanged")

	group("forecast cancellation and advance dead unit")
	b = fresh({}, {"knight":{"hp":0,"tp":3}})
	check(b.state.actor() == "mage", "fallen ally skipped")
	b.state.units.mage.hp = 0
	act(b) # Current command is invalidated by death in a fixture; advance explicitly below.
	b = fresh()
	var intent = b.state.intents.warlock.duplicate(true)
	b.state.units.knight.hp = 0
	b.state.cursor = 1
	act(b)
	check(b.state.events.any(func(x): return x.type == "cancel" and x.actor == "warlock"), "no retarget after target death")
	check(intent.targets == ["knight"] and b.state.units.mage.hp == 72, "no hidden alternate target")

	group("charged AoE gives full prior-round opportunity")
	b = fresh()
	# Keep foes alive by healing fixtures; verify policy independently of combat balance.
	b.state.round = 2; b.begin_round()
	check(b.state.intents.warlock.skill == "charge", "R2 prepare")
	b.execute(b.calculator.calculate(b.state, "warlock", "charge", ["warlock"]))
	b.state.round = 3; b.begin_round()
	check(b.state.intents.warlock.skill == "nova" and b.state.intents.warlock.targets.size() == 3, "R3 fixed AoE targets")

	group("carry resources, clear statuses, import once")
	var r = RunManager.new(Content.new())
	check(r.new_run(42, r.catalog.data.presets.sustain), "run initialized")
	r.start_battle(r.state.revision); play_battle(r.battle, "sustain")
	var end = r.battle.snapshot(); var rev = r.state.revision
	check(r.collect_battle(rev) and not r.collect_battle(rev), "battle imports once")
	check(r.state.party.knight.hp == end.units.knight.hp and r.state.party.mage.tp == end.units.mage.tp, "HP/TP copied once")
	r.continue_result(r.state.revision); r.choose_reward(0, r.state.revision)
	var carry = r.state.party.duplicate(true)
	r.start_battle(r.state.revision)
	check(r.battle.state.units.knight.hp == carry.knight.hp and r.battle.state.units.mage.tp == carry.mage.tp, "next battle no full refill")
	check(r.battle.state.units.values().all(func(u): return u.statuses.is_empty() and u.modifiers.is_empty() and not u.guard), "battle-local state reset")

	group("equipment maxima clamp only, no resurrection/refill")
	r = RunManager.new(Content.new()); r.new_run(42, r.catalog.data.presets.burst)
	r.state.gear.reservoir = 1; r.state.gear.amulet = 1
	r.state.party.knight.hp = 20; r.state.party.knight.tp = 1
	r.equip("knight", 0, "reservoir", r.state.revision)
	check(r.state.party.knight.tp == 1 and r.state.party.knight.stats.MAX_TP == 8 and r.state.party.knight.hp == 20, "maxima increase does not refill")
	r.state.party.knight.tp = 8
	r.equip("knight", 0, "amulet", r.state.revision)
	check(r.state.party.knight.tp == 5, "decreased MAX_TP clamps current")
	r.state.party.knight.hp = 0
	r.equip("knight", 0, "reservoir", r.state.revision)
	check(r.state.party.knight.hp == 0, "equipment never revives")
	check(not r.equip("knight", 0, "missing", r.state.revision), "unknown/unowned gear rejected")
	r.state.party.knight.hp = 112; r.state.gear.edge = 1
	r.equip("knight", 0, "edge", r.state.revision)
	check(r.state.party.knight.hp == 90, "decreased MAX_HP clamps current HP")

	group("three rewards, finite event, item capacity and double choice")
	r = RunManager.new(Content.new()); r.new_run(42, r.catalog.data.presets.burst)
	r.start_battle(r.state.revision); play_battle(r.battle); r.collect_battle(r.state.revision); r.continue_result(r.state.revision)
	check(r.state.offers.size() == 3, "three reward categories")
	rev = r.state.revision
	check(r.choose_reward(0, rev) and not r.choose_reward(0, rev), "reward cannot double claim")
	check(not r.choose_event(0, r.state.revision), "event unavailable out of phase")
	r.state.inventory.potion = 3
	check(not r.can_add_item("potion", 1), "item stack has finite capacity")
	r.start_battle(r.state.revision); play_battle(r.battle); r.collect_battle(r.state.revision); r.continue_result(r.state.revision); r.choose_reward(2, r.state.revision)
	check(r.state.phase == "event", "event after second normal encounter")
	rev = r.state.revision
	check(r.choose_event(1, rev) and not r.choose_event(1, rev), "event finite choice")

	group("two complete builds, results and deterministic runs")
	for mode in ["burst", "sustain"]:
		r = play_run(42, mode)
		check(r.state.outcome == "clear" and r.state.battles.size() == 4, "build completes four fights: " + mode)
		var summary = {"build":mode,"outcome":r.state.outcome,"party":r.state.party,"battles":r.state.battles.map(func(x): return {"encounter":x.encounter,"rounds":x.result.rounds,"start":x.start.party,"end":x.end.party,"actions":x.result.actions.map(func(a): return a.skill)})}
		summaries.append(summary)
		var repeated = play_run(42, mode)
		check(r.result() == repeated.result(), "same seed + choices reproduce full logs")
		check(r.result().total.damage_dealt == r.state.battles.reduce(func(total, x): return total + x.result.damage_dealt, 0), "run totals derived from battle events")
		print("BUILD ", mode, " ", r.state.outcome, " / total rounds ", r.result().total.rounds, " / final ", r.state.party)
	var variations: Dictionary = {}
	for seed_value in range(12):
		r = RunManager.new(Content.new()); r.new_run(seed_value, r.catalog.data.presets.burst)
		variations[str(r.state.route)] = true
	check(variations.size() > 1, "different seeds vary encounters")
	var reward_variations: Dictionary = {}
	for seed_value in range(8):
		r = RunManager.new(Content.new()); r.new_run(seed_value, r.catalog.data.presets.burst)
		# Offer generation is tested after its legitimate predecessor state.
		r.start_battle(r.state.revision); play_battle(r.battle); r.collect_battle(r.state.revision)
		var control = r.reward_rng.state
		for i in range(20): r.battle.preview("knight", "attack", r.battle.state.order[-1])
		check(control == r.reward_rng.state, "battle preview cannot consume reward randomness")
		r.continue_result(r.state.revision)
		reward_variations[str(r.state.offers)] = true
	check(reward_variations.size() > 1, "different seeds vary rewards")

	group("defeat, finish rejection, retry resets every run resource")
	r = RunManager.new(Content.new()); r.new_run(42, r.catalog.data.presets.burst)
	for unit in r.state.party.values(): unit.hp = 0
	r.start_battle(r.state.revision)
	check(r.battle.state.winner == "enemy", "fallen party loses immediately")
	for unit in r.battle.state.units.values(): unit.hp = 0
	r.battle.check_winner()
	check(r.battle.state.winner == "enemy", "simultaneous wipe is a player defeat")
	r.collect_battle(r.state.revision); r.continue_result(r.state.revision)
	check(r.state.outcome == "defeat" and not r.start_battle(r.state.revision), "defeat terminates adventure")
	r.new_run(42, r.catalog.data.presets.burst)
	var clean = RunManager.new(Content.new()); clean.new_run(42, clean.catalog.data.presets.burst)
	check(r.snapshot() == clean.snapshot(), "retry resets state/log/gear/items/route")

	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	var file = FileAccess.open("res://tests/artifacts/build_runs.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(summaries, "\t")); file.close()
	print("RESULT: %d groups / %d assertions / %d failures" % [groups, assertions, failures])
	quit(0 if failures == 0 else 1)
