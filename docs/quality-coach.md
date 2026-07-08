# C1 Quality Coach

Quality Coach explains why the C1 is or is not winning in the latest matched benchmark captures.

## Run It

```bash
./script/build_and_run.sh --benchmark
./script/build_and_run.sh --quality-coach
```

Or run the calibration loop:

```bash
./script/build_and_run.sh --calibrate
```

Or run the full proof:

```bash
./script/build_and_run.sh --full-proof
```

The report is written to:

```text
work/c1-quality-coach-latest.md
```

The generated software look is written to:

```text
work/c1-coach-look-latest.json
```

In the app, open `Studio` and click `Apply Coach Look` to run Quality Coach and apply the generated look to the live software pipeline.
For the full workflow, open `Benchmark` and click `Calibrate C1 Look`; it captures paired frames, learns the look, applies it, rebuilds visual proof, and runs processed visual scoring.
The app restores the last active look on launch, so a calibrated room setup does not need to be reapplied every time.

## What It Looks At

- Face-window brightness, warmth, saturation, sharpness, and texture.
- Side-to-side light imbalance.
- Subject/background separation.
- Whether C1 has any measured advantage worth verifying by eye.
- A conservative `LookSettings` recommendation for warmth, saturation, sharpness, cleanup, portrait light, background treatment, adaptive face balance, Studio Grade, and learned Studio Match correction from the paired Studio Display capture.

## Current Local Result

The latest coach report says C1 is not ready to replace Studio Display in this setup.

Specific fixes from the current frames:

- Lighting is uneven across the frame; move or soften the key light before judging the C1.
- Subject separation is weak; add face light or dim the background.
- C1 detail is reading as texture/noise; use the coach look or reduce sharpness before using Crisp looks.

The current `Coach Tuned` look enables Auto Face Balance, Studio Grade, learned Studio Match correction, and Skin Protect. Those are software corrections in the C1 Studio output path; they do not unlock Apple's Portrait, Studio Light, or Center Stage.

## Evidence Boundary

Quality Coach uses fixed frame windows and image metrics. It is not face recognition, and it does not prove video-call quality by itself.

A real C1 win still requires `work/c1-visual-proof-latest.jpg` to clearly beat Studio Display by eye in the actual call setup.
