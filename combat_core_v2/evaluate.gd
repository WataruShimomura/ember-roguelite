extends SceneTree

const C = preload("res://combat_core_v2/catalog.gd")
const R = preload("res://combat_core_v2/route.gd")
const F = preload("res://combat_core_v2/fixtures.gd")
const P = preload("res://combat_core_v2/policy.gd")
const B = preload("res://combat_core_v2/battle.gd")
const PATHS = {
	"standard":["medicine","medicine"],
	"attack":["fuse","combo"],
	"defense":["counter","medicine"],
	"status":["medicine","glove"],
	"mixed":["counter","glove"]
}
var failures: int = 0
var checks: int = 0

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + title)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	var quick: bool = "--quick" in args
	var thresholds: bool = not "--off" in args
	var output = {"instructions":"4caaebc762dcce3919ee4b02ccec3d2827e7a490","baseline":"49c9f13a697a07b6d2e96c80ad566f389d8731bd","engine":Engine.get_version_info().string,"thresholds":thresholds,"runs":[],"fireless":[],"long":[],"build_fixtures":[]}
	for seed_value in (range(42,45) if quick else range(42,52)):
		for mode in C.MODES:
			for path in (PATHS.keys() if mode in ["U2","U3"] else ["standard"]):
				for style in (["rush","read","reserve"] if quick else P.STYLES):
					output.runs.append(play(seed_value,mode,path,style,thresholds))
		if not quick and thresholds:
			for style in ["rush","read","counter"]:
				output.fireless.append(fireless(seed_value,style))
		print("SEED ",seed_value)
	if not quick:
		for v in [0,1]:
			for tp in [4,18,30]:
				var b = F.make("F5",42,tp,"standard",thresholds,v)
				output.long.append({"variant":v,"tp":tp,"turns":battle(b,"read"),"outcome":b.s.outcome,"round":b.s.round,"events":b.events})
			for gear in ["standard","fuse","glove","mail"]:
				var b = F.make("F6",42,18,gear,thresholds,v)
				output.build_fixtures.append({"variant":v,"gear":gear,"turns":battle(b,"read"),"outcome":b.s.outcome,"round":b.s.round,"events":b.events})
	output.failures = failures
	output.checks = checks
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	var suffix = "quick" if quick else ("threshold" if thresholds else "none")
	var file = FileAccess.open("res://tests/artifacts/v2_%s.json" % suffix,FileAccess.WRITE)
	file.store_string(JSON.stringify(output))
	file.close()
	print("V2 EVAL: ",output.runs.size()," routes / ",checks," checks / ",failures," failures")
	quit(0 if failures == 0 else 1)

func configure(route, path: String, reward: String) -> void:
	match reward:
		"fuse": check(route.equip("mage","fuse"),"equip acquired ring")
		"combo": check(route.exchange("blade",3,"combo"),"equip learned combo")
		"counter":
			check(route.exchange("warden",0,"counter"),"equip learned counter")
			check(route.equip("warden","mail"),"equip owned mail")
		"glove": check(route.equip("mage","glove"),"equip acquired gloves")
	if route.node == 2 and path == "attack":
		check(route.equip("blade","seal"),"use owned gear")
	if route.node == 2 and path in ["status","mixed"]:
		check(route.exchange("mage",2,"detonate"),"exchange one known slot")
	if route.node == 2 and path == "defense":
		check(route.equip("blade","hook"),"take redirect-to-mark support")

func play(seed_value: int, mode: String, path: String, style: String, thresholds: bool) -> Dictionary:
	var route = R.new(seed_value,mode,thresholds)
	for node in range(3):
		check(route.start(),"start valid encounter")
		var turns: Array = battle(route.battle,style)
		check(route.collect() and route.proceed(),"complete battle result")
		route.history[-1].turns = turns
		if route.phase != "level": break
		check(route.level_up(),"numeric growth transition")
		var reward: String = PATHS[path][node] if mode in ["U2","U3"] else ""
		check(route.take(reward) and not route.take(reward),"single reward")
		if mode in ["U2","U3"]: configure(route,path,reward)
		P.camp(route,style)
		route.history[-1].outgoing = route.records()
	return {"seed":seed_value,"mode":mode,"path":path,"style":style,"battles":route.history}

func battle(b, style: String, exclude: Array = []) -> Array:
	var turns: Array = []
	var waiting: int = 0
	for _step in range(180):
		if b.s.outcome != "": break
		var enemy: Array = b.live(b.s.enemies)
		var delay: bool = style == "delay" and enemy.size() == 1 and b.s.units[enemy[0]].hp * 4 <= b.s.units[enemy[0]].max and waiting < 9
		if delay: waiting += 1
		var move: Dictionary = P.select(b,"read" if style == "delay" else style,delay,exclude)
		if move.is_empty():
			check(false,"has move")
			break
		var u: Dictionary = b.s.units[move.actor]
		turns.append([b.s.round,move.actor,move.skill,move.target,u.hp,u.tp,delay])
		if not b.submit(move,b.s.revision):
			check(false,"legal policy input")
			break
	check(not b.s.outcome.is_empty(),"battle terminates within cap")
	return turns

func fireless(seed_value: int, style: String) -> Dictionary:
	var b = B.new()
	var moves: Dictionary = C.data.initial_loadout.duplicate(true)
	moves.blade[0] = "riposte"
	moves.warden[0] = "rally"
	b.start(2,seed_value + 1994,C.initial_party(3),moves,{"blade":"seal","warden":"flag"},1,true)
	var turns = battle(b,style,["ignite","detonate","relay","counter"])
	check(not b.events.any(func(e): return e.event == "burn_apply"),"fireless uses no burn")
	return {"seed":seed_value,"style":style,"turns":turns,"outcome":b.s.outcome,"round":b.s.round,"events":b.events}
