"""Publish a compact comparison from the Godot evaluator's full trace."""

import json
from collections import Counter
from pathlib import Path
from statistics import mean


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tests" / "artifacts" / "design_lab_v2.json"
DESTINATION = ROOT / "docs" / "design-lab-v2" / "metrics.json"
POLICIES = ("rush", "sustain", "reserve", "delay", "adaptive")
GEAR = ("base", "lure", "medic")
MODES = ("plan", "clock")


def hp(battle):
    return sum(battle["end"]["hp"].values())


def stock(battle, mode):
    carry = battle["end"]
    return carry["shared"] if mode == "plan" else sum(carry["stock"].values())


def summarize(battles, mode):
    inputs = [choice for battle in battles for choice in battle["choices"]]
    commands: Counter = Counter()
    for battle in battles:
        commands.update(battle["counts"])
    return {
        "battles": len(battles),
        "clears": sum(b["outcome"] == "clear" for b in battles),
        "mean_end_hp": mean(map(hp, battles)),
        "mean_end_resource": mean(stock(b, mode) for b in battles),
        "mean_inputs": mean(len(b["choices"]) for b in battles),
        "mean_resolution_time": mean(b["round" if mode == "plan" else "tick"] for b in battles),
        "commands": commands,
        "empty_resource_inputs": sum(choice[2] == 0 for choice in inputs),
        "inputs": len(inputs),
        **{key: sum(b[key] for b in battles) for key in (
            "spent", "enemy_heals", "damage_taken", "heavy_hits", "counter_damage",
            "forecast_responses", "healing"
        )},
    }


def compare_delays(runs, mode):
    paired = {(r["gear"], r["seed"], r["style"]): r for r in runs}
    results = {}
    for gear in GEAR:
        rows = []
        for _, seed, _ in (key for key in paired if key[0] == gear and key[2] == "delay"):
            delayed = paired[gear, seed, "delay"]["battles"]
            normal = paired[gear, seed, "adaptive"]["battles"]
            rows.append({
                "seed": seed,
                "same_horizon": len(delayed) == len(normal),
                "end_hp_delta": hp(delayed[-1]) - hp(normal[-1]),
                "end_resource_delta": stock(delayed[-1], mode) - stock(normal[-1], mode),
                "input_delta": sum(len(b["choices"]) for b in delayed) -
                               sum(len(b["choices"]) for b in normal),
            })
        results[gear] = rows
    return results


def main():
    raw = json.loads(SOURCE.read_text(encoding="utf-8"))
    assert raw["failures"] == 0 and len(raw["runs"]) == 300
    modes = {}
    for mode in MODES:
        runs = [r for r in raw["runs"] if r["mode"] == mode]
        configurations = {}
        for gear in GEAR:
            selected = [r for r in runs if r["gear"] == gear]
            assert len(selected) == 50
            configurations[gear] = {
                "battle_1": summarize([r["battles"][0] for r in selected], mode),
                "battle_2": summarize([r["battles"][1] for r in selected if len(r["battles"]) == 2], mode),
                "battle_2_by_policy": {
                    p: summarize([r["battles"][1] for r in selected
                                  if len(r["battles"]) == 2 and r["style"] == p], mode)
                    for p in POLICIES
                },
            }
        modes[mode] = {
            "configurations": configurations,
            "delay_minus_adaptive": compare_delays(runs, mode),
            "seed_42": [r for r in runs if r["seed"] == 42 and r["style"] == "adaptive"],
        }
    result = {
        **{key: raw[key] for key in ("base", "instructions", "design", "engine", "checks", "failures", "positions", "stall")},
        "run_count": len(raw["runs"]),
        "seeds": sorted({r["seed"] for r in raw["runs"]}),
        "input_columns": ["round", "tick", "ready_actor_resource_or_shared", "input", "delaying"],
        "modes": modes,
    }
    DESTINATION.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
