# C1 Studio OBS Output Workflow

This is the practical Composer-free bridge until C1 Studio has its own CMIO Camera Extension.

## Goal

Use the tuned C1 Studio preview in Zoom, Meet, or Teams through OBS Virtual Camera.

## Steps

1. Launch C1 Studio 2026 with `./script/build_and_run.sh`.
2. In the `Studio` tab, click `Go Live`.
3. Approve macOS camera access if prompted.
4. In OBS, add a `Window Capture` source for `C1 Studio Output`.
5. Start OBS Virtual Camera.
6. In Zoom/Meet/Teams, choose `OBS Virtual Camera`.
7. Tune the look with the live software controls or a look preset.
8. Click `Save Current Look` or `Lock Current Look` to persist the tuned software look.

For a launch smoke test:

```bash
./script/build_and_run.sh --bridge-smoke
```

## Current Limitations

- This does not yet create a native macOS camera device by itself.
- OBS must stay open for conferencing apps to see the tuned feed.
- Hardware controls still require the UVC helper proof; software look controls affect the rendered output window only.
- `Auto Face Balance` samples the face window and gently corrects exposure, warmth, and hot saturation in software.
- `Portrait Light` is a local Core Image face-light effect.
- `Background Blur` and `Background Dim` use Vision person segmentation. They are our local replacement path because Apple Video Effects do not currently report C1 support.
- First launch may stop at `Waiting for macOS camera permission` until the app is approved in System Settings.

## Why This Path Exists

Direct UVC controls are currently blocked in an unprivileged user session, and Opal's installed shim appears to require Opal-signed clients. The OBS output window gives us a usable video path now without bundling Opal binaries or modifying system extensions.
