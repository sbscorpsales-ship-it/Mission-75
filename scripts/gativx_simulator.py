"""Select the newest available iPhone simulator, preferring iPhone 17 Pro on that runtime."""
from __future__ import annotations

import json
import re
import subprocess
import sys
from typing import Any


def ios_runtime_version(identifier: str) -> tuple[int, int, int] | None:
    """Return a numeric iOS runtime version, or None for non-iOS runtimes."""
    match = re.search(r"iOS-(\d+)-(\d+)(?:-(\d+))?", identifier)
    if not match:
        return None
    major, minor, patch = match.groups()
    return int(major), int(minor), int(patch or 0)


def select_simulator(payload: dict[str, Any]) -> dict[str, Any] | None:
    """Select newest installed iOS runtime first, then prefer iPhone 17 Pro."""
    candidates: list[dict[str, Any]] = []
    for runtime, devices in payload.get("devices", {}).items():
        version = ios_runtime_version(runtime)
        if version is None:
            continue
        for device in devices:
            name = device.get("name", "")
            udid = device.get("udid")
            if device.get("isAvailable") is True and name.startswith("iPhone") and udid:
                candidates.append({
                    "runtime": runtime,
                    "version": version,
                    "name": name,
                    "udid": udid,
                })

    if not candidates:
        return None

    newest_version = max(candidate["version"] for candidate in candidates)
    newest_devices = [candidate for candidate in candidates if candidate["version"] == newest_version]
    preferred = [candidate for candidate in newest_devices if candidate["name"] == "iPhone 17 Pro"]
    return sorted(preferred or newest_devices, key=lambda candidate: (candidate["name"], candidate["udid"]))[0]


def main() -> int:
    try:
        raw = subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "available", "-j"],
            text=True,
        )
        selected = select_simulator(json.loads(raw))
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"Unable to inspect available iPhone simulators: {error}", file=sys.stderr)
        return 1

    if selected is None:
        print("No available iPhone simulator on an installed iOS runtime.", file=sys.stderr)
        return 1

    print(f"{selected['runtime']}|{selected['name']}|{selected['udid']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
