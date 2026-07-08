#!/usr/bin/env python3
"""Read-only Opal XPC bridge viability probe for C1 Studio 2026."""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import subprocess
from datetime import datetime
from pathlib import Path


OPAL_APP = Path("/Applications/Opal Composer.app")
SHIM = Path("/Library/PrivilegedHelperTools/com.opalcamera.Opal.v2.cameraExtensionShim")
SHIM_PLIST = Path("/Library/LaunchDaemons/com.opalcamera.Opal.v2.cameraExtensionShim.plist")
MACH_SERVICE = "com.opalcamera.Opal.v2.cameraExtensionShim"
XPC_SERVICES = [
    OPAL_APP / "Contents/XPCServices/OpalCameraUVCService.xpc",
    OPAL_APP / "Contents/XPCServices/OpalCameraDeviceService.xpc",
    OPAL_APP / "Contents/XPCServices/OpalCameraVideoService.xpc",
]
DIST_APP = Path("dist/C1Control2026.app")


def workspace_root() -> Path:
    env_root = os.environ.get("C1_STUDIO_WORKSPACE")
    if env_root:
        candidate = Path(env_root).expanduser()
        if candidate.exists():
            return candidate
    for candidate in [Path.cwd(), *Path(__file__).resolve().parents]:
        if (candidate / "Package.swift").exists():
            return candidate
    return Path.cwd()


ROOT = workspace_root()


def run(cmd: list[str], timeout: int = 10) -> str:
    try:
        result = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout, check=False)
        return (result.stdout + result.stderr).strip()
    except Exception as exc:
        return f"{type(exc).__name__}: {exc}"


def read_plist(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        with path.open("rb") as handle:
            return plistlib.load(handle)
    except Exception:
        return {}


def codesign_detail(path: Path) -> dict:
    if not path.exists():
        return {"available": False, "path": str(path)}
    output = run(["codesign", "-dv", "--verbose=4", str(path)], timeout=10)
    detail = {"available": True, "path": str(path), "raw": output.splitlines()}
    for key in ["Identifier", "TeamIdentifier"]:
        match = re.search(rf"^{key}=(.+)$", output, re.MULTILINE)
        if match:
            detail[key] = match.group(1).strip()
    entitlements = run(["codesign", "-d", "--entitlements", ":-", str(path)], timeout=10)
    detail["entitlements_raw"] = entitlements.splitlines()[:80]
    return detail


def string_hits(path: Path, terms: list[str], limit: int = 120) -> list[str]:
    if not path.exists():
        return []
    output = run(["strings", str(path)], timeout=14)
    hits = []
    for line in output.splitlines():
        lowered = line.lower()
        if any(term.lower() in lowered for term in terms):
            hits.append(line.strip())
        if len(hits) >= limit:
            break
    return hits


def launchctl_state() -> dict:
    output = run(["launchctl", "print", f"system/{MACH_SERVICE}"], timeout=8)
    return {
        "running": "state = running" in output,
        "endpoint_visible": f'"{MACH_SERVICE}"' in output or MACH_SERVICE in output,
        "excerpt": output.splitlines()[:100],
    }


def xpc_service_report(path: Path) -> dict:
    info = read_plist(path / "Contents/Info.plist")
    executable_name = info.get("CFBundleExecutable")
    executable = path / "Contents/MacOS" / executable_name if executable_name else path
    strings_terms = [
        "OpalCameraDeviceServiceProtocol",
        "OpalCameraDeviceServiceResponderProtocol",
        "setWhiteBalance",
        "setWhiteBalanceAuto",
        "setFocus",
        "setExposure",
        "setBrightness",
        "setSaturation",
        "setSharpness",
        "UVCControl",
        "NSXPCListener",
        "interfaceWithProtocol",
        "listener:shouldAcceptNewConnection:",
    ]
    return {
        "path": str(path),
        "available": path.exists(),
        "bundle_identifier": info.get("CFBundleIdentifier"),
        "bundle_version": info.get("CFBundleVersion"),
        "xpc_service": info.get("XPCService"),
        "mach_services": info.get("MachServices") or info.get("SMPrivilegedExecutables") or {},
        "has_global_mach_service": bool(info.get("MachServices")),
        "codesign": codesign_detail(path),
        "control_symbol_hits": string_hits(executable, strings_terms, limit=80),
    }


def shim_report() -> dict:
    plist = read_plist(SHIM_PLIST)
    authorized = plist.get("SMAuthorizedClients") or []
    mach_services = plist.get("MachServices") or {}
    strings = string_hits(
        SHIM,
        [
            "SMAuthorizedClients",
            "requirementString",
            "NSXPC client does not meet the requirements",
            "retrieveEndpointWithCompletionHandler",
            "publishWithEndpoint",
            "CameraExtensionShimProtocol",
            "OpalCameraExtensionAPIProtocol",
            "NSXPCListener",
            "auditToken",
        ],
        limit=100,
    )
    signed_gate = any("97Z3HJWCRT" in item or "com.opalcamera.Opal.v2" in item for item in authorized + strings)
    return {
        "path": str(SHIM),
        "plist": {
            "available": SHIM_PLIST.exists(),
            "mach_services": mach_services,
            "authorized_clients": authorized,
        },
        "launchctl": launchctl_state(),
        "codesign": codesign_detail(SHIM),
        "authorization_strings": strings,
        "signed_client_gate": signed_gate,
    }


def verdict(report: dict) -> str:
    shim = report["shim"]
    xpcs = report["embedded_xpc_services"]
    global_xpcs = [item for item in xpcs if item.get("has_global_mach_service")]
    uvc = next((item for item in xpcs if item.get("bundle_identifier") == "com.opalcamera.OpalCameraUVCService"), {})
    if not report["opal_app_exists"]:
        return "Opal bridge unavailable: Opal Composer is not installed."
    if global_xpcs:
        return "Opal bridge maybe viable: an embedded Opal XPC service exposes a global Mach service; manual protocol testing required."
    if shim["launchctl"]["running"] and shim["signed_client_gate"]:
        if uvc.get("control_symbol_hits"):
            return "Opal bridge blocked: UVC control code exists, but it is embedded app XPC; the only global shim is gated to Opal-signed clients."
        return "Opal bridge blocked: the only global shim is gated to Opal-signed clients and no callable UVC control surface was proven."
    if shim["launchctl"]["running"]:
        return "Opal bridge uncertain: shim is running, but no callable control protocol was proven."
    return "Opal bridge unavailable: no running global Opal bridge was proven."


def recommendation(report: dict) -> str:
    text = report["verdict"]
    if text.startswith("Opal bridge blocked"):
        return "Do not make Opal XPC the v1 control backend. Prioritize direct UVC helper proof or the OBS/CMIO owned pipeline."
    if text.startswith("Opal bridge maybe"):
        return "Prototype an NSXPC client in Lab Mode only; do not ship until protocol and authorization are proven."
    return "Keep Opal bridge as diagnostic evidence only."


def collect() -> dict:
    report = {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "workspace": str(ROOT),
        "opal_app_exists": OPAL_APP.exists(),
        "shim": shim_report(),
        "embedded_xpc_services": [xpc_service_report(path) for path in XPC_SERVICES],
        "c1_studio_codesign": codesign_detail(ROOT / DIST_APP),
    }
    report["verdict"] = verdict(report)
    report["recommendation"] = recommendation(report)
    return report


def render_text(report: dict) -> str:
    lines = [
        "# C1 Opal Bridge Probe",
        "",
        f"Generated: {report['generated_at']}",
        "",
        "## Verdict",
        report["verdict"],
        "",
        "## Recommendation",
        report["recommendation"],
        "",
        "## Global Shim",
        f"- Installed: {'yes' if Path(report['shim']['path']).exists() else 'no'}",
        f"- Running: {'yes' if report['shim']['launchctl']['running'] else 'no'}",
        f"- Endpoint visible: {'yes' if report['shim']['launchctl']['endpoint_visible'] else 'no'}",
        f"- Signed-client gate: {'yes' if report['shim']['signed_client_gate'] else 'not proven'}",
        f"- Authorized clients: `{report['shim']['plist']['authorized_clients']}`",
        "",
        "## Embedded XPC Services",
        "",
        "| Service | Bundle ID | Global Mach Service | Control/Protocol Clues |",
        "| --- | --- | --- | ---: |",
    ]
    for item in report["embedded_xpc_services"]:
        lines.append(
            f"| {Path(item['path']).name} | {item.get('bundle_identifier') or ''} | "
            f"{'yes' if item.get('has_global_mach_service') else 'no'} | "
            f"{len(item.get('control_symbol_hits') or [])} |"
        )
    lines.extend([
        "",
        "## Useful Control Clues",
    ])
    for item in report["embedded_xpc_services"]:
        hits = item.get("control_symbol_hits") or []
        if not hits:
            continue
        lines.append(f"### {Path(item['path']).name}")
        for hit in hits[:30]:
            lines.append(f"- `{hit}`")
        lines.append("")
    lines.extend([
        "## Evidence Boundary",
        "- This probe is read-only.",
        "- It does not connect to private Opal protocols.",
        "- It does not launch, unload, install, or modify Opal components.",
        "- A blocked Opal bridge does not mean direct UVC/helper control is impossible.",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    report = collect()
    content = json.dumps(report, indent=2) if args.json else render_text(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content)
    print(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
