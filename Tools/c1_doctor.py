#!/usr/bin/env python3
"""Read-only C1 Studio camera-doctor verdict."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
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
OPAL_APP = Path("/Applications/Opal Composer.app")
FIRMWARE_NAMES = ("Opal582_v2.bin", "Opal_v0.12.bin", "tadpole_firmware.json")


def run(cmd: list[str], timeout: int = 12) -> str:
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


def read_text(path: Path, fallback: str = "") -> str:
    if not path.exists():
        return fallback
    return path.read_text(errors="replace")


def first_matching_line(path: Path, patterns: tuple[str, ...]) -> str:
    text = read_text(path)
    for line in text.splitlines():
        if not line.strip() or line.startswith("#") or line in ("## Verdict",):
            continue
        if any(pattern in line for pattern in patterns):
            return line.strip()
    return ""


def latest_reverse_json() -> dict:
    helper = ROOT / "Tools" / "c1_reverse_lab.py"
    if not helper.exists():
        return {"error": "reverse lab helper missing"}
    output = run([str(helper), "--json"], timeout=35)
    try:
        return json.loads(output)
    except Exception:
        return {"error": "reverse lab json parse failed", "output_tail": "\n".join(output.splitlines()[-20:])}


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def collect_firmware_payloads() -> list[dict]:
    if not OPAL_APP.exists():
        return []
    payloads = []
    for name in FIRMWARE_NAMES:
        for path in OPAL_APP.glob(f"Contents/**/{name}"):
            item = {
                "path": str(path),
                "name": name,
                "size": path.stat().st_size,
            }
            if path.is_file() and name.endswith((".bin", ".json")):
                item["sha256"] = hash_file(path)
                if name.endswith(".json"):
                    item["text_excerpt"] = read_text(path).strip()[:300]
            payloads.append(item)
    return sorted(payloads, key=lambda item: item["path"])


def apple_effects_status() -> str:
    output = read_text(WORK / "c1-apple-effects-latest.txt")
    if not output:
        return "No Apple effects probe output yet; run `./script/build_and_run.sh --apple-effects`."
    if "Supported Apple effect formats: none reported for C1" in output:
        return "No Apple Portrait, Studio Light, or Center Stage-capable C1 formats reported."
    return "Apple effects probe has non-empty output; inspect `work/c1-apple-effects-latest.txt`."


def visual_proof_gate() -> dict:
    path = WORK / "c1-visual-proof-latest.json"
    if not path.exists():
        return {"exists": False, "valid": False, "verdict": "Visual proof gate missing; rebuild visual proof."}
    try:
        gate = json.loads(path.read_text(errors="replace"))
    except Exception as exc:
        return {"exists": True, "valid": False, "verdict": f"Visual proof gate unreadable: {type(exc).__name__}: {exc}"}
    gate["exists"] = True
    gate["valid"] = bool(gate.get("valid"))
    gate["verdict"] = gate.get("verdict") or ("Face-valid proof." if gate["valid"] else "Face-invalid proof.")
    return gate


def opal_bridge_verdict() -> str:
    path = WORK / "c1-opal-bridge-latest.md"
    if not path.exists():
        return "No Opal bridge probe report yet."
    lines = path.read_text(errors="replace").splitlines()
    for index, line in enumerate(lines):
        if line == "## Verdict":
            for candidate in lines[index + 1: index + 6]:
                if candidate.strip():
                    return candidate.strip()
    return "Opal bridge probe exists; inspect `work/c1-opal-bridge-latest.md`."


def daily_recommendation(gate: dict) -> str:
    win_marker = WORK / "c1-visual-proof-win.txt"
    proof = WORK / "c1-visual-proof-latest.jpg"
    if win_marker.exists():
        if not gate.get("valid"):
            return "Use Studio Display. A visual win marker exists, but the latest visual proof is not face-valid."
        return "C1 allowed: visual proof has been manually marked as a win."
    if proof.exists():
        if not gate.get("valid"):
            return "Use Studio Display. Latest visual proof is not face-valid; recapture with a centered face before reconsidering C1."
        return "Use Studio Display. C1 remains lab/rescue-only unless `work/c1-visual-proof-win.txt` is intentionally created after a fresh visual win."
    return "Use Studio Display. Run benchmark + visual proof before reconsidering C1."


def collect() -> dict:
    reverse = latest_reverse_json()
    usb = reverse.get("usb", {}) if isinstance(reverse, dict) else {}
    control = reverse.get("control_proof", {}) if isinstance(reverse, dict) else {}
    devices = list_devices()
    firmware_payloads = collect_firmware_payloads()
    gate = visual_proof_gate()
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "workspace": str(ROOT),
        "devices": devices,
        "opal_c1_visible": any("Opal C1" in item["name"] for item in devices),
        "studio_display_visible": any("Studio Display" in item["name"] for item in devices),
        "usb": {
            "available": usb.get("available", False),
            "vendor_id": usb.get("vendor_id"),
            "product_id": usb.get("product_id"),
            "bcd_device": usb.get("bcd_device"),
            "serial": (usb.get("strings") or {}).get("serial"),
        },
        "firmware_payloads": firmware_payloads,
        "apple_effects": apple_effects_status(),
        "control_status": control.get("status", "unknown"),
        "opal_bridge_verdict": opal_bridge_verdict(),
        "control_counts": {
            "readable": control.get("readable_count", 0),
            "writable": control.get("writable_count", 0),
            "blocked": control.get("blocked_count", 0),
            "access_denied": control.get("access_denied_count", 0),
        },
        "benchmark_verdict": first_matching_line(WORK / "c1-quality-bench-latest.md", ("C1", "Benchmark incomplete", "No decisive")),
        "motion_verdict": first_matching_line(WORK / "c1-motion-bench-latest.md", ("Motion", "C1")),
        "stability_verdict": first_matching_line(WORK / "c1-stability-bench-latest.md", ("Stability", "C1")),
        "quality_coach_verdict": first_matching_line(WORK / "c1-quality-coach-latest.md", ("C1", "Quality coach blocked", "No measured")),
        "visual_score_verdict": first_matching_line(WORK / "c1-visual-score-latest.md", ("Processed", "No processed", "C1")),
        "release_score": first_matching_line(WORK / "c1-release-score-latest.md", ("Lab-Ready", "Release Candidate", "No-Go")),
        "visual_proof_exists": (WORK / "c1-visual-proof-latest.jpg").exists(),
        "visual_proof_gate": gate,
        "visual_win_marker_exists": (WORK / "c1-visual-proof-win.txt").exists(),
        "recommendation": daily_recommendation(gate),
        "reverse_error": reverse.get("error") if isinstance(reverse, dict) else "reverse report unavailable",
    }


def render_text(report: dict) -> str:
    usb = report["usb"]
    firmware_payloads = report["firmware_payloads"]
    lines = [
        "# C1 Studio Doctor",
        "",
        f"Generated: {report['generated_at']}",
        "",
        "## Diagnosis",
        report["recommendation"],
        "",
        "## Evidence",
        f"- Opal C1 visible: {'yes' if report['opal_c1_visible'] else 'no'}",
        f"- Studio Display visible: {'yes' if report['studio_display_visible'] else 'no'}",
        f"- USB: {'present' if usb['available'] else 'not proven'} ({usb.get('vendor_id')}:{usb.get('product_id')}), bcdDevice `{usb.get('bcd_device')}`",
        f"- Serial: `{usb.get('serial')}`",
        f"- Apple effects: {report['apple_effects']}",
        f"- Hardware controls: {report['control_status']} ({report['control_counts']['readable']} readable, {report['control_counts']['writable']} writable, {report['control_counts']['access_denied']} access-denied)",
        f"- Opal bridge: {report['opal_bridge_verdict']}",
        f"- Benchmark: {report['benchmark_verdict'] or 'No benchmark verdict found.'}",
        f"- Motion: {report['motion_verdict'] or 'No motion bench verdict found.'}",
        f"- Call stability: {report['stability_verdict'] or 'No call stability verdict found.'}",
        f"- Quality coach: {report['quality_coach_verdict'] or 'No quality coach report found.'}",
        f"- Processed visual score: {report['visual_score_verdict'] or 'No processed visual score found.'}",
        f"- Release score: {report['release_score'] or 'No release score found.'}",
        f"- Visual proof sheet: {'exists' if report['visual_proof_exists'] else 'missing'}",
        f"- Visual proof gate: {report['visual_proof_gate'].get('verdict', 'missing')}",
        "",
        "## Firmware",
    ]
    if usb.get("bcd_device"):
        lines.append(f"- Passive USB device version: `{usb['bcd_device']}`.")
    else:
        lines.append("- Passive USB device version: not available from this run.")
    if firmware_payloads:
        lines.append("- Installed Opal firmware/resource payloads found locally:")
        for item in firmware_payloads:
            if "sha256" in item:
                lines.append(f"  - `{item['name']}` `{item['sha256']}` ({item['size']} bytes) at `{item['path']}`")
            else:
                lines.append(f"  - `{item['name']}` ({item['size']} bytes) at `{item['path']}`")
    else:
        lines.append("- No installed Opal firmware payloads found under `/Applications/Opal Composer.app`.")
    lines.extend([
        "- No firmware flashing path is enabled or recommended.",
        "- Firmware is not the current proven blocker; image quality and control access are.",
        "",
        "## Next Gates",
        "- To reconsider C1, run `./script/build_and_run.sh --benchmark` with your face/framing in the real call setup.",
        "- Run `./script/build_and_run.sh --motion-bench` to verify the C1 motion/framerate thesis.",
        "- Run `./script/build_and_run.sh --stability-bench` to verify call-session luma/color stability.",
        "- Run `./script/build_and_run.sh --quality-coach` to turn the latest captures into setup fixes.",
        "- Then run `./script/build_and_run.sh --visual-proof` and `./script/build_and_run.sh --visual-score`.",
        "- Inspect `work/c1-visual-proof-latest.jpg`, `work/c1-visual-proof-latest.md`, and `work/c1-visual-score-latest.md`.",
        "- Only create `work/c1-visual-proof-win.txt` if C1 Coach Tuned or C1 Signature clearly beats Studio Display by eye.",
        "- Run the reversible root probe only if hardware controls are still worth pursuing.",
        "- Run `./script/build_and_run.sh --opal-bridge-probe` before treating Opal Composer as a control foundation.",
    ])
    if report.get("reverse_error"):
        lines.extend(["", "## Reverse Lab Warning", str(report["reverse_error"])])
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
