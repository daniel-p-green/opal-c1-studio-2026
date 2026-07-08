# C1 Quality Benchmark

The benchmark answers the practical question: in this room, under this lighting, is the Opal C1 worth choosing over the Studio Display camera?

## What It Does

- Captures one still frame from `Opal C1 (ctrl)` at `1920x1080@60.000240`.
- Captures one still frame from `Studio Display Camera` at `1920x1080@30`.
- Computes brightness, contrast, sharpness, saturation, fine texture/noise, and red-blue warmth.
- Writes a Markdown report and the captured frames under `work/quality-bench/`.

## Run It

From the workspace:

```bash
./script/build_and_run.sh --benchmark
```

For the full decision workflow:

```bash
./script/build_and_run.sh --full-proof
```

To test the motion/framerate thesis separately:

```bash
./script/build_and_run.sh --motion-bench
```

To create the visual proof sheet from the latest benchmark captures:

```bash
./script/build_and_run.sh --visual-proof
```

For the preferred call-quality proof:

```bash
./script/build_and_run.sh --face-proof
```

`--face-proof` runs benchmark capture plus visual proof first, retries capture up to three times until the face gate passes, then runs Quality Coach, Doctor, and release score. It exits nonzero if the face gate still fails.

This also writes:

```text
work/c1-visual-proof-latest.md
work/c1-visual-proof-latest.json
work/visual-proof/*-latest.jpg
work/c1-visual-score-latest.md
```

Those files gate whether the proof is a real face-in-frame comparison. If the gate fails, do not mark a C1 visual win from that sheet.
The processed visual score ranks saved C1 Signature, Coach Tuned, and related outputs only when the face gate is valid.

To turn those captures into setup guidance before judging the C1:

```bash
./script/build_and_run.sh --quality-coach
```

Or from the app:

1. Open `C1 Studio 2026`.
2. Select the `Doctor` tab.
3. Click `Run Full Proof` to capture benchmark frames, build the visual proof sheet, and rerun Doctor.

You can still run only the capture step from the `Benchmark` tab with `Run C1 vs Studio Bench`.

The `Benchmark` tab also has `Run Quality Coach`, which reads the latest benchmark captures and writes `work/c1-quality-coach-latest.md` plus `work/c1-coach-look-latest.json`.
Use `Calibrate C1 Look` when you want the app to run capture -> Quality Coach -> apply Coach Tuned -> visual proof -> processed visual score as one workflow.

## How To Read It

- Higher sharpness means more edge detail, not automatically a better face image.
- Higher contrast can look clearer, but can also look harsher.
- Higher fine texture can mean real detail or visible noise.
- A still frame does not measure motion cadence, exposure drift, white-balance drift, autofocus behavior, or Zoom compression. Use the motion benchmark for the first part of that gap.

## Current Local Result

Recent packaged-helper benches show why this app needs both measurement and tuning:

- One run found a clear C1 still-frame advantage: C1 sharpness `16.669` and contrast `0.307` versus Studio Display sharpness `5.6459` and contrast `0.2659`.
- Another run found no decisive still-frame advantage: C1 sharpness `5.2938` and contrast `0.267` versus Studio Display sharpness `5.5358` and contrast `0.2659`.

The current diagnosis is stricter: if `work/c1-visual-proof-latest.md` is not face-valid, or if `work/c1-visual-proof-latest.jpg` does not show C1 Coach Tuned or C1 Signature visibly beating Studio Display in the actual call setup, use Studio Display and treat the C1 as a lab/rescue project rather than a daily camera.
