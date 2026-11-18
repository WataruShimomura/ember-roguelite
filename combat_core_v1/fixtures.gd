extends RefCounted

const Catalog = preload("res://combat_core_v1/catalog.gd")
const Battle = preload("res://combat_core_v1/battle.gd")
const IDS = ["F1","F2","F3","F4","F5","F6"]
const LABELS = {"F1":"致死予告","F2":"盾と優先順位","F3":"状態と連携","F4":"瀕死敵と回復","F5":"長期・枯渇","F6":"同じ敵・別装備"}

static func gears(build: String) -> Dictionary:
	var equipped: Dictionary = {}
	for gear in Catalog.data.growth.paths.get(build, {}).get("gears", []):
		equipped[Catalog.data.gear[gear].owner] = gear
	return equipped

static func make(id: String, seed_value: int, tp: int, build: String, thresholds: bool, variant: int = 0):
	var party: Dictionary = Catalog.initial_party()
	for actor in party: party[actor].tp = tp
	var battle = Battle.new()
	var fixture: Dictionary = {}
	var encounter: int = 0
	var moves: Dictionary = Catalog.data.builds[build].duplicate(true)
	match id:
		"F1":
			party.mage.hp = 22
			fixture.intents = {"caster": {"kind":"heavy","target":"mage","power": 39,"interruptible":true}}
		"F2":
			fixture.enemies = Catalog.data.encounters[0].enemies.duplicate(true)
			fixture.enemies.caster.current = 9 if variant == 0 else 50
			fixture.intents = {"caster": {"kind":"strike","target":"mage","power":12}}
		"F3":
			moves = Catalog.data.builds.assault.duplicate(true)
			fixture.states = {"shield":{"guard":false}, "caster":{"mark": 3 if variant == 0 else 0, "burn": 0 if variant == 0 else 2}}
		"F4":
			party.mage.hp = 33
			fixture.enemies = {"shield":{"hp":63,"current":5,"hit":10}}
			fixture.states = {"shield":{"guard":false}}
			fixture.intents = {"shield":{"kind":"strike","target":"warden","power":10}}
			moves = Catalog.data.builds.standard.duplicate(true)
		"F5":
			encounter = 2
			fixture.enemies = Catalog.data.encounters[2].enemies.duplicate(true)
			fixture.enemies.boss.hp *= 2 if variant == 0 else 3
		"F6": encounter = mini(variant, 1)
	battle.start(encounter, seed_value, party, moves, gears(build), int(Catalog.data.rules.start_kits), thresholds, fixture)
	return battle
