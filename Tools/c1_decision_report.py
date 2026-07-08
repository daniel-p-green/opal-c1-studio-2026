#!/usr/bin/env python3
"""Investment decision report for C1 Studio 2026."""

from __future__ import annotations

import argparse
import json
import os
import re
from datetime import datetime
from pathlib import Path


def workspace_root() -> Path:
    env_root = os.environ.get("C1_STUDIO_WORKSPACE")
    if env_root:
        candidate = Path(env_root).expanduser()
        if candidate.exists():
            return candidate
    for candidate in [Path.cwd(), *Path(__file__).resolve().parents]:
        if (candidate / "Package.swift").exists():
            return candidate
    return Path.cwd()


ROOT = workspace_root()
WORK = ROOT / "work"


def read_text(path: Path) -> str:
    return path.read_text(errors="replace") if path.exists() else ""


def first_section_line(path: Path, section: str) -> str:
    lines = read_text(path).splitlines()
    for index, line in enumerate(lines):
        if line.strip() == section:
            for candidate in lines[index + 1 : index + 8]:
                if candidate.strip() and not candidate.startswith("#"):
                    return candidate.strip()
    return ""


def release_score() -> dict:
    text = read_text(WORK / "c1-release-score-latest.md")
    score_match = re.search(r"^(\d+)\s*/\s*(\d+)$", text, re.MULTILINE)
    return {
        "verdict": first_section_line(WORK / "c1-release-score-latest.md", "## Verdict"),
        "score": int(score_match.group(1)) if score_match else None,
        "total": int(score_match.group(2)) if score_match else None,
    }


def collect() -> dict:
    score = release_score()
    visual_gate = ""
    visual_json = read_text(WORK / "c1-visual-proof-latest.json")
    if visual_json:
        try:
            parsed = json.loads(visual_json)
            visual_gate = parsed.get("verdict") or ""
        except Exception:
            visual_gate = "Visual proof gate unreadable."
    data = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "doctor": first_section_line(WORK / "c1-doctor-latest.md", "## Diagnosis"),
        "release": score,
        "readiness": {
            "obs_bridge": "OBS bridge ready: yes" in read_text(WORK / "c1-readiness-latest.md"),
            "hardware_controls": "Hardware controls ready: yes" in read_text(WORK / "c1-readiness-latest.md"),
        },
        "positive_evidence": {
            "enumerates": "Opal C1 visible: yes" in read_text(WORK / "c1-doctor-latest.md"),
            "motion": first_section_line(WORK / "c1-motion-bench-latest.md", "## Verdict"),
            "stability": first_section_line(WORK / "c1-stability-bench-latest.md", "## Verdict"),
            "benchmark": first_section_line(WORK / "c1-quality-bench-latest.md", "## Verdict"),
        },
        "blockers": {
            "visual_gate": visual_gate or "No visual proof gate.",
            "quality_coach": first_section_line(WORK / "c1-quality-coach-latest.md", "## Verdict"),
            "hardware_controls": first_section_line(WORK / "c1-control-promotion-latest.md", "## Verdict"),
            "opal_bridge": first_section_line(WORK / "c1-opal-bridge-latest.md", "## Verdict"),
            "apple_effects": read_text(WORK / "c1-apple-effects-latest.txt").strip(),
        },
    }
    data["decision"] = decide(data)
    return data


def decide(data: dict) -> dict:
    score = data["release"].get("score") or 0
    total = data["release"].get("total") or 125
    score_ratio = score / total if total else 0
    doctor = data["doctor"]
    visual_blocked = "not face-valid" in doctor or "Face-invalid" in data["blockers"]["visual_gate"]
    controls_blocked = not data["readiness"]["hardware_controls"]
    apple_blocked = "none reported for C1" in data["blockers"]["apple_effects"]
    bridge_unproven = "no callable control protocol" in data["blockers"]["opal_bridge"]

    if doctor.startswith("C1 allowed") and score_ratio >= 0.75 and data["readiness"]["hardware_controls"]:
        status = "continue"
        summary = "Continue: C1 has enough verified daily-camera evidence to justify product investment."
    elif score_ratio >= 0.6 and not data["readiness"]["hardware_controls"]:
        status = "freeze_lab"
        summary = "Freeze as lab/OBS rescue: useful evidence exists, but the C1 is not worth more daily-camera investment now."
    else:
        status = "retire"
        summary = "Retire: evidence does not justify continued investment."

    reopen = [
        "A fresh face-valid visual proof shows C1 Coach Tuned clearly beating Studio Display.",
        "Hardware controls are promoted after root/helper proof with readable and writable WB, exposure, and focus.",
        "A callable Opal bridge, direct UVC helper, or owned CMIO/DriverKit path is proven without launching Opal Composer UI.",
    ]
    return {
        "status": status,
        "summary": summary,
        "daily_camera_recommendation": "Use Studio Display; use iPhone Continuity when quality matters.",
        "why": {
            "score_ratio": round(score_ratio, 3),
            "visual_blocked": visual_blocked,
            "controls_blocked": controls_blocked,
            "apple_effects_blocked": apple_blocked,
            "opal_bridge_unproven": bridge_unproven,
        },
        "reopen_criteria": reopen,
    }


def render_text(data: dict) -> str:
    decision = data["decision"]
    release = data["release"]
    lines = [
        "# C1 Studio Investment Decision",
        "",
        f"Generated: {data['generated_at']}",
        "",
        "## Decision",
        f"{decision['status']}: {decision['summary']}",
        "",
        "## Daily Camera Recommendation",
        decision["daily_camera_recommendation"],
        "",
        "## Evidence",
        f"- Doctor: {data['doctor'] or 'No doctor diagnosis.'}",
        f"- Release score: {release.get('score')}/{release.get('total')} ({release.get('verdict') or 'No verdict.'})",
        f"- Motion: {data['positive_evidence']['motion'] or 'No motion evidence.'}",
        f"- Stability: {data['positive_evidence']['stability'] or 'No stability evidence.'}",
        f"- Still benchmark: {data['positive_evidence']['benchmark'] or 'No benchmark evidence.'}",
        "",
        "## Blockers",
        f"- Visual proof: {data['blockers']['visual_gate']}",
        f"- Quality coach: {data['blockers']['quality_coach'] or 'No quality coach verdict.'}",
        f"- Hardware controls: {data['blockers']['hardware_controls'] or 'No promotion verdict.'}",
        f"- Opal bridge: {data['blockers']['opal_bridge'] or 'No Opal bridge verdict.'}",
        "- Apple effects: unavailable for C1 in the local probe.",
        "",
        "## Product Call",
        "- Stop treating the C1 as a daily-camera product candidate.",
        "- Keep C1 Studio as a lab/OBS rescue and evidence harness.",
        "- Do not spend more time on firmware unless a new firmware source is discovered and verified read-only first.",
        "- Do not chase Opal Composer as the foundation unless a callable bridge is proven.",
        "",
        "## Reopen Criteria",
    ]
    lines.extend(f"- {item}" for item in decision["reopen_criteria"])
    lines.extend([
        "",
        "## Evidence Boundary",
        "- This decision is based on current local reports in `work/`.",
        "- It can be overturned by a fresh face-valid proof or promoted hardware-control evidence.",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    data = collect()
    content = json.dumps(data, indent=2) if args.json else render_text(data)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content)
    print(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
