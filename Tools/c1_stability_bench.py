#!/usr/bin/env python3
"""Call-session stability bench for C1 Studio 2026."""

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


def linear_drift(values: np.ndarray) -> float:
    if values.size < 2:
        return 0.0
    x = np.arange(values.size, dtype=np.float32)
    slope = np.polyfit(x, values.astype(np.float32), 1)[0]
    return float(slope * max(0, values.size - 1))


def analyze_frames(raw: bytes, width: int, height: int, sample_fps: int, duration: float) -> dict:
    frame_size = width * height * 3
    frame_count = len(raw) // frame_size
    expected = max(1, int(round(duration * sample_fps)))
    if frame_count <= 0:
        return {
            "frame_count": 0,
            "expected_frames": expected,
            "delivery_ratio": 0.0,
            "stale_frame_ratio": 1.0,
        }

    usable = raw[: frame_count * frame_size]
    frames = np.frombuffer(usable, dtype=np.uint8).reshape((frame_count, height, width, 3)).astype(np.float32) / 255.0
    r = frames[:, :, :, 0]
    g = frames[:, :, :, 1]
    b = frames[:, :, :, 2]
    luma = 0.2126 * r + 0.7152 * g + 0.0722 * b

    maxc = np.max(frames, axis=3)
    minc = np.min(frames, axis=3)
    saturation = np.where(maxc > 0, (maxc - minc) / np.maximum(maxc, 1e-6), 0)

    brightness = np.mean(luma, axis=(1, 2))
    warmth = np.mean(r - b, axis=(1, 2))
    sat = np.mean(saturation, axis=(1, 2))
    textures = np.array([texture_score(item) for item in luma])
    deltas = np.mean(np.abs(np.diff(luma, axis=0)), axis=(1, 2)) if frame_count > 1 else np.array([])
    stale_ratio = float(np.mean(deltas < 0.0005)) if deltas.size else 1.0

    bucket_size = max(1, sample_fps)

    def bucket_means(values: np.ndarray) -> list[float]:
        buckets = []
        for start in range(0, values.size, bucket_size):
            bucket = values[start : start + bucket_size]
            if bucket.size:
                buckets.append(round(float(np.mean(bucket)), 5))
        return buckets

    return {
        "frame_count": int(frame_count),
        "expected_frames": expected,
        "delivery_ratio": round(float(frame_count / expected), 3),
        "brightness_mean": round(float(np.mean(brightness)), 4),
        "brightness_std": round(float(np.std(brightness)), 5),
        "brightness_range": round(float(np.max(brightness) - np.min(brightness)), 5),
        "brightness_drift": round(linear_drift(brightness), 5),
        "warmth_mean": round(float(np.mean(warmth)), 5),
        "warmth_std": round(float(np.std(warmth)), 5),
        "warmth_range": round(float(np.max(warmth) - np.min(warmth)), 5),
        "warmth_drift": round(linear_drift(warmth), 5),
        "saturation_mean": round(float(np.mean(sat)), 5),
        "saturation_std": round(float(np.std(sat)), 5),
        "texture_mean": round(float(np.mean(textures)), 4),
        "texture_range": round(float(np.max(textures) - np.min(textures)), 4),
        "motion_delta_mean": round(float(np.mean(deltas)), 5) if deltas.size else 0.0,
        "motion_delta_p95": round(float(np.percentile(deltas, 95)), 5) if deltas.size else 0.0,
        "stale_frame_ratio": round(stale_ratio, 4),
        "second_brightness": bucket_means(brightness),
        "second_warmth": bucket_means(warmth),
    }


def capture_stability(device: dict, size: str, fps: str, duration: float, sample_fps: int, timeout: int) -> dict:
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
        analysis = analyze_frames(result.stdout, width, height, sample_fps, duration)
        frame_count = analysis.get("frame_count", 0)
        analysis.update({
            "ok": result.returncode == 0 and frame_count >= max(1, int(analysis["expected_frames"] * 0.75)),
            "returncode": result.returncode,
            "mode": {"size": size, "fps": fps},
            "sample": {"width": width, "height": height, "fps": sample_fps, "duration": duration},
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
            "expected_frames": max(1, int(round(duration * sample_fps))),
            "delivery_ratio": 0.0,
            "stale_frame_ratio": 1.0,
            "stderr_tail": (exc.stderr or b"timed out").decode(errors="replace") if isinstance(exc.stderr, bytes) else str(exc.stderr or "timed out"),
            "command": " ".join(cmd[:-1] + ["<rawvideo>"]),
        }


def capture_with_fallbacks(device: dict | None, candidates: list[tuple[str, str]], duration: float, sample_fps: int, timeout: int) -> dict:
    if not device:
        return {"ok": False, "frame_count": 0, "stderr_tail": "device not listed by AVFoundation", "attempts": []}
    attempts = []
    for size, fps in candidates:
        attempt = capture_stability(device, size, fps, duration, sample_fps, timeout)
        attempts.append(dict(attempt))
        if attempt["ok"]:
            attempt["attempts"] = attempts
            return attempt
    result = attempts[-1] if attempts else {"ok": False, "frame_count": 0, "stderr_tail": "no candidates"}
    result["attempts"] = attempts
    return result


def capture_issues(label: str, item: dict) -> list[str]:
    issues = []
    if not item.get("ok"):
        issues.append(f"{label} capture failed")
        return issues
    if item.get("delivery_ratio", 0) < 0.92:
        issues.append(f"{label} dropped or failed to deliver sampled frames")
    if abs(float(item.get("brightness_drift", 0))) > 0.025:
        issues.append(f"{label} exposure/luma drift is high")
    if float(item.get("brightness_range", 0)) > 0.06:
        issues.append(f"{label} brightness flicker range is high")
    if abs(float(item.get("warmth_drift", 0))) > 0.018:
        issues.append(f"{label} white-balance/color drift is high")
    if float(item.get("warmth_range", 0)) > 0.045:
        issues.append(f"{label} color flicker range is high")
    if float(item.get("stale_frame_ratio", 0)) > 0.35:
        issues.append(f"{label} stale-frame ratio is high")
    return issues


def verdict(report: dict) -> str:
    c1 = report["captures"].get("opal_c1", {})
    studio = report["captures"].get("studio_display", {})
    if not c1.get("ok"):
        return "Stability blocked: Opal C1 did not complete the call-session capture."
    issues = capture_issues("C1", c1)
    studio_issues = capture_issues("Studio Display", studio) if studio else []
    if issues:
        return "Stability warning: " + "; ".join(issues) + "."
    if studio.get("ok"):
        advantages = []
        if c1.get("delivery_ratio", 0) >= studio.get("delivery_ratio", 0):
            advantages.append("sample delivery matched Studio Display")
        if c1.get("brightness_range", 1) <= max(0.015, float(studio.get("brightness_range", 0)) * 1.25):
            advantages.append("luma drift stayed competitive")
        if c1.get("warmth_range", 1) <= max(0.012, float(studio.get("warmth_range", 0)) * 1.35):
            advantages.append("color drift stayed competitive")
        if advantages:
            return "Stability pass: C1 completed the call-session sample; " + "; ".join(advantages) + "."
    if studio_issues:
        return "Stability pass: C1 completed the call-session sample; Studio Display comparison had its own instability."
    return "Stability pass: C1 completed the call-session sample with acceptable delivery, luma drift, and color drift."


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
        "duration": args.duration,
        "sample_fps": args.sample_fps,
        "captures": captures,
    }
    report["verdict"] = verdict(report)
    return report


def render_text(report: dict) -> str:
    lines = [
        "# C1 Call Stability Bench",
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
        lines.append(
            f"- {key}: {'ok' if item.get('ok') else 'failed'} "
            f"`{mode.get('size', '?')} @ {mode.get('fps', '?')}` "
            f"sampled {item.get('frame_count', 0)}/{item.get('expected_frames', '?')} frames"
        )
        if not item.get("ok"):
            lines.append(f"  - {item.get('stderr_tail', '')}")
    lines.extend([
        "",
        "## Stability Metrics",
        "",
        "| Camera | Delivery | Brightness Mean | Brightness Range | Brightness Drift | Warmth Range | Warmth Drift | Stale Frames | Texture |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ])
    for key, item in report["captures"].items():
        lines.append(
            f"| {key} | {item.get('delivery_ratio', 0)} | "
            f"{item.get('brightness_mean', '')} | {item.get('brightness_range', '')} | "
            f"{item.get('brightness_drift', '')} | {item.get('warmth_range', '')} | "
            f"{item.get('warmth_drift', '')} | {item.get('stale_frame_ratio', '')} | "
            f"{item.get('texture_mean', '')} |"
        )
    lines.extend([
        "",
        "## Per-Second Trace",
        "",
        "| Camera | Brightness | Warmth R-B |",
        "| --- | --- | --- |",
    ])
    for key, item in report["captures"].items():
        lines.append(
            f"| {key} | {', '.join(str(v) for v in item.get('second_brightness', []))} | "
            f"{', '.join(str(v) for v in item.get('second_warmth', []))} |"
        )
    lines.extend([
        "",
        "## Evidence Boundary",
        "- This is a short call-session proxy, not a full Zoom/Meet certification.",
        "- It detects capture failure, sampled-frame delivery, stale frames, luma drift, and color drift.",
        "- It does not prove autofocus tracking, real network-call behavior, or a subjective visual win.",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--duration", type=float, default=8.0)
    parser.add_argument("--sample-fps", type=int, default=8)
    parser.add_argument("--timeout", type=int, default=18)
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
