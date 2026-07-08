#!/usr/bin/env python3
"""C1 Studio 2026 readiness report."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
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


def run(cmd: list[str], timeout: int = 8) -> str:
    try:
        result = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout, check=False)
        return (result.stdout + result.stderr).strip()
    except Exception as exc:
        return f"{type(exc).__name__}: {exc}"


def list_devices() -> list[dict]:
    output = run(["ffmpeg", "-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""], timeout=8)
    devices = []
    in_video = False
    for line in output.splitlines():
        if "AVFoundation video devices:" in line:
            in_video = True
            continue
        if "AVFoundation audio devices:" in line:
            in_video = False
            continue
        if not in_video:
            continue
        match = re.search(r"\[(\d+)\]\s+(.+)$", line)
        if match:
            devices.append({"index": int(match.group(1)), "name": match.group(2).strip()})
    return devices


def read_first_lines(path: Path, count: int = 40) -> list[str]:
    if not path.exists():
        return []
    return path.read_text(errors="replace").splitlines()[:count]


def latest_benchmark_verdict() -> str:
    path = WORK / "c1-quality-bench-latest.md"
    for line in read_first_lines(path, 30):
        if line and not line.startswith("#") and line not in ("## Verdict",):
            if "C1" in line or "Benchmark incomplete" in line or "No decisive" in line:
                return line
    return "No benchmark report yet."


def latest_quality_coach_verdict() -> str:
    path = WORK / "c1-quality-coach-latest.md"
    for line in read_first_lines(path, 30):
        if line and not line.startswith("#") and line not in ("## Verdict",):
            if "C1" in line or "Quality coach blocked" in line or "No measured" in line:
                return line
    return "No quality coach report yet."


def latest_visual_score_verdict() -> str:
    path = WORK / "c1-visual-score-latest.md"
    for line in read_first_lines(path, 30):
        if line and not line.startswith("#") and line not in ("## Verdict",):
            if "Processed" in line or "No processed" in line or "C1" in line:
                return line
    return "No processed visual score report yet."


def latest_motion_verdict() -> str:
    path = WORK / "c1-motion-bench-latest.md"
    for line in read_first_lines(path, 30):
        if line and not line.startswith("#") and line not in ("## Verdict",):
            if "Motion" in line or "C1" in line:
                return line
    return "No motion bench report yet."


def latest_stability_verdict() -> str:
    path = WORK / "c1-stability-bench-latest.md"
    for line in read_first_lines(path, 30):
        if line and not line.startswith("#") and line not in ("## Verdict",):
            if "Stability" in line or "C1" in line:
                return line
    return "No call stability bench report yet."


def latest_release_score() -> str:
    path = WORK / "c1-release-score-latest.md"
    for line in read_first_lines(path, 20):
        if "Lab-Ready:" in line or "Release Candidate:" in line or "No-Go:" in line:
            return line
    return "No release score report yet."


def control_proof_status() -> str:
    root_probe = WORK / "c1-root-probe.json"
    if root_probe.exists():
        return "Root probe JSON exists; run promotion gate."
    path = WORK / "c1-control-proof-latest.md"
    for line in read_first_lines(path, 30):
        if "Direct UVC" in line or "Do not promote" in line:
            return line
    return "No control proof report yet."


def promotion_status() -> str:
    path = WORK / "c1-control-promotion-latest.md"
    for line in read_first_lines(path, 30):
        if line.startswith("Do not promote") or line.startswith("Promote"):
            return line
    return "No promotion verdict yet."


def opal_bridge_status() -> str:
    path = WORK / "c1-opal-bridge-latest.md"
    for line in read_first_lines(path, 35):
        if line and not line.startswith("#") and line not in ("## Verdict",):
            if "Opal bridge" in line:
                return line
    return "No Opal bridge probe report yet."


def doctor_recommendation() -> str:
    path = WORK / "c1-doctor-latest.md"
    if not path.exists():
        return "No doctor report yet; run `./script/build_and_run.sh --doctor`."
    lines = path.read_text(errors="replace").splitlines()
    for index, line in enumerate(lines):
        if line == "## Diagnosis" and index + 1 < len(lines):
            for candidate in lines[index + 1: index + 5]:
                if candidate.strip():
                    return candidate.strip()
    return "Doctor report exists; inspect `work/c1-doctor-latest.md`."


def collect() -> dict:
    devices = list_devices()
    names = [device["name"] for device in devices]
    system_extensions = run(["/bin/zsh", "-lc", "systemextensionsctl list | rg -i 'obs|opal|camera|extension'"], timeout=8)
    obs_extension = "com.obsproject.obs-studio.mac-camera-extension" in system_extensions
    data = {
        "workspace": str(ROOT),
        "devices": devices,
        "checks": {
            "opal_c1_listed": any("Opal C1" in name for name in names),
            "studio_display_listed": any("Studio Display" in name for name in names),
            "obs_virtual_camera_listed": any("OBS Virtual Camera" in name for name in names),
            "obs_camera_extension_active": obs_extension,
            "benchmark_report_exists": (WORK / "c1-quality-bench-latest.md").exists(),
            "motion_report_exists": (WORK / "c1-motion-bench-latest.md").exists(),
            "stability_report_exists": (WORK / "c1-stability-bench-latest.md").exists(),
            "quality_coach_report_exists": (WORK / "c1-quality-coach-latest.md").exists(),
            "coach_look_exists": (WORK / "c1-coach-look-latest.json").exists(),
            "calibration_report_exists": (WORK / "c1-calibration-latest.md").exists(),
            "visual_score_report_exists": (WORK / "c1-visual-score-latest.md").exists(),
            "processed_variants_exist": any((WORK / "visual-proof").glob("*-latest.jpg")) if (WORK / "visual-proof").exists() else False,
            "release_score_exists": (WORK / "c1-release-score-latest.md").exists(),
            "control_proof_exists": (WORK / "c1-control-proof-latest.md").exists(),
            "opal_bridge_report_exists": (WORK / "c1-opal-bridge-latest.md").exists(),
            "root_probe_exists": (WORK / "c1-root-probe.json").exists(),
            "promotion_report_exists": (WORK / "c1-control-promotion-latest.md").exists(),
            "doctor_report_exists": (WORK / "c1-doctor-latest.md").exists(),
        },
        "benchmark_verdict": latest_benchmark_verdict(),
        "motion_verdict": latest_motion_verdict(),
        "stability_verdict": latest_stability_verdict(),
        "quality_coach_verdict": latest_quality_coach_verdict(),
        "visual_score_verdict": latest_visual_score_verdict(),
        "release_score": latest_release_score(),
        "control_proof_status": control_proof_status(),
        "opal_bridge_status": opal_bridge_status(),
        "promotion_status": promotion_status(),
        "doctor_recommendation": doctor_recommendation(),
        "system_extensions_excerpt": system_extensions.splitlines()[:30],
    }
    checks = data["checks"]
    data["call_ready_bridge"] = bool(
        checks["opal_c1_listed"]
        and checks["obs_virtual_camera_listed"]
        and checks["obs_camera_extension_active"]
    )
    data["hardware_control_ready"] = bool(checks["root_probe_exists"] and "Promote" in data["promotion_status"])
    return data


def render_text(report: dict) -> str:
    checks = report["checks"]
    rows = [
        ("Opal C1 visible", checks["opal_c1_listed"]),
        ("Studio Display visible", checks["studio_display_listed"]),
        ("OBS Virtual Camera visible", checks["obs_virtual_camera_listed"]),
        ("OBS Camera Extension active", checks["obs_camera_extension_active"]),
        ("Benchmark report exists", checks["benchmark_report_exists"]),
        ("Motion bench report exists", checks["motion_report_exists"]),
        ("Call stability report exists", checks["stability_report_exists"]),
        ("Quality coach report exists", checks["quality_coach_report_exists"]),
        ("Coach look exists", checks["coach_look_exists"]),
        ("Calibration report exists", checks["calibration_report_exists"]),
        ("Processed visual score exists", checks["visual_score_report_exists"]),
        ("Processed proof variants exist", checks["processed_variants_exist"]),
        ("Release score exists", checks["release_score_exists"]),
        ("Control proof exists", checks["control_proof_exists"]),
        ("Opal bridge probe exists", checks["opal_bridge_report_exists"]),
        ("Root probe JSON exists", checks["root_probe_exists"]),
        ("Promotion report exists", checks["promotion_report_exists"]),
        ("Doctor report exists", checks["doctor_report_exists"]),
    ]
    lines = [
        "# C1 Studio Readiness",
        "",
        "## Verdict",
        f"- OBS bridge ready: {'yes' if report['call_ready_bridge'] else 'no'}",
        f"- Hardware controls ready: {'yes' if report['hardware_control_ready'] else 'no'}",
        "",
        "## Checklist",
        "",
        "| Check | Status |",
        "| --- | --- |",
    ]
    for label, ok in rows:
        lines.append(f"| {label} | {'pass' if ok else 'missing'} |")
    lines.extend([
        "",
        "## Camera Devices",
    ])
    lines.extend(f"- [{device['index']}] {device['name']}" for device in report["devices"])
    lines.extend([
        "",
        "## Evidence",
        f"- Benchmark: {report['benchmark_verdict']}",
        f"- Motion: {report['motion_verdict']}",
        f"- Call stability: {report['stability_verdict']}",
        f"- Quality coach: {report['quality_coach_verdict']}",
        f"- Processed visual score: {report['visual_score_verdict']}",
        f"- Release score: {report['release_score']}",
        f"- Hardware proof: {report['control_proof_status']}",
        f"- Opal bridge: {report['opal_bridge_status']}",
        f"- Promotion: {report['promotion_status']}",
        f"- Doctor: {report['doctor_recommendation']}",
        "",
        "## Next Actions",
    ])
    if not checks["obs_virtual_camera_listed"]:
        lines.append("- Open OBS and enable OBS Virtual Camera for the current bridge workflow.")
    if not checks["benchmark_report_exists"]:
        lines.append("- Run `./script/build_and_run.sh --benchmark`.")
    if not checks["motion_report_exists"]:
        lines.append("- Run `./script/build_and_run.sh --motion-bench`.")
    if not checks["stability_report_exists"]:
        lines.append("- Run `./script/build_and_run.sh --stability-bench`.")
    if not checks["quality_coach_report_exists"]:
        lines.append("- Run `./script/build_and_run.sh --quality-coach` after a benchmark.")
    if not checks["calibration_report_exists"] or not checks["visual_score_report_exists"]:
        lines.append("- Run `./script/build_and_run.sh --calibrate` to generate the learned look and processed proof package.")
    if not checks["release_score_exists"]:
        lines.append("- Run `./script/build_and_run.sh --release-score`.")
    if not checks["control_proof_exists"]:
        lines.append("- Run `./script/build_and_run.sh --control-proof`.")
    if not checks["opal_bridge_report_exists"]:
        lines.append("- Run `./script/build_and_run.sh --opal-bridge-probe`.")
    if not checks["root_probe_exists"]:
        lines.append("- Run the reversible root probe from the control proof report before promoting hardware controls.")
    if not checks["doctor_report_exists"]:
        lines.append("- Run `./script/build_and_run.sh --doctor` for the current daily-camera diagnosis.")
    if not lines[-1].startswith("-"):
        lines.append("- Ready for the OBS bridge path; hardware controls still require promotion evidence.")
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
