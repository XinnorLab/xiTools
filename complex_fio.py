# coding: utf-8
"""Advanced NVMe fio test runner implementing complex test matrix and scoring.

This module provides a ``run_complex`` entry point that is used by
``nvme_fio.py`` when ``--complex`` flag is supplied.  The implementation is a
light‑weight approximation of the massive requirements for the complex mode and
is intended as a foundation.  It focuses on the following aspects:

* discovery of unused NVMe namespaces (reusing helpers from ``nvme_fio``)
* running an extended matrix of fio workloads (sequential, random, mixed and
  latency tests including QD sweep)
* repeated execution with aggregation of mean/standard deviation and CoV
* basic SMART collection and pre‑filtering
* simple normalisation and scoring according to a selected RAID profile
* exporting aggregated results into JSON/YAML/CSV files

The functionality is intentionally limited – PCIe/NUMA topology analysis,
burst/on‑off workloads and advanced stability heuristics are left as TODOs to
keep the implementation manageable.
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import os
import shutil
import statistics
import subprocess
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Tuple

try:  # optional YAML support
    import yaml  # type: ignore
except Exception:  # pragma: no cover - optional dependency
    yaml = None  # type: ignore

# default parameters taken from the specification
DEFAULT_RUNTIME = 60
DEFAULT_RAMP = 10
DEFAULT_REPEAT = 3
DEFAULT_QD = [1, 4, 16, 32]
DEFAULT_BS = ["4k", "128k"]

# --------------------------- data structures -------------------------------


def _mean_std(values: Iterable[float]) -> Tuple[float, float]:
    """Return mean and standard deviation for *values* (empty -> 0, 0)."""
    data = list(values)
    if not data:
        return 0.0, 0.0
    if len(data) == 1:
        return data[0], 0.0
    return statistics.mean(data), statistics.stdev(data)


@dataclass
class FioResult:
    """Aggregated metrics for a single fio workload."""

    bw: float  # MB/s or derived from IOPS
    iops: float
    lat_p50: float = 0.0
    lat_p90: float = 0.0
    lat_p99: float = 0.0
    lat_p999: float = 0.0
    lat_max: float = 0.0
    # standard deviation / coefficient of variation across repeats
    bw_std: float = 0.0
    bw_cov: float = 0.0
    iops_std: float = 0.0
    iops_cov: float = 0.0


@dataclass
class DeviceReport:
    """Aggregated report for a device."""

    name: str
    smart: Dict[str, int] = field(default_factory=dict)
    results: Dict[str, FioResult] = field(default_factory=dict)
    score: float = 0.0
    reasons: List[str] = field(default_factory=list)


# --------------------------- SMART helpers ---------------------------------

SMART_FIELDS = {
    "critical_warning": int,
    "percentage_used": int,
    "media_errors": "media_errors",  # alias in nvme-cli output
    "num_err_log_entries": int,
    "temperature": int,
}


def collect_smart(dev: str) -> Dict[str, int]:
    """Return subset of SMART data for *dev* using ``nvme smart-log``."""
    if shutil.which("nvme") is None:
        return {}
    try:
        out = subprocess.check_output(["nvme", "smart-log", dev], text=True)
    except Exception:
        return {}
    data: Dict[str, int] = {}
    for line in out.splitlines():
        for key in SMART_FIELDS:
            if f"{key}:" in line:
                try:
                    data[key] = int(line.split(":", 1)[1].strip().split()[0])
                except ValueError:
                    pass
    return data


def smart_prefilter(report: DeviceReport) -> None:
    """Apply basic SMART based filtering and annotate *report.reasons*."""
    s = report.smart
    if not s:
        return
    if s.get("critical_warning"):
        report.reasons.append("critical warning")
    if s.get("percentage_used", 0) >= 90:
        report.reasons.append("worn out >=90%")
    if s.get("media_errors", 0) > 0:
        report.reasons.append("media errors >0")
    if s.get("temperature", 0) >= 80:  # simplistic threshold
        report.reasons.append("high temperature")


# --------------------------- fio helpers -----------------------------------


def _fio_cmd(dev: str, name: str, rw: str, bs: str, qd: int, **extra: str) -> List[str]:
    """Construct fio command list."""
    ioengine = "io_uring" if shutil.which("fio") else "libaio"
    cmd = [
        "fio",
        "--name",
        name,
        "--filename",
        dev,
        "--rw",
        rw,
        f"--bs={bs}",
        f"--iodepth={qd}",
        "--ioengine",
        ioengine,
        "--direct=1",
        f"--runtime={DEFAULT_RUNTIME}",
        f"--ramp_time={DEFAULT_RAMP}",
        "--time_based=1",
        "--output-format=json",
        "--group_reporting=1",
    ]
    for k, v in extra.items():
        if v is None:
            continue
        if len(k) == 1:
            cmd.extend([f"-{k}", str(v)])
        else:
            cmd.append(f"--{k}={v}")
    return cmd


@dataclass
class FioTest:
    name: str
    rw: str
    bs: str
    qd: int
    rwmixread: Optional[int] = None
    extra: Dict[str, str] = field(default_factory=dict)

    def build_cmd(self, dev: str) -> List[str]:
        params = dict(self.extra)
        if self.rwmixread is not None:
            params["rwmixread"] = str(self.rwmixread)
        return _fio_cmd(dev, self.name, self.rw, self.bs, self.qd, **params)


# test matrix ---------------------------------------------------------------


def build_test_matrix(allow_write: bool, qd_sweep: List[int]) -> List[FioTest]:
    tests: List[FioTest] = []
    # Sequential tests
    tests.append(FioTest("seq_read", "read", "128k", 32))
    if allow_write:
        tests.append(FioTest("seq_write", "write", "128k", 32))
    # Random read/write QD sweep
    for qd in qd_sweep:
        tests.append(FioTest(f"rand_read_qd{qd}", "randread", "4k", qd))
        if allow_write:
            tests.append(FioTest(f"rand_write_qd{qd}", "randwrite", "4k", qd))
    # Mixed workloads
    tests.append(FioTest("mixed_70_30", "randrw", "4k", 32, rwmixread=70))
    tests.append(FioTest("mixed_50_50", "randrw", "4k", 32, rwmixread=50))
    # Latency tests (QD=1)
    tests.append(FioTest("latency_read", "read", "4k", 1))
    if allow_write:
        tests.append(FioTest("latency_write", "write", "4k", 1))
    # TODO: burst/on-off workload
    return tests


# --------------------------- execution -------------------------------------


def _run_fio_once(cmd: List[str]) -> Dict[str, float]:
    """Execute fio command and return basic metrics."""
    out = subprocess.check_output(cmd, text=True)
    data = json.loads(out)
    job = data.get("jobs", [{}])[0]
    result: Dict[str, float] = {}
    if "read" in job:
        r = job["read"]
    else:
        r = job["write"]
    result["bw"] = r.get("bw", 0) / 1024.0  # convert KiB/s -> MiB/s
    result["iops"] = r.get("iops", 0)
    lat_ns = r.get("clat_ns", {})
    for p in ("50.000000", "90.000000", "99.000000", "99.900000"):
        if p in lat_ns.get("percentile", {}):
            result[f"p{p.split('.')[0]}"] = lat_ns["percentile"][p] / 1e6
    result["max"] = lat_ns.get("max", 0) / 1e6
    return result


def run_test(dev: str, test: FioTest, repeat: int, dry_run: bool = False) -> FioResult:
    bw_samples: List[float] = []
    iops_samples: List[float] = []
    lat_p50 = lat_p90 = lat_p99 = lat_p999 = lat_max = 0.0
    for _ in range(repeat):
        if dry_run:
            sample = {"bw": 0, "iops": 0}
        else:
            cmd = test.build_cmd(dev)
            sample = _run_fio_once(cmd)
        bw_samples.append(sample.get("bw", 0.0))
        iops_samples.append(sample.get("iops", 0.0))
        lat_p50 = sample.get("p50", lat_p50)
        lat_p90 = sample.get("p90", lat_p90)
        lat_p99 = sample.get("p99", lat_p99)
        lat_p999 = sample.get("p99.9", lat_p999)
        lat_max = max(lat_max, sample.get("max", lat_max))
    bw_mean, bw_std = _mean_std(bw_samples)
    iops_mean, iops_std = _mean_std(iops_samples)
    bw_cov = (bw_std / bw_mean) * 100 if bw_mean else 0.0
    iops_cov = (iops_std / iops_mean) * 100 if iops_mean else 0.0
    return FioResult(
        bw=bw_mean,
        iops=iops_mean,
        lat_p50=lat_p50,
        lat_p90=lat_p90,
        lat_p99=lat_p99,
        lat_p999=lat_p999,
        lat_max=lat_max,
        bw_std=bw_std,
        bw_cov=bw_cov,
        iops_std=iops_std,
        iops_cov=iops_cov,
    )


# --------------------------- scoring --------------------------------------

PROFILES = {
    "throughput": {
        "seq_read": 0.25,
        "seq_write": 0.25,
        "rand_read_qd32": 0.2,
        "rand_write_qd32": 0.1,
        "latency_read": 0.05,
        "latency_write": 0.05,
        "stability": 0.1,
    },
    "iops": {
        "rand_read_qd32": 0.3,
        "rand_write_qd32": 0.25,
        "latency_read": 0.125,
        "latency_write": 0.125,
        "seq_read": 0.1,
        "seq_write": 0.1,
        "stability": 0.1,
    },
    "parity": {
        "rand_write_qd32": 0.25,
        "seq_write": 0.2,
        "latency_write": 0.2,
        "rand_read_qd32": 0.15,
        "latency_read": 0.1,
        "seq_read": 0.1,
        "stability": 0.1,
    },
}


def normalise(metrics: Dict[str, float], higher_better: bool) -> Dict[str, float]:
    max_val = max(metrics.values()) or 1.0
    if higher_better:
        return {k: v / max_val for k, v in metrics.items()}
    return {k: 1 - (v / max_val) for k, v in metrics.items()}


def apply_scoring(devices: List[DeviceReport], profile: str) -> None:
    weights = PROFILES[profile]
    # collect per-test metrics across devices
    metric_maps: Dict[str, Dict[str, float]] = {}
    for dev in devices:
        for test_name, result in dev.results.items():
            metric_maps.setdefault(test_name, {})[dev.name] = (
                result.bw if "seq" in test_name or "rand" in test_name else result.lat_p50
            )
        metric_maps.setdefault("stability", {})[dev.name] = (
            sum(r.bw_cov for r in dev.results.values()) / max(len(dev.results), 1)
        )
    norm_metrics: Dict[str, Dict[str, float]] = {}
    for name, values in metric_maps.items():
        higher_better = name not in {"latency_read", "latency_write", "stability"}
        norm_metrics[name] = normalise(values, higher_better=higher_better)
    for dev in devices:
        score = 0.0
        for name, weight in weights.items():
            val = norm_metrics.get(name, {}).get(dev.name, 0.0)
            score += weight * val
        dev.score = round(score, 4)


# --------------------------- export helpers --------------------------------


def export_reports(devices: List[DeviceReport], fmt: List[str], path: str = "report") -> None:
    os.makedirs(path, exist_ok=True)
    base = os.path.join(path, "results")
    if "json" in fmt:
        with open(base + ".json", "w") as fh:
            json.dump([dev.__dict__ for dev in devices], fh, indent=2)
    if "csv" in fmt:
        with open(base + ".csv", "w", newline="") as fh:
            writer = csv.writer(fh)
            header = ["device", "score"]
            writer.writerow(header)
            for dev in devices:
                writer.writerow([dev.name, dev.score])
    if "yaml" in fmt and yaml:
        with open(base + ".yaml", "w") as fh:
            yaml.safe_dump([dev.__dict__ for dev in devices], fh)


# --------------------------- main entry ------------------------------------


def run_complex(args: argparse.Namespace) -> int:
    from nvme_fio import discover_nvme_namespaces, select_namespaces

    devs = discover_nvme_namespaces()
    if not devs:
        print("No unused NVMe namespaces found")
        return 1
    selected = select_namespaces(devs)
    if not selected:
        return 1
    qd_sweep = args.qd or DEFAULT_QD
    tests = build_test_matrix(args.allow_write, qd_sweep)
    reports: List[DeviceReport] = []
    for dev in selected:
        report = DeviceReport(name=dev)
        if not args.no_smart:
            report.smart = collect_smart(dev)
            smart_prefilter(report)
        for test in tests:
            result = run_test(dev, test, args.repeat, args.dry_run)
            report.results[test.name] = result
        reports.append(report)
    apply_scoring(reports, args.profile)
    reports.sort(key=lambda r: r.score, reverse=True)
    print("Complex test results:")
    for rep in reports:
        print(f"{rep.name}: score={rep.score:.3f} reasons={','.join(rep.reasons) or 'OK'}")
    if args.top:
        print("Top devices:")
        for rep in reports[: args.top]:
            print(f"  {rep.name} ({rep.score:.3f})")
    if args.bottom:
        print("Bottom devices:")
        for rep in reports[-args.bottom :]:
            print(f"  {rep.name} ({rep.score:.3f})")
    if args.export:
        export_reports(reports, args.export, path="report")
    return 0
