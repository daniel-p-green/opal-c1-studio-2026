#!/usr/bin/env python3
"""Turn the latest C1-vs-Studio benchmark frames into setup guidance."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path

import numpy as np


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
BENCH_REPORT = WORK / "c1-quality-bench-latest.md"
LOOK_OUTPUT = WORK / "c1-coach-look-latest.json"
VISUAL_GATE = WORK / "c1-visual-proof-latest.json"


def run(cmd: list[str], timeout: int = 12) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(cmd, text=True, capture_output=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired as exc:
        return subprocess.CompletedProcess(
            cmd,
            124,
            stdout=(exc.stdout or b"").decode(errors="replace") if isinstance(exc.stdout, bytes) else (exc.stdout or ""),
            stderr=(exc.stderr or b"").decode(errors="replace") if isinstance(exc.stderr, bytes) else (exc.stderr or "timed out"),
        )


def image_to_array(path: Path) -> np.ndarray:
    probe = run([
        "ffprobe",
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height",
        "-of", "json",
        str(path),
    ], timeout=8)
    data = json.loads(probe.stdout)
    stream = data["streams"][0]
    width = int(stream["width"])
    height = int(stream["height"])
    raw = subprocess.check_output([
        "ffmpeg",
        "-hide_banner",
        "-v", "error",
        "-i", str(path),
        "-f", "rawvideo",
        "-pix_fmt", "rgb24",
        "-",
    ], timeout=12)
    return np.frombuffer(raw, dtype=np.uint8).reshape((height, width, 3)).astype(np.float32) / 255.0


def parse_benchmark_paths() -> dict[str, Path]:
    if not BENCH_REPORT.exists():
        return {}
    captures: dict[str, Path] = {}
    pattern = re.compile(r"^- ([a-z0-9_]+): ok `([^`]+)`")
    for line in BENCH_REPORT.read_text(errors="replace").splitlines():
        match = pattern.match(line.strip())
        if not match:
            continue
        path = Path(match.group(2))
        if path.exists():
            captures[match.group(1)] = path
    return captures


def latest_visual_gate(paths: dict[str, Path]) -> dict:
    if not VISUAL_GATE.exists():
        return {
            "exists": False,
            "matched": False,
            "valid": None,
            "verdict": "Visual proof gate missing; run visual proof or face proof to validate face framing.",
        }
    try:
        gate = json.loads(VISUAL_GATE.read_text(errors="replace"))
    except Exception as exc:
        return {
            "exists": True,
            "matched": False,
            "valid": None,
            "verdict": f"Visual proof gate unreadable: {type(exc).__name__}: {exc}",
        }

    studio = paths.get("studio_display")
    c1 = paths.get("opal_c1")
    matched = bool(
        studio
        and c1
        and gate.get("studioImage") == studio.name
        and gate.get("opalImage") == c1.name
    )
    return {
        "exists": True,
        "matched": matched,
        "valid": bool(gate.get("valid")) if matched else None,
        "verdict": gate.get("verdict") or "Visual proof gate has no verdict.",
        "studio_image": gate.get("studioImage", ""),
        "opal_image": gate.get("opalImage", ""),
    }


def crop(rgb: np.ndarray, x0: float, y0: float, x1: float, y1: float) -> np.ndarray:
    height, width, _ = rgb.shape
    left = max(0, min(width - 1, int(width * x0)))
    right = max(left + 1, min(width, int(width * x1)))
    top = max(0, min(height - 1, int(height * y0)))
    bottom = max(top + 1, min(height, int(height * y1)))
    return rgb[top:bottom, left:right, :]


def basic_metrics(rgb: np.ndarray) -> dict:
    r = rgb[:, :, 0]
    g = rgb[:, :, 1]
    b = rgb[:, :, 2]
    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    maxc = np.max(rgb, axis=2)
    minc = np.min(rgb, axis=2)
    saturation = np.where(maxc > 0, (maxc - minc) / np.maximum(maxc, 1e-6), 0)
    gx = np.diff(luma, axis=1)
    gy = np.diff(luma, axis=0)
    sharpness = float(np.var(gx)) if gx.size else 0.0
    sharpness += float(np.var(gy)) if gy.size else 0.0
    if luma.shape[0] >= 3 and luma.shape[1] >= 3:
        center = luma[1:-1, 1:-1]
        neighbor_average = (
            luma[:-2, 1:-1] + luma[2:, 1:-1] + luma[1:-1, :-2] + luma[1:-1, 2:]
        ) / 4.0
        residual_texture = float(np.std(center - neighbor_average)) * 1000
    else:
        residual_texture = 0.0
    return {
        "brightness": round(float(np.mean(luma)), 4),
        "contrast": round(float(np.std(luma)), 4),
        "sharpness": round(sharpness * 10000, 4),
        "saturation": round(float(np.mean(saturation)), 4),
        "noise_texture": round(residual_texture, 4),
        "warmth_rb_delta": round(float(np.mean(r) - np.mean(b)), 4),
    }


def analyze_image(path: Path) -> dict:
    rgb = image_to_array(path)
    face_window = crop(rgb, 0.30, 0.18, 0.70, 0.72)
    left_window = crop(rgb, 0.12, 0.20, 0.42, 0.78)
    right_window = crop(rgb, 0.58, 0.20, 0.88, 0.78)
    background_window = np.concatenate([
        crop(rgb, 0.00, 0.00, 0.22, 1.00).reshape(-1, 3),
        crop(rgb, 0.78, 0.00, 1.00, 1.00).reshape(-1, 3),
    ]).reshape(-1, 1, 3)

    face = basic_metrics(face_window)
    overall = basic_metrics(rgb)
    left_brightness = basic_metrics(left_window)["brightness"]
    right_brightness = basic_metrics(right_window)["brightness"]
    background = basic_metrics(background_window)
    return {
        "path": str(path),
        "width": int(rgb.shape[1]),
        "height": int(rgb.shape[0]),
        "overall": overall,
        "face_window": face,
        "left_right_luma_delta": round(abs(left_brightness - right_brightness), 4),
        "background_brightness": background["brightness"],
        "subject_background_delta": round(face["brightness"] - background["brightness"], 4),
    }


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def suggested_look(studio: dict | None, c1: dict | None) -> dict:
    look = {
        "name": "Coach Tuned",
        "exposureEV": 0.0,
        "brightness": 0.0,
        "contrast": 1.0,
        "saturation": 1.0,
        "warmth": 0.06,
        "sharpness": 0.06,
        "vignette": 0.04,
        "portraitLift": 0.14,
        "noiseReduction": 0.42,
        "highlightSoftening": 0.34,
        "backgroundBlur": 0.18,
        "backgroundDim": 0.06,
        "autoFaceBalance": True,
        "autoStudioGrade": True,
        "studioGradeAmount": 0.58,
        "studioMatchAmount": 0.34,
        "studioMatchExposureEV": 0.0,
        "studioMatchWarmth": 0.0,
        "studioMatchSaturation": 1.0,
        "studioMatchContrast": 1.0,
        "skinToneProtect": 0.42,
        "mirror": True,
    }
    if not studio or not c1:
        return look

    c1_face = c1["face_window"]
    studio_face = studio["face_window"]
    brightness = c1_face["brightness"]
    warmth = c1_face["warmth_rb_delta"]
    saturation_ratio = c1_face["saturation"] / max(studio_face["saturation"], 1e-6)
    texture_ratio = c1_face["noise_texture"] / max(studio_face["noise_texture"], 1e-6)
    sharpness_ratio = c1_face["sharpness"] / max(studio_face["sharpness"], 1e-6)
    brightness_delta = studio_face["brightness"] - c1_face["brightness"]
    warmth_delta = studio_face["warmth_rb_delta"] - c1_face["warmth_rb_delta"]
    contrast_ratio = studio["overall"]["contrast"] / max(c1["overall"]["contrast"], 1e-6)

    look["exposureEV"] = round(clamp((0.52 - brightness) * 0.8, -0.18, 0.18), 3)
    look["brightness"] = round(clamp((0.52 - brightness) * 0.05, -0.025, 0.025), 3)
    look["studioMatchExposureEV"] = round(clamp(brightness_delta * 0.95, -0.18, 0.18), 3)
    look["studioMatchWarmth"] = round(clamp(warmth_delta * 1.55, -0.22, 0.22), 3)
    look["studioMatchSaturation"] = round(clamp(studio_face["saturation"] / max(c1_face["saturation"], 1e-6), 0.94, 1.08), 3)
    look["studioMatchContrast"] = round(clamp(contrast_ratio, 0.90, 1.06), 3)

    if warmth < -0.18:
        look["warmth"] = 0.24
    elif warmth < -0.11:
        look["warmth"] = 0.18
    elif warmth < -0.055:
        look["warmth"] = 0.12
    elif warmth > 0.07:
        look["warmth"] = -0.04

    if saturation_ratio > 1.18:
        look["saturation"] = 0.92
    elif saturation_ratio > 1.08:
        look["saturation"] = 0.97
    elif saturation_ratio < 0.88:
        look["saturation"] = 1.05

    if texture_ratio > 1.20 or sharpness_ratio > 1.35:
        look["sharpness"] = 0.02
        look["noiseReduction"] = 0.58
        look["highlightSoftening"] = 0.42
        look["contrast"] = 0.97
        look["studioGradeAmount"] = max(look["studioGradeAmount"], 0.72)
        look["studioMatchAmount"] = max(look["studioMatchAmount"], 0.42)
        look["skinToneProtect"] = max(look["skinToneProtect"], 0.58)
    elif texture_ratio > 1.08:
        look["sharpness"] = 0.04
        look["noiseReduction"] = 0.50
        look["studioGradeAmount"] = max(look["studioGradeAmount"], 0.64)
        look["studioMatchAmount"] = max(look["studioMatchAmount"], 0.38)
        look["skinToneProtect"] = max(look["skinToneProtect"], 0.50)

    if c1["subject_background_delta"] < 0.02:
        look["portraitLift"] = max(look["portraitLift"], 0.20)
        look["backgroundBlur"] = max(look["backgroundBlur"], 0.24)
        look["backgroundDim"] = max(look["backgroundDim"], 0.10)
    if c1["left_right_luma_delta"] > 0.10:
        look["portraitLift"] = min(max(look["portraitLift"], 0.18), 0.24)
        look["highlightSoftening"] = max(look["highlightSoftening"], 0.40)
        look["studioGradeAmount"] = max(look["studioGradeAmount"], 0.66)
        look["studioMatchAmount"] = max(look["studioMatchAmount"], 0.40)
        look["skinToneProtect"] = max(look["skinToneProtect"], 0.52)

    return look


def compare_and_advise(studio: dict | None, c1: dict | None, gate: dict) -> tuple[str, list[str], list[str]]:
    if not studio or not c1:
        return (
            "Quality coach blocked: latest matched Studio Display and C1 captures are missing.",
            ["Run `./script/build_and_run.sh --benchmark` first."],
            [],
        )
    if gate.get("matched") and gate.get("valid") is False:
        return (
            "Quality coach blocked: latest matched captures are not face-valid.",
            [
                gate.get("verdict", "Face gate failed."),
                "Run `./script/build_and_run.sh --face-proof` with a centered, visible face before judging C1 image quality.",
            ],
            [],
        )

    issues: list[str] = []
    wins: list[str] = []
    c1_face = c1["face_window"]
    studio_face = studio["face_window"]

    if c1_face["warmth_rb_delta"] < -0.055:
        issues.append("C1 is too cool/blue in the center window; warm the light or lock a warmer white balance.")
    elif c1_face["warmth_rb_delta"] > 0.07:
        issues.append("C1 is too warm/red in the center window; cool white balance before adding saturation.")

    if c1_face["brightness"] < 0.48:
        issues.append("Center exposure is low on C1; add front light before increasing gain.")
    elif c1_face["brightness"] > 0.70:
        issues.append("Center exposure is high on C1; reduce exposure before sharpening or contrast.")

    if c1["left_right_luma_delta"] > 0.10:
        issues.append("Lighting is uneven across the frame; move the key light closer to camera axis or soften it.")

    if c1["subject_background_delta"] < 0.02:
        issues.append("Subject does not separate from the background; add face light or dim the background.")

    if c1_face["saturation"] > studio_face["saturation"] * 1.18:
        issues.append("C1 saturation is noticeably hotter than Studio Display; reduce saturation before judging detail.")
    elif c1_face["saturation"] < studio_face["saturation"] * 0.85:
        issues.append("C1 color is flatter than Studio Display; add warmth first, then modest saturation.")

    if c1_face["sharpness"] > studio_face["sharpness"] * 1.30 and c1_face["noise_texture"] > studio_face["noise_texture"] * 1.08:
        issues.append("C1 detail is reading as texture/noise; soften sharpening or improve light before using Crisp looks.")

    if c1_face["sharpness"] > studio_face["sharpness"] * 1.10:
        wins.append("C1 has more center-window detail than Studio Display.")
    if c1["overall"]["contrast"] > studio["overall"]["contrast"] * 1.05:
        wins.append("C1 has stronger tonal separation.")
    if c1_face["noise_texture"] < studio_face["noise_texture"] * 0.95:
        wins.append("C1 is cleaner in the center-window texture metric.")

    if not issues and wins:
        verdict = "C1 is promising in this setup; inspect the visual proof and consider marking a visual win only if it wins by eye."
    elif not issues:
        verdict = "C1 is technically acceptable, but it has not produced a remarkable advantage yet."
    else:
        verdict = "C1 is not ready to replace Studio Display in this setup; fix the setup issues below before judging the camera."
    return verdict, issues, wins


def collect() -> dict:
    paths = parse_benchmark_paths()
    gate = latest_visual_gate(paths)
    studio = analyze_image(paths["studio_display"]) if "studio_display" in paths else None
    c1 = analyze_image(paths["opal_c1"]) if "opal_c1" in paths else None
    verdict, issues, wins = compare_and_advise(studio, c1, gate)
    look = suggested_look(studio, c1)
    LOOK_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    LOOK_OUTPUT.write_text(json.dumps(look, indent=2))
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "benchmark_report": str(BENCH_REPORT),
        "studio_display": studio,
        "opal_c1": c1,
        "visual_gate": gate,
        "verdict": verdict,
        "setup_actions": issues,
        "c1_advantages": wins,
        "suggested_look": look,
        "suggested_look_path": str(LOOK_OUTPUT),
    }


def render_text(report: dict) -> str:
    lines = [
        "# C1 Quality Coach",
        "",
        f"Generated: {report['generated_at']}",
        "",
        "## Verdict",
        report["verdict"],
        "",
        "## What To Change First",
    ]
    actions = report["setup_actions"]
    if actions:
        lines.extend(f"- {action}" for action in actions)
    else:
        lines.append("- No major setup flaw detected from the latest still frames; judge by the visual proof sheet and motion.")

    lines.extend(["", "## C1 Advantages To Verify"])
    wins = report["c1_advantages"]
    if wins:
        lines.extend(f"- {win}" for win in wins)
    else:
        lines.append("- No measured C1 advantage is strong enough yet. Studio Display remains the honest default.")

    look = report["suggested_look"]
    lines.extend([
        "",
        "## Suggested Software Look",
        f"- File: `{report['suggested_look_path']}`",
        f"- Exposure: {look['exposureEV']:+.3f} EV",
        f"- Warmth: {look['warmth']:+.2f}",
        f"- Saturation: {look['saturation']:.2f}",
        f"- Sharpness: {look['sharpness']:.2f}",
        f"- Clean: {look['noiseReduction']:.2f}",
        f"- Auto Face Balance: {'on' if look.get('autoFaceBalance') else 'off'}",
        f"- Studio Grade: {'on' if look.get('autoStudioGrade') else 'off'} @ {look.get('studioGradeAmount', 0):.2f}",
        f"- Studio Match: {look.get('studioMatchAmount', 0):.2f} (EV {look.get('studioMatchExposureEV', 0):+.3f}, warmth {look.get('studioMatchWarmth', 0):+.3f}, sat {look.get('studioMatchSaturation', 1):.2f}, contrast {look.get('studioMatchContrast', 1):.2f})",
        f"- Skin Protect: {look.get('skinToneProtect', 0):.2f}",
        f"- Portrait Light: {look['portraitLift']:.2f}",
        f"- Background Blur/Dim: {look['backgroundBlur']:.2f}/{look['backgroundDim']:.2f}",
    ])

    lines.extend([
        "",
        "## Metrics",
        "",
        "| Camera | Center Brightness | Center Warmth R-B | Center Saturation | Center Sharpness | Center Texture | Side-Light Delta | Center/Background |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ])
    for key, label in (("studio_display", "Studio Display"), ("opal_c1", "Opal C1")):
        item = report.get(key)
        if not item:
            continue
        face = item["face_window"]
        lines.append(
            f"| {label} | {face['brightness']} | {face['warmth_rb_delta']} | {face['saturation']} | "
            f"{face['sharpness']} | {face['noise_texture']} | {item['left_right_luma_delta']} | "
            f"{item['subject_background_delta']} |"
        )

    lines.extend([
        "",
        "## Face Gate",
        report["visual_gate"].get("verdict", "Visual proof gate unavailable."),
        f"- Gate matched latest benchmark captures: {'yes' if report['visual_gate'].get('matched') else 'no'}",
        f"- Face-valid captures: {report['visual_gate'].get('valid') if report['visual_gate'].get('matched') else 'unknown'}",
        "",
        "## Evidence Boundary",
        "- This coach uses fixed center-window and frame metrics from the latest benchmark stills.",
        "- It treats those center-window metrics as face-quality evidence only when the visual-proof face gate matches and passes.",
        "- It does not score autofocus hunting, exposure drift, rolling shutter, video-call compression, or motion cadence.",
        "- A C1 win still requires visual proof by eye in the actual call setup.",
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
