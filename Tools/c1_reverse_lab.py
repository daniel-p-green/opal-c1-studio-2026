#!/usr/bin/env python3
"""Read-only Opal C1 reverse-lab evidence collector."""

from __future__ import annotations

import argparse
import binascii
import glob
import json
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path


VID = 0x03E7
PID = 0xF63B
OPAL_APP = Path("/Applications/Opal Composer.app")
UVC_SERVICE = OPAL_APP / "Contents/XPCServices/OpalCameraUVCService.xpc/Contents/MacOS/OpalCameraUVCService"
DEVICE_SERVICE = OPAL_APP / "Contents/XPCServices/OpalCameraDeviceService.xpc/Contents/MacOS/OpalCameraDeviceService"
VIDEO_SERVICE = OPAL_APP / "Contents/XPCServices/OpalCameraVideoService.xpc/Contents/MacOS/OpalCameraVideoService"
SHIM = Path("/Library/PrivilegedHelperTools/com.opalcamera.Opal.v2.cameraExtensionShim")
SHIM_PLIST = Path("/Library/LaunchDaemons/com.opalcamera.Opal.v2.cameraExtensionShim.plist")
MACH_SERVICE = "com.opalcamera.Opal.v2.cameraExtensionShim"

PRIORITY_SYMBOLS = [
    "UVCCameraDevice setWhiteBalance:",
    "UVCCameraDevice setWhiteBalanceAuto:",
    "UVCCameraDevice setFocus:",
    "UVCCameraDevice setFocusAuto:",
    "UVCCameraDevice setExposureTime:",
    "UVCCameraDevice setExposureAuto:",
    "UVCCameraDevice setISO:",
    "UVCCameraDevice setBrightness:",
    "UVCCameraDevice setContrast:",
    "UVCCameraDevice setSaturation:",
    "UVCCameraDevice setAntiBandingMode:",
    "UVCControl getDataForType:length:",
    "UVCControl setDataWithValue:length:",
    "UVCDeviceProperties initWithDeviceHandle:terminalId:processingId:interfaceId:",
]

CONTROL_CANDIDATES = [
    ("focusAbsolute", 1, 6, 2),
    ("focusAuto", 1, 17, 1),
    ("exposureAuto", 1, 2, 1),
    ("exposureTime", 1, 4, 4),
    ("irisAbsolute", 1, 8, 2),
    ("zoomAbsolute", 1, 10, 2),
    ("brightness", 3, 2, 2),
    ("contrast", 3, 3, 2),
    ("gain", 3, 4, 2),
    ("powerLineFrequency", 3, 5, 1),
    ("saturation", 3, 7, 2),
    ("sharpness", 3, 8, 2),
    ("gamma", 3, 9, 2),
    ("whiteBalanceTemperature", 3, 10, 2),
    ("whiteBalanceAuto", 3, 15, 1),
]

CONTROL_BY_KEY = {key: (entity, selector, size) for key, entity, selector, size in CONTROL_CANDIDATES}

UVC_REQUESTS = {
    0x86: "GET_INFO",
    0x81: "GET_CUR",
    0x82: "GET_MIN",
    0x83: "GET_MAX",
    0x84: "GET_RES",
    0x87: "GET_DEF",
}


def maybe_reexec_with_tmp_venv() -> None:
    if os.environ.get("C1_REVERSE_LAB_REEXEC"):
        return
    try:
        import usb.core  # noqa: F401
        return
    except Exception:
        pass

    candidates = sorted(glob.glob("/tmp/opal-depthai-venv/bin/python*"))
    for candidate in candidates:
        if Path(candidate).name.startswith("python"):
            env = os.environ.copy()
            env["C1_REVERSE_LAB_REEXEC"] = "1"
            os.execve(candidate, [candidate, *sys.argv], env)


def run(cmd: list[str], timeout: int = 8) -> str:
    try:
        result = subprocess.run(cmd, check=False, text=True, capture_output=True, timeout=timeout)
        output = (result.stdout + result.stderr).strip()
        return output if output else f"(exit {result.returncode}, no output)"
    except Exception as exc:
        return f"{type(exc).__name__}: {exc}"


def shell_quote(path: Path | str) -> str:
    value = str(path)
    return "'" + value.replace("'", "'\"'\"'") + "'"


def hex_bytes(value) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return binascii.hexlify(value).decode()
    return binascii.hexlify(bytes(value)).decode()


def int_value(data: bytes) -> int | str | None:
    if not data:
        return None
    if len(data) in (1, 2, 4):
        return int.from_bytes(data, "little", signed=len(data) != 1)
    return data.hex()


def collect_usb() -> dict:
    try:
        import usb.core
        import usb.util
    except Exception as exc:
        return {"available": False, "error": f"pyusb unavailable: {exc}"}

    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        return {"available": False, "error": "Opal C1 USB device not found"}

    data = {
        "available": True,
        "vendor_id": f"0x{VID:04x}",
        "product_id": f"0x{PID:04x}",
        "bcd_device": f"0x{dev.bcdDevice:04x}",
        "bus": getattr(dev, "bus", None),
        "address": getattr(dev, "address", None),
        "strings": {},
        "interfaces": [],
        "control_probes": [],
    }

    for label, index in [("manufacturer", dev.iManufacturer), ("product", dev.iProduct), ("serial", dev.iSerialNumber)]:
        try:
            data["strings"][label] = usb.util.get_string(dev, index)
        except Exception as exc:
            data["strings"][label] = f"unreadable: {exc}"

    for cfg in dev:
        for intf in cfg:
            data["interfaces"].append({
                "interface": intf.bInterfaceNumber,
                "alt": intf.bAlternateSetting,
                "class": f"0x{intf.bInterfaceClass:02x}",
                "subclass": f"0x{intf.bInterfaceSubClass:02x}",
                "protocol": f"0x{intf.bInterfaceProtocol:02x}",
                "endpoints": [f"0x{ep.bEndpointAddress:02x}" for ep in intf],
                "extra": hex_bytes(intf.extra_descriptors),
            })

    for key, entity, selector, size in CONTROL_CANDIDATES:
        probe = {"key": key, "entity": entity, "selector": selector, "size": size, "requests": {}}
        for request, request_name in UVC_REQUESTS.items():
            try:
                raw = bytes(dev.ctrl_transfer(0xA1, request, selector << 8, (entity << 8) | 1, size, timeout=1000))
                probe["requests"][request_name] = {"raw": raw.hex(), "value": int_value(raw)}
            except Exception as exc:
                probe["requests"][request_name] = {"error": str(exc)}
        info = probe["requests"].get("GET_INFO", {})
        raw_info = info.get("raw")
        if raw_info:
            flags = int.from_bytes(bytes.fromhex(raw_info), "little")
            probe["readable"] = bool(flags & 0x01)
            probe["writable"] = bool(flags & 0x02)
            probe["blocker"] = None
        else:
            errors = [value.get("error", "") for value in probe["requests"].values() if isinstance(value, dict)]
            denied = [error for error in errors if "Access denied" in error or "insufficient permissions" in error]
            probe["readable"] = False
            probe["writable"] = False
            probe["blocker"] = "access_denied" if denied else (errors[0] if errors else "unknown")
        data["control_probes"].append(probe)

    return data


def encode_value(value: int, size: int) -> bytes:
    signed = size != 1
    return int(value).to_bytes(size, "little", signed=signed)


def write_uvc_control(key: str, value: int, yes_write: bool) -> dict:
    if key not in CONTROL_BY_KEY:
        return {"ok": False, "error": f"unknown control key: {key}"}
    if not yes_write:
        return {
            "ok": False,
            "error": "refusing to write without --yes-write; default mode is read-only",
        }
    try:
        import usb.core
    except Exception as exc:
        return {"ok": False, "error": f"pyusb unavailable: {exc}"}

    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        return {"ok": False, "error": "Opal C1 USB device not found"}

    entity, selector, size = CONTROL_BY_KEY[key]
    payload = encode_value(value, size)
    try:
        written = dev.ctrl_transfer(0x21, 0x01, selector << 8, (entity << 8) | 1, payload, timeout=1000)
        return {
            "ok": True,
            "key": key,
            "value": value,
            "entity": entity,
            "selector": selector,
            "size": size,
            "bytes_written": written,
            "payload": payload.hex(),
        }
    except Exception as exc:
        return {
            "ok": False,
            "key": key,
            "value": value,
            "entity": entity,
            "selector": selector,
            "size": size,
            "error": str(exc),
        }


def collect_symbols(binary: Path) -> dict:
    if not binary.exists():
        return {"path": str(binary), "available": False}
    nm_output = run(["nm", "-m", str(binary)], timeout=12)
    strings_output = run(["strings", str(binary)], timeout=12)
    hits = []
    for symbol in PRIORITY_SYMBOLS:
        needle = symbol.replace(" ", "")
        if symbol in nm_output or symbol in strings_output or needle in nm_output or needle in strings_output:
            hits.append(symbol)

    interesting = []
    for line in nm_output.splitlines():
        lowered = line.lower()
        if any(term in lowered for term in ["uvc", "whitebalance", "focus", "exposure", "brightness", "saturation", "controlqueue", "depthai"]):
            interesting.append(line.strip())
        if len(interesting) >= 80:
            break

    return {
        "path": str(binary),
        "available": True,
        "priority_hits": hits,
        "interesting_symbols": interesting,
        "linked_libraries": run(["otool", "-L", str(binary)], timeout=8).splitlines(),
    }


def collect_shim_symbols() -> dict:
    if not SHIM.exists():
        return {"path": str(SHIM), "available": False}

    strings_output = run(["strings", str(SHIM)], timeout=12)
    interesting = []
    for line in strings_output.splitlines():
        lowered = line.lower()
        if any(term in lowered for term in [
            "mach", "xpc", "service", "uvc", "cameraextension", "protocol",
            "endpoint", "authorization", "opalcamera", "virtual", "camera",
        ]):
            interesting.append(line.strip())
        if len(interesting) >= 120:
            break

    return {
        "path": str(SHIM),
        "available": True,
        "codesign": run(["codesign", "-dv", "--verbose=4", str(SHIM)], timeout=8).splitlines(),
        "launch_daemon_plist": run(["plutil", "-p", str(SHIM_PLIST)], timeout=8).splitlines() if SHIM_PLIST.exists() else [],
        "interesting_strings": interesting,
    }


def collect_bridge_candidates() -> dict:
    launchctl = run(["launchctl", "print", f"system/{MACH_SERVICE}"], timeout=8)
    shim_strings = collect_shim_symbols()
    return {
        "direct_uvc": {
            "status": "probe_required",
            "notes": "Standard UVC control transfers are attempted read-only in the USB section.",
        },
        "opal_shim": {
            "mach_service": MACH_SERVICE,
            "running": "state = running" in launchctl,
            "endpoint_visible": MACH_SERVICE in launchctl,
            "launchctl": launchctl.splitlines()[:80],
            "expected_blocker": "Shim strings include NSXPC authorization and Opal team requirement; non-Opal clients are likely rejected.",
            "shim": shim_strings,
        },
        "opal_embedded_xpc": {
            "status": "not_global",
            "notes": "UVC/Device/Video XPC services are embedded inside Opal Composer.app and no global MachServices were found in their Info.plists.",
            "services": [str(UVC_SERVICE), str(DEVICE_SERVICE), str(VIDEO_SERVICE)],
        },
        "depthai": {
            "status": "unknown",
            "notes": "Prior local depthai probe found zero available devices while Opal's extension owned the camera.",
        },
    }


def collect_system() -> dict:
    script_path = Path(__file__).resolve()
    root_output_json = Path.cwd() / "work" / "c1-root-probe.json"
    root_output_text = Path.cwd() / "work" / "c1-root-probe.md"
    return {
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "host": platform.platform(),
        "uid": os.getuid(),
        "euid": os.geteuid(),
        "is_root": os.geteuid() == 0,
        "root_probe_command": f"sudo {shell_quote(script_path)} --json --output {shell_quote(root_output_json)}",
        "root_probe_text_command": f"sudo {shell_quote(script_path)} --text --output {shell_quote(root_output_text)}",
        "sw_vers": run(["sw_vers"]),
        "opal_processes": run(["pgrep", "-afil", "Opal|Composer|OpalCamera|cameraExtension"]),
        "system_extensions": run(["/bin/zsh", "-lc", "systemextensionsctl list | rg -i 'opal|obs|camera|extension'"]),
        "launch_daemon": run(["/bin/zsh", "-lc", "launchctl print system/com.opalcamera.Opal.v2.cameraExtensionShim 2>&1 | head -n 80"]),
    }


def summarize_backend(report: dict) -> list[str]:
    lines = []
    usb = report.get("usb", {})
    probes = usb.get("control_probes", [])
    blocked = [probe for probe in probes if probe.get("blocker") == "access_denied"]
    writable = [probe for probe in probes if probe.get("writable")]
    if usb.get("available"):
        lines.append(f"USB: Opal C1 present ({usb.get('vendor_id')}:{usb.get('product_id')}), bcdDevice {usb.get('bcd_device')}.")
    else:
        lines.append(f"USB: unavailable ({usb.get('error', 'unknown error')}).")
    if writable:
        lines.append(f"Direct UVC: {len(writable)} controls report writable through GET_INFO.")
    elif blocked:
        lines.append("Direct UVC: blocked by access denied in this user session; run the root probe to test helper viability.")
    else:
        lines.append("Direct UVC: no writable controls proven yet.")
    bridge = report.get("bridges", {}).get("opal_shim", {})
    if bridge.get("running"):
        lines.append("Opal shim: running as a global Mach service, but strings show NSXPC authorization checks for Opal-signed clients.")
    else:
        lines.append("Opal shim: not confirmed running.")
    if report.get("uvc_service", {}).get("priority_hits"):
        lines.append("Opal UVCService: contains focus/exposure/white-balance/brightness control symbols worth mapping.")
    return lines


def control_value(probe: dict, request_name: str) -> str:
    item = probe.get("requests", {}).get(request_name, {})
    if "value" in item:
        return str(item["value"])
    if "raw" in item:
        return item["raw"]
    return ""


def control_proof(report: dict) -> dict:
    probes = report.get("usb", {}).get("control_probes", [])
    readable = [probe for probe in probes if probe.get("readable")]
    writable = [probe for probe in probes if probe.get("writable")]
    blocked = [probe for probe in probes if probe.get("blocker")]
    access_denied = [probe for probe in blocked if probe.get("blocker") == "access_denied"]
    low_risk_write = None
    for key in ["brightness", "contrast", "saturation", "sharpness", "powerLineFrequency"]:
        candidate = next((probe for probe in writable if probe.get("key") == key), None)
        if candidate:
            current = control_value(candidate, "GET_CUR")
            low_risk_write = {
                "key": key,
                "current": current,
                "command": f"{shell_quote(Path(__file__).resolve())} --write-control {key} --value {current or 0} --yes-write",
            }
            break
    if writable:
        status = "direct_uvc_proven"
    elif access_denied:
        status = "needs_root_probe"
    elif probes:
        status = "uvc_probe_failed"
    else:
        status = "no_controls_seen"
    return {
        "status": status,
        "readable_count": len(readable),
        "writable_count": len(writable),
        "blocked_count": len(blocked),
        "access_denied_count": len(access_denied),
        "low_risk_write": low_risk_write,
        "controls": [
            {
                "key": probe.get("key"),
                "entity": probe.get("entity"),
                "selector": probe.get("selector"),
                "size": probe.get("size"),
                "readable": probe.get("readable"),
                "writable": probe.get("writable"),
                "current": control_value(probe, "GET_CUR"),
                "minimum": control_value(probe, "GET_MIN"),
                "maximum": control_value(probe, "GET_MAX"),
                "resolution": control_value(probe, "GET_RES"),
                "default": control_value(probe, "GET_DEF"),
                "blocker": probe.get("blocker"),
            }
            for probe in probes
        ],
    }


def render_control_proof(report: dict) -> str:
    proof = report.get("control_proof") or control_proof(report)
    lines = [
        "# C1 Hardware Control Proof",
        "",
        f"Generated: {report['system']['generated_at']}",
        f"Root: {report['system']['is_root']} (uid={report['system']['uid']}, euid={report['system']['euid']})",
        "",
        "## Verdict",
    ]
    status = proof["status"]
    if status == "direct_uvc_proven":
        lines.append(f"Direct UVC control is proven: {proof['readable_count']} readable, {proof['writable_count']} writable controls.")
    elif status == "needs_root_probe":
        lines.append("Direct UVC is present but blocked by user-session USB permissions. Run the reversible root probe next.")
    elif status == "uvc_probe_failed":
        lines.append("UVC control probes ran but did not prove readable/writable controls. Inspect blockers below.")
    else:
        lines.append("No UVC control candidates were proven.")
    lines.extend([
        "",
        "## Next Command",
        "```bash",
        report["system"]["root_probe_command"],
        "```",
        "",
        "## Control Counts",
        f"- Readable: {proof['readable_count']}",
        f"- Writable: {proof['writable_count']}",
        f"- Blocked: {proof['blocked_count']}",
        f"- Access denied: {proof['access_denied_count']}",
        "",
    ])
    if proof.get("low_risk_write"):
        lines.extend([
            "## Low-Risk Write Verification Candidate",
            "Only run this after reviewing the root probe values. It writes the current value back to the same control.",
            "",
            "```bash",
            proof["low_risk_write"]["command"],
            "```",
            "",
        ])
    lines.extend([
        "## Controls",
        "",
        "| Control | Entity | Selector | R | W | Current | Min | Max | Step | Default | Blocker |",
        "| --- | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |",
    ])
    for control in proof["controls"]:
        lines.append(
            f"| {control['key']} | {control['entity']} | {control['selector']} | "
            f"{control['readable']} | {control['writable']} | {control['current']} | "
            f"{control['minimum']} | {control['maximum']} | {control['resolution']} | "
            f"{control['default']} | {control['blocker'] or ''} |"
        )
    lines.extend([
        "",
        "## Evidence Boundary",
        "- This report does not flash firmware.",
        "- This report does not unload or replace Opal system extensions.",
        "- Writes require explicit `--write-control ... --yes-write` and are not part of the default probe.",
    ])
    return "\n".join(lines)


def render_text(report: dict) -> str:
    lines = []
    lines.append("# C1 Reverse Lab Report")
    lines.append("")
    lines.append(f"Generated: {report['system']['generated_at']}")
    lines.append(f"Root: {report['system']['is_root']} (uid={report['system']['uid']}, euid={report['system']['euid']})")
    lines.append("")
    lines.append("## Product-Relevant Backend Summary")
    lines.extend(f"- {line}" for line in summarize_backend(report))
    lines.append("")
    if "write_result" in report:
        lines.append("## Write Attempt Result")
        lines.append(json.dumps(report["write_result"], indent=2))
        lines.append("")
    lines.append("## Reversible Root Probe")
    lines.append("Run this manually only when you want to test whether a local helper can read standard UVC controls:")
    lines.append("")
    lines.append("```bash")
    lines.append(report["system"]["root_probe_command"])
    lines.append("```")
    lines.append("")
    lines.append("## System")
    lines.append(report["system"]["sw_vers"])
    lines.append("")
    lines.append("## Opal Processes")
    lines.append(report["system"]["opal_processes"])
    lines.append("")
    lines.append("## System Extensions")
    lines.append(report["system"]["system_extensions"])
    lines.append("")
    lines.append("## USB")
    usb = report["usb"]
    lines.append(json.dumps({k: v for k, v in usb.items() if k not in ("interfaces", "control_probes")}, indent=2))
    lines.append("")
    lines.append("### Interfaces")
    for intf in usb.get("interfaces", []):
        lines.append(json.dumps(intf, indent=2))
    lines.append("")
    lines.append("### Read-only UVC Control Probes")
    lines.append("")
    lines.append("| Control | Entity | Selector | Size | Readable | Writable | Current | Min | Max | Default | Blocker |")
    lines.append("| --- | ---: | ---: | ---: | --- | --- | --- | --- | --- | --- | --- |")
    for probe in usb.get("control_probes", []):
        req = probe.get("requests", {})
        def value(name: str) -> str:
            item = req.get(name, {})
            if "value" in item:
                return str(item["value"])
            return ""
        lines.append(
            f"| {probe.get('key')} | {probe.get('entity')} | {probe.get('selector')} | {probe.get('size')} | "
            f"{probe.get('readable')} | {probe.get('writable')} | {value('GET_CUR')} | {value('GET_MIN')} | "
            f"{value('GET_MAX')} | {value('GET_DEF')} | {probe.get('blocker') or ''} |"
        )
    lines.append("")
    for probe in usb.get("control_probes", []):
        lines.append(json.dumps(probe, indent=2))
    lines.append("")
    lines.append("## Bridge Candidates")
    lines.append(json.dumps(report["bridges"], indent=2))
    lines.append("")
    lines.append("## Opal UVC Service Symbols")
    lines.append(json.dumps(report["uvc_service"], indent=2))
    lines.append("")
    lines.append("## Opal Device Service Symbols")
    lines.append(json.dumps(report["device_service"], indent=2))
    lines.append("")
    lines.append("## Opal Video Service Symbols")
    lines.append(json.dumps(report["video_service"], indent=2))
    return "\n".join(lines)


def main() -> int:
    maybe_reexec_with_tmp_venv()
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--text", action="store_true")
    parser.add_argument("--control-proof", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--write-control", choices=sorted(CONTROL_BY_KEY))
    parser.add_argument("--value", type=int)
    parser.add_argument("--yes-write", action="store_true")
    args = parser.parse_args()

    write_result = None
    if args.write_control:
        if args.value is None:
            parser.error("--write-control requires --value")
        write_result = write_uvc_control(args.write_control, args.value, args.yes_write)

    report = {
        "system": collect_system(),
        "usb": collect_usb(),
        "bridges": collect_bridge_candidates(),
        "uvc_service": collect_symbols(UVC_SERVICE),
        "device_service": collect_symbols(DEVICE_SERVICE),
        "video_service": collect_symbols(VIDEO_SERVICE),
    }
    report["control_proof"] = control_proof(report)
    if write_result is not None:
        report["write_result"] = write_result

    if args.control_proof:
        content = json.dumps(report["control_proof"], indent=2) if args.json else render_control_proof(report)
    else:
        content = json.dumps(report, indent=2) if args.json else render_text(report)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(content)
    print(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
