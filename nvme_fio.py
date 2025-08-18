#!/usr/bin/env python3
"""
Utility to run fio benchmarks on unused NVMe namespaces.

- discovers NVMe namespaces that are not part of any filesystem or LVM
- allows the user to interactively choose which of those namespaces to test
- runs sequential read and write tests with fio
    * 128k block size
    * libaio ioengine
    * direct I/O
    * iodepth 32, numjobs 4
    * offset increment 10%
    * runtime 60s
- outputs a simple table with bandwidth and IOPS
"""
import json
import os
import shutil
import subprocess
import sys
from typing import List, Tuple, Optional

RUNTIME_SECONDS = 60  # run each fio test for 1 minute


def select_namespaces(namespaces: List[str]) -> List[str]:
    """Prompt the user to choose which namespaces to test."""
    print("Found the following NVMe namespaces:")
    for dev in namespaces:
        print(f"  - {dev}")
    print()
    print("Where to conduct testing?")
    print("1) All disks")
    print("2) First N disks")
    print("3) Specific disks")
    choice = input("Choose an option [1-3]: ").strip()
    if choice == "1":
        selected = namespaces
    elif choice == "2":
        n_str = input("Enter N: ").strip()
        try:
            n = int(n_str)
        except ValueError:
            print("Invalid value for N.", file=sys.stderr)
            return []
        if n < 1 or n > len(namespaces):
            print("Invalid value for N.", file=sys.stderr)
            return []
        selected = namespaces[:n]
    elif choice == "3":
        names = input(
            "Enter disk names separated by space (e.g., nvme0n1 nvme1n1): "
        ).split()
        selected = []
        for name in names:
            disk = f"/dev/{name}" if not name.startswith("/dev/") else name
            if disk in namespaces:
                selected.append(disk)
            else:
                print(f"Disk {disk} not found.", file=sys.stderr)
        if not selected:
            print("No valid disk selected.", file=sys.stderr)
            return []
    else:
        print("Unknown option.", file=sys.stderr)
        return []
    print("Selected disks for testing:")
    for dev in selected:
        print(f"  - {dev}")
    return selected


def _is_unused(dev: dict) -> bool:
    """Return True if device tree has no filesystem or LVM usage."""
    if dev.get("mountpoint") or dev.get("fstype"):
        return False
    for child in dev.get("children", []) or []:
        if not _is_unused(child):
            return False
    return True


def discover_nvme_namespaces() -> List[str]:
    """Return list of unused NVMe namespaces (e.g., /dev/nvme0n1)."""
    try:
        out = subprocess.check_output(
            [
                "lsblk",
                "-J",
                "-o",
                "NAME,TYPE,MOUNTPOINT,FSTYPE,TRAN",
            ]
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"lsblk failed: {exc}", file=sys.stderr)
        return []
    data = json.loads(out.decode())
    namespaces: List[str] = []
    for dev in data.get("blockdevices", []):
        if dev.get("tran") != "nvme" or dev.get("type") != "disk":
            continue
        if _is_unused(dev):
            namespaces.append(f"/dev/{dev['name']}")
    return namespaces


def run_fio(dev: str, mode: str) -> Tuple[Optional[float], Optional[float]]:
    """Run fio for given device and mode (read/write).

    Returns tuple of (bandwidth_MB_s, iops)."""
    cmd = [
        "fio",
        "--name",
        f"{mode}-{os.path.basename(dev)}",
        "--filename",
        dev,
        "--rw",
        mode,
        "--ioengine=libaio",
        "--direct=1",
        "--bs=128k",
        "--iodepth=32",
        "--numjobs=4",
        "--offset_increment=10%",
        "--time_based",
        f"--runtime={RUNTIME_SECONDS}",
        "--output-format=json",
    ]
    try:
        out = subprocess.check_output(cmd, text=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"fio {mode} on {dev} failed: {exc}", file=sys.stderr)
        return None, None
    try:
        data = json.loads(out)
        job = data.get("jobs", [{}])[0][mode]
        bw_mb = job.get("bw", 0) / 1024.0  # fio reports KB/s
        return bw_mb, job.get("iops")
    except Exception as exc:  # pragma: no cover - defensive
        print(f"failed to parse fio output for {dev}: {exc}", file=sys.stderr)
        return None, None


def main() -> int:
    if shutil.which("fio") is None:
        print("fio not found in PATH", file=sys.stderr)
        return 1
    devs = discover_nvme_namespaces()
    if not devs:
        print("No unused NVMe namespaces found", file=sys.stderr)
        return 1
    devs = select_namespaces(devs)
    if not devs:
        return 1

    results = []
    for dev in devs:
        read_bw, read_iops = run_fio(dev, "read")
        write_bw, write_iops = run_fio(dev, "write")
        results.append((dev, read_bw, read_iops, write_bw, write_iops))

    header = "{:<15} {:>15} {:>12} {:>15} {:>12}".format(
        "Device", "Read BW (MB/s)", "Read IOPS", "Write BW (MB/s)", "Write IOPS"
    )
    print(header)
    print("-" * len(header))
    for dev, rbw, riops, wbw, wiops in results:
        print(
            "{:<15} {:>15} {:>12} {:>15} {:>12}".format(
                dev,
                f"{rbw:.1f}" if rbw is not None else "n/a",
                f"{riops:.0f}" if riops is not None else "n/a",
                f"{wbw:.1f}" if wbw is not None else "n/a",
                f"{wiops:.0f}" if wiops is not None else "n/a",
            )
        )
    return 0


if __name__ == "__main__":  # pragma: no cover - entrypoint
    sys.exit(main())

