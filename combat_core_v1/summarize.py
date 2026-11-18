"""Publish reproducible results from the Combat Core Godot evaluator."""

import json
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean


ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "tests" / "artifacts"
DESTINATION = ROOT / "docs" / "combat-core-v1" / "comparisons.json"
PARTY = ("blade", "mage", "warden")
PRIMARY = ("rush", "sustain", "counter", "synergy", "reserve", "read")


def load(name):
    return json.loads((ARTIFACTS / f"combat_core_{name}.json").read_text(encoding="utf-8"))


def total(party, key):
    return sum(party[actor][key] for actor in PARTY)


def battles_by_stage(runs, node):
    return [b for r in runs for b in r["battles"] if b["node"] == node]


def summarize_battles(battles):
    if not battles:
        return {"count": 0, "clears": 0}
    commands = Counter()
    targets = Counter()
    gear = Counter()
    responses = Counter()
    turns = Counter()
    metrics = Counter()
    for battle in battles:
        for _, actor, _, tp, skill, target, delaying in battle["turns"]:
            commands[skill] += 1
            targets[f"{actor}:{skill}:{target}"] += 1
            turns["full_tp"] += tp == 30
            turns["empty_tp"] += tp == 0
            turns["delay"] += delaying
        for event in battle["events"][:battle["combat_events"]]:
            kind, actor, target, amount, source = (
                event[key] for key in ("event", "actor", "target", "amount", "source")
            )
            if kind == "gear":
                gear[source] += 1
            if kind in ("interrupt", "cover", "split", "expose") or (
                kind == "redirect" and source == "taunt"
            ) or (kind == "mitigation" and source in ("dampen", "convert")):
                responses[f"{kind}:{source}"] += 1
            if kind == "damage":
                metrics["taken" if target in PARTY else "dealt"] += amount
                if target in PARTY and source in ("heavy", "sweep"):
                    metrics[f"taken:{source}"] += amount
            if kind == "heal" and target in PARTY:
                metrics["healed"] += amount
            if kind == "tp" and source.startswith("threshold:"):
                metrics["threshold_tp"] += amount
                metrics["overflow_tp"] += 2 - amount
            if kind == "tp" and amount < 0:
                metrics["spent_tp"] -= amount
    return {
        "count": len(battles),
        "clears": sum(b["outcome"] == "clear" for b in battles),
        "mean_round": mean(b["round"] for b in battles),
        "mean_end_hp": mean(total(b["end"], "hp") for b in battles),
        "mean_end_tp": mean(total(b["end"], "tp") for b in battles),
        "mean_live_end_tp": mean(sum(u["tp"] for u in b["end"].values() if u["hp"] > 0) for b in battles),
        "mean_start_hp": mean(total(b["start"]["party"], "hp") for b in battles),
        "mean_start_tp": mean(total(b["start"]["party"], "tp") for b in battles),
        "mean_alive": mean(sum(u["hp"] > 0 for u in b["end"].values()) for b in battles),
        "commands": commands,
        "targets": targets,
        "gear": gear,
        "responses": responses,
        "turns": sum(commands.values()),
        "turn_context": turns,
        "totals": metrics,
    }


def compact_run(run):
    return {
        **{k: run[k] for k in ("seed", "mode", "path", "style")},
        "battles": [
            [
                b["node"], b["outcome"], b["round"], total(b["start"]["party"], "hp"),
                total(b["start"]["party"], "tp"), total(b["end"], "hp"), total(b["end"], "tp"),
            ]
            for b in run["battles"]
        ],
    }


def cohort(raw):
    by_mode_path = defaultdict(list)
    for run in raw["runs"]:
        by_mode_path[run["mode"], run["path"]].append(run)
    return {
        "checks": raw["checks"],
        "failures": raw["failures"],
        "groups": [
            {
                "mode": mode,
                "path": path,
                "all_runs": len(group),
                "all_bosses": len(battles_by_stage(group, 2)),
                "all_clears": sum(b["outcome"] == "clear" for b in battles_by_stage(group, 2)),
                "primary_runs": len(primary),
                "primary_stages": [summarize_battles(battles_by_stage(primary, i)) for i in range(3)],
                "boss_by_policy": {
                    style: {
                        "started": len(choice),
                        "reached": len(battles_by_stage(choice, 2)),
                        "clears": sum(b["outcome"] == "clear" for b in battles_by_stage(choice, 2)),
                    }
                    for style in sorted({r["style"] for r in group})
                    for choice in [[r for r in group if r["style"] == style]]
                },
            }
            for (mode, path), group in sorted(by_mode_path.items())
            for primary in [[r for r in group if r["style"] in PRIMARY]]
        ],
        "runs": [compact_run(r) for r in raw["runs"]],
    }


def confirm_inputs(enabled, disabled):
    reference = {
        (r["seed"], b["node"]): (b["seed"], b["start"]["enemies"])
        for r in enabled["runs"] for b in r["battles"]
    }
    for raw in (enabled, disabled):
        assert raw["failures"] == 0 and len(raw["runs"]) == 640
        for r in raw["runs"]:
            first = r["battles"][0]["start"]
            assert first["level"] == 1 and not first["gears"]
            assert [first["party"][id]["tp"] for id in PARTY] == [18] * 3
            for battle in r["battles"]:
                assert (battle["seed"], battle["start"]["enemies"]) == reference[r["seed"], battle["node"]]
            for previous, following in zip(r["battles"], r["battles"][1:]):
                assert previous["outgoing"] == following["start"]["party"]
                growth = previous["growth"]
                numeric = r["mode"] in ("U1", "U3")
                tactical = r["mode"] in ("U2", "U3")
                assert bool(growth["gear"]) == tactical
                assert (growth["loadout_before"] != growth["loadout_after"]) == (
                    tactical and previous["node"] == 0
                )
                for actor in PARTY:
                    old = growth["before"][actor]
                    new = growth["after"][actor]
                    hp_gain = (10 if previous["node"] == 0 else 14) if numeric else 0
                    assert new["max"] - old["max"] == hp_gain
                    assert new["power"] - old["power"] == (3 if numeric else 0)
                    assert new["hp"] - old["hp"] == (hp_gain if old["hp"] > 0 else 0)
                    assert new["tp"] == old["tp"]


def main():
    full, off = load("full"), load("off")
    confirm_inputs(full, off)
    output = {
        **{key: full[key] for key in ("base", "instructions", "engine")},
        "seeds": sorted({r["seed"] for r in full["runs"]}),
        "primary_policies": PRIMARY,
        "turn_columns": ["round", "actor", "hp", "tp", "skill", "target", "delay"],
        "compact_battle_columns": ["node", "outcome", "round", "start_hp", "start_tp", "end_hp", "end_tp"],
        "thresholds": cohort(full),
        "no_recovery": cohort(off),
        "direct_boss": full["direct"],
        "situations": full["situations"],
        "stall": full["stall"],
        "ablation": [r for r in full["ablation"] if r["seed"] == 42],
        "ablation_outcomes": [
            {k: r[k] for k in ("mode", "seed", "without_glove", "outcome", "round", "end")}
            for r in full["ablation"]
        ],
        "sample_routes": [r for r in full["runs"] if r["seed"] == 42 and r["style"] == "read"],
    }
    DESTINATION.write_text(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
