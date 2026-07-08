# C1 Motion Benchmark

The motion benchmark tests the practical C1 thesis that still-frame quality alone cannot prove: whether the camera path can deliver stable motion and a useful framerate advantage over Studio Display.

## Run It

```bash
./script/build_and_run.sh --motion-bench
```

Or run the full proof:

```bash
./script/build_and_run.sh --full-proof
```

The report is written to:

```text
work/c1-motion-bench-latest.md
```

## What It Measures

- Whether C1 can capture through the requested `1920x1080@60.000240` path.
- Sampled-frame delivery during a short raw-frame capture.
- Brightness drift across the sample.
- Motion deltas and fine texture/noise in the downsampled frames.

## Current Local Result

The latest packaged full-proof run did prove the short-sample motion thesis:

- Studio Display captured at `1920x1080@30`.
- C1 captured at `1920x1080@60.000240`.
- Both delivered the expected sampled frames.

This means motion/framerate remains a plausible C1 advantage. It still does not override the Doctor verdict, because the latest Quality Coach report says the image is not ready to beat Studio Display yet.

## Evidence Boundary

This is a short downsampled capture. It does not replace a real Zoom/Meet test, autofocus tracking test, or subjective motion review.

For longer call-session luma/color drift and stale-frame checks, run:

```bash
./script/build_and_run.sh --stability-bench
```
