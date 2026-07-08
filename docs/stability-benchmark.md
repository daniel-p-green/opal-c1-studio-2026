# C1 Call Stability Benchmark

The call stability benchmark tests the thing a still frame cannot show: whether the C1 holds a steady image during a short Zoom-like run.

## Run It

```bash
./script/build_and_run.sh --stability-bench
```

Or run the full proof:

```bash
./script/build_and_run.sh --full-proof
```

The report is written to:

```text
work/c1-stability-bench-latest.md
```

## What It Measures

- Sampled-frame delivery across a longer capture than the motion bench.
- Brightness mean, range, and drift.
- Warmth/color range and drift.
- Stale-frame ratio.
- Per-second brightness and warmth traces.

## Product Meaning

A C1 that looks sharp for one frame can still be a bad webcam if auto exposure, white balance, or frame delivery wanders during a call.

This gate does not prove a visual win, but it does prevent a weak stream from being promoted just because `1080p60` opened once.

## Evidence Boundary

This is a short local call-session proxy. It does not replace a real Zoom/Meet/Teams test, face-valid visual proof, autofocus tracking proof, or manual hardware-control promotion.
