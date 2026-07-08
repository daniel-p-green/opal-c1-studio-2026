#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="C1Control2026"
BUNDLE_ID="dev.c1studio.rescue"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [ -d "$ROOT_DIR/Tools" ]; then
  cp -R "$ROOT_DIR/Tools" "$APP_CONTENTS/Resources/Tools"
  chmod +x "$APP_CONTENTS/Resources/Tools/"*.py 2>/dev/null || true
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>C1 Studio 2026</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSCameraUsageDescription</key>
  <string>C1 Studio 2026 needs camera access to preview and control the Opal C1.</string>
  <key>NSCameraPortraitEffectEnabled</key>
  <true/>
  <key>NSCameraStudioLightEnabled</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
mkdir -p "$ROOT_DIR/work"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

visual_gate_passed() {
  [ -f "$ROOT_DIR/work/c1-visual-proof-latest.md" ] && /usr/bin/grep -q "Face-valid proof: pass" "$ROOT_DIR/work/c1-visual-proof-latest.md"
}

visual_gate_verdict() {
  if [ ! -f "$ROOT_DIR/work/c1-visual-proof-latest.json" ]; then
    echo "Face gate has not run yet."
    return
  fi
  /usr/bin/python3 - "$ROOT_DIR/work/c1-visual-proof-latest.json" <<'PY'
import json
import sys
from pathlib import Path

try:
    data = json.loads(Path(sys.argv[1]).read_text())
    print(data.get("verdict") or "Face gate has no verdict.")
except Exception as exc:
    print(f"Face gate unreadable: {type(exc).__name__}: {exc}")
PY
}

run_face_capture_attempts() {
  local max_attempts="${1:-3}"
  local attempt=1
  while [ "$attempt" -le "$max_attempts" ]; do
    echo "Face proof capture attempt $attempt/$max_attempts"
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_quality_bench.py" --text --output "$ROOT_DIR/work/c1-quality-bench-latest.md"
    "$APP_BINARY" --visual-proof
    if visual_gate_passed; then
      return 0
    fi
    visual_gate_verdict
    if [ "$attempt" -lt "$max_attempts" ]; then
      echo "Face gate failed; recenter and keep your face visible. Retrying in 2 seconds..."
      sleep 2
    fi
    attempt=$((attempt + 1))
  done
  return 3
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --experimental-writes|experimental-writes)
    /usr/bin/open -n --env C1_STUDIO_ENABLE_UVC_WRITES=1 "$APP_BUNDLE"
    ;;
  --preview-smoke|preview-smoke)
    /usr/bin/open -n "$APP_BUNDLE" --args --autostart-preview
    sleep 4
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --bridge-smoke|bridge-smoke|--go-live-smoke|go-live-smoke)
    /usr/bin/open -n "$APP_BUNDLE" --args --autostart-bridge
    sleep 4
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --look-smoke|look-smoke)
    /usr/bin/open -n "$APP_BUNDLE" --args --save-look-smoke
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --apple-effects|apple-effects)
    "$APP_BINARY" --apple-effects-probe | tee "$ROOT_DIR/work/c1-apple-effects-latest.txt"
    ;;
  --look-render-smoke|look-render-smoke)
    "$APP_BINARY" --look-render-smoke
    ;;
  --coach-look-smoke|coach-look-smoke)
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_quality_coach.py" --output "$ROOT_DIR/work/c1-quality-coach-latest.md" >/dev/null
    "$APP_BINARY" --coach-look-smoke
    ;;
  --active-look-smoke|active-look-smoke)
    "$APP_BINARY" --active-look-smoke
    ;;
  --visual-proof|visual-proof)
    "$APP_BINARY" --visual-proof
    ;;
  --visual-score|visual-score)
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_visual_score.py" --output "$ROOT_DIR/work/c1-visual-score-latest.md"
    ;;
  --doctor|doctor)
    "$APP_BINARY" --apple-effects-probe > "$ROOT_DIR/work/c1-apple-effects-latest.txt" || true
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_opal_bridge_probe.py" --output "$ROOT_DIR/work/c1-opal-bridge-latest.md" || true
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_doctor.py" --output "$ROOT_DIR/work/c1-doctor-latest.md"
    ;;
  --full-proof|full-proof)
    "$APP_BINARY" --apple-effects-probe > "$ROOT_DIR/work/c1-apple-effects-latest.txt" || true
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_opal_bridge_probe.py" --output "$ROOT_DIR/work/c1-opal-bridge-latest.md" || true
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_quality_bench.py" --text --output "$ROOT_DIR/work/c1-quality-bench-latest.md"
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_motion_bench.py" --output "$ROOT_DIR/work/c1-motion-bench-latest.md"
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_stability_bench.py" --output "$ROOT_DIR/work/c1-stability-bench-latest.md"
    "$APP_BINARY" --visual-proof
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_quality_coach.py" --output "$ROOT_DIR/work/c1-quality-coach-latest.md"
    "$APP_BINARY" --visual-proof
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_visual_score.py" --output "$ROOT_DIR/work/c1-visual-score-latest.md"
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_readiness.py" --output "$ROOT_DIR/work/c1-readiness-latest.md"
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_release_score.py" --output "$ROOT_DIR/work/c1-release-score-latest.md"
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_doctor.py" --output "$ROOT_DIR/work/c1-doctor-latest.md"
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_readiness.py" --output "$ROOT_DIR/work/c1-readiness-latest.md"
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_release_score.py" --output "$ROOT_DIR/work/c1-release-score-latest.md"
    {
      echo "# C1 Studio Full Proof"
      echo
      echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo
      echo "## Doctor"
      echo
      cat "$ROOT_DIR/work/c1-doctor-latest.md"
      echo
      echo "## Benchmark"
      echo
      cat "$ROOT_DIR/work/c1-quality-bench-latest.md"
      echo
      echo "## Motion Bench"
      echo
      cat "$ROOT_DIR/work/c1-motion-bench-latest.md"
      echo
      echo "## Call Stability Bench"
      echo
      cat "$ROOT_DIR/work/c1-stability-bench-latest.md"
      echo
      echo "## Quality Coach"
      echo
      cat "$ROOT_DIR/work/c1-quality-coach-latest.md"
      echo
      echo "## Processed Visual Score"
      echo
      cat "$ROOT_DIR/work/c1-visual-score-latest.md"
      echo
      echo "## Readiness"
      echo
      cat "$ROOT_DIR/work/c1-readiness-latest.md"
      echo
      echo "## Release Score"
      echo
      cat "$ROOT_DIR/work/c1-release-score-latest.md"
      echo
      echo "## Visual Proof"
      echo
      echo "- Sheet: \`$ROOT_DIR/work/c1-visual-proof-latest.jpg\`"
      echo "- Face gate: \`$ROOT_DIR/work/c1-visual-proof-latest.md\`"
      echo "- Face gate JSON: \`$ROOT_DIR/work/c1-visual-proof-latest.json\`"
      echo "- Win marker: \`$ROOT_DIR/work/c1-visual-proof-win.txt\`"
    } > "$ROOT_DIR/work/c1-full-proof-latest.md"
    cat "$ROOT_DIR/work/c1-full-proof-latest.md"
    ;;
  --face-proof|face-proof)
    "$APP_BINARY" --apple-effects-probe > "$ROOT_DIR/work/c1-apple-effects-latest.txt" || true
    set +e
    run_face_capture_attempts 3
    face_capture_status=$?
    set -e
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_quality_coach.py" --output "$ROOT_DIR/work/c1-quality-coach-latest.md"
    "$APP_BINARY" --visual-proof
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_visual_score.py" --output "$ROOT_DIR/work/c1-visual-score-latest.md"
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_doctor.py" --output "$ROOT_DIR/work/c1-doctor-latest.md"
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_release_score.py" --output "$ROOT_DIR/work/c1-release-score-latest.md"
    {
      echo "# C1 Face Proof"
      echo
      echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo
      cat "$ROOT_DIR/work/c1-visual-proof-latest.md"
      echo
      echo "## Doctor"
      echo
      cat "$ROOT_DIR/work/c1-doctor-latest.md"
      echo
      echo "## Processed Visual Score"
      echo
      cat "$ROOT_DIR/work/c1-visual-score-latest.md"
      echo
      echo "## Recapture Steps"
      echo
      echo "- Sit centered and keep your face fully visible."
      echo "- Avoid standing up, looking down at the phone, or leaving the chair during capture."
      echo "- Keep the same room lighting for Studio Display and C1."
      echo "- The CLI face proof now retries up to 3 captures before failing."
      echo "- Run \`./script/build_and_run.sh --face-proof\` again before marking a C1 visual win."
    } > "$ROOT_DIR/work/c1-face-proof-latest.md"
    cat "$ROOT_DIR/work/c1-face-proof-latest.md"
    if [ "$face_capture_status" -ne 0 ] || ! visual_gate_passed; then
      exit 3
    fi
    ;;
  --benchmark|benchmark)
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_quality_bench.py" --text --output "$ROOT_DIR/work/c1-quality-bench-latest.md"
    ;;
  --motion-bench|motion-bench)
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_motion_bench.py" --output "$ROOT_DIR/work/c1-motion-bench-latest.md"
    ;;
  --stability-bench|stability-bench)
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_stability_bench.py" --output "$ROOT_DIR/work/c1-stability-bench-latest.md"
    ;;
  --quality-coach|quality-coach)
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_quality_coach.py" --output "$ROOT_DIR/work/c1-quality-coach-latest.md"
    ;;
  --calibrate|calibrate)
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_quality_bench.py" --text --output "$ROOT_DIR/work/c1-quality-bench-latest.md"
    "$APP_BINARY" --visual-proof
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_quality_coach.py" --output "$ROOT_DIR/work/c1-quality-coach-latest.md"
    "$APP_BINARY" --visual-proof
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_visual_score.py" --output "$ROOT_DIR/work/c1-visual-score-latest.md"
    {
      echo "# C1 Look Calibration"
      echo
      echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo
      echo "## Quality Coach"
      echo
      cat "$ROOT_DIR/work/c1-quality-coach-latest.md"
      echo
      echo "## Processed Visual Score"
      echo
      cat "$ROOT_DIR/work/c1-visual-score-latest.md"
      echo
      echo "## Artifacts"
      echo
      echo "- Coach look: \`$ROOT_DIR/work/c1-coach-look-latest.json\`"
      echo "- Visual proof: \`$ROOT_DIR/work/c1-visual-proof-latest.jpg\`"
      echo "- Saved variants: \`$ROOT_DIR/work/visual-proof/\`"
    } > "$ROOT_DIR/work/c1-calibration-latest.md"
    cat "$ROOT_DIR/work/c1-calibration-latest.md"
    ;;
  --control-proof|control-proof)
    "$APP_CONTENTS/Resources/Tools/c1_reverse_lab.py" --control-proof --output "$ROOT_DIR/work/c1-control-proof-latest.md"
    ;;
  --opal-bridge-probe|opal-bridge-probe)
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_opal_bridge_probe.py" --output "$ROOT_DIR/work/c1-opal-bridge-latest.md"
    ;;
  --promote-controls|promote-controls)
    "$APP_CONTENTS/Resources/Tools/c1_promote_controls.py" "$ROOT_DIR/work/c1-root-probe.json" --output "$ROOT_DIR/work/c1-control-promotion-latest.md"
    ;;
  --readiness|readiness)
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_readiness.py" --output "$ROOT_DIR/work/c1-readiness-latest.md"
    ;;
  --release-score|release-score)
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_release_score.py" --output "$ROOT_DIR/work/c1-release-score-latest.md"
    ;;
  --decision|decision)
    C1_STUDIO_WORKSPACE="$ROOT_DIR" "$APP_CONTENTS/Resources/Tools/c1_decision_report.py" --output "$ROOT_DIR/work/c1-decision-latest.md"
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--experimental-writes|--preview-smoke|--bridge-smoke|--go-live-smoke|--look-smoke|--look-render-smoke|--coach-look-smoke|--active-look-smoke|--visual-proof|--visual-score|--apple-effects|--doctor|--full-proof|--face-proof|--benchmark|--motion-bench|--stability-bench|--quality-coach|--calibrate|--control-proof|--opal-bridge-probe|--promote-controls|--readiness|--release-score|--decision|--verify]" >&2
    exit 2
    ;;
esac
