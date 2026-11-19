extends SceneTree

const C = preload("res://combat_core_v2/catalog.gd")
const F = preload("res://combat_core_v2/fixtures.gd")
const E = preload("res://combat_core_v2/effects.gd")
const R = preload("res://combat_core_v2/route.gd")
var checks: int = 0
var failures: int = 0
var evidence: Dictionary = {}

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + title)

func action(actor: String, skill: String, target: String) -> Dictionary:
	return {"actor":actor,"skill":skill,"target":target}

func use(b, actor: String, skill: String, target: String) -> bool:
	var move = action(actor,skill,target)
	var state: Dictionary = b.s.duplicate(true)
	var last: int = b.events.size()
	var predicted: Array = b.preview(move)
	check(b.s == state,"pure preview")
	var accepted: bool = b.submit(move,b.s.revision)
	check(accepted and b.events.slice(last,last+predicted.size()) == predicted,"exact prediction " + skill)
	return accepted

func _initialize() -> void:
	for id in C.PARTY: check(C.data.allies[id].skills.size() == 6 and C.data.initial_loadout[id].size() == 4,"candidate and slot count")
	check_guards()
	check_burn()
	check_items()
	check_rewards()
	check_wave()
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	var output = FileAccess.open("res://tests/artifacts/v2_rules.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence}))
	print("V2 RULES: %d checks / %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)

func check_guards() -> void:
	for v in [0,1]:
		var b = F.make("F2",42,18,"seal",true,v)
		var target: String = "shield" if v == 0 else "boss"
		check(b.s.units[target].guard,"both enemies use generic guard")
		use(b,"blade","break",target)
		check(not b.s.units[target].guard and b.s.units[target].lock == 4,"same guard and gear effect " + target)
	var exposed = F.make("F3",42,18,"standard",true)
	var plain: Array = exposed.preview(action("blade","attack","caster"))
	var technique: Array = exposed.preview(action("blade","break","caster"))
	check(plain.any(func(e): return e.event == "damage" and e.amount == 13) and technique.any(func(e): return e.event == "damage" and e.amount == 8) and not technique.any(func(e): return e.event == "break"),"normal hit wins against unguarded caster")
	var b = F.make("F1",42,0,"standard",true)
	use(b,"blade","attack","shield")
	use(b,"mage","dampen","caster")
	use(b,"warden","split","mage")
	check(b.s.units.mage.hp == 7,"0 TP still has two cooperative roles")
	evidence.zero_tp = b.events
	b = F.make("F1",42,18,"standard",true)
	var before: Dictionary = b.s.duplicate(true)
	var predicted: Array = b.preview(action("blade","taunt","caster"))
	check(not predicted.is_empty() and b.s == before,"taunt projection pure")
	use(b,"blade","taunt","caster")
	check(b.s.intents.caster.target == "blade" and not b.submit(action("blade","taunt","caster"),0),"published target changes and stale input fails")

func check_burn() -> void:
	var b = F.make("F3",42,18,"standard",true)
	use(b,"blade","break","shield")
	use(b,"mage","ignite","caster")
	use(b,"warden","attack","shield")
	check(b.s.units.caster.burn == {"actor":"mage","ticks":1,"power":6},"mage burn initially ticks once")
	use(b,"blade","slashes","caster")
	check(b.s.units.caster.burn == {"actor":"mage","ticks":2,"power":6},"blade extends and retains source")
	evidence.maintain = b.events.duplicate(true)
	for equipped in ["standard","glove"]:
		b = F.make("F3",42,18,equipped,true)
		use(b,"blade","break","shield")
		use(b,"mage","attack","shield")
		use(b,"warden","counter","warden")
		check(b.s.units.caster.burn.get("actor") == "warden","counter source carried")
		use(b,"blade","attack","shield")
		use(b,"mage","detonate","caster")
		check(b.s.units.caster.burn.is_empty() and b.events.any(func(e): return e.event == "burn_consume" and e.source == "warden" and e.amount == 6),"different owner consumes")
		check(b.events.any(func(e): return e.event == "gear" and e.source == "glove") == (equipped == "glove"),"gear ablation changes actual transfer")
		evidence["consume_" + equipped] = b.events
	for hp in [83,19]:
		b = F.make("F3",42,18,"standard",true,1)
		b.s.units.caster.hp = hp
		b.s.units.caster.cutoffs = b.s.units.caster.cutoffs.filter(func(value): return value < hp)
		b.s.units.caster.burn.ticks = 2
		use(b,"blade","break","shield")
		var direct = b.copy()
		use(b,"mage","attack","caster")
		use(direct,"mage","detonate","caster")
		check(b.s.units.mage.tp - direct.s.units.mage.tp <= 8,"burn conversion charges TP before threshold")
		if hp == 19:
			check(not direct.alive("caster") and b.alive("caster"),"conversion wins the urgent kill")
			use(b,"warden","attack","shield")
			use(direct,"warden","attack","shield")
			check(b.s.units.warden.hp < direct.s.units.warden.hp,"urgent kill prevents actual enemy damage")
		else:
			use(b,"warden","attack","shield")
			use(direct,"warden","attack","shield")
			check(b.s.units.mage.tp > direct.s.units.mage.tp and not b.s.units.caster.burn.is_empty(),"maintaining preserves resource and a pending tick")
		evidence["trade_%d" % hp] = {"preserve":b.events,"consume":direct.events}
	b = F.make("F3",42,18,"glove",true,1)
	b.s.units.shield.hp = 0
	b.s.units.mender.hp = 0
	use(b,"blade","attack","caster")
	var follow = b.copy()
	follow.s.units.mage.gear = "standard"
	use(b,"mage","detonate","caster")
	use(follow,"mage","detonate","caster")
	check(b.s.intents.caster.power == 23 and follow.s.intents.caster.power == 28,"solo consumption gear changes the pending damage")
	evidence.solo_consumption = {"with":b.events,"without":follow.events}

func check_items() -> void:
	for delay in [false,true]:
		var b = F.make("F4",42,18,"standard",true)
		check(not "blade" in b.targets("blade","kit"),"no item waste at full HP")
		if delay:
			for cycle in range(3):
				use(b,"blade","taunt","shield")
				use(b,"mage","dampen","shield")
				use(b,"warden","kit" if cycle == 0 else "split","mage")
		use(b,"blade","attack","shield")
		if not delay: check(b.care("blade","kit","mage"),"immediate kill allows the same camp healing")
		check(b.s.kits == 0 and b.s.units.mage.hp == 64 and not b.care("blade","kit","mage"),"same remedy and finite stock")
		check(b.s.units.blade.tp == (9 if delay else 18),"time adds no TP")
		evidence["delay_%s" % str(delay)] = {"hp":b.s.units.blade.hp,"tp":b.s.units.blade.tp,"mage":b.s.units.mage.hp,"kits":b.s.kits,"events":b.events}
	var b = F.make("F2",42,18,"standard",true)
	E.damage(b,"blade","shield",33,"test",false)
	E.heal(b,"shield","shield",33,"test")
	E.damage(b,"blade","shield",33,"test",false)
	check(b.s.units.blade.tp == 22,"healing does not restore threshold credits")

func check_rewards() -> void:
	for reward in ["counter","fuse","medicine"]:
		var r = R.new()
		check(not r.exchange("warden",3,"counter") and not r.equip("mage","fuse"),"unowned items rejected")
		r.start()
		r.battle.s.outcome = "clear"
		r.collect()
		var moves: Dictionary = r.moves.duplicate(true)
		check(r.proceed() and r.level_up() and r.level == 2,"separate result and level transitions")
		check(r.take(reward) and not r.take(reward) and r.moves == moves and r.gears.is_empty(),"one reward, independent configuration")
		if reward == "counter": check(r.exchange("warden",3,"counter") and r.moves.warden[3] == "counter","new skill available next fight")
		if reward == "fuse": check(r.equip("mage","fuse"),"gear can now be equipped")
		if reward == "medicine": check(r.kits == 2,"medicine is one finite item")
		r.party.mage.hp = 33
		if reward == "medicine": check(r.care("mage") and r.party.mage.hp == 64,"medicine changes next fight entry HP")
		r.start()
		if reward != "medicine":
			var b = r.battle
			b.s.intents.caster.merge({"kind":"strike","target":"warden","power":28},true)
			use(b,"blade","break","shield")
			use(b,"mage","mark","caster")
			if reward == "fuse": check(b.s.units.caster.burn.get("actor") == "mage" and b.s.units.caster.burn.get("power") == 8,"ring makes the fixed opening a burn setup")
			if reward == "counter":
				use(b,"warden","counter","warden")
				check(b.s.units.caster.burn.get("actor") == "warden","learned skill converts hit into a cross-character opener")
		evidence["reward_opening_" + reward] = {"start":r.start_state,"events":r.battle.events}
		r.battle.s.outcome = "clear"
		r.collect()
		check(r.proceed() and r.level_up() and r.take("combo" if reward != "counter" else "glove"),"second individual acquisition")
		check(r.moves.warden[3] == ("counter" if reward == "counter" else "brace"),"second reward retains first configuration")
		evidence["reward_" + reward] = r.records()

func check_wave() -> void:
	var b = F.make("F6",42,18,"standard",true,1)
	b.s.units.mage.moves[2] = "wave"
	use(b,"blade","attack","shield")
	for id in b.s.enemies:
		b.s.units[id].hp = b.s.units[id].cutoffs[0] + 1
	var pivot: int = b.events.size()
	use(b,"mage","wave","all")
	var events: Array = b.events.slice(pivot)
	check(events.filter(func(e): return e.event == "threshold").size() == 3,"one newly crossed cutoff per enemy")
	check(b.s.units.mage.tp == 14 and b.s.units.blade.tp == 24 and b.s.units.warden.tp == 24,"wave costs ten and grants six per living member")
	evidence.wave = events
