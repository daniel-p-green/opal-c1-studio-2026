#!/usr/bin/env python3
"""Score processed C1 visual-proof variants against Studio Display."""

from __future__ import annotations

import argparse
import json
import os
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
GATE_JSON = WORK / "c1-visual-proof-latest.json"


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


def crop(rgb: np.ndarray, x0: float, y0: float, x1: float, y1: float) -> np.ndarray:
    height, width, _ = rgb.shape
    left = max(0, min(width - 1, int(width * x0)))
    right = max(left + 1, min(width, int(width * x1)))
    top = max(0, min(height - 1, int(height * y0)))
    bottom = max(top + 1, min(height, int(height * y1)))
    return rgb[top:bottom, left:right, :]


def metrics(path: Path) -> dict:
    rgb = image_to_array(path)
    center = crop(rgb, 0.30, 0.18, 0.70, 0.72)
    r = center[:, :, 0]
    g = center[:, :, 1]
    b = center[:, :, 2]
    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    maxc = np.max(center, axis=2)
    minc = np.min(center, axis=2)
    saturation = np.where(maxc > 0, (maxc - minc) / np.maximum(maxc, 1e-6), 0)
    gx = np.diff(luma, axis=1)
    gy = np.diff(luma, axis=0)
    sharpness = float(np.var(gx) + np.var(gy)) * 10000
    residual = luma[1:-1, 1:-1] - (
        luma[:-2, 1:-1] + luma[2:, 1:-1] + luma[1:-1, :-2] + luma[1:-1, 2:]
    ) / 4.0
    return {
        "brightness": round(float(np.mean(luma)), 4),
        "contrast": round(float(np.std(luma)), 4),
        "sharpness": round(sharpness, 4),
        "saturation": round(float(np.mean(saturation)), 4),
        "texture": round(float(np.std(residual)) * 1000, 4),
        "warmth_rb_delta": round(float(np.mean(r) - np.mean(b)), 4),
        "width": int(rgb.shape[1]),
        "height": int(rgb.shape[0]),
    }


def load_gate() -> dict:
    if not GATE_JSON.exists():
        return {"valid": False, "verdict": "Visual proof gate missing.", "variants": []}
    try:
        gate = json.loads(GATE_JSON.read_text(errors="replace"))
    except Exception as exc:
        return {"valid": False, "verdict": f"Visual proof gate unreadable: {type(exc).__name__}: {exc}", "variants": []}
    gate["valid"] = bool(gate.get("valid"))
    gate["verdict"] = gate.get("verdict") or ("Face-valid proof." if gate["valid"] else "Face-invalid proof.")
    gate["variants"] = gate.get("variants") or []
    return gate


def variant_scores(gate: dict) -> list[dict]:
    rows: list[dict] = []
    for variant in gate.get("variants", []):
        path = Path(variant.get("path", ""))
        if not path.exists():
            continue
        try:
            item = {
                "role": variant.get("role", ""),
                "title": variant.get("title", ""),
                "path": str(path),
                "metrics": metrics(path),
            }
        except Exception as exc:
            item = {
                "role": variant.get("role", ""),
                "title": variant.get("title", ""),
                "path": str(path),
                "error": f"{type(exc).__name__}: {exc}",
            }
        rows.append(item)
    return rows


def score_candidate(studio: dict, candidate: dict) -> float:
    sm = studio["metrics"]
    cm = candidate["metrics"]
    score = 0.0
    brightness_delta = abs(cm["brightness"] - sm["brightness"])
    warmth_delta = abs(cm["warmth_rb_delta"] - sm["warmth_rb_delta"])
    texture_ratio = cm["texture"] / max(sm["texture"], 1e-6)
    sharpness_ratio = cm["sharpness"] / max(sm["sharpness"], 1e-6)
    score += max(0.0, 1.0 - brightness_delta / 0.10) * 25
    score += max(0.0, 1.0 - warmth_delta / 0.06) * 20
    score += min(max(sharpness_ratio - 1.0, 0.0), 0.55) * 35
    score -= max(texture_ratio - 1.15, 0.0) * 18
    score += max(0.0, 1.0 - abs(cm["saturation"] - sm["saturation"]) / 0.08) * 12
    return round(score, 2)


def collect() -> dict:
    gate = load_gate()
    rows = variant_scores(gate)
    studio = next((row for row in rows if row.get("role") == "studio_display" and "metrics" in row), None)
    candidates = [row for row in rows if row.get("role", "").startswith("c1_") and "metrics" in row]
    for row in candidates:
        row["score"] = score_candidate(studio, row) if studio else 0
    best = max(candidates, key=lambda row: row.get("score", 0), default=None)
    if not gate["valid"]:
        verdict = "Processed visual score blocked: latest visual proof is not face-valid."
    elif not studio or not best:
        verdict = "Processed visual score blocked: proof variants are missing."
    elif best.get("score", 0) >= 38:
        verdict = f"Processed C1 candidate to inspect: {best['title']} has the strongest measured balance, but still needs a human visual win."
    else:
        verdict = "No processed C1 candidate has a strong enough measured edge over Studio Display."
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "gate": gate,
        "variants": rows,
        "best": best,
        "verdict": verdict,
    }


def render_text(report: dict) -> str:
    lines = [
        "# C1 Processed Visual Score",
        "",
        f"Generated: {report['generated_at']}",
        "",
        "## Verdict",
        report["verdict"],
        "",
        "## Face Gate",
        report["gate"].get("verdict", "Visual proof gate unavailable."),
        "",
        "## Variants",
        "",
        "| Variant | Score | Brightness | Warmth R-B | Saturation | Sharpness | Texture |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in report["variants"]:
        metrics_row = row.get("metrics")
        if not metrics_row:
            lines.append(f"| {row.get('title', row.get('role', 'unknown'))} |  |  |  |  |  |  |")
            continue
        lines.append(
            f"| {row.get('title', row.get('role', 'unknown'))} | {row.get('score', '')} | "
            f"{metrics_row['brightness']} | {metrics_row['warmth_rb_delta']} | {metrics_row['saturation']} | "
            f"{metrics_row['sharpness']} | {metrics_row['texture']} |"
        )
    lines.extend([
        "",
        "## Evidence Boundary",
        "- Scores use saved processed visual-proof images, not the raw camera stream alone.",
        "- A blocked face gate blocks the processed score from supporting a C1 win.",
        "- This is a guardrail and ranking aid; a daily-camera win still requires visual inspection in the actual call setup.",
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
