extends RefCounted

# Prototypes are opt-in. The ordinary game still loads the Ver.0.3 definitions.
const BASELINE = "baseline"
const MODES = [BASELINE, "tp", "skills", "gear"]

static func requested() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lab="):
			var mode = argument.trim_prefix("--lab=")
			if mode in MODES: return mode
			push_warning("Unknown Design Lab variant: " + mode)
	return BASELINE

static func apply(mode: String, catalog, visuals = null) -> void:
	if mode == BASELINE: return
	catalog.data.rules.tp_recovery.pool = 0
	if mode == "skills":
		var trial = JSON.parse_string(FileAccess.get_file_as_string("res://lab/skills.json"))
		for id in trial.effects: catalog.data.skills[id].effects = trial.effects[id]
		if visuals != null:
			visuals.data.skills.merge(trial.names, true)
			visuals.data.skill_hints = trial.hints
	if mode == "gear":
		var trial = JSON.parse_string(FileAccess.get_file_as_string("res://lab/gear.json"))
		catalog.data.skills.ward = trial.skill
		catalog.data.equipment.ring = trial.equipment
		if visuals != null:
			visuals.data.equipment.ring.merge(trial.display, true)
			visuals.data.skills.ward = trial.skill_name
			visuals.data.skill_hints = {"ward": trial.hint}
	catalog.validate()
