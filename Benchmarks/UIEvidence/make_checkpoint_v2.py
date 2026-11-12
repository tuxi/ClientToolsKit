#!/usr/bin/env python3
"""Write the non-frozen detector-v2 checkpoint metadata."""

from __future__ import annotations

import hashlib
import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent
RUN = ROOT / "baseline-v2"


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    environment = json.loads((RUN / "environment.json").read_text())
    evaluation = json.loads((RUN / "evaluation.json").read_text())
    gate = json.loads((RUN / "gate.json").read_text())
    fingerprint_lines = (ROOT / "audit-v1.1/baseline_fingerprint.txt").read_text().splitlines()
    checkpoint = {
        "schema": "ui_evidence_detector_v2_checkpoint.v1",
        "created_at": datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds"),
        "status": "enabled_checkpoint_not_frozen",
        "p1c_frozen": False,
        "producer": environment["tool"],
        "dataset_sha256": environment["dataset_sha256"],
        "source_sha256": environment["source_sha256"],
        "runner_source_sha256": environment["runner_source_sha256"],
        "evaluator_source_sha256": environment["evaluator_v2_source_sha256"],
        "baseline_v1_fingerprint": fingerprint_lines[0].split("=", 1)[1],
        "baseline_v2_run_metadata_sha256": digest(RUN / "run_metadata.json"),
        "baseline_v2_evaluation_sha256": digest(RUN / "evaluation.json"),
        "gate": gate,
        "metrics": {
            key: evaluation["aggregate"][key]
            for key in (
                "strict_content_f1",
                "strict_bbox_iou50",
                "strict_bbox_recall_iou50",
                "many_to_one_leaf_recall",
                "visual_line_bbox_rate_iou50",
                "visual_line_bbox_recall_iou50",
                "repeated_group_precision",
                "repeated_group_recall",
                "repeated_group_f1",
                "vision_rectangle_precision",
                "vision_rectangle_recall",
                "vision_rectangle_f1",
                "crop_integrity_rate",
                "stale_crop_artifacts",
                "hard_failure_count",
                "latency_p50_ms",
                "latency_p95_ms",
            )
        },
    }
    (RUN / "checkpoint.json").write_text(json.dumps(checkpoint, indent=2) + "\n")
    print(json.dumps(checkpoint, indent=2))


if __name__ == "__main__":
    main()
