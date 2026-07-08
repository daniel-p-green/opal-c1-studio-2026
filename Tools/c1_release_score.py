#!/usr/bin/env python3
"""C1 Studio 2026 release-readiness scorecard."""

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


def first_verdict(path: Path) -> str:
    lines = read_text(path).splitlines()
    for index, line in enumerate(lines):
        if line.strip() == "## Verdict":
            for candidate in lines[index + 1: index + 8]:
                if candidate.strip() and not candidate.startswith("#"):
                    return candidate.strip()
    return ""


def doctor_diagnosis() -> str:
    lines = read_text(WORK / "c1-doctor-latest.md").splitlines()
    for index, line in enumerate(lines):
        if line.strip() == "## Diagnosis":
            for candidate in lines[index + 1: index + 8]:
                if candidate.strip():
                    return candidate.strip()
    return ""


def readiness_value(label: str) -> bool:
    text = read_text(WORK / "c1-readiness-latest.md")
    pattern = rf"\| {re.escape(label)} \| (pass|missing) \|"
    match = re.search(pattern, text)
    return bool(match and match.group(1) == "pass")


def visual_gate() -> dict:
    text = read_text(WORK / "c1-visual-proof-latest.json")
    if not text:
        return {"valid": False, "verdict": "Visual proof gate missing."}
    try:
        gate = json.loads(text)
    except Exception as exc:
        return {"valid": False, "verdict": f"Visual proof gate unreadable: {type(exc).__name__}: {exc}"}
    return {
        "valid": bool(gate.get("valid")),
        "verdict": gate.get("verdict") or ("Face-valid proof." if gate.get("valid") else "Face-invalid proof."),
    }


def coach_calibration() -> dict:
    text = read_text(WORK / "c1-coach-look-latest.json")
    if not text:
        return {"ready": False, "detail": "Coach Tuned look missing."}
    try:
        look = json.loads(text)
    except Exception as exc:
        return {"ready": False, "detail": f"Coach Tuned look unreadable: {type(exc).__name__}: {exc}"}
    ready = bool(
        look.get("autoStudioGrade")
        and look.get("autoFaceBalance")
        and float(look.get("studioMatchAmount") or 0) > 0
        and float(look.get("studioMatchSaturation") or 0) > 0
        and float(look.get("studioMatchContrast") or 0) > 0
    )
    if ready:
        return {
            "ready": True,
            "detail": (
                "Coach Tuned has Auto Face Balance, Studio Grade, and learned Studio Match "
                f"{float(look.get('studioMatchAmount') or 0):.2f}."
            ),
        }
    return {"ready": False, "detail": "Coach Tuned does not yet include learned Studio Match calibration."}


def processed_proof() -> dict:
    score = first_verdict(WORK / "c1-visual-score-latest.md")
    variant_dir = WORK / "visual-proof"
    variants = list(variant_dir.glob("*-latest.jpg")) if variant_dir.exists() else []
    ready = bool(score and len(variants) >= 2)
    return {
        "ready": ready,
        "verdict": score or "Processed visual score missing.",
        "detail": f"{len(variants)} saved processed proof variants." if variants else "No saved processed proof variants.",
    }


def evidence() -> dict:
    benchmark = first_verdict(WORK / "c1-quality-bench-latest.md")
    motion = first_verdict(WORK / "c1-motion-bench-latest.md")
    stability = first_verdict(WORK / "c1-stability-bench-latest.md")
    coach = first_verdict(WORK / "c1-quality-coach-latest.md")
    visual_score = first_verdict(WORK / "c1-visual-score-latest.md")
    doctor = doctor_diagnosis()
    apple = read_text(WORK / "c1-apple-effects-latest.txt")
    control = read_text(WORK / "c1-control-promotion-latest.md")
    gate = visual_gate()
    calibration = coach_calibration()
    proof = processed_proof()
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "doctor": doctor,
        "benchmark": benchmark,
        "motion": motion,
        "stability": stability,
        "quality_coach": coach,
        "visual_score": visual_score,
        "apple_effects_supported": "Supported Apple effect formats: none reported for C1" not in apple and bool(apple.strip()),
        "controls_promoted": control.startswith("Promote"),
        "visual_gate": gate,
        "visual_win": (WORK / "c1-visual-proof-win.txt").exists() and gate["valid"],
        "calibration": calibration,
        "processed_proof": proof,
        "checks": {
            "opal_c1_visible": readiness_value("Opal C1 visible"),
            "studio_display_visible": readiness_value("Studio Display visible"),
            "obs_bridge_ready": readiness_value("OBS Virtual Camera visible") and readiness_value("OBS Camera Extension active"),
            "benchmark_exists": (WORK / "c1-quality-bench-latest.md").exists(),
            "motion_exists": (WORK / "c1-motion-bench-latest.md").exists(),
            "stability_exists": (WORK / "c1-stability-bench-latest.md").exists(),
            "quality_coach_exists": (WORK / "c1-quality-coach-latest.md").exists(),
            "calibration_exists": (WORK / "c1-calibration-latest.md").exists(),
            "processed_score_exists": (WORK / "c1-visual-score-latest.md").exists(),
            "control_proof_exists": readiness_value("Control proof exists"),
            "root_probe_exists": readiness_value("Root probe JSON exists"),
        },
    }


def score(report: dict) -> dict:
    items = []

    def add(name: str, points: int, ok: bool, detail: str) -> None:
        items.append({"name": name, "points": points, "earned": points if ok else 0, "ok": ok, "detail": detail})

    checks = report["checks"]
    add("Camera enumerates", 10, checks["opal_c1_visible"], "Opal C1 visible to AVFoundation.")
    add("Studio comparison available", 5, checks["studio_display_visible"], "Studio Display is visible for current-room comparison.")
    add("OBS bridge ready", 15, checks["obs_bridge_ready"], "OBS Virtual Camera and extension are available.")
    add("Still-frame advantage", 10, "C1 has" in report["benchmark"], report["benchmark"] or "No benchmark verdict.")
    add("Motion thesis", 15, report["motion"].startswith("Motion thesis intact"), report["motion"] or "No motion verdict.")
    add("Call stability", 10, report["stability"].startswith("Stability pass"), report["stability"] or "No call stability verdict.")
    add("Calibration workflow", 10, report["calibration"]["ready"], report["calibration"]["detail"])
    add("Processed proof package", 5, report["processed_proof"]["ready"], f"{report['processed_proof']['verdict']} {report['processed_proof']['detail']}")
    add("Image-quality coach", 20, report["quality_coach"].startswith("C1 is promising"), report["quality_coach"] or "No quality coach verdict.")
    add("Hardware controls", 15, report["controls_promoted"], "Hardware controls are promoted." if report["controls_promoted"] else "Hardware controls are not promoted.")
    add("Apple effects", 5, report["apple_effects_supported"], "Apple effects reported supported." if report["apple_effects_supported"] else "Apple Portrait/Studio Light/Center Stage unavailable for C1.")
    add("Manual visual win", 5, report["visual_win"], "Face-valid visual win marker exists." if report["visual_win"] else f"No face-valid manual visual win. {report['visual_gate']['verdict']}")

    total = sum(item["points"] for item in items)
    earned = sum(item["earned"] for item in items)
    blockers = [item for item in items if not item["ok"] and item["points"] >= 15]
    if report["doctor"].startswith("C1 allowed") and earned >= 75:
        grade = "Release Candidate"
        verdict = "C1 can be treated as a candidate daily camera in this setup."
    elif checks["obs_bridge_ready"] and report["motion"].startswith("Motion thesis intact") and report["stability"].startswith("Stability pass"):
        grade = "Lab-Ready"
        verdict = "C1 is useful as a lab/OBS bridge, but not daily-camera ready."
    else:
        grade = "No-Go"
        verdict = "C1 is not ready for daily use."
    return {"score": earned, "total": total, "grade": grade, "verdict": verdict, "items": items, "blockers": blockers}


def collect() -> dict:
    report = evidence()
    report.update(score(report))
    return report


def render_text(report: dict) -> str:
    lines = [
        "# C1 Studio Release Score",
        "",
        f"Generated: {report['generated_at']}",
        "",
        "## Verdict",
        f"{report['grade']}: {report['verdict']}",
        "",
        "## Score",
        f"{report['score']} / {report['total']}",
        "",
        "## Scorecard",
        "",
        "| Gate | Points | Status | Evidence |",
        "| --- | ---: | --- | --- |",
    ]
    for item in report["items"]:
        status = "pass" if item["ok"] else "blocked"
        lines.append(f"| {item['name']} | {item['earned']}/{item['points']} | {status} | {item['detail']} |")
    lines.extend(["", "## Primary Blockers"])
    if report["blockers"]:
        lines.extend(f"- {item['name']}: {item['detail']}" for item in report["blockers"])
    else:
        lines.append("- No major scored blocker remains.")
    lines.extend([
        "",
        "## Current Recommendation",
        f"- Doctor: {report['doctor'] or 'No Doctor diagnosis found.'}",
        "- Keep Studio Display as the default until the image-quality coach and visual proof beat it by eye.",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    report = collect()
    content = json.dumps(report, indent=2) if args.json else render_text(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content)
    print(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
