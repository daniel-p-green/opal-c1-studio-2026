# C1 Studio Release Score

The release score is the compact product-readiness grade for the current C1 stack.

## Run It

```bash
./script/build_and_run.sh --release-score
```

Or run the full proof:

```bash
./script/build_and_run.sh --full-proof
```

The report is written to:

```text
work/c1-release-score-latest.md
```

## What It Scores

- C1 enumeration.
- Studio Display comparison availability.
- OBS bridge readiness.
- Still-frame advantage.
- Motion/framerate thesis.
- Call-session stability.
- Calibration workflow.
- Processed visual proof package.
- Quality Coach verdict.
- Hardware controls.
- Apple effects.
- Manual visual-win marker backed by a face-valid visual proof.

## Current Local Result

The current score is **80/125, Lab-Ready**, not daily-camera ready.

C1 has a working OBS bridge, stronger detail, a currently proven short-sample `1080p60` path, passing call stability, and a calibration/proof workflow. It still loses daily-camera points because Quality Coach is blocked without a face-valid proof, hardware controls are not promoted, Apple effects are unavailable, and no face-valid manual visual win has been marked.
