extends SceneTree

const Catalog = preload("res://combat_core_v1/catalog.gd")
const Battle = preload("res://combat_core_v1/battle.gd")
const Effects = preload("res://combat_core_v1/effects.gd")
const Route = preload("res://combat_core_v1/route.gd")
const Fixtures = preload("res://combat_core_v1/fixtures.gd")
const Policy = preload("res://combat_core_v1/policy.gd")
const BASE = "c21c5bc4d42ff83602d2f74bd4d5f18c1678eed5"
const INSTRUCTIONS = "37ae0259ef66118069c2c2957db64af16b67838d"
var checks: int = 0
var failures: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	var quick: bool = OS.get_cmdline_user_args().has("--quick")
	var off_only: bool = OS.get_cmdline_user_args().has("--off")
	var policies = ["rush", "read", "reserve"] if quick else Policy.STYLES
	var seeds = range(42, 45) if quick else range(42, 52)
	var output = {"base": BASE, "instructions": INSTRUCTIONS, "engine": Engine.get_version_info().string, "runs": [], "direct": [], "situations": [], "stall": [], "ablation": []}
	check_rules()
	for seed_value in seeds:
		for mode in Catalog.MODES:
			for path in Catalog.data.growth.paths.keys() if mode in ["U2","U3"] else ["standard"]:
				for style in policies:
					output.runs.append(play(seed_value, mode, path, style, not off_only))
					if not quick and not off_only and style in ["rush","read","reserve"]:
						output.direct.append(direct(seed_value, mode, path, style))
		print("SEED ", seed_value, " done")
	if not quick:
		for mode in [false,true]:
			output.stall.append(stall(mode, false))
			output.stall.append(stall(mode, true))
		output.situations = situations()
		output.ablation = ablation()
	output.checks = checks
	output.failures = failures
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	var filename = "quick" if quick else ("off" if off_only else "full")
	var file = FileAccess.open("res://tests/artifacts/combat_core_%s.json" % filename, FileAccess.WRITE)
	if file == null:
		printerr("FAIL: cannot save tests")
		quit(1)
		return
	file.store_string(JSON.stringify(output))
	file.close()
	print("COMBAT CORE: %d routes / %d direct / %d checks / %d failures" % [output.runs.size(), output.direct.size(), checks, failures])
	quit(0 if failures == 0 else 1)

func move(actor: String, skill: String, target: String) -> Dictionary:
	return {"actor": actor, "skill": skill, "target": target}

func check_rules() -> void:
	for id in Catalog.PARTY:
		check(Catalog.data.allies[id].skills.size() == 6, "six candidates " + id)
		for build in Catalog.data.builds:
			var slots: Array = Catalog.data.builds[build][id]
			check(slots.size() == 4 and slots.all(func(skill): return skill in Catalog.data.allies[id].skills), "four defined slots")
	var b = Fixtures.make("F1", 42, 18, "standard", true)
	var initial: Dictionary = b.s.duplicate(true)
	check(b.s.order == ["blade","mage","warden","caster","shield"], "speed order")
	check(not b.submit(move("blade","combo","caster"), 0), "unselected skill rejected")
	var a = move("blade","taunt","caster")
	var expected: Array = b.preview(a)
	check(expected.size() >= 2 and b.s == initial, "preview is pure")
	check(b.submit(a, 0) and b.events.slice(1) == expected, "player preview matches execution")
	check(not b.submit(a, 0), "stale input rejected")
	check(b.s.intents.caster.target == "blade", "taunt actually moves forecast")
	check(b.submit(move("mage","dampen","caster"), b.s.revision), "dampen available")
	var forecast: Array = b.intent_preview("caster")
	var damage: Array = forecast.filter(func(e): return e.event == "damage")
	check(damage.size() == 1 and damage[0].target == "blade" and damage[0].amount == 30, "enemy forecast contains exact changed impact")
	var first: int = b.events.size()
	b.submit(move("warden","attack","shield"), b.s.revision)
	check(b.events.slice(first).has(damage[0]), "forecast agrees with resolved enemy action")
	for enabled in [false,true]:
		b = Fixtures.make("F2", 42, 18, "standard", enabled, 1)
		Effects.damage(b, "blade", "shield", 33, "probe", false)
		check(b.s.units.blade.tp == (22 if enabled else 18), "two new thresholds")
		Effects.heal(b, "caster", "shield", 33, "probe")
		Effects.damage(b, "blade", "shield", 33, "probe", false)
		check(b.s.units.blade.tp == (22 if enabled else 18), "recovery cannot restore thresholds")
		b.s.units.mage.hp = 0
		b.s.units.blade.tp = 30
		Effects.damage(b, "blade", "shield", 1000, "probe", false)
		check(b.s.units.shield.cutoffs.is_empty() and b.s.units.blade.tp == 30 and b.s.units.mage.tp == (22 if enabled else 18), "overkill pays once; dead excluded; cap enforced")
	b = Fixtures.make("F1", 42, 0, "standard", true)
	check(not b.usable("blade","interrupt") and b.usable("mage","dampen") and b.usable("warden","split"), "zero TP roles and costs")
	check(b.submit(move("blade","attack","shield"),0) and b.submit(move("mage","dampen","caster"),1) and b.submit(move("warden","split","mage"),2) and b.s.units.mage.hp == 7, "free dampen plus split survives lethal F1")
	b = Fixtures.make("F1", 42, 18, "standard", true)
	check(b.submit(move("blade","break","shield"),0) and b.submit(move("mage","dampen","caster"),1) and b.submit(move("warden","cover","mage"),2) and b.s.units.mage.hp == 22 and b.s.units.warden.hp == 93, "another answer to F1: cover")
	b = Battle.new()
	b.start(2,42,Catalog.initial_party(),Catalog.data.builds.sustain,{"mage":"glove"},1,true,{"states":{"boss":{"burn":1}},"intents":{"boss":{"kind":"sweep","target":"all","power":41,"ritual":true}}})
	b.submit(move("blade","attack","shield"),0)
	var no_glove = b.copy()
	no_glove.s.units.mage.gear = "standard"
	var burst = move("mage","detonate","boss")
	var geared: Array = b.preview(burst)
	check(geared.any(func(e): return e.event == "gear" and e.source == "glove") and not no_glove.preview(burst).any(func(e): return e.event == "gear"), "ablation removes actual spread")
	check(b.submit(burst,1) and b.exposed("boss") and b.s.units.shield.burn == 2, "last burn propagates with enough duration to reach the next turn")
	check(b.intent_preview("boss").any(func(e): return e.event == "enemy" and e.amount == 25), "exposure changes forecast for second threat")
	b.submit(move("warden","attack","shield"),2)
	check(b.s.units.mage.hp == 50, "second threat executes at preview strength")
	b = Battle.new()
	b.start(2,42,Catalog.initial_party(),Catalog.data.builds.counter,{"warden":"mail"},1,true,{"intents":{"boss":{"kind":"heavy","target":"mage","power":48}}})
	b.submit(move("blade","attack","shield"),0)
	b.submit(move("mage","dampen","boss"),1)
	b.submit(move("warden","cover","mage"),2)
	check(b.s.units.warden.reward == 14 and b.events.any(func(e): return e.source == "mail"), "actual covered hit banks exactly one retaliation boost")
	var route = Route.new()
	check(route.exchange("blade",0,"combo") and not route.exchange("blade",1,"combo"), "exchange and duplicate validation")
	check(route.start() and not route.exchange("blade",0,"slashes"), "combat loadout immutable")

func run_battle(b, style: String) -> Array:
	var turns: Array = []
	var delay_count: int = 0
	for _step in range(180):
		if not b.s.outcome.is_empty(): break
		var actor: String = b.actor()
		var enemies: Array = b.live(b.s.enemies)
		var waiting: bool = style == "delay" and enemies.size() == 1 and b.s.units[enemies[0]].hp * 4 <= b.s.units[enemies[0]].max and delay_count < 9
		if waiting: delay_count += 1
		var a: Dictionary = Policy.select(b, "read" if style == "delay" else style, waiting)
		if a.is_empty():
			check(false, "legal move exists")
			break
		var unit: Dictionary = b.s.units[actor]
		turns.append([b.s.round, actor, unit.hp, unit.tp, a.skill, a.target, waiting])
		if not b.submit(a, b.s.revision):
			check(false, "selected move accepted")
			break
	check(not b.s.outcome.is_empty(), "battle reaches outcome within evaluation cap")
	return turns

func values(b) -> Dictionary:
	var out: Dictionary = {}
	for id in Catalog.PARTY:
		var unit: Dictionary = b.s.units[id]
		out[id] = {"hp":unit.hp,"tp":unit.tp,"max":unit.max,"power":unit.power}
	return out

func play(seed_value: int, mode: String, path: String, style: String, thresholds: bool) -> Dictionary:
	var route = Route.new(seed_value, mode, thresholds)
	for node in range(3):
		check(route.start(), "start route encounter")
		var turns: Array = run_battle(route.battle, style)
		check(route.collect(), "collect route encounter")
		var row: Dictionary = route.history[-1]
		row.turns = turns
		row.outgoing = route.party.duplicate(true)
		if route.phase != "camp": break
		Policy.camp(route, style)
		check(route.grow(path), "advance with exactly one growth choice")
		check(not route.grow(path), "growth cannot be replayed")
		row.outgoing = route.party.duplicate(true)
	return {"seed":seed_value,"mode":mode,"path":path,"style":style,"thresholds":thresholds,"battles":route.history}

func direct(seed_value: int, mode: String, path: String, style: String) -> Dictionary:
	var battle = Battle.new()
	var party: Dictionary = Catalog.initial_party(3 if mode in ["U1","U3"] else 1)
	var tactical: bool = mode in ["U2","U3"]
	battle.start(2, seed_value + 1994, party, Catalog.data.builds[path if tactical else "standard"], Fixtures.gears(path) if tactical else {}, int(Catalog.data.rules.start_kits), true)
	var turns = run_battle(battle, style)
	return {"seed":seed_value,"mode":mode,"path":path,"style":style,"start":party,"end":values(battle),"outcome":battle.s.outcome,"round":battle.s.round,"turn_count":turns.size()}

func stall(thresholds: bool, delayed: bool) -> Dictionary:
	var b = Fixtures.make("F4", 42, 18, "standard", thresholds)
	if delayed:
		for _round in range(3):
			b.submit(move("blade","taunt","shield"), b.s.revision)
			b.submit(move("mage","dampen","shield"), b.s.revision)
			var spell = "aid" if b.usable("warden","aid") else "split"
			b.submit(move("warden",spell,"mage"), b.s.revision)
	b.submit(move("blade","attack","shield"), b.s.revision)
	check(b.s.outcome == "clear", "stall probe resolves")
	if not delayed: check(b.care("warden","aid","mage"), "same treatment available after immediate kill")
	check(not b.care("warden","aid","mage"), "once per battle including camp")
	check(not b.events.any(func(e): return e.event == "threshold"), "low enemy grants no TP")
	return {"thresholds":thresholds,"delay":delayed,"result":values(b),"kits":b.s.kits,"care":b.s.care,"events":b.events}

func situations() -> Array:
	var rows: Array = []
	for id in Fixtures.IDS:
		if id == "F4": continue
		var tps = [4,18,30] if id == "F5" else ([0,4,18] if id == "F1" else [18])
		var builds = ["standard","assault","counter","sustain"] if id == "F6" else ["standard"]
		var variants = [0,1] if id in ["F2","F3","F5","F6"] else [0]
		for tp in tps:
			for build in builds:
				for variant in variants:
					for enabled in ([true,false] if id in ["F5","F6"] else [true]):
						var b = Fixtures.make(id,42,tp,build,enabled,variant)
						var state: Dictionary = b.s.duplicate(true)
						var branches: Array = []
						if id in ["F1","F2","F3"]:
							for a in b.options():
								if a.skill == "kit": continue
								var fork = b.copy()
								fork.submit(a, fork.s.revision)
								while fork.s.outcome.is_empty() and fork.s.round == 1:
									fork.submit(Policy.select(fork,"read"), fork.s.revision)
								branches.append({"move":a,"end":values(fork),"events":fork.events})
						if id == "F3":
							var mage = b.copy()
							mage.submit(move("blade","attack","shield"), mage.s.revision)
							for skill in ["attack","detonate"]:
								var fork = mage.copy()
								var a = move("mage",skill,"caster")
								fork.submit(a, fork.s.revision)
								while fork.s.outcome.is_empty() and fork.s.round == 1:
									fork.submit(Policy.select(fork,"read"), fork.s.revision)
								branches.append({"move":a,"end":values(fork),"events":fork.events})
						var turns = run_battle(b,"read")
						rows.append({"id":id,"tp":tp,"build":build,"variant":variant,"thresholds":enabled,"start":state,"end":values(b),"round":b.s.round,"outcome":b.s.outcome,"branches":branches,"turns":turns,"events":b.events})
	return rows

func ablation() -> Array:
	var reports: Array = []
	for mode in Catalog.MODES:
		for seed_value in range(42,52):
			for attempt in ([false,true] if mode == "U3" else [false]):
				var b = Battle.new()
				var party: Dictionary = Catalog.initial_party(3 if mode in ["U1","U3"] else 1)
				party.mage.hp = 30
				party.warden.hp = 68
				var tactics: bool = mode in ["U2","U3"]
				var loadout: Dictionary = Catalog.data.builds.sustain if tactics else Catalog.data.builds.standard
				var gear: Dictionary = Fixtures.gears("sustain") if tactics else {}
				if attempt: gear.erase("mage")
				b.start(2,seed_value,party,loadout,gear,1,true,{"states":{"boss":{"burn":2}}})
				var start: Dictionary = b.s.duplicate(true)
				var alternatives: Array = []
				for skill in ["attack","break","taunt"]:
					var a = move("blade",skill,"shield" if skill != "taunt" else "boss")
					var branch = b.copy()
					if not branch.submit(a,branch.s.revision): continue
					while branch.s.outcome.is_empty() and branch.s.round < 3:
						branch.submit(Policy.select(branch,"read"),branch.s.revision)
					var enemies: Dictionary = {}
					for id in branch.s.enemies: enemies[id] = branch.s.units[id].hp
					alternatives.append({"input":a,"end":values(branch),"enemies":enemies,"events":branch.events})
				var turns = run_battle(b,"read")
				reports.append({"mode":mode,"seed":seed_value,"without_glove":attempt,"start":start,"events":b.events,"turns":turns,"end":values(b),"outcome":b.s.outcome,"round":b.s.round,"alternatives":alternatives})
	return reports
