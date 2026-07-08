# C1 Studio Readiness Check

The readiness check is the go/no-go screen for using the C1 today.

## Run It

From the workspace:

```bash
./script/build_and_run.sh --readiness
```

Or from the app:

1. Open `C1 Studio 2026`.
2. Select the `Readiness` tab.
3. Click `Run Readiness Check`.

## What It Checks

- Opal C1 is visible to AVFoundation/ffmpeg.
- Studio Display camera is visible for comparison.
- OBS Virtual Camera is visible.
- OBS Camera Extension is active.
- Benchmark evidence exists.
- Calibration and processed visual-score evidence exists.
- Hardware Control Proof exists.
- Root probe JSON exists.
- Control promotion verdict exists.
- App camera permission, when run from the app.

## Current Result

The current packaged readiness report says:

- OBS bridge ready: `yes`
- Hardware controls ready: `no`

That means the practical path today is:

1. Open the `Studio` tab.
2. Click `Go Live`.
3. Capture `C1 Studio Output` in OBS.
4. Start OBS Virtual Camera.
5. Pick OBS Virtual Camera in Zoom/Meet/Teams.

Hardware controls remain gated on `work/c1-root-probe.json`.
