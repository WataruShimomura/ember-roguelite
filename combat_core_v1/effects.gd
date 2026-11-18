extends RefCounted

const Catalog = preload("res://combat_core_v1/catalog.gd")
const PARTY = Catalog.PARTY

static func change_tp(b, id: String, amount: int, source: String) -> void:
	var unit: Dictionary = b.s.units[id]
	var old: int = unit.tp
	unit.tp = clampi(old + amount, 0, int(Catalog.data.rules.max_tp))
	b.record("tp", id, id, unit.tp - old, source)

static func damage(b, actor: String, target: String, power: int, source: String, physical: bool, opening: bool = false) -> int:
	if not b.alive(target): return 0
	var unit: Dictionary = b.s.units[target]
	var amount: int = maxi(0, power)
	if physical and unit.get("guard", false):
		amount = floori(amount * float(Catalog.data.rules.guard_percent) / 100)
		b.record("mitigation", target, target, power - amount, "guard")
	if target == "boss" and not (opening or b.exposed(target) or source in ["burn","reply"]):
		var held: int = floori(amount * float(Catalog.data.rules.ritual_percent) / 100)
		b.record("mitigation", target, target, amount - held, "ritual")
		amount = held
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
	if unit.hp == 0: b.record("ko", actor, target, 0, source)
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

static func treatment(b, owner: String, skill: String, target: String) -> void:
	if skill == "kit":
		b.s.kits -= 1
		heal(b, owner, target, int(Catalog.data.rules.kit_hp), skill)
		return
	b.s.care[owner] -= 1
	change_tp(b, owner, -int(Catalog.data.skills[skill].cost), skill)
	heal(b, owner, target, int(Catalog.data.skills[skill].power), skill)
	if skill == "convert" and b.s.outcome.is_empty():
		for id in b.live(b.s.enemies):
			if b.s.units[id].burn > 0: weaken(b, owner, id, 6, skill)

static func mark(b, target: String, rounds: int, source: String) -> void:
	if not b.alive(target): return
	b.s.units[target].mark = maxi(int(b.s.units[target].mark), b.s.round + rounds)
	b.record("status", "", target, rounds, source)

static func burn(b, target: String, ticks: int, source: String) -> void:
	if not b.alive(target): return
	b.s.units[target].burn = maxi(int(b.s.units[target].burn), ticks)
	b.record("status", "", target, ticks, source)

static func weaken(b, actor: String, target: String, value: int, source: String) -> void:
	var intent: Dictionary = b.s.intents.get(target, {})
	if intent.get("done", true) or intent.cancelled or intent.softened or not intent.kind in ["strike", "heavy", "sweep"]: return
	var actual: int = mini(int(intent.power), value)
	intent.power -= actual
	intent.softened = true
	b.record("mitigation", actor, target, actual, source)

static func hit(b, actor: String, target: String, skill: String, physical: bool, power: int) -> void:
	if physical and target != "shield" and b.alive("shield") and b.s.units.shield.guard:
		b.record("redirect", "shield", target, 0, "guard")
		target = "shield"
	var victim: Dictionary = b.s.units[target]
	var opening: bool = target == "boss" and b.exposed(target)
	var definition: Dictionary = Catalog.data.skills[skill]
	var consumed_burn: int = 0
	if skill == "break":
		var extra: int = modifier(b, actor, "break_lock") if target == "shield" else 0
		victim.guard = false
		victim.lock = maxi(int(victim.lock), b.s.round + 2 + extra)
		if b.s.intents[target].kind == "guard" and not b.s.intents[target].done:
			b.s.intents[target].cancelled = true
		b.record("break", actor, target, 1 + extra)
	if skill == "combo" and victim.mark > b.s.round:
		power += int(definition.bonus)
		victim.mark = 0
		b.record("combo", actor, target, int(definition.bonus), skill)
	if skill == "detonate" and victim.burn > 0:
		power += int(definition.bonus)
		consumed_burn = victim.burn
		victim.burn = 0
		b.record("combo", actor, target, int(definition.bonus), skill)
		if target == "boss":
			victim.exposed_until = b.s.round + 2
			b.record("expose", actor, target, 1, skill)
	if skill == "thrust" and b.s.intents[target].target == actor and not b.s.intents[target].done:
		power += int(definition.bonus)
	var rally: int = b.s.units[actor].rally
	if rally > 0:
		power += rally
		b.s.units[actor].rally = 0
	damage(b, actor, target, power, skill, physical, opening)
	if rally > 0: mark(b, target, int(Catalog.data.rules.mark_rounds), "rally")
	match skill:
		"mark":
			if b.alive(target):
				mark(b, target, int(Catalog.data.rules.mark_rounds), skill)
				var ticks: int = modifier(b, actor, "mark_burn")
				if ticks > 0: burn(b, target, ticks, "gear_burn")
		"ignite": burn(b, target, int(Catalog.data.rules.burn_ticks), skill)
		"detonate":
			var remaining: Array = b.live(b.s.enemies).filter(func(id): return id != target)
			if consumed_burn > 0 and not remaining.is_empty():
				var transfer: int = modifier(b, actor, "detonate_spread")
				if transfer > 0:
					burn(b, remaining[0], mini(consumed_burn + transfer, int(Catalog.data.rules.burn_ticks)), "gear_burn")
		"interrupt":
			var intent: Dictionary = b.s.intents[target]
			if b.alive(target) and not intent.done and not intent.cancelled and intent.kind == "heavy" and intent.interruptible:
				intent.cancelled = true
				b.record("interrupt", actor, target)

static func perform(b, move: Dictionary) -> void:
	var actor: String = move.actor
	var skill: String = move.skill
	var target: String = move.target
	b.record("action", actor, target, 0, skill)
	if skill in ["kit", "aid", "convert"]:
		treatment(b, actor, skill, target)
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
			b.s.units[actor].stance = {"reply": int(definition.reply) + bonus, "reduction": int(definition.reduction)}
			b.record("stance", actor, actor, definition.reply + bonus, skill)
		"dampen": weaken(b, actor, target, int(definition.power), skill)
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
	var reduction: int = mini(value, int(stance.get("reduction", 0)))
	if reduction > 0: b.record("mitigation", target, target, reduction, source)
	var actual: int = damage(b, enemy, target, value - reduction, source, false)
	if actual > 0 and b.alive(target) and stance.has("reply"):
		damage(b, target, enemy, int(stance.reply), "reply", false)
		if enemy == "boss" and b.alive(enemy):
			b.s.units.boss.exposed_until = b.s.round + 2
			b.record("expose", target, enemy, 1, "reply")
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
