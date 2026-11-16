extends SceneTree

const Content = preload("res://core/content_catalog.gd")
const Simulator = preload("res://tests/run_simulator.gd")

func _initialize() -> void:
	var results: Array = []
	var failures: int = 0
	var checks: int = 0
	for route in [{"name": "burst", "choices": ["detonate", "ember_hunt"]}, {"name": "sustain", "choices": ["riposte", "counter_order"]}]:
		for mode in ["C", "entry_only", "pool_only", "off"]:
			var catalog = Content.new()
			if mode == "entry_only": catalog.data.rules.tp_recovery.pool = 0
			if mode == "pool_only": catalog.data.rules.tp_recovery.entry = 0
			if mode == "off": catalog.data.rules.tp_recovery.enabled = false
			var played = Simulator.play(catalog, 42, route.name, route.choices)
			checks += 1
			if played.has("error") or played.outcome != "clear":
				failures += 1
				printerr("FAIL: comparison route ", route.name, " / ", mode, " / ", played.get("error", played.get("outcome", "unknown")))
				continue
			for stats in played.stats:
				checks += 2
				var carried = stats.carried_tp.values().reduce(func(n, value): return n + value, 0)
				var ended = stats.tp_end.values().reduce(func(n, value): return n + value, 0)
				if carried + stats.entry + stats.natural + stats.absorb + stats.growth_tp + stats.item_tp - stats.spent != ended:
					failures += 1
					printerr("FAIL: resource accounting ", route.name, " / ", mode)
				if stats.natural > (int(catalog.data.rules.tp_recovery.pool) * 3 if catalog.data.rules.tp_recovery.enabled else 0):
					failures += 1
					printerr("FAIL: finite pool budget ", route.name, " / ", mode)
			results.append({"seed": 42, "route": route.name, "choices": route.choices, "tp_mode": mode, "rules": catalog.data.rules.tp_recovery.duplicate(true), "outcome": played.outcome, "battles": played.stats, "final_party": played.run.state.party.duplicate(true), "inventory": played.run.state.inventory.duplicate(true)})
			var boss = played.stats[-1]
			if mode == "C":
				checks += 1
				var demonstrated = boss.growth_events.get("growth:detonate", 0) > 0 if route.name == "burst" else (boss.growth_events.get("growth:riposte", 0) > 0 and boss.growth_events.get("growth:counter_order", 0) > 0)
				if not demonstrated:
					failures += 1
					printerr("FAIL: selected growth must change boss actions: ", route.name)
			print("COMPARE ", route.name, " / ", mode, " boss R", boss.rounds, " normal=", boss.normal, " skills=", boss.skills, " rate=", snappedf(boss.normal_rate, .001), " endTP=", boss.tp_end)
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	var file = FileAccess.open("res://tests/artifacts/v03_comparisons.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t")); file.close()
	print("COMPARISON RESULT: %d completed runs / %d checks / %d failures" % [results.size(), checks, failures])
	quit(0 if failures == 0 else 1)
