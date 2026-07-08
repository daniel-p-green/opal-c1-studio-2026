#!/usr/bin/env python3
"""Capture and score local webcam frames for C1 Studio 2026."""

from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np


def workspace_root() -> Path:
    env_root = os_environ_root()
    if env_root:
        return env_root
    for candidate in [Path.cwd(), *Path(__file__).resolve().parents]:
        if (candidate / "Package.swift").exists():
            return candidate
    return Path.cwd()


def os_environ_root() -> Path | None:
    import os

    value = os.environ.get("C1_STUDIO_WORKSPACE")
    if not value:
        return None
    path = Path(value).expanduser()
    return path if path.exists() else None


ROOT = workspace_root()
WORK = ROOT / "work" / "quality-bench"


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


def list_devices() -> list[dict]:
    result = run(["ffmpeg", "-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""], timeout=8)
    devices = []
    in_video = False
    for line in (result.stderr + result.stdout).splitlines():
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


def choose_device(devices: list[dict], needle: str) -> dict | None:
    lowered = needle.lower()
    for device in devices:
        if lowered in device["name"].lower():
            return device
    return None


def capture_frame(device: dict, out_path: Path, size: str, fps: str, timeout: int) -> dict:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-y",
        "-f", "avfoundation",
        "-framerate", fps,
        "-video_size", size,
        "-i", f"{device['name']}:none",
        "-frames:v", "1",
        "-update", "1",
        str(out_path),
    ]
    result = run(cmd, timeout=timeout)
    return {
        "device": device,
        "path": str(out_path),
        "ok": result.returncode == 0 and out_path.exists() and out_path.stat().st_size > 0,
        "returncode": result.returncode,
        "stderr_tail": "\n".join((result.stderr + result.stdout).splitlines()[-20:]),
        "command": " ".join(cmd),
    }


def capture_with_fallbacks(device: dict, out_stem: str, candidates: list[tuple[str, str]], timeout: int) -> dict:
    attempts = []
    for index, (size, fps) in enumerate(candidates):
        suffix = "" if index == 0 else f"-try{index + 1}"
        out_path = WORK / f"{out_stem}{suffix}.jpg"
        attempt = capture_frame(device, out_path, size, fps, timeout)
        attempt["mode"] = {"size": size, "fps": fps}
        attempts.append(attempt)
        if attempt["ok"]:
            result = dict(attempt)
            result["attempts"] = [dict(item) for item in attempts]
            return result
    result = attempts[-1] if attempts else {"ok": False, "path": "", "stderr_tail": "no capture candidates"}
    result = dict(result)
    result["attempts"] = [dict(item) for item in attempts]
    return result


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


def score_image(path: Path) -> dict:
    rgb = image_to_array(path)
    r = rgb[:, :, 0]
    g = rgb[:, :, 1]
    b = rgb[:, :, 2]
    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b

    maxc = np.max(rgb, axis=2)
    minc = np.min(rgb, axis=2)
    saturation = np.where(maxc > 0, (maxc - minc) / np.maximum(maxc, 1e-6), 0)

    gx = np.diff(luma, axis=1)
    gy = np.diff(luma, axis=0)
    sharpness = float(np.var(gx) + np.var(gy))

    # High-frequency residual approximation: useful as a relative noise/texture signal.
    center = luma[1:-1, 1:-1]
    neighbor_average = (
        luma[:-2, 1:-1] + luma[2:, 1:-1] + luma[1:-1, :-2] + luma[1:-1, 2:]
    ) / 4.0
    residual = center - neighbor_average

    return {
        "brightness": round(float(np.mean(luma)), 4),
        "contrast": round(float(np.std(luma)), 4),
        "sharpness": round(sharpness * 10000, 4),
        "saturation": round(float(np.mean(saturation)), 4),
        "noise_texture": round(float(np.std(residual)) * 1000, 4),
        "warmth_rb_delta": round(float(np.mean(r) - np.mean(b)), 4),
        "width": int(rgb.shape[1]),
        "height": int(rgb.shape[0]),
    }


def verdict(scores: dict) -> str:
    c1 = scores.get("opal_c1", {}).get("score")
    studio = scores.get("studio_display", {}).get("score")
    if not c1 or not studio:
        return "Benchmark incomplete; one or both captures failed."

    wins = []
    if c1["sharpness"] > studio["sharpness"] * 1.08:
        wins.append("C1 has materially higher edge detail")
    if c1["contrast"] > studio["contrast"] * 1.05:
        wins.append("C1 has stronger tonal separation")
    if c1["noise_texture"] < studio["noise_texture"] * 0.92:
        wins.append("C1 appears cleaner in fine texture")
    if not wins:
        return "No decisive C1 advantage from this still-frame bench; use motion/framerate and manual controls as the C1 thesis."
    return "; ".join(wins) + "."


def render_text(report: dict) -> str:
    lines = [
        "# C1 Quality Bench",
        "",
        f"Generated: {report['generated_at']}",
        "",
        "## Verdict",
        report["verdict"],
        "",
        "## Captures",
    ]
    for key, item in report["captures"].items():
        lines.append(f"- {key}: {'ok' if item['ok'] else 'failed'} `{item['path']}`")
        if not item["ok"]:
            lines.append(f"  - {item['stderr_tail']}")
    lines.extend([
        "",
        "## Scores",
        "",
        "| Camera | Mode | Brightness | Contrast | Sharpness | Saturation | Noise/Texture | Warmth R-B | Size |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ])
    for key, item in report["captures"].items():
        score = item.get("score")
        if not score:
            continue
        mode = item.get("mode") or {}
        mode_label = f"{mode.get('size', '?')} @ {mode.get('fps', '?')}"
        lines.append(
            f"| {key} | {mode_label} | {score['brightness']} | {score['contrast']} | {score['sharpness']} | "
            f"{score['saturation']} | {score['noise_texture']} | {score['warmth_rb_delta']} | "
            f"{score['width']}x{score['height']} |"
        )
    lines.extend([
        "",
        "## Notes",
        "- This is a still-frame bench. It does not score autofocus stability, exposure drift, rolling shutter, or motion cadence.",
        "- Higher sharpness is not always better for faces; use it as evidence, not a taste verdict.",
        "- Run under the same lighting and framing for C1 and Studio Display to make the comparison meaningful.",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--text", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--timeout", type=int, default=16)
    parser.add_argument("--c1-size", default="1920x1080")
    parser.add_argument("--c1-fps", default="60.000240")
    parser.add_argument("--studio-size", default="1920x1080")
    parser.add_argument("--studio-fps", default="30")
    parser.add_argument("--inter-capture-delay", type=float, default=1.0)
    args = parser.parse_args()

    devices = list_devices()
    c1 = choose_device(devices, "Opal C1")
    studio = choose_device(devices, "Studio Display")
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    captures: dict[str, dict] = {}

    if studio:
        captures["studio_display"] = capture_with_fallbacks(
            studio,
            f"studio-display-{timestamp}",
            [(args.studio_size, args.studio_fps), (args.studio_size, "30.000030"), ("1280x720", "30")],
            args.timeout,
        )
    else:
        captures["studio_display"] = {"ok": False, "path": "", "stderr_tail": "Studio Display Camera not listed by AVFoundation"}
    time.sleep(args.inter_capture_delay)
    if c1:
        captures["opal_c1"] = capture_with_fallbacks(
            c1,
            f"opal-c1-{timestamp}",
            [(args.c1_size, args.c1_fps), (args.c1_size, "30"), ("1280x720", "30")],
            args.timeout,
        )
    else:
        captures["opal_c1"] = {"ok": False, "path": "", "stderr_tail": "Opal C1 not listed by AVFoundation"}

    for item in captures.values():
        if item.get("ok"):
            try:
                item["score"] = score_image(Path(item["path"]))
            except Exception as exc:
                item["ok"] = False
                item["score_error"] = str(exc)

    report = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "devices": devices,
        "captures": captures,
        "verdict": verdict({"opal_c1": captures.get("opal_c1", {}), "studio_display": captures.get("studio_display", {})}),
    }

    content = json.dumps(report, indent=2) if args.json else render_text(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content)
    print(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
