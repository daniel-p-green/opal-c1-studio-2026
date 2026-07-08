# Execution Postmortem

This is a postmortem on the project execution, not the Opal C1 hardware itself.

The short version: the investigation produced a useful public artifact, but the product decision should have happened much earlier. We spent too much time building a better rescue app before proving that the C1 could win against the actual 2026 alternatives: Studio Display for convenience and iPhone Continuity Camera for quality.

## What Went Well

### 1. Verification-first hardware triage worked

The project did not rely on vibes. It verified:

- macOS camera enumeration,
- USB identity,
- AVFoundation capture,
- available video modes,
- `1080p60` behavior,
- motion delivery,
- call-session luma/color stability,
- Apple effects availability,
- UVC control probe status,
- Opal XPC/service clues,
- and release-readiness scoring.

That turned "is the C1 dead?" into a clear answer: no, it is hardware-alive.

### 2. Safety boundaries stayed intact

We did not run unknown privileged installers, flash firmware, unload system extensions, or ship Opal binaries. The repo now documents those boundaries clearly.

For an abandoned-camera rescue project, that matters more than squeezing out one more speculative test.

### 3. The app became a useful evidence harness

The Swift/AppKit app was not wasted. It created a repeatable local harness:

- Doctor,
- Readiness,
- Lab,
- Benchmark,
- OBS bridge,
- visual proof,
- release score,
- control proof,
- Opal bridge probe,
- stability benchmark.

That made the final no-go decision defensible instead of hand-wavy.

### 4. The public repo is honest

The final artifact does not pretend the prototype became a product. It says the C1 is hardware-alive but not worth continued daily-camera investment, and it explains why.

That is the most useful thing this project can be for other C1 owners.

## Where We Spent Too Much Time

### 1. We built product surface before proving product advantage

The biggest miss was building too much of "C1 Studio 2026" before forcing the decisive comparison:

> Does this beat Studio Display or iPhone Continuity Camera for real calls?

The app gained presets, proof sheets, adaptive looks, OBS bridge behavior, and multiple scorecards before the core product thesis was killed by a simpler fact: `1080p60` is not enough when Continuity Camera exists.

### 2. We over-invested in software image tuning

Software looks, face-aware relighting, background blur, Studio Match, skin protection, and Quality Coach were technically interesting. But they were compensating for an unproven source image.

The smarter gate would have been:

1. capture face-valid Studio Display vs C1,
2. inspect visually,
3. only build tuning if the C1 had a credible raw advantage on a face.

Instead, we built tuning infrastructure before securing the visual win.

### 3. We let "maybe controls" stay alive too long

The UVC and Opal XPC paths were worth inspecting. But once unprivileged controls were blocked and Opal bridge viability was unproven, the next question should have been:

> Is the camera good enough to justify a helper/DriverKit/CMIO path?

The answer was no. So deeper control work should have stopped sooner.

### 4. We treated `1080p60` like a bigger win than it was

The C1 did prove a stable `1080p60` path. That felt meaningful because Studio Display does not offer the same practical motion path.

But the actual user alternative is not only Studio Display. It is also iPhone Continuity Camera. Once that was stated plainly, `1080p60` stopped being a decisive advantage.

### 5. Too many reports before one decision report

The project accumulated many useful reports:

- Doctor,
- Readiness,
- Release Score,
- Motion Bench,
- Stability Bench,
- Quality Coach,
- Visual Score,
- Opal Bridge Probe,
- Hardware Control Proof.

The missing artifact was a blunt investment decision report. Once added, it clarified the whole project. It should have existed earlier.

## What We Would Do If Starting Over

### Step 1. Define the kill criteria first

Before writing the app:

- C1 must visibly beat Studio Display on a face.
- C1 must offer a meaningful advantage over iPhone Continuity Camera.
- Hardware WB/exposure/focus must be controllable, or the software pipeline must be good enough without them.
- Apple effects must either work or be clearly replaceable.
- The final workflow must be easier than "use Continuity Camera."

If those fail, stop.

### Step 2. Run the shortest decisive proof

Start with a 30-minute proof pack:

```bash
ffmpeg list devices
ffmpeg capture Studio Display still
ffmpeg capture C1 still
ffmpeg capture short C1 motion sample
check Apple effects support
run one UVC GET_INFO probe
```

Then manually inspect a face-valid side-by-side.

No native app yet. No presets. No OBS bridge. No scorecard waterfall.

### Step 3. Compare against the real alternatives

The comparison set should have been:

- Studio Display,
- iPhone Continuity Camera,
- Opal C1 raw,
- Opal C1 with minimal software tuning.

We initially over-indexed on Studio Display. The correct market comparison was Continuity Camera.

### Step 4. Only build after a visual win

If the face-valid proof showed C1 winning, then build:

- a small control utility,
- source-level WB/exposure/focus proof,
- OBS/virtual-camera bridge,
- and eventually a proper CMIO/DriverKit path.

If it did not win, only publish the postmortem.

### Step 5. Use a single decision scoreboard

Instead of many reports from the beginning, use one scoreboard:

| Gate | Stop/Go |
| --- | --- |
| Enumerates and captures | Go |
| Beats Studio Display on face | Required |
| Beats or meaningfully complements Continuity Camera | Required |
| Hardware controls proven | Required for app investment |
| Apple effects available or replaced well | Required |
| Workflow simpler than alternatives | Required |

The current project eventually converged on this logic, but too late.

## Recommended Future Pattern

For abandoned hardware rescues, use this order:

1. **Alive proof**: can the hardware enumerate and produce data?
2. **Alternative proof**: what does the user already have that is better?
3. **Visual/product proof**: does the rescued hardware win in the actual use case?
4. **Control proof**: can we control the device at the source?
5. **Workflow proof**: is the resulting path simpler or better enough to use?
6. **Only then build the app.**

This project did steps 1, 4, 5, and app-building too early. The real stop was step 2 plus step 3.

## Final Assessment

The project was successful as an investigation and public postmortem.

It was not successful as a product build, because the product should not exist unless the C1 can beat modern Apple camera paths. It cannot, based on current evidence.

The best outcome is the one now in the public repo:

- preserve the technical findings,
- document the no-go,
- avoid unsafe firmware/control work,
- and save future C1 owners from repeating the same rabbit hole.
