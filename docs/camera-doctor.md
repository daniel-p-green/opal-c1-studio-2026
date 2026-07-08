# C1 Studio Doctor

The doctor command is the current top-level diagnosis for whether the C1 is worth using today.

```bash
./script/build_and_run.sh --doctor
```

For a fresh end-to-end proof from the command line:

```bash
./script/build_and_run.sh --full-proof
```

That captures matched frames, runs Motion Bench, runs Quality Coach, builds the visual proof sheet, runs Doctor, runs Readiness, and writes `work/c1-full-proof-latest.md`.

For a tighter face-in-frame proof:

```bash
./script/build_and_run.sh --face-proof
```

That retries capture up to three times, writes `work/c1-face-proof-latest.md`, and exits nonzero until both Studio Display and C1 captures contain a detectable face.

Or from the app:

1. Open `C1 Studio 2026`.
2. Select the `Doctor` tab.
3. Click `Run Doctor` for the current diagnosis.

For a fresh decision pass from inside the app, click `Run Full Proof`. It captures a C1-vs-Studio benchmark, runs Quality Coach, builds the visual proof sheet, then reruns Doctor from that evidence.

Use `Run Face Proof` when the goal is specifically to decide whether the C1 is better for calls. It guides the same visual-proof gate and refuses to treat a torso/empty-room capture as valid.
For the best result, start preview or Go Live first and wait for the header's `Face Proof` status to say ready before running Face Proof. The in-app button blocks capture until that live status is ready.

It writes:

- `work/c1-doctor-latest.md`
- `work/c1-apple-effects-latest.txt`
- `work/c1-motion-bench-latest.md`
- `work/c1-quality-coach-latest.md`
- `work/c1-release-score-latest.md`
- `work/c1-visual-score-latest.md`
- `work/c1-face-proof-latest.md` when run through `--face-proof`
- `work/c1-visual-proof-latest.md`
- `work/c1-visual-proof-latest.json`
- `work/visual-proof/*-latest.jpg`
- `work/c1-full-proof-latest.md` when run through `--full-proof`

## Current Policy

C1 Studio is conservative by default:

- Use Studio Display unless a fresh face-valid visual proof shows C1 clearly winning.
- Do not flash firmware.
- Do not promote hardware sliders until the root probe proves readable/writable UVC controls.
- Do not assume Apple Portrait, Studio Light, or Center Stage work on the C1; the local probe currently reports no supported C1 formats.

## Visual Win Marker

The doctor only allows C1 as the recommended daily camera when this file exists:

```text
work/c1-visual-proof-win.txt
```

Create that file only after `work/c1-visual-proof-latest.md` reports `Face-valid proof: pass`, then inspect `work/c1-visual-proof-latest.jpg` from a real face-in-frame call setup and decide C1 Coach Tuned or C1 Signature clearly beats Studio Display.

The app and Doctor now reject stale or invalid visual wins when the latest visual proof gate is missing or face-invalid.

The app exposes this as `Mark C1 Visual Win`, with a confirmation prompt. Use `Clear Visual Win` to return to the conservative Studio Display recommendation.
