#!/usr/bin/env python3
"""Short motion/stability bench for C1 Studio 2026."""

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


def run_text(cmd: list[str], timeout: int = 10) -> str:
    try:
        result = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout, check=False)
        return (result.stdout + result.stderr).strip()
    except Exception as exc:
        return f"{type(exc).__name__}: {exc}"


def list_devices() -> list[dict]:
    output = run_text(["ffmpeg", "-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""], timeout=8)
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


def choose_device(devices: list[dict], needle: str) -> dict | None:
    lowered = needle.lower()
    for device in devices:
        if lowered in device["name"].lower():
            return device
    return None


def texture_score(luma: np.ndarray) -> float:
    if luma.shape[0] < 3 or luma.shape[1] < 3:
        return 0.0
    center = luma[1:-1, 1:-1]
    neighbor_average = (
        luma[:-2, 1:-1] + luma[2:, 1:-1] + luma[1:-1, :-2] + luma[1:-1, 2:]
    ) / 4.0
    return float(np.std(center - neighbor_average)) * 1000


def analyze_frames(raw: bytes, width: int, height: int) -> dict:
    frame_size = width * height * 3
    frame_count = len(raw) // frame_size
    if frame_count <= 0:
        return {"frame_count": 0}
    usable = raw[: frame_count * frame_size]
    frames = np.frombuffer(usable, dtype=np.uint8).reshape((frame_count, height, width, 3)).astype(np.float32) / 255.0
    luma = 0.2126 * frames[:, :, :, 0] + 0.7152 * frames[:, :, :, 1] + 0.0722 * frames[:, :, :, 2]
    brightness_by_frame = np.mean(luma, axis=(1, 2))
    frame_deltas = np.mean(np.abs(np.diff(luma, axis=0)), axis=(1, 2)) if frame_count > 1 else np.array([])
    texture_by_frame = np.array([texture_score(item) for item in luma])
    return {
        "frame_count": int(frame_count),
        "brightness_mean": round(float(np.mean(brightness_by_frame)), 4),
        "brightness_range": round(float(np.max(brightness_by_frame) - np.min(brightness_by_frame)), 4),
        "brightness_std": round(float(np.std(brightness_by_frame)), 4),
        "frame_delta_mean": round(float(np.mean(frame_deltas)), 4) if frame_deltas.size else 0.0,
        "frame_delta_p95": round(float(np.percentile(frame_deltas, 95)), 4) if frame_deltas.size else 0.0,
        "texture_mean": round(float(np.mean(texture_by_frame)), 4),
    }


def capture_motion(device: dict, size: str, fps: str, duration: float, sample_fps: int, timeout: int) -> dict:
    width = 320
    height = 180
    cmd = [
        "ffmpeg",
        "-hide_banner",
        "-nostdin",
        "-f", "avfoundation",
        "-framerate", fps,
        "-video_size", size,
        "-i", f"{device['name']}:none",
        "-t", str(duration),
        "-vf", f"scale={width}:{height},fps={sample_fps}",
        "-an",
        "-f", "rawvideo",
        "-pix_fmt", "rgb24",
        "-",
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, timeout=timeout, check=False)
        stderr = result.stderr.decode(errors="replace")
        analysis = analyze_frames(result.stdout, width, height)
        expected = max(1, int(round(duration * sample_fps)))
        frame_count = analysis.get("frame_count", 0)
        analysis.update({
            "ok": result.returncode == 0 and frame_count >= max(1, int(expected * 0.75)),
            "returncode": result.returncode,
            "mode": {"size": size, "fps": fps},
            "sample": {"width": width, "height": height, "fps": sample_fps, "duration": duration, "expected_frames": expected},
            "delivery_ratio": round(float(frame_count / expected), 3),
            "stderr_tail": "\n".join(stderr.splitlines()[-16:]),
            "command": " ".join(cmd[:-1] + ["<rawvideo>"]),
        })
        return analysis
    except subprocess.TimeoutExpired as exc:
        return {
            "ok": False,
            "returncode": 124,
            "mode": {"size": size, "fps": fps},
            "sample": {"width": width, "height": height, "fps": sample_fps, "duration": duration},
            "frame_count": 0,
            "delivery_ratio": 0.0,
            "stderr_tail": (exc.stderr or b"timed out").decode(errors="replace") if isinstance(exc.stderr, bytes) else str(exc.stderr or "timed out"),
            "command": " ".join(cmd[:-1] + ["<rawvideo>"]),
        }


def capture_with_fallbacks(device: dict | None, candidates: list[tuple[str, str]], duration: float, sample_fps: int, timeout: int) -> dict:
    if not device:
        return {"ok": False, "frame_count": 0, "stderr_tail": "device not listed by AVFoundation", "attempts": []}
    attempts = []
    for size, fps in candidates:
        attempt = capture_motion(device, size, fps, duration, sample_fps, timeout)
        attempts.append(dict(attempt))
        if attempt["ok"]:
            attempt["attempts"] = attempts
            return attempt
    result = attempts[-1] if attempts else {"ok": False, "frame_count": 0, "stderr_tail": "no candidates"}
    result["attempts"] = attempts
    return result


def verdict(report: dict) -> str:
    c1 = report["captures"].get("opal_c1", {})
    studio = report["captures"].get("studio_display", {})
    if not c1.get("ok") or not studio.get("ok"):
        return "Motion bench incomplete; one or both cameras failed the short capture."
    c1_fps = float(c1.get("mode", {}).get("fps", "0"))
    wins = []
    cautions = []
    if c1_fps >= 55:
        wins.append("C1 1080p60 path captured")
    else:
        cautions.append("C1 fell back below 60 fps in this motion bench")
    if c1.get("delivery_ratio", 0) < 0.9:
        cautions.append("C1 sampled-frame delivery was weak")
    if c1.get("brightness_range", 1) > max(0.06, studio.get("brightness_range", 0) * 1.6):
        cautions.append("C1 brightness drift was higher than Studio Display")
    if c1.get("texture_mean", 0) > studio.get("texture_mean", 0) * 1.8:
        cautions.append("C1 motion sample carries much more fine texture/noise")
    if cautions:
        return "Motion thesis not proven: " + "; ".join(cautions) + "."
    if wins:
        return "Motion thesis intact: " + "; ".join(wins) + " with stable short-sample delivery."
    return "Motion bench passed, but no unique C1 motion advantage was measured."


def collect(args: argparse.Namespace) -> dict:
    devices = list_devices()
    studio = choose_device(devices, "Studio Display")
    c1 = choose_device(devices, "Opal C1")
    captures = {
        "studio_display": capture_with_fallbacks(
            studio,
            [(args.studio_size, args.studio_fps), (args.studio_size, "30.000030"), ("1280x720", "30")],
            args.duration,
            args.sample_fps,
            args.timeout,
        ),
        "opal_c1": capture_with_fallbacks(
            c1,
            [(args.c1_size, args.c1_fps), (args.c1_size, "30"), ("1280x720", "30")],
            args.duration,
            args.sample_fps,
            args.timeout,
        ),
    }
    report = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "devices": devices,
        "captures": captures,
    }
    report["verdict"] = verdict(report)
    return report


def render_text(report: dict) -> str:
    lines = [
        "# C1 Motion Bench",
        "",
        f"Generated: {report['generated_at']}",
        "",
        "## Verdict",
        report["verdict"],
        "",
        "## Captures",
    ]
    for key, item in report["captures"].items():
        mode = item.get("mode") or {}
        sample = item.get("sample") or {}
        lines.append(
            f"- {key}: {'ok' if item.get('ok') else 'failed'} "
            f"`{mode.get('size', '?')} @ {mode.get('fps', '?')}` sampled "
            f"{item.get('frame_count', 0)}/{sample.get('expected_frames', '?')} frames"
        )
        if not item.get("ok"):
            lines.append(f"  - {item.get('stderr_tail', '')}")
    lines.extend([
        "",
        "## Scores",
        "",
        "| Camera | Input Mode | Frames | Delivery | Brightness Mean | Brightness Range | Brightness Drift | Motion Delta | Texture |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ])
    for key, item in report["captures"].items():
        mode = item.get("mode") or {}
        lines.append(
            f"| {key} | {mode.get('size', '?')} @ {mode.get('fps', '?')} | "
            f"{item.get('frame_count', 0)} | {item.get('delivery_ratio', 0)} | "
            f"{item.get('brightness_mean', '')} | {item.get('brightness_range', '')} | "
            f"{item.get('brightness_std', '')} | {item.get('frame_delta_p95', '')} | "
            f"{item.get('texture_mean', '')} |"
        )
    lines.extend([
        "",
        "## Evidence Boundary",
        "- This is a short downsampled raw-frame capture. It detects capture failure, brightness drift, sampled-frame delivery, and texture/noise.",
        "- It does not replace a real Zoom/Meet test, autofocus tracking test, or subjective motion review.",
        "- A C1 win still needs the visual proof sheet and live call behavior to beat Studio Display by eye.",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--duration", type=float, default=3.0)
    parser.add_argument("--sample-fps", type=int, default=10)
    parser.add_argument("--timeout", type=int, default=12)
    parser.add_argument("--c1-size", default="1920x1080")
    parser.add_argument("--c1-fps", default="60.000240")
    parser.add_argument("--studio-size", default="1920x1080")
    parser.add_argument("--studio-fps", default="30")
    args = parser.parse_args()

    report = collect(args)
    content = json.dumps(report, indent=2) if args.json else render_text(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content)
    print(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
