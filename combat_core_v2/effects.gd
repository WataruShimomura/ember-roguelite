extends RefCounted

const Catalog = preload("res://combat_core_v2/catalog.gd")
const PARTY = Catalog.PARTY

static func change_tp(b, id: String, amount: int, source: String) -> void:
	var unit: Dictionary = b.s.units[id]
	var old: int = unit.tp
	unit.tp = clampi(old + amount, 0, int(Catalog.data.rules.max_tp))
	b.record("tp", id, id, unit.tp - old, source)

static func damage(b, actor: String, target: String, power: int, source: String, physical: bool) -> int:
	if not b.alive(target): return 0
	var unit: Dictionary = b.s.units[target]
	var amount: int = maxi(0, power)
	if physical and unit.get("guard", false):
		amount = floori(amount * float(Catalog.data.rules.guard_percent) / 100)
		b.record("mitigation", target, target, power - amount, "guard")
	amount = mini(amount, unit.hp)
	unit.hp -= amount
	b.record("damage", actor, target, amount, source)
	if target in b.s.enemies:
		for cutoff in unit.cutoffs.duplicate():
			if unit.hp <= cutoff:
				unit.cutoffs.erase(cutoff)
				b.record("threshold", actor, target, cutoff)
				if b.s.thresholds:
					for id in b.live(PARTY): change_tp(b, id, int(Catalog.data.rules.threshold_tp), "threshold:" + target)
	if unit.hp == 0:
		if unit.has("burn"): unit.burn = {}
		b.record("ko", actor, target, 0, source)
	return amount

static func modifier(b, id: String, trigger: String) -> int:
	var gear: String = b.s.units[id].gear
	var def: Dictionary = Catalog.data.gear[gear]
	if def.trigger != trigger: return 0
	b.record("gear", id, id, int(def.value), gear)
	return int(def.value)

static func heal(b, owner: String, target: String, amount: int, source: String) -> void:
	var unit: Dictionary = b.s.units[target]
	var actual: int = mini(amount, unit.max - unit.hp)
	unit.hp += actual
	b.record("heal", owner, target, actual, source)

static func treatment(b, owner: String, target: String) -> void:
	b.s.kits -= 1
	heal(b, owner, target, int(Catalog.data.rules.kit_hp), "kit")

static func mark(b, target: String, rounds: int, source: String) -> void:
	if not b.alive(target): return
	b.s.units[target].mark = maxi(int(b.s.units[target].mark), b.s.round + rounds)
	b.record("status", "", target, rounds, source)

static func burn(b, actor: String, target: String, ticks: int, potency: int, source: String) -> void:
	if not b.alive(target): return
	var previous: Dictionary = b.s.units[target].burn
	if int(previous.get("ticks", 0)) * int(previous.get("power", 0)) > ticks * potency: return
	b.s.units[target].burn = {"actor":actor, "ticks":ticks, "power":potency}
	b.record("burn_apply", actor, target, ticks, source)
	b.events[-1].power = potency

static func tick_burn(b, id: String) -> void:
	var status: Dictionary = b.s.units[id].burn
	if status.is_empty(): return
	status.ticks -= 1
	damage(b, status.actor, id, status.power, "burn", false)
	if status.ticks == 0 or not b.alive(id):
		b.s.units[id].burn = {}
		b.record("burn_expire", status.actor, id)

static func spread_consumed(b, target: String, status: Dictionary) -> void:
	var remaining: Array = b.live(b.s.enemies).filter(func(id): return id != target)
	for owner in b.live(PARTY):
		if remaining.is_empty():
			var gear: Dictionary = Catalog.data.gear[b.s.units[owner].gear]
			var relief: int = int(gear.get("solo_weakening",0))
			if relief > 0 and b.alive(target) and can_weaken(b,target):
				b.record("gear",owner,target,relief,b.s.units[owner].gear)
				weaken(b,owner,target,relief,"burn_gear")
			continue
		var transfer: int = modifier(b,owner,"party_burn_spread")
		if transfer > 0:
			burn(b,owner,remaining[0],mini(status.ticks + transfer,int(Catalog.data.rules.burn_ticks)),status.power,"spread")

static func landing(b, target: String, physical: bool) -> String:
	if not physical or b.s.units[target].get("escort",false): return target
	for id in b.live(b.s.order):
		if id in b.s.enemies and b.s.units[id].escort and b.s.units[id].guard:
			b.record("redirect",id,target,0,"guard")
			return id
	return target

static func can_weaken(b, target: String) -> bool:
	var intent: Dictionary = b.s.intents.get(target, {})
	return not intent.get("done",true) and not intent.cancelled and not intent.softened and intent.kind in ["strike","heavy","sweep"]

static func weaken(b, actor: String, target: String, value: int, source: String) -> void:
	if not can_weaken(b,target): return
	var intent: Dictionary = b.s.intents[target]
	var actual: int = mini(int(intent.power), value)
	intent.power -= actual
	intent.softened = true
	b.record("mitigation", actor, target, actual, source)

static func hit(b, actor: String, target: String, skill: String, physical: bool, power: int) -> void:
	target = landing(b,target,physical)
	var victim: Dictionary = b.s.units[target]
	var definition: Dictionary = Catalog.data.skills[skill]
	var consumed_burn: Dictionary = {}
	if skill == "break" and (victim.guard or b.s.intents[target].kind == "guard"):
		var extra: int = modifier(b, actor, "break_lock")
		victim.guard = false
		victim.lock = maxi(int(victim.lock), b.s.round + 2 + extra)
		if b.s.intents[target].kind == "guard" and not b.s.intents[target].done:
			b.s.intents[target].cancelled = true
		b.record("break", actor, target, 1 + extra)
	if skill == "combo" and victim.mark > b.s.round:
		power += int(definition.bonus)
		victim.mark = 0
		b.record("combo", actor, target, int(definition.bonus), skill)
	if skill == "detonate" and not victim.burn.is_empty():
		consumed_burn = victim.burn
		var converted: int = consumed_burn.ticks * consumed_burn.power
		power += converted
		victim.burn = {}
		b.record("burn_consume", actor, target, converted, consumed_burn.actor)
		b.events[-1].ticks = consumed_burn.ticks
	if skill == "thrust" and b.s.intents[target].target == actor and not b.s.intents[target].done:
		power += int(definition.bonus)
	var rally: int = b.s.units[actor].rally
	if rally > 0:
		power += rally
		b.s.units[actor].rally = 0
	damage(b, actor, target, power, skill, physical)
	if rally > 0: mark(b, target, int(Catalog.data.rules.mark_rounds), "rally")
	match skill:
		"mark":
			if b.alive(target):
				mark(b, target, int(Catalog.data.rules.mark_rounds), skill)
				var ticks: int = modifier(b, actor, "mark_burn")
				if ticks > 0:
					var definition_gear: Dictionary = Catalog.data.gear[b.s.units[actor].gear]
					burn(b, actor, target, ticks, int(definition_gear.get("potency",Catalog.data.rules.burn_damage)), "gear_burn")
		"ignite": burn(b, actor, target, int(Catalog.data.rules.burn_ticks), int(Catalog.data.rules.burn_damage), skill)
		"slashes":
			if b.alive(target) and not victim.burn.is_empty() and victim.burn.ticks < int(Catalog.data.rules.burn_ticks):
				victim.burn.ticks += 1
				b.record("burn_extend", actor, target, victim.burn.ticks, victim.burn.actor)
		"relay":
			for other in b.live(b.s.enemies):
				var burning: Dictionary = b.s.units[other].burn
				if other != target and not burning.is_empty():
					burn(b,actor,target,burning.ticks,burning.power,skill)
					break
		"detonate":
			if not consumed_burn.is_empty(): spread_consumed(b,target,consumed_burn)
		"interrupt":
			var intent: Dictionary = b.s.intents[target]
			if b.alive(target) and not intent.done and not intent.cancelled and intent.kind == "heavy":
				intent.cancelled = true
				b.record("interrupt", actor, target)

static func perform(b, move: Dictionary) -> void:
	var actor: String = move.actor
	var skill: String = move.skill
	var target: String = move.target
	b.record("action", actor, target, 0, skill)
	if skill == "kit":
		treatment(b, actor, target)
		return
	var definition: Dictionary = Catalog.data.skills[skill]
	var cost: int = definition.cost
	if cost > 0: change_tp(b, actor, -cost, skill)
	match skill:
		"taunt":
			var intent: Dictionary = b.s.intents[target]
			if not intent.done and not intent.cancelled and intent.kind in ["strike", "heavy"] and intent.target != actor:
				intent.target = actor
				b.record("redirect", actor, target, 0, skill)
				var rounds: int = modifier(b, actor, "taunt_mark")
				if rounds > 0: mark(b, target, rounds, "gear_mark")
		"riposte", "counter":
			var bonus: int = b.s.units[actor].reward if skill == "counter" else 0
			b.s.units[actor].reward -= bonus
			b.s.units[actor].stance = {"reply": int(definition.reply) + bonus, "reduction": int(definition.reduction), "burn": skill == "counter"}
			b.record("stance", actor, actor, definition.reply + bonus, skill)
		"dampen": weaken(b, actor, target, int(definition.power), skill)
		"brace":
			b.s.units[target].brace = int(definition.power)
			b.record("brace",actor,target,int(definition.power),skill)
		"cover", "split":
			b.s.protection = {"owner": actor, "target": target, "kind": skill}
			b.record("protect", actor, target, 0, skill)
		"rally":
			b.s.units[target].rally = int(definition.power)
			b.record("rally", actor, target, definition.power)
		_:
			var targets: Array = b.live(b.s.enemies) if target == "all" else [target]
			var power: int = int(b.s.units[actor].power) + int(definition.get("power", 0))
			var physical: bool = actor != "mage"
			for id in targets: hit(b, actor, id, skill, physical, power)

static func hit_party(b, enemy: String, target: String, value: int, source: String) -> int:
	if not b.alive(target): return 0
	var stance: Dictionary = b.s.units[target].stance
	b.s.units[target].stance = {}
	var reduction: int = mini(value, int(stance.get("reduction", 0)) + int(b.s.units[target].brace))
	b.s.units[target].brace = 0
	if reduction > 0: b.record("mitigation", target, target, reduction, source)
	var actual: int = damage(b, enemy, target, value - reduction, source, false)
	if actual > 0 and b.alive(target) and stance.has("reply"):
		damage(b, target, enemy, int(stance.reply), "reply", false)
		if stance.burn: burn(b,target,enemy,int(Catalog.data.rules.burn_ticks),int(Catalog.data.rules.burn_damage),"reply")
	return actual

static func enemy_action(b, id: String) -> void:
	var intent: Dictionary = b.s.intents[id]
	intent.done = true
	var kind: String = intent.kind
	var target: String = intent.target
	if kind == "heavy": b.s.units[id].charged = ""
	if intent.cancelled or (target != "all" and not b.alive(target)):
		b.record("cancel", id, target, 0, kind)
		return
	var power: int = b.intent_power(intent)
	b.record("enemy", id, target, power, kind)
	match kind:
		"guard":
			b.s.units[id].guard = b.s.round >= b.s.units[id].lock
		"charge": b.s.units[id].charged = target
		"heal":
			b.s.units[id].heals -= 1
			heal(b, id, target, power, kind)
		"sweep":
			for member in b.live(PARTY): hit_party(b, id, member, power, kind)
		"strike", "heavy":
			var protection: Dictionary = b.s.protection
			if protection.get("target", "") == target and b.alive(protection.owner):
				b.s.protection = {}
				var guard: String = protection.owner
				if protection.kind == "cover":
					var reduced: int = floori(power * float(Catalog.data.rules.cover_percent) / 100)
					b.record("cover", guard, target, power - reduced)
					if hit_party(b, id, guard, reduced, kind) > 0 and b.alive(guard):
						var reply: int = modifier(b, guard, "cover_counter")
						b.s.units[guard].reward = maxi(b.s.units[guard].reward, reply)
				else:
					b.record("split", guard, target, power)
					var half: int = floori(power / 2.0)
					hit_party(b, id, target, half, kind)
					if hit_party(b, id, guard, power - half, kind) > 0 and b.alive(guard):
						var rounds: int = modifier(b, guard, "split_mark")
						if rounds > 0: mark(b, id, rounds, "gear_mark")
			else: hit_party(b, id, target, power, kind)
