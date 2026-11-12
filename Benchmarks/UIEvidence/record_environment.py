#!/usr/bin/env python3
"""Record reproducibility metadata without absolute workspace paths."""

from __future__ import annotations

import hashlib
import json
import platform
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent
SOURCE_FILES = [
    "Sources/ClientToolsKit/InspectUIImageTool.swift",
    "Sources/ClientToolsKit/UIEvidence.swift",
    "Sources/ClientToolsKit/UIEvidenceVision.swift",
    "Sources/ClientToolsKit/ToolWorkspace.swift",
]


def command(*args: str) -> str:
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "unavailable"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "baseline"
    manifest = json.loads((ROOT / "dataset" / "manifest.json").read_text())
    repo = ROOT.parents[1]
    payload = {
        "schema": "ui_evidence_benchmark_environment.v1",
        "captured_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds"),
        "timezone": "Asia/Shanghai",
        "dataset_sha256": manifest["dataset_sha256"],
        "image_count": manifest["image_count"],
        "repetitions_per_image": 3,
        "warmup_calls": 0,
        "latency_scope": "all measured calls, including process/model cold start",
        "os": platform.platform(),
        "machine": platform.machine(),
        "python": platform.python_version(),
        "swift": command("swift", "--version").splitlines()[0] if command("swift", "--version") != "unavailable" else "unavailable",
        "tool": {
            "name": "ClientToolsKit.inspect_ui_image",
            "version": "1",
            "schema": "ui_evidence.v1",
        },
        "source_sha256": {
            path: digest(repo / path)
            for path in SOURCE_FILES
        },
        "runner_source_sha256": digest(ROOT / "Runner" / "main.swift"),
        "evaluator_source_sha256": digest(ROOT / "evaluate.py"),
        "generator_source_sha256": digest(ROOT / "generator" / "generate_dataset.py"),
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / "environment.json").write_text(json.dumps(payload, indent=2) + "\n")
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
