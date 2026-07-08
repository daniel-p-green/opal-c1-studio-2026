# C1 Opal Bridge Probe

The Opal bridge probe answers one narrow question:

Can C1 Studio safely use the installed Opal Composer stack as a local control backend?

## Run It

```bash
./script/build_and_run.sh --opal-bridge-probe
```

The report is written to:

```text
work/c1-opal-bridge-latest.md
```

## What It Checks

- Whether `/Applications/Opal Composer.app` exists.
- Whether the privileged `cameraExtensionShim` LaunchDaemon is running.
- Whether the shim exposes a global Mach service.
- Whether the shim appears gated to Opal-signed clients.
- Whether embedded Opal XPC services expose global Mach services.
- Whether the installed UVC service still contains focus, exposure, white-balance, and image-control symbols.

## Current Product Meaning

If the report says the Opal bridge is blocked, do not make Opal XPC the v1 control backend.

That pushes the product back toward:

- direct UVC helper proof,
- OBS/virtual-camera output with software controls,
- or a later owned CMIO/DriverKit pipeline.

## Evidence Boundary

This probe is read-only. It does not connect to private Opal protocols, launch or unload Opal services, install helpers, flash firmware, or modify system extensions.
