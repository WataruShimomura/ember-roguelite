extends RefCounted

const Catalog = preload("res://combat_core_v2/catalog.gd")
const Battle = preload("res://combat_core_v2/battle.gd")
const IDS = ["F1","F2","F3","F4","F5","F6"]
const LABELS = {"F1":"大技と護衛","F2":"構えの比較","F3":"火傷連携","F4":"瀕死敵と傷薬","F5":"長期・枯渇","F6":"装備の有無"}

static func make(id: String, seed_value: int, tp: int, gear: String, thresholds: bool, variant: int = 0):
	var party: Dictionary = Catalog.initial_party()
	for actor in party: party[actor].tp = tp
	var battle = Battle.new()
	var fixture: Dictionary = {}
	var encounter: int = 0
	var moves: Dictionary = Catalog.data.initial_loadout.duplicate(true)
	var equipped: Dictionary = {}
	if gear != "standard": equipped[Catalog.data.gear[gear].owner] = gear
	match id:
		"F1":
			party.mage.hp = 22
			fixture.intents = {"caster":{"kind":"heavy","target":"mage","power":39}}
		"F2":
			encounter = 2 if variant == 1 else 0
			fixture.enemies = Catalog.data.encounters[encounter].enemies.duplicate(true)
			if variant == 1: fixture.states = {"shield":{"guard":false}}
		"F3":
			encounter = 1
			fixture.states = {"shield":{"guard":false}}
			fixture.intents = {"caster":{"kind":"strike","target":"warden","power":28}}
			moves.mage[2] = "detonate"
			moves.warden[3] = "counter"
			if variant == 1: fixture.states.caster = {"burn":{"actor":"warden","ticks":1,"power":6}}
		"F4":
			party.mage.hp = 33
			fixture.enemies = {"shield":{"hp":63,"current":5,"hit":10}}
			fixture.states = {"shield":{"guard":false}}
			fixture.intents = {"shield":{"kind":"strike","target":"warden","power":10}}
		"F5":
			encounter = 2
			fixture.enemies = Catalog.data.encounters[2].enemies.duplicate(true)
			fixture.enemies.boss.hp = int(fixture.enemies.boss.hp * (1.5 if variant == 0 else 2))
		"F6":
			encounter = mini(variant,1)
			moves.mage[2] = "detonate"
			moves.warden[3] = "counter"
	battle.start(encounter,seed_value,party,moves,equipped,int(Catalog.data.rules.start_kits),thresholds,fixture)
	return battle
