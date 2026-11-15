extends SceneTree

const Content = preload("res://core/content_catalog.gd")
const BattleEngine = preload("res://core/battle_engine.gd")
const Visuals = preload("res://ui/visual_catalog.gd")
var failures: int = 0
var assertions: int = 0
var groups: int = 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func group(title: String) -> void:
	groups += 1
	print("TEST %02d  %s" % [groups, title])

func fresh(loadout: Dictionary = {}, seed_value: int = 42):
	var battle = BattleEngine.new(Content.new())
	battle.start(loadout, seed_value)
	return battle

func act(battle, skill: String = "attack", target: String = "warlock") -> bool:
	return battle.submit(battle.state.actor(), skill, target, battle.state.revision)

func auto_play(battle, defensive: bool = false) -> void:
	var safety: int = 0
	while battle.state.phase != "finished" and safety < 350:
		safety += 1
		var actor = battle.state.actor()
		var enemies = battle.state.alive("enemy")
		var skill = "attack"
		var target = str(enemies[0])
		if defensive:
			skill = "guard"
		elif actor == "mage" and battle.state.tp >= 2:
			skill = "fireball"
		elif actor == "cleric" and battle.state.tp >= 2:
			var allies = battle.state.alive("ally")
			allies.sort_custom(func(a, b): return battle.state.units[a].hp < battle.state.units[b].hp)
			if battle.state.units[allies[0]].hp < battle.state.units[allies[0]].stats.MAX_HP - 15:
				skill = "heal"
				target = allies[0]
		var accepted = act(battle, skill, target)
		check(accepted, "automatic battle action accepted")
		if not accepted:
			break
	check(battle.state.phase == "finished", "battle terminates")

func _initialize() -> void:
	group("fixed SPEED order and stable ID ties")
	var b = fresh()
	check(b.state.order == ["knight", "mage", "warlock", "cleric", "sentinel"], "default order")
	b = fresh({"cleric": ["boots", "boots"]})
	check(b.state.order == ["knight", "mage", "cleric", "warlock", "sentinel"], "equipment changes initial order")
	var c = Content.new()
	c.data.units.mage.stats.SPEED = 18
	b = BattleEngine.new(c)
	b.start({}, 42)
	check(b.state.order.slice(0, 2) == ["knight", "mage"], "ties use unit ID")

	group("one action per round, dead unit skip, stale and foreign commands")
	b = fresh()
	check(not b.submit("mage", "attack", "warlock", 0), "non-current actor rejected")
	check(not b.submit("knight", "fireball", "warlock", 0), "foreign skill rejected")
	check(act(b), "first action accepted")
	check(not b.submit("knight", "attack", "warlock", 0), "double input rejected")
	act(b)
	act(b)
	check(b.state.round == 2 and b.state.actor() == "knight", "round wraps")
	var first_actions = b.state.events.filter(func(e): return e.type == "action" and e.round == 1)
	check(first_actions.size() == 5, "exactly five actions in first round")
	b = fresh()
	b.state.units.mage.hp = 0
	act(b)
	check(b.state.actor() == "cleric", "dead ally skipped; enemy advances")
	b.state.units.warlock.hp = 1
	act(b)
	check(b.state.units.warlock.hp == 0, "enemy can be defeated")

	group("TP cost, generation, bounds and illegal input")
	b = fresh({"knight": ["crest", "crest"]})
	check(not act(b, "inspire"), "skill not owned rejected")
	act(b)
	check(b.state.tp == 5, "TP caps at five including equipment")
	act(b, "wave")
	check(b.state.tp == 2, "wave costs three")
	act(b, "heal", "knight")
	check(b.state.tp == 0, "heal costs two")
	var before = b.state.snapshot()
	check(not act(b, "strike"), "insufficient TP rejected")
	check(b.state.snapshot() == before, "rejected input is side effect free")
	act(b, "guard")
	check(b.state.tp == 0, "guard does not generate TP")

	group("prediction equals resolution; previews do not mutate anything")
	b = fresh({"knight": ["ring"], "mage": ["ember"]})
	var unchanged = b.state.snapshot()
	var rng_state = b.state.rng.state
	var definitions = b.catalog.data.duplicate(true)
	for i in range(30):
		b.preview("knight", "strike", "warlock")
		b.preview("mage", "fireball", "warlock")
		b.intent_preview("warlock")
	check(b.state.snapshot() == unchanged and b.state.rng.state == rng_state, "preview leaves state and RNG untouched")
	var prediction = b.preview("knight", "strike", "warlock")
	var old_hp = b.state.units.warlock.hp
	act(b, "strike")
	check(old_hp - b.state.units.warlock.hp == prediction.effects[0].amount, "actual HP loss matches preview")
	check(prediction.effects[0].raw == 26, "base + skill + ring")
	check(b.catalog.data == definitions, "content resources immutable during battle")
	var action = b.state.events.filter(func(e): return e.type == "action")[0]
	check(action.calculation == prediction, "logged calculation identical to preview")

	group("enemy executes disclosed action; no retargeting")
	b = fresh()
	var intent = b.state.intents.warlock.duplicate(true)
	act(b, "guard")
	var recalculated = b.intent_preview("warlock").calculation
	check(recalculated.effects[0].raw == 6, "enemy intent updates after guard")
	act(b, "guard")
	var enemy_action = b.state.events.filter(func(e): return e.type == "action" and e.actor == "warlock")[0]
	check(enemy_action.skill == intent.skill and enemy_action.targets == intent.targets, "enemy obeys forecast")
	check(enemy_action.calculation == recalculated, "enemy uses updated forecast calculation")
	b = fresh()
	b.state.units.knight.hp = 0
	b.state.cursor = 1
	act(b, "guard")
	check(b.state.events.any(func(e): return e.type == "cancel" and e.actor == "warlock"), "dead target cancels action")
	check(b.state.units.mage.hp == 72, "no surprise retarget")

	group("guard multiplication, floor and expiry")
	b = fresh({"knight": ["stone"]})
	act(b, "guard")
	check(b.intent_preview("warlock").calculation.effects[0].raw == 4, "floor(12 × .35) = 4")
	act(b, "guard")
	check(b.state.units.knight.hp == 96, "guard mitigates enemy damage")
	act(b, "guard")
	check(b.state.round == 2 and not b.state.units.knight.guard, "guard expires before own next input")
	check(b.state.units.mage.guard and b.state.units.cleric.guard, "others retain guard until their turn")

	group("modifiers, equipment sources and expiration")
	b = fresh({"mage": ["crest"]})
	act(b, "pressure")
	var decreased = b.intent_preview("warlock").calculation
	check(decreased.effects[0].raw == 9, "pressure reduces enemy POWER")
	check(decreased.effects[0].sources.any(func(s): return s.source == "skill:pressure"), "debuff has source ID")
	act(b)
	check(b.state.units.warlock.modifiers.is_empty(), "debuff expires after next action")
	b.state.tp = 5
	act(b, "inspire")
	check(b.state.units.cleric.modifiers.size() == 1, "self inspire survives casting")
	check(b.preview("knight", "attack", "sentinel").effects[0].raw == 17, "inspire boosts next action")
	act(b, "guard")
	check(b.state.units.knight.modifiers.is_empty(), "guard consumes next-action buff")
	check(b.state.events.any(func(e): return e.type == "equipment" and e.source == "equipment:crest:0" and e.trigger == "effect"), "TP equipment trigger logged")

	group("fixed seed burn, timing and duration")
	var burn_runs: Array = []
	for i in range(2):
		b = fresh({"mage": ["ember"]}, 777)
		act(b)
		var fire_preview = b.preview("mage", "fireball", "sentinel")
		check(is_equal_approx(fire_preview.effects[1].chance, 0.75), "ember adds 15 percentage points")
		act(b, "fireball", "sentinel")
		burn_runs.append(b.state.events.filter(func(e): return e.type == "status"))
	check(burn_runs[0] == burn_runs[1], "same seed reproduces identical rolls")
	b = fresh()
	b.state.units.sentinel.statuses.burn = {"remaining": 2, "actor": "mage", "source": "skill:fireball"}
	b.state.units.sentinel.guard = true
	b.resolver.round_end(b.state)
	check(b.state.units.sentinel.hp == 106 and b.state.units.sentinel.statuses.burn.remaining == 1, "burn ignores guard and ticks at round end")
	b.resolver.round_end(b.state)
	check(b.state.units.sentinel.hp == 102 and b.state.units.sentinel.statuses.is_empty(), "burn expires after two ticks")

	group("charged AoE has a full prior-round warning")
	b = fresh()
	for i in range(3): act(b, "guard")
	check(b.state.round == 2 and b.state.intents.warlock.skill == "charge", "round two warns charge")
	act(b, "guard")
	act(b, "guard")
	check(b.state.units.warlock.charged, "charge executes")
	act(b, "guard")
	check(b.state.round == 3 and b.state.intents.warlock.skill == "nova", "next round discloses AoE")
	check(b.state.intents.warlock.targets.size() == 3, "AoE target list fixed at round start")

	group("full victory, result/log agreement and action uniqueness")
	b = fresh({"knight": ["ring", "boots"], "mage": ["ember", "ring"], "cleric": ["crest", "stone"]})
	auto_play(b)
	check(b.state.winner == "ally", "offensive build wins")
	var result = b.result()
	var dealt: int = 0
	var taken: int = 0
	var healing: int = 0
	var seen: Dictionary = {}
	for event in b.state.events:
		if event.type == "damage":
			if b.state.units[event.actor].team == "ally": dealt += event.amount
			if b.state.units[event.target].team == "ally": taken += event.amount
		if event.type == "heal": healing += event.amount
		if event.type == "action":
			var key = "%d:%s" % [event.round, event.actor]
			check(not seen.has(key), "at most one action per unit/round")
			seen[key] = true
	check(result.damage_dealt == dealt and result.damage_taken == taken and result.healing == healing, "result derived from events")
	check(not act(b), "finished battle rejects input")
	for unit in b.state.units.values():
		check(unit.hp >= 0 and unit.hp <= unit.stats.MAX_HP, "HP within limits")
	print("  Offensive: ", result.rounds, " rounds / damage taken ", result.damage_taken)

	group("second build, defeat flow and clean retry")
	var offense = fresh({"knight": ["ring", "boots"], "mage": ["ember", "ring"]})
	var defense = fresh({"knight": ["amulet", "stone"]})
	check(offense.preview("knight", "attack", "warlock").effects[0].raw == 18 and defense.preview("knight", "attack", "warlock").effects[0].raw == 15, "builds change offensive damage")
	check(defense.state.units.knight.hp == 112 and offense.state.units.knight.hp == 100, "builds change survival capacity")
	act(offense, "guard")
	act(defense, "guard")
	check(offense.intent_preview("warlock").calculation.effects[0].raw == 6 and defense.intent_preview("warlock").calculation.effects[0].raw == 4, "defensive build mitigates more")
	b = fresh({"knight": ["amulet", "stone"], "mage": ["amulet", "stone"], "cleric": ["crest", "stone"]})
	auto_play(b)
	check(b.state.winner == "ally", "defensive build also playable")
	print("  Defensive: ", b.result().rounds, " rounds / damage taken ", b.result().damage_taken)
	b = fresh()
	auto_play(b, true)
	check(b.state.winner == "enemy", "defeat path completes")
	b.start({}, 42)
	var new_battle = fresh()
	check(b.state.snapshot() == new_battle.state.snapshot(), "retry resets every field including events and statuses")
	check(b.state.rng.state == new_battle.state.rng.state, "retry resets RNG")

	group("healing cap, missing assets and definition extensibility")
	b = fresh()
	b.state.units.knight.hp = 95
	var heal = b.preview("cleric", "heal", "knight")
	check(heal.effects[0].amount == 5 and heal.effects[0].raw == 21, "healing capped to missing HP")
	var v = Visuals.new()
	check(v.texture("") == null and v.texture("res://missing.png") == null, "missing assets have fallback")
	c = Content.new()
	c.data.stats.append("TEST_NUMBER")
	c.data.units.knight.stats.TEST_NUMBER = 7
	c.data.units.knight.stats.POWER = 20
	b = BattleEngine.new(c)
	b.start({}, 42)
	check(b.state.units.knight.stats.TEST_NUMBER == 7, "new numeric stat retained")
	check(b.preview("knight", "attack", "warlock").effects[0].raw == 20, "POWER definition changes need no UI or rule edits")
	print("RESULT: %d groups / %d assertions / %d failures" % [groups, assertions, failures])
	quit(0 if failures == 0 else 1)
