# C1 Studio 2026

An honest rescue attempt for the Opal C1 webcam on modern macOS.

This repository contains a native macOS prototype, reverse-engineering tools, and a written postmortem. The project started with an ambitious goal: make the Opal C1 feel like the 2026 version of what Opal Composer should have been for C1 owners.

The final decision is intentionally blunt:

**Do not keep investing in the C1 as a serious 2026 daily webcam. Use Apple Studio Display for convenience, or iPhone Continuity Camera when quality matters.**

This is an independent project. It is not affiliated with or endorsed by Opal Camera Inc. See [Public Disclaimer](docs/public-disclaimer.md).

## Why This Exists

The Opal C1 hardware is still detectable on macOS, but Opal Composer 2 no longer supports it. Older Opal software can make parts of the stack appear, but the camera is unreliable and the official software path is effectively abandoned.

This project investigated whether a lightweight replacement app could make the C1 worthwhile again:

- initialize the camera without relying on Opal Composer UI,
- expose manual controls such as white balance, exposure, focus, brightness, contrast, saturation, sharpness, and anti-flicker,
- provide a tuned preview and OBS/Zoom-compatible output,
- replicate some modern camera effects in software,
- and decide whether the C1 can beat Studio Display or iPhone Continuity Camera in real use.

## Final Verdict

The C1 is **hardware-alive but not product-worthy**.

What worked:

- macOS sees the camera as `Opal C1 (ctrl)`.
- The camera can deliver frames.
- A short `1080p60` path was proven.
- A longer call-stability bench passed with low luma/color drift.
- The C1 can show more raw edge detail than Studio Display in some captures.
- OBS bridge output is possible through a `C1 Studio Output` window.
- The app can apply software looks, face-aware relighting, background blur/dim, and generated tuning presets.

What failed:

- Apple Portrait, Studio Light, and Center Stage are not available for the C1.
- Hardware UVC controls remain blocked in the normal user session.
- Opal's old XPC services contain useful control symbols, but no callable control bridge was proven.
- The latest visual proof was not face-valid.
- There is no verified evidence that the C1 beats Studio Display on a real face in a real call setup.
- The only durable advantage, `1080p60`, is not enough because iPhone Continuity Camera can already provide a better modern camera path.

Current project recommendation:

**Freeze this as a lab/OBS rescue and evidence harness. Do not treat it as a daily-camera product candidate.**

## Timeline

### 1. Hardware and App Bundle Inspection

We inspected installed Opal Composer builds and old Opal app resources. Both Composer 1.x and Composer 2.x still contain C1-related resources, UVC services, firmware payload names, and DepthAI/libusb-linked components.

Composer 2 appears to reject the C1 by product/support policy, not because every relevant code path vanished.

### 2. Camera Enumeration and Raw Capture

macOS and AVFoundation could see the C1. ffmpeg could capture frames, proving the hardware was not dead.

Later probes showed normal video modes including 720p, 1080p, 1440p, and 4K-class modes. The most useful practical path was `1920x1080 @ 60.000240`.

### 3. Reverse-Lab and Control Mapping

The reverse-lab helper mapped likely UVC controls:

- white balance temperature and auto white balance,
- focus absolute and auto focus,
- exposure time and auto exposure,
- gain,
- brightness,
- contrast,
- saturation,
- sharpness,
- gamma,
- power-line frequency,
- zoom,
- iris.

But unprivileged control reads were blocked by USB permissions. No normal user-session path proved readable/writable hardware controls.

### 4. Software Camera App Prototype

The Swift/AppKit app grew into a working local prototype:

- Doctor tab,
- Studio preview,
- Control surface,
- Readiness report,
- Lab probes,
- Benchmark tools,
- OBS output window,
- software looks,
- face detection,
- face-aware tuning,
- background blur/dim,
- visual-proof generation,
- quality coach,
- release score.

This made the C1 more inspectable and somewhat more usable, but it did not make it remarkable.

### 5. Apple Effects Check

The local Apple effects probe found no C1 formats that support Apple Portrait, Studio Light, or Center Stage.

That matters because Studio Display and iPhone Continuity Camera benefit from Apple's modern camera pipeline. The C1 does not get that lift.

### 6. Motion and Stability Benchmarks

The C1 did prove a real technical win:

- `1080p60` opened successfully.
- The motion benchmark passed.
- The call-stability benchmark passed.
- The C1 delivered the sampled stream with low drift.

But this is not enough in 2026. If the goal is simply high-quality 1080p video, iPhone Continuity Camera is a better path with less custom software.

### 7. Opal Bridge Probe

The installed Opal stack still contains promising control methods such as `setWhiteBalance:`, `setFocus:`, `setExposure:`, `setBrightness:`, and `setSaturation:`.

However, the probe did not prove a callable control bridge:

- embedded Opal XPC services do not expose global Mach services,
- the global shim exists but does not expose a proven control protocol,
- using Opal as the product foundation remains speculative.

### 8. Final Product Decision

The release score reached lab-ready territory, but not daily-camera territory. The decisive issue is not whether the C1 can be made to show an image. It can.

The issue is whether it can justify replacing simpler, better options:

- Studio Display is integrated and acceptable for calls.
- iPhone Continuity Camera is better when quality matters.
- The C1 still lacks proven hardware controls, Apple effects, and a face-valid visual win.

So the project is retired as a product bet.

## What Is In This Repo

- `Sources/C1Control2026/`: Swift/AppKit prototype app.
- `Tools/`: read-only probes, benchmarks, scorecards, and decision helpers.
- `script/build_and_run.sh`: local build/run/probe entrypoint.
- `docs/`: focused notes for camera doctor, benchmarks, hardware controls, Opal bridge probing, and OBS output.
- `opal-c1-findings.md`: sanitized investigation notes.
- `docs/execution-postmortem.md`: what went well, where the project overspent effort, and the restart plan.
- `docs/public-disclaimer.md`: public safety and affiliation disclaimer.
- `LICENSE`: MIT license.

## Run Locally

Requirements:

- macOS,
- Swift toolchain,
- ffmpeg on `PATH`,
- an Opal C1 attached if you want live probes.

Build and launch:

```bash
./script/build_and_run.sh
```

Run the current decision reports:

```bash
./script/build_and_run.sh --doctor
./script/build_and_run.sh --readiness
./script/build_and_run.sh --release-score
./script/build_and_run.sh --decision
```

Run focused probes:

```bash
./script/build_and_run.sh --control-proof
./script/build_and_run.sh --opal-bridge-probe
./script/build_and_run.sh --motion-bench
./script/build_and_run.sh --stability-bench
```

## Safety Boundaries

The default workflows are read-only with respect to firmware and installed Opal components.

- No firmware flashing.
- No system extension unloading.
- No privileged installer execution.
- No bundled Opal binaries.
- No hardware writes unless explicitly enabled for a controlled experiment.
- Generated `work/` reports can contain local paths, device names, captures, and serial-like identifiers. Review before sharing.

## Reopen Criteria

This project should only be reopened as a serious daily-camera effort if at least one of these becomes true:

- a fresh face-valid proof shows C1 output clearly beating Studio Display,
- hardware white balance, exposure, and focus controls become readable and writable through a safe helper,
- a callable Opal bridge or owned CMIO/DriverKit path is proven,
- or a new safe firmware/control source appears and can be inspected without flashing first.

Until then, the honest 2026 answer is simple:

**Use Studio Display for normal calls. Use iPhone Continuity Camera when you want the better camera.**
