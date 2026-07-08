#!/usr/bin/env python3
"""Evaluate a root probe JSON file and decide whether C1 controls can be promoted."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


TARGET_CONTROLS = [
    "whiteBalanceTemperature",
    "whiteBalanceAuto",
    "focusAbsolute",
    "focusAuto",
    "exposureTime",
    "exposureAuto",
    "gain",
    "brightness",
    "contrast",
    "saturation",
    "sharpness",
    "powerLineFrequency",
]


def load_probe(path: Path) -> dict:
    return json.loads(path.read_text())


def evaluate(report: dict) -> dict:
    proof = report.get("control_proof") or {}
    controls = {control["key"]: control for control in proof.get("controls", [])}
    promoted = []
    blocked = []
    for key in TARGET_CONTROLS:
        control = controls.get(key)
        if not control:
            blocked.append({"key": key, "reason": "missing"})
            continue
        has_range = control.get("minimum") not in ("", None) and control.get("maximum") not in ("", None)
        if control.get("readable") and control.get("writable") and has_range:
            promoted.append(control)
        else:
            blocked.append({
                "key": key,
                "reason": control.get("blocker") or "not readable/writable or missing range",
                "readable": control.get("readable"),
                "writable": control.get("writable"),
            })
    status = "promote_helper_backend" if promoted and len(blocked) <= 3 else "do_not_promote"
    return {
        "status": status,
        "promoted_count": len(promoted),
        "blocked_count": len(blocked),
        "promoted": promoted,
        "blocked": blocked,
        "root": report.get("system", {}).get("is_root"),
    }


def render_text(result: dict, path: Path) -> str:
    lines = [
        "# C1 Control Promotion Verdict",
        "",
        f"Probe: `{path}`",
        "",
        "## Verdict",
    ]
    if result["status"] == "promote_helper_backend":
        lines.append(f"Promote the helper backend for controlled experiments: {result['promoted_count']} controls look readable/writable.")
    else:
        lines.append(f"Do not promote yet: {result['promoted_count']} controls ready, {result['blocked_count']} blocked.")
    lines.extend([
        "",
        "## Promoted Candidates",
        "",
        "| Control | Entity | Selector | Current | Min | Max | Step | Default |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ])
    for control in result["promoted"]:
        lines.append(
            f"| {control['key']} | {control['entity']} | {control['selector']} | "
            f"{control.get('current', '')} | {control.get('minimum', '')} | {control.get('maximum', '')} | "
            f"{control.get('resolution', '')} | {control.get('default', '')} |"
        )
    lines.extend([
        "",
        "## Blocked",
        "",
    ])
    for item in result["blocked"]:
        lines.append(f"- {item['key']}: {item['reason']}")
    lines.extend([
        "",
        "## Safety Gate",
        "- Before normal UI promotion, perform one write-back test on a low-risk control by writing the current value back unchanged.",
        "- Do not enable iris unless it returns a real range and responds.",
        "- Do not enable firmware paths.",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("probe", type=Path, nargs="?", default=Path("work/c1-root-probe.json"))
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    if not args.probe.exists():
        result = {
            "status": "missing_probe",
            "error": f"probe file not found: {args.probe}",
            "promoted_count": 0,
            "blocked_count": len(TARGET_CONTROLS),
            "promoted": [],
            "blocked": [{"key": key, "reason": "missing root probe"} for key in TARGET_CONTROLS],
        }
    else:
        result = evaluate(load_probe(args.probe))

    content = json.dumps(result, indent=2) if args.json else render_text(result, args.probe)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content)
    print(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
