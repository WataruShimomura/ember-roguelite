"""Summarize local Godot logs for the Design Lab review."""

import json
from collections import Counter
from pathlib import Path
from statistics import mean


ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "tests" / "artifacts"
REPORT = ROOT / "docs" / "design-experiments"
MODES = ("baseline", "tp", "skills", "gear", "gear_ring", "gear_ward", "gear_bench", "gear_rest")


def distribution(battles):
    turns = [turn for battle in battles for turn in battle["turns"]]
    commands = Counter(turn[4] for turn in turns)
    return {
        "battles": len(battles),
        "rounds": sum(b["rounds"] for b in battles),
        "actions": len(turns),
        "commands": commands,
        "normal_rate": commands["attack"] / max(1, len(turns)),
        "full_rate": sum(b["full"] for b in battles) / max(1, len(turns)),
        "empty_rate": sum(b["empty"] for b in battles) / max(1, len(turns)),
        "tp_flow": {
            field: sum(b[field] for b in battles)
            for field in ("entry", "entry_overflow", "natural", "natural_unused", "absorb",
                          "growth_tp", "item_tp", "spent")
        },
        "blocked_skills": accumulated_counts(battles, "blocked_skills"),
        "consumed_items": accumulated_counts(battles, "inventory_used"),
        "equipment_events": accumulated_counts(battles, "equipment_effects"),
        "damage_taken": sum(b["result"]["damage_taken"] for b in battles),
        "actual_ward_hp_saved": sum(b["ward_prevented_hp"] for b in battles),
        "warded_hits": sum(b["ward_hits"] for b in battles),
        "ward_targets": Counter(t[5][0] for t in turns if t[4] == "ward"),
        "ward_use_with_predicted_prevention": sum(
            t[4] == "ward" and t[9]["prevention"] > 0 for t in turns
        ),
        "strike_vs_guard": sum(t[4] == "strike" and t[8][0][2] for t in turns),
        "fireball_vs_already_burning": sum(t[4] == "fireball" and "burn" in t[8][0][1] for t in turns),
    }


def accumulated_counts(battles, key):
    counts = Counter()
    for battle in battles:
        counts.update(battle[key])
    return counts


def party_total(run, key):
    return sum(unit[key] for unit in run["party"].values())


def cohort(runs, start=0):
    battles = [battle for run in runs for battle in run["battles"][start:]]
    return {
        **distribution(battles),
        "runs": len(runs),
        "clear": sum(run["outcome"] == "clear" for run in runs),
        "mean_end_hp": mean(party_total(run, "hp") for run in runs),
        "mean_end_tp": mean(party_total(run, "tp") for run in runs),
        "failures": [
            [r["seed"], r["preset"], r["policy"], r["battles"][-1]["encounter"]]
            for r in runs if r["outcome"] != "clear"
        ],
    }


def compare_delays(runs):
    by_input = {(r["seed"], r["preset"], r["policy"]): r for r in runs}
    rows = []
    for (seed, preset, policy), delayed in by_input.items():
        if policy != "delay":
            continue
        regular = by_input[seed, preset, "conditional"]
        rows.append({
            "seed": seed, "preset": preset,
            "end_hp_delta": party_total(delayed, "hp") - party_total(regular, "hp"),
            "end_tp_delta": party_total(delayed, "tp") - party_total(regular, "tp"),
            "round_delta": sum(b["rounds"] for b in delayed["battles"]) -
                           sum(b["rounds"] for b in regular["battles"]),
            "inventory_delta": {
                item: delayed["inventory"].get(item, 0) - regular["inventory"].get(item, 0)
                for item in set(delayed["inventory"]) | set(regular["inventory"])
            },
        })
    return rows


def abridge_run(run):
    def resources(party):
        return {actor: [unit["hp"], unit["tp"]] for actor, unit in party.items()}

    return {
        **{key: run[key] for key in ("seed", "preset", "policy", "route", "outcome", "inventory")},
        "history": [
            {key: event[key] for key in ("node", "kind", "reward", "choice", "actor", "after",
                                         "offers") if key in event}
            for event in run["history"] if event["kind"] != "restore"
        ],
        "battles": [
            {
                **{key: battle[key] for key in ("seed", "rounds", "commands", "full", "empty",
                                                "natural", "inventory_used", "ward_prevented_hp")},
                "hp_tp_in": resources(battle["start"]["party"]),
                "hp_tp_out": resources(battle["end"]["party"]),
            }
            for battle in run["battles"]
        ],
    }


def summarize(raw):
    runs = raw["runs"]
    assert len(runs) == 140 and len(raw["delay_probe"]) == 40 and len(raw["long_fight"]) == 20
    assert raw["failures"] == 0
    return {
        "rules": raw["rules"],
        "aggregate": cohort(runs),
        "by_policy": {
            policy: cohort([r for r in runs if r["policy"] == policy])
            for policy in sorted({r["policy"] for r in runs})
        },
        "by_battle_number": {
            str(node + 1): distribution([r["battles"][node] for r in runs if node < len(r["battles"])])
            for node in range(4)
        },
        "post_equip_battles_only": cohort(runs, 2),
        "delay_minus_conditional": compare_delays(runs),
        "delay_probes": raw["delay_probe"],
        "long_fights": raw["long_fight"],
        "runs": [abridge_run(run) for run in runs],
        "detailed_runs": [
            r for r in runs if r["seed"] == 42 and r["policy"] in ("conditional", "delay")
        ],
        "position_count": len(raw["positions"]),
        "sample_positions": [
            pos for pos in raw["positions"]
            if (pos["node"], pos["round"], pos["actor"]) in
               ((0, 1, "knight"), (0, 1, "mage"), (0, 3, "knight"), (2, 3, "knight"), (2, 1, "knight"))
        ],
    }


def format_json(value, depth=0):
    if depth == 4 or not isinstance(value, (dict, list)) or not value:
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    indent = "  " * (depth + 1)
    if isinstance(value, dict):
        entries = [json.dumps(key, ensure_ascii=False) + ": " + format_json(child, depth + 1)
                   for key, child in value.items()]
        opening, closing = "{", "}"
    else:
        entries = [format_json(child, depth + 1) for child in value]
        opening, closing = "[", "]"
    return opening + "\n" + indent + (",\n" + indent).join(entries) + "\n" + "  " * depth + closing


def main():
    raw = {mode: json.loads((ARTIFACTS / f"design_lab_{mode}.json").read_text(encoding="utf-8"))
           for mode in MODES}
    baseline_inputs = [(r["seed"], r["preset"], r["policy"], r["route"], r["initial_loadout"])
                       for r in raw["baseline"]["runs"]]
    for mode, data in raw.items():
        assert data["mode"] == mode
        for key in ("base", "instructions", "engine"):
            assert data[key] == raw["baseline"][key]
        assert [(r["seed"], r["preset"], r["policy"], r["route"], r["initial_loadout"])
                for r in data["runs"]] == baseline_inputs
    metadata = json.loads((REPORT / "DECISIONS.json").read_text(encoding="utf-8"))
    result = {
        **{key: raw["baseline"][key] for key in ("base", "instructions", "engine")},
        "seeds": list(range(42, 52)),
        "initial_loadouts": {r["preset"]: r["initial_loadout"] for r in raw["baseline"]["runs"]},
        "turn_columns": ["round", "actor", "hp", "tp", "skill", "targets", "cost", "pending_intents",
                         "target_hp_statuses_guard", "estimated_values", "delaying"],
        "position_alternative_columns": [
            "skill", "target", "cost", "estimated_values", "dealt", "taken", "party_hp", "party_tp",
            "enemies_alive", "winner", "inventory"
        ],
        "evaluation": metadata,
        "modes": {mode: summarize(data) for mode, data in raw.items()},
    }
    (REPORT / "METRICS.json").write_text(format_json(result) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
