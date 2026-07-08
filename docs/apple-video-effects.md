# Apple Video Effects Probe

C1 Studio can open Apple's Video Effects panel, but macOS currently reports no Apple effect-capable formats for the plugged-in Opal C1.

## Run It

```bash
./script/build_and_run.sh --apple-effects
```

## Current Result

Latest local probe:

```text
Device: Opal C1 (ctrl)
Portrait enabled in Control Center: false
Portrait active on C1 current format: false
Center Stage enabled in Control Center: false
Center Stage active on C1 current format: false
Studio Light enabled in Control Center: false
Studio Light active on C1 current format: false
Supported Apple effect formats: none reported for C1
```

## Product Meaning

Do not position C1 Studio as a way to unlock Apple's Portrait, Studio Light, or Center Stage on the C1 unless a future probe reports supported formats.

The realistic 2026 path is our own compute pipeline:

- Vision-based face tracking
- Vision person segmentation for background blur/dim
- local portrait relighting
- noise cleanup
- highlight softening
- 1080p60 output where stable
- OBS Virtual Camera publishing

That path still needs visual proof against Studio Display before it is worth daily use.
