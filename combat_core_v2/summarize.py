"""Summarize the matched Godot trials and retain reproducible sample traces."""

import json
from collections import Counter, defaultdict
from pathlib import Path
from statistics import mean


ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / "tests" / "artifacts"
OUTPUT = ROOT / "docs" / "combat-core-v2" / "metrics.json"
PRIMARY = ("rush", "sustain", "counter", "synergy", "reserve", "read")


def load(name):
    return json.loads((ARTIFACTS / f"v2_{name}.json").read_text(encoding="utf-8"))


def total(party, field, living=False):
    return sum(p[field] for p in party.values() if not living or p["hp"] > 0)


def boss(run):
    last = run["battles"][-1]
    return last if last["node"] == 2 else None


def group(runs):
    bosses = [b for run in runs if (b := boss(run))]
    commands = Counter()
    targets = Counter()
    burn_routes = Counter()
    gear = Counter()
    counts = Counter()
    acquisition = Counter()
    for r in runs:
        for b in r["battles"]:
            counts["camp_kits"] += len(b.get("camp_items", []))
            reward = b.get("reward", {}).get("id", "")
            if reward:
                acquisition[reward] += 1
            for e in b["events"]:
                if e["event"] == "heal" and e["source"] == "kit":
                    counts["combat_kits"] += 1
    for b in bosses:
        for _, actor, skill, target, _, tp, delaying in b["turns"]:
            commands[skill] += 1
            targets[f"{actor}:{skill}:{target}"] += 1
            counts["zero_tp"] += tp == 0
            counts["full_tp"] += tp == 30
            counts["delay_turns"] += delaying
        for e in b["events"]:
            kind, source = e["event"], e["source"]
            if kind == "gear":
                gear[source] += 1
            if kind == "burn_apply":
                burn_routes[f"apply:{e['actor']}:{source}"] += 1
            if kind == "burn_extend":
                burn_routes[f"extend:{source}>{e['actor']}"] += 1
            if kind == "burn_consume":
                burn_routes[f"consume:{source}>{e['actor']}"] += 1
            if kind == "tp" and source.startswith("threshold:"):
                counts["threshold_tp"] += e["amount"]
                counts["overflow_tp"] += 2 - e["amount"]
            if kind == "tp" and e["amount"] < 0:
                counts["tp_spent"] -= e["amount"]
            if kind == "damage" and e["target"] in ("blade", "mage", "warden"):
                counts["damage_taken"] += e["amount"]
    return {
        "runs": len(runs),
        "normal_wins": sum(r["battles"][0]["outcome"] == "clear" for r in runs),
        "boss_reached": len(bosses),
        "boss_clears": sum(b["outcome"] == "clear" for b in bosses),
        "mean_boss_start_hp": mean(total(b["start"]["party"], "hp") for b in bosses) if bosses else 0,
        "mean_boss_start_tp": mean(total(b["start"]["party"], "tp") for b in bosses) if bosses else 0,
        "mean_boss_end_hp": mean(total(b["end"]["party"], "hp") for b in bosses) if bosses else 0,
        "mean_boss_end_tp": mean(total(b["end"]["party"], "tp", True) for b in bosses) if bosses else 0,
        "mean_boss_rounds": mean(b["round"] for b in bosses) if bosses else 0,
        "commands": commands,
        "targets": targets,
        "status_routes": burn_routes,
        "gear_triggers": gear,
        "counts": counts,
        "rewards": acquisition,
    }


def summarize(raw):
    cohorts = defaultdict(list)
    for r in raw["runs"]:
        cohorts[(r["mode"], r["path"])].append(r)
    return [
        {
            "mode": mode,
            "path": path,
            "primary": group([r for r in runs if r["style"] in PRIMARY]),
            "all": group(runs),
            "by_policy": {
                style: group([r for r in runs if r["style"] == style])
                for style in sorted({r["style"] for r in runs})
            },
        }
        for (mode, path), runs in sorted(cohorts.items())
    ]


def validate(raw, reference=None):
    assert raw["failures"] == 0 and len(raw["runs"]) == 960
    lookup = {} if reference is None else reference
    for r in raw["runs"]:
        for b in r["battles"]:
            i = (r["seed"], b["node"])
            snapshot = (b["seed"], b["start"]["enemies"])
            assert lookup.setdefault(i, snapshot) == snapshot
        first = r["battles"][0]["start"]
        assert first["level"] == 1 and not first["gears"] and first["kits"] == 1
        for left, right in zip(r["battles"], r["battles"][1:]):
            assert left["outgoing"]["party"] == right["start"]["party"]
            assert left["outgoing"]["kits"] == right["start"]["kits"]
            before, after = left["growth"]["before"], left["growth"]["after"]
            assert after["level"] - before["level"] == (r["mode"] in ("U1", "U3"))
            assert before["loadout"] == after["loadout"]
            assert left["reward"]["after"]["loadout"] == after["loadout"]
            assert left["reward"]["after"]["gears"] == after["gears"]
    return lookup


def main():
    on, off, previous = (load(key) for key in ("threshold", "none", "stage2_before"))
    validate(off, validate(on))
    validate(previous)
    fixed = load("rules")
    assert fixed["failures"] == 0
    matrix = {
        **{key: on[key] for key in ("instructions", "baseline", "engine")},
        "seeds": list(range(42, 52)),
        "turn_columns": ["round", "actor", "skill", "target", "hp", "tp", "delay"],
        "primary_policies": PRIMARY,
        "check_counts": {"threshold": on["checks"], "none": off["checks"], "rules": fixed["checks"]},
        "stage2_before": summarize(previous),
        "threshold": summarize(on),
        "no_recovery": summarize(off),
        "fireless": on["fireless"],
        "long": on["long"] + off["long"],
        "build_fixtures": on["build_fixtures"],
        "fixed_cases": fixed["evidence"],
        "sample_routes": [r for r in on["runs"] if r["seed"] == 42 and r["style"] == "read"],
    }
    OUTPUT.write_text(json.dumps(matrix, ensure_ascii=False, separators=(",", ":")) + "\n",
                      encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
