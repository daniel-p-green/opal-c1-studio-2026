# Public Disclaimer

This repository is an independent rescue prototype and investigation note for the Opal C1 webcam.

It is not affiliated with, endorsed by, or supported by Opal Camera Inc.

## Not A Driver

This is not a production camera driver.

The code includes a Swift/AppKit prototype, read-only probes, local benchmarks, and OBS-oriented experiments. It should not be treated as a supported replacement for Opal Composer.

## No Firmware Flashing

The default workflows do not flash firmware, unload system extensions, run privileged installers, or modify installed Opal components.

Do not add or run firmware-write paths unless you fully understand the hardware risk.

## Local Reports

Many commands write reports under `work/`. Those files can contain local device names, paths, screenshots, camera captures, serial-like identifiers, or other machine-specific details. They are intentionally ignored by git.

Review any generated report before sharing it publicly.

## Final Recommendation

The project conclusion is a no-go for daily use:

Use Studio Display for normal calls. Use iPhone Continuity Camera when image quality matters.
