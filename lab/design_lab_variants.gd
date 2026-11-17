extends RefCounted

# Prototypes are opt-in. The ordinary game still loads the Ver.0.3 definitions.
const BASELINE = "baseline"
const MODES = [BASELINE, "tp"]

static func requested() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lab="):
			var mode = argument.trim_prefix("--lab=")
			if mode in MODES: return mode
			push_warning("Unknown Design Lab variant: " + mode)
	return BASELINE

static func apply(mode: String, catalog, _visuals = null) -> void:
	if mode == BASELINE: return
	catalog.data.rules.tp_recovery.pool = 0
	catalog.validate()
