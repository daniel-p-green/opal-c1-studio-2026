# Hardware Control Proof

This workflow decides whether C1 Studio can safely graduate from software look tuning to real hardware camera controls.

## Run The Safe Proof

From the workspace:

```bash
./script/build_and_run.sh --control-proof
```

Or from the app:

1. Open `C1 Studio 2026`.
2. Select the `Lab` tab.
3. Click `Run Control Proof`.

## Current Result

The current unprivileged proof sees all 15 mapped C1 UVC control candidates, but every `GET_*` request is blocked by `access_denied`.

Mapped controls:

- focus
- autofocus
- exposure mode
- exposure time
- iris
- zoom
- brightness
- contrast
- gain
- power-line frequency
- saturation
- sharpness
- gamma
- white-balance temperature
- auto white balance

## Reversible Root Probe

The app/report emits the exact command for the next proof step. It writes JSON to `work/c1-root-probe.json` and does not flash firmware, unload extensions, or write settings:

```bash
sudo 'dist/C1Control2026.app/Contents/Resources/Tools/c1_reverse_lab.py' --json --output 'work/c1-root-probe.json'
```

## Promotion Gate

Only promote controls to normal app UI when the root probe proves:

- `GET_INFO` returns readable/writable flags for target controls.
- `GET_CUR`, `GET_MIN`, `GET_MAX`, `GET_RES`, and `GET_DEF` return sane values.
- A low-risk write-back test can write the current value back to the same control and read it again.
- Zoom/OBS can still own or receive video while the helper reads/writes controls.

Until then, C1 Studio should keep hardware sliders visibly disabled and use software look tuning plus OBS output as the practical path.

## Evaluate A Root Probe

After running the reversible root probe, evaluate it:

```bash
./script/build_and_run.sh --promote-controls
```

This reads `work/c1-root-probe.json` and writes `work/c1-control-promotion-latest.md`.

Current state without the root JSON:

- `0` controls ready.
- `12` target controls blocked because the root probe is missing.
- Verdict: do not promote.
