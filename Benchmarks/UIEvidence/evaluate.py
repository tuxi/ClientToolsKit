#!/usr/bin/env python3
"""Score an immutable inspect_ui_image run against DOM-derived ground truth."""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import statistics
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageStat

ROOT = Path(__file__).resolve().parent
DEFAULT_DATASET = ROOT / "dataset"
DEFAULT_RUN = ROOT / "baseline"

BANNED_RECOMMENDATION_KEYS = {
    "recommended_component", "layout_should_be", "use_this_view", "next_call",
    "selected_design", "recommended_layout", "recommended_navigation",
    "recommended_component_id", "component_recommendation", "layout_recommendation",
    "ui_layout", "ui_layout_v1", "recommendation", "recommendations",
}
BANNED_RECOMMENDATION_VALUES = {
    "ui_layout.v1", "recommended_component", "layout_should_be", "use_this_view",
}
EPSILON = 1e-6


def bbox(raw: dict[str, Any]) -> tuple[float, float, float, float]:
    return (float(raw["x"]), float(raw["y"]), float(raw["width"]), float(raw["height"]))


def iou(a: tuple[float, float, float, float], b: tuple[float, float, float, float]) -> float:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    x0, y0 = max(ax, bx), max(ay, by)
    x1, y1 = min(ax + aw, bx + bw), min(ay + ah, by + bh)
    intersection = max(0.0, x1 - x0) * max(0.0, y1 - y0)
    union = aw * ah + bw * bh - intersection
    return intersection / union if union > 0 else 0.0


def bbox_valid(raw: dict[str, Any]) -> bool:
    try:
        x, y, width, height = bbox(raw)
    except (KeyError, TypeError, ValueError):
        return False
    values = (x, y, width, height)
    return (
        all(math.isfinite(value) for value in values)
        and x >= -EPSILON
        and y >= -EPSILON
        and width > 0
        and height > 0
        and x + width <= 1 + EPSILON
        and y + height <= 1 + EPSILON
    )


def normalize_text(value: str | None) -> str:
    if not value:
        return ""
    value = unicodedata.normalize("NFKC", value).casefold()
    return "".join(character for character in value if character.isalnum())


def match_boxes(
    truth: list[dict[str, Any]],
    predicted: list[dict[str, Any]],
    threshold: float = 0.5,
) -> tuple[int, list[tuple[dict[str, Any], dict[str, Any], float]]]:
    candidates: list[tuple[float, int, int]] = []
    for index, gt in enumerate(truth):
        for pred_index, pred in enumerate(predicted):
            score = iou(bbox(gt["bbox"]), bbox(pred["bbox"]))
            if score >= threshold:
                candidates.append((score, index, pred_index))
    candidates.sort(reverse=True)
    used_truth: set[int] = set()
    used_predicted: set[int] = set()
    matches: list[tuple[dict[str, Any], dict[str, Any], float]] = []
    for score, truth_index, predicted_index in candidates:
        if truth_index in used_truth or predicted_index in used_predicted:
            continue
        used_truth.add(truth_index)
        used_predicted.add(predicted_index)
        matches.append((truth[truth_index], predicted[predicted_index], score))
    return len(matches), matches


def match_text(
    truth: list[dict[str, Any]],
    predicted: list[dict[str, Any]],
) -> tuple[int, list[tuple[dict[str, Any], dict[str, Any], float]], list[dict[str, Any]], list[dict[str, Any]]]:
    used_predicted: set[int] = set()
    matched: list[tuple[dict[str, Any], dict[str, Any], float]] = []
    truth_unmatched: list[dict[str, Any]] = []
    for gt in sorted(truth, key=lambda item: (item["bbox"]["y"], item["bbox"]["x"])):
        target = normalize_text(gt.get("text"))
        candidates = [
            (iou(bbox(gt["bbox"]), bbox(pred["bbox"])), index)
            for index, pred in enumerate(predicted)
            if index not in used_predicted and normalize_text(pred.get("text")) == target and target
        ]
        if not candidates:
            truth_unmatched.append(gt)
            continue
        score, index = max(candidates)
        used_predicted.add(index)
        matched.append((gt, predicted[index], score))
    predicted_unmatched = [
        pred for index, pred in enumerate(predicted) if index not in used_predicted
    ]
    return len(matched), matched, truth_unmatched, predicted_unmatched


def match_groups(truth: list[dict[str, Any]], predicted: list[dict[str, Any]]) -> tuple[int, list[tuple[dict[str, Any], dict[str, Any], float]]]:
    candidates: list[tuple[float, int, int]] = []
    for g_index, gt in enumerate(truth):
        for p_index, pred in enumerate(predicted):
            if gt.get("axis") != pred.get("axis"):
                continue
            score = iou(bbox(gt["bbox"]), bbox(pred["bbox"]))
            if score >= 0.5:
                candidates.append((score, g_index, p_index))
    candidates.sort(reverse=True)
    used_truth: set[int] = set()
    used_predicted: set[int] = set()
    matches: list[tuple[dict[str, Any], dict[str, Any], float]] = []
    for score, t_index, p_index in candidates:
        if t_index in used_truth or p_index in used_predicted:
            continue
        used_truth.add(t_index)
        used_predicted.add(p_index)
        matches.append((truth[t_index], predicted[p_index], score))
    return len(matches), matches


def prf(tp: int, fp: int, fn: int) -> tuple[float, float, float]:
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return precision, recall, f1


def walk_json(value: Any, path: str = "$") -> Iterable[tuple[str, str, Any]]:
    if isinstance(value, dict):
        for key, nested in value.items():
            child = f"{path}.{key}"
            yield child, key, nested
            yield from walk_json(nested, child)
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            yield from walk_json(nested, f"{path}[{index}]")


def recommendation_leaks(evidence: dict[str, Any], content: str) -> list[str]:
    leaks: list[str] = []
    for path, key, value in walk_json(evidence):
        if key.casefold() in BANNED_RECOMMENDATION_KEYS:
            leaks.append(f"{path} uses forbidden key {key!r}")
        if isinstance(value, str) and value.casefold() in BANNED_RECOMMENDATION_VALUES:
            leaks.append(f"{path} contains forbidden value {value!r}")
    lower = content.casefold()
    for value in BANNED_RECOMMENDATION_VALUES:
        if value in lower:
            leaks.append(f"tool content contains forbidden value {value!r}")
    return sorted(set(leaks))


def crop_usability(
    run_root: Path,
    image_id: str,
    checks: list[dict[str, Any]],
) -> tuple[int, list[dict[str, Any]]]:
    usable = 0
    enriched: list[dict[str, Any]] = []
    for check in checks:
        item = dict(check)
        path = run_root / "assets" / image_id / check.get("workspace_path", "")
        item["path_exists"] = path.is_file()
        item["pil_decodable"] = False
        item["variance"] = 0.0
        item["nonblank"] = False
        if path.is_file():
            try:
                with Image.open(path) as image:
                    image.verify()
                with Image.open(path) as image:
                    rgb = image.convert("RGB")
                    width, height = rgb.size
                    stat = ImageStat.Stat(rgb.convert("L"))
                    variance = float(stat.var[0]) if stat.var else 0.0
                item["pil_decodable"] = True
                item["width"] = width
                item["height"] = height
                item["variance"] = round(variance, 6)
                item["nonblank"] = variance > 0.1
            except Exception as error:  # report decode failure rather than abort the run
                item["decode_error"] = str(error)
        item["usable"] = bool(
            check.get("usable")
            and item["path_exists"]
            and item["pil_decodable"]
            and item["nonblank"]
        )
        item["escape"] = bool(check.get("escaped_workspace"))
        usable += int(item["usable"])
        enriched.append(item)
    return usable, enriched


def safe_ratio(numerator: int | float, denominator: int | float) -> float:
    return float(numerator) / float(denominator) if denominator else 0.0


def percentile(values: list[float], quantile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(1, math.ceil(quantile * len(ordered)))
    return ordered[min(len(ordered) - 1, rank - 1)]


def score_image(
    record: dict[str, Any],
    truth: dict[str, Any],
    manifest_image: dict[str, Any],
    run_root: Path,
) -> dict[str, Any]:
    evidence = record["evidence"]
    elements = evidence.get("elements", [])
    text_predictions = [element for element in elements if element.get("kind") == "text"]
    container_predictions = [element for element in elements if element.get("kind") == "container"]

    text_tp, text_matches, text_unmatched, text_fp_items = match_text(truth["text"], text_predictions)
    text_fn = len(text_unmatched)
    text_fp = len(text_fp_items)
    ocr_precision, ocr_recall, ocr_f1 = prf(text_tp, text_fp, text_fn)
    bbox_hits = sum(1 for _, _, score in text_matches if score >= 0.5)
    mean_text_iou = statistics.fmean(score for _, _, score in text_matches) if text_matches else 0.0
    text_bbox_rate = safe_ratio(bbox_hits, len(text_matches))
    text_bbox_recall = safe_ratio(bbox_hits, len(truth["text"]))

    container_tp, container_matches = match_boxes(truth["containers"], container_predictions)
    container_fp = len(container_predictions) - container_tp
    container_fn = len(truth["containers"]) - container_tp
    container_precision, container_recall, container_f1 = prf(container_tp, container_fp, container_fn)

    group_truth = truth.get("repeated_groups", [])
    group_predictions = evidence.get("repeated_groups", [])
    group_tp, group_matches = match_groups(group_truth, group_predictions)
    group_fp = len(group_predictions) - group_tp
    group_fn = len(group_truth) - group_tp
    _, _, group_f1 = prf(group_tp, group_fp, group_fn)

    label_correct = 0
    label_total = 0
    label_errors: list[str] = []
    for gt, pred, _ in text_matches:
        label_total += 1
        if pred.get("evidence") == "observed":
            label_correct += 1
        else:
            label_errors.append(f"text {gt.get('text')!r}: expected observed, got {pred.get('evidence')}")
    for gt, pred, _ in container_matches:
        label_total += 1
        if pred.get("evidence") == "inferred":
            label_correct += 1
        else:
            label_errors.append(f"container {gt.get('id')!r}: expected inferred, got {pred.get('evidence')}")

    crop_usable_count, crops = crop_usability(run_root, record["id"], record.get("crop_checks", []))
    crop_count = len(record.get("crop_checks", []))
    crop_rate = safe_ratio(crop_usable_count, crop_count)

    workspace_assets = run_root / "assets" / record["id"]
    referenced_crops = {check.get("workspace_path", "") for check in record.get("crop_checks", [])}
    orphan_crops: list[str] = []
    crop_groups: dict[tuple[str, str], list[str]] = defaultdict(list)
    for path in sorted(workspace_assets.rglob("*.png")):
        relative = path.relative_to(workspace_assets).as_posix()
        if relative == record.get("image", ""):
            continue
        if "/ui-evidence/" not in "/" + relative:
            continue
        match = re.search(r"crop-(\d+)-[0-9a-f]+-([A-Za-z_]+)\.png$", path.name)
        if match:
            crop_groups[(match.group(1), match.group(2))].append(relative)
        if relative not in referenced_crops:
            orphan_crops.append(relative)
    nondeterministic_crop_groups = [
        {"index": key[0], "purpose": key[1], "files": files}
        for key, files in sorted(crop_groups.items())
        if len(files) > 1
    ]

    hard_failures: list[dict[str, str]] = []
    if evidence.get("schema") != "ui_evidence.v1":
        hard_failures.append({"category": "schema_contract", "detail": f"schema={evidence.get('schema')!r}"})
    if evidence.get("coordinate_space") != "normalized_top_left":
        hard_failures.append({"category": "coordinate_space", "detail": f"coordinate_space={evidence.get('coordinate_space')!r}"})
    for element in elements:
        if not bbox_valid(element.get("bbox", {})):
            hard_failures.append({"category": "bbox_out_of_bounds", "detail": f"element={element.get('id')} bbox={element.get('bbox')}"})
    for group in group_predictions:
        if not bbox_valid(group.get("bbox", {})):
            hard_failures.append({"category": "bbox_out_of_bounds", "detail": f"group={group.get('id')} bbox={group.get('bbox')}"})
    for crop in evidence.get("crops", []):
        if not bbox_valid(crop.get("source_bbox", {})):
            hard_failures.append({"category": "bbox_out_of_bounds", "detail": f"crop={crop.get('asset_id')} bbox={crop.get('source_bbox')}"})

    source_check = record.get("source_check", {})
    if source_check.get("escaped_workspace"):
        hard_failures.append({"category": "crop_escape", "detail": "source path escaped workspace"})
    if not source_check.get("decodable"):
        hard_failures.append({"category": "source_decode", "detail": "source was not decodable"})
    if not source_check.get("sha256_matches"):
        hard_failures.append({"category": "source_hash", "detail": "source SHA-256 did not match the immutable manifest"})
    if not source_check.get("dimensions_match_evidence"):
        hard_failures.append({"category": "source_dimensions", "detail": "source pixels did not match evidence dimensions"})

    for check in crops:
        if check.get("escaped_workspace"):
            hard_failures.append({"category": "crop_escape", "detail": f"crop path escaped workspace: {check.get('workspace_path')}"})
        if not check.get("decodable") or not check.get("pil_decodable"):
            hard_failures.append({"category": "crop_decode", "detail": f"crop not decodable: {check.get('workspace_path')}"})
        if not check.get("relation_valid"):
            hard_failures.append({"category": "source_crop_relation", "detail": f"invalid relation for {check.get('asset_id')}"})
        if not check.get("dimensions_match_source_bbox"):
            hard_failures.append({"category": "source_crop_relation", "detail": f"pixel dimensions do not match source_bbox for {check.get('asset_id')}"})
        requested = check.get("requested_bbox", {})
        actual = check.get("source_bbox", {})
        if any(abs(float(requested.get(key, -1)) - float(actual.get(key, -2))) > EPSILON for key in ("x", "y", "width", "height")):
            hard_failures.append({"category": "source_crop_relation", "detail": f"source_bbox differs from request for {check.get('asset_id')}"})

    leaks = recommendation_leaks(evidence, record.get("tool_content", ""))
    for leak in leaks:
        hard_failures.append({"category": "recommendation_leak", "detail": leak})

    latencies = [float(value) for value in record.get("latencies_ms", [])]
    result = {
        "id": record["id"],
        "category": truth.get("category", ""),
        "tags": truth.get("tags", []),
        "image": manifest_image.get("image", record.get("image", "")),
        "mime_type": evidence.get("source", {}).get("mime_type", ""),
        "text_gt": len(truth["text"]),
        "text_pred": len(text_predictions),
        "text_tp": text_tp,
        "text_fp": text_fp,
        "text_fn": text_fn,
        "ocr_precision": round(ocr_precision, 6),
        "ocr_recall": round(ocr_recall, 6),
        "ocr_f1": round(ocr_f1, 6),
        "text_bbox_hits": bbox_hits,
        "text_bbox_iou50": round(text_bbox_rate, 6),
        "text_bbox_recall_at_iou50": round(text_bbox_recall, 6),
        "mean_matched_text_iou": round(mean_text_iou, 6),
        "containers_gt": len(truth["containers"]),
        "containers_pred": len(container_predictions),
        "containers_tp": container_tp,
        "containers_fp": container_fp,
        "containers_fn": container_fn,
        "container_precision": round(container_precision, 6),
        "container_recall": round(container_recall, 6),
        "container_f1": round(container_f1, 6),
        "groups_gt": len(group_truth),
        "groups_pred": len(group_predictions),
        "groups_tp": group_tp,
        "groups_fp": group_fp,
        "groups_fn": group_fn,
        "repeated_group_f1": round(group_f1, 6),
        "evidence_label_correct": label_correct,
        "evidence_label_total": label_total,
        "evidence_label_accuracy": round(safe_ratio(label_correct, label_total), 6),
        "crop_requests": crop_count,
        "crop_usable": crop_usable_count,
        "crop_usable_rate": round(crop_rate, 6),
        "orphan_crop_files": len(orphan_crops),
        "nondeterministic_crop_groups": len(nondeterministic_crop_groups),
        "latency_p50_ms": round(percentile(latencies, 0.50), 3),
        "latency_p95_ms": round(percentile(latencies, 0.95), 3),
        "hard_failure_count": len(hard_failures),
        "hard_failures": hard_failures,
        "soft_findings": [],
        "text_misses": [item.get("text", "") for item in text_unmatched[:20]],
        "text_false_positives": [item.get("text", "") for item in text_fp_items[:20]],
        "label_errors": label_errors[:20],
        "crops": crops,
        "orphan_crops": orphan_crops,
        "nondeterministic_crop_group_details": nondeterministic_crop_groups,
    }
    soft: list[dict[str, Any]] = []
    if text_fn:
        soft.append({"category": "ocr_miss", "count": text_fn, "examples": result["text_misses"]})
    if text_fp:
        soft.append({"category": "ocr_false_positive", "count": text_fp, "examples": result["text_false_positives"]})
    if text_tp and bbox_hits < text_tp:
        soft.append({"category": "text_bbox_iou50_miss", "count": text_tp - bbox_hits})
    if container_fn:
        soft.append({"category": "container_miss", "count": container_fn})
    if container_fp:
        soft.append({"category": "container_false_positive", "count": container_fp})
    if group_fn:
        soft.append({"category": "repeated_group_miss", "count": group_fn})
    if group_fp:
        soft.append({"category": "repeated_group_false_positive", "count": group_fp})
    if label_total and label_correct < label_total:
        soft.append({"category": "evidence_label_error", "count": label_total - label_correct, "examples": label_errors[:10]})
    if crop_rate < 1:
        soft.append({"category": "crop_unusable", "count": crop_count - crop_usable_count})
    if orphan_crops:
        soft.append({"category": "crop_output_nondeterminism", "count": len(orphan_crops)})
    result["soft_findings"] = soft
    return result


def aggregate_metrics(rows: list[dict[str, Any]], all_latencies: list[float], cold_start_ms: float) -> dict[str, Any]:
    sums = Counter()
    for row in rows:
        for key in (
            "text_gt", "text_pred", "text_tp", "text_fp", "text_fn", "text_bbox_hits",
            "containers_gt", "containers_pred", "containers_tp", "containers_fp", "containers_fn",
            "groups_gt", "groups_pred", "groups_tp", "groups_fp", "groups_fn",
            "evidence_label_correct", "evidence_label_total", "crop_requests", "crop_usable",
            "orphan_crop_files", "nondeterministic_crop_groups", "hard_failure_count",
        ):
            sums[key] += int(row[key])
    ocr_precision, ocr_recall, ocr_f1 = prf(sums["text_tp"], sums["text_fp"], sums["text_fn"])
    container_precision, container_recall, container_f1 = prf(
        sums["containers_tp"], sums["containers_fp"], sums["containers_fn"]
    )
    _, _, repeated_group_f1 = prf(sums["groups_tp"], sums["groups_fp"], sums["groups_fn"])
    return {
        "image_count": len(rows),
        "hard_failure_count": sums["hard_failure_count"],
        "hard_failed_images": sum(1 for row in rows if row["hard_failure_count"] > 0),
        "ocr_precision": round(ocr_precision, 6),
        "ocr_recall": round(ocr_recall, 6),
        "ocr_f1": round(ocr_f1, 6),
        "text_gt": sums["text_gt"],
        "text_pred": sums["text_pred"],
        "text_tp": sums["text_tp"],
        "text_fp": sums["text_fp"],
        "text_fn": sums["text_fn"],
        "text_bbox_iou50": round(safe_ratio(sums["text_bbox_hits"], sums["text_tp"]), 6),
        "text_bbox_recall_at_iou50": round(safe_ratio(sums["text_bbox_hits"], sums["text_gt"]), 6),
        "mean_matched_text_iou": round(statistics.fmean(row["mean_matched_text_iou"] for row in rows), 6) if rows else 0.0,
        "containers_gt": sums["containers_gt"],
        "containers_pred": sums["containers_pred"],
        "containers_tp": sums["containers_tp"],
        "containers_fp": sums["containers_fp"],
        "containers_fn": sums["containers_fn"],
        "container_precision": round(container_precision, 6),
        "container_recall": round(container_recall, 6),
        "container_f1": round(container_f1, 6),
        "groups_gt": sums["groups_gt"],
        "groups_pred": sums["groups_pred"],
        "groups_tp": sums["groups_tp"],
        "groups_fp": sums["groups_fp"],
        "groups_fn": sums["groups_fn"],
        "repeated_group_f1": round(repeated_group_f1, 6),
        "evidence_label_accuracy": round(safe_ratio(sums["evidence_label_correct"], sums["evidence_label_total"]), 6),
        "evidence_label_correct": sums["evidence_label_correct"],
        "evidence_label_total": sums["evidence_label_total"],
        "crop_requests": sums["crop_requests"],
        "crop_usable": sums["crop_usable"],
        "crop_usable_rate": round(safe_ratio(sums["crop_usable"], sums["crop_requests"]), 6),
        "orphan_crop_files": sums["orphan_crop_files"],
        "nondeterministic_crop_images": sum(1 for row in rows if row["orphan_crop_files"] > 0),
        "nondeterministic_crop_groups": sums["nondeterministic_crop_groups"],
        "latency_samples": len(all_latencies),
        "latency_p50_ms": round(percentile(all_latencies, 0.50), 3),
        "latency_p95_ms": round(percentile(all_latencies, 0.95), 3),
        "latency_mean_ms": round(statistics.fmean(all_latencies), 3) if all_latencies else 0.0,
        "cold_start_ms": round(cold_start_ms, 3),
    }


def write_metrics_csv(path: Path, rows: list[dict[str, Any]], aggregate: dict[str, Any]) -> None:
    fields = [
        "id", "category", "tags", "image", "mime_type",
        "text_gt", "text_pred", "text_tp", "text_fp", "text_fn",
        "ocr_precision", "ocr_recall", "ocr_f1", "text_bbox_hits",
        "text_bbox_iou50", "text_bbox_recall_at_iou50", "mean_matched_text_iou",
        "containers_gt", "containers_pred", "containers_tp", "containers_fp", "containers_fn",
        "container_precision", "container_recall", "container_f1",
        "groups_gt", "groups_pred", "groups_tp", "groups_fp", "groups_fn", "repeated_group_f1",
        "evidence_label_correct", "evidence_label_total", "evidence_label_accuracy",
        "crop_requests", "crop_usable", "crop_usable_rate",
        "orphan_crop_files", "nondeterministic_crop_groups", "latency_p50_ms", "latency_p95_ms", "hard_failure_count",
    ]
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            rendered = {field: row.get(field, "") for field in fields}
            rendered["tags"] = "|".join(row.get("tags", []))
            writer.writerow(rendered)
        rendered = {field: aggregate.get(field, "") for field in fields}
        rendered["id"] = "__aggregate__"
        rendered["tags"] = "all"
        writer.writerow(rendered)


def write_latency_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["id", "category", "latency_p50_ms", "latency_p95_ms"])
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row[key] for key in writer.fieldnames})


def write_failures(path: Path, rows: list[dict[str, Any]], aggregate: dict[str, Any]) -> None:
    lines = [
        "# Failure classification report",
        "",
        "This report is diagnostic only. No detector, OCR, crop, or schema behavior was changed after the run began.",
        "",
        f"- Images: {aggregate['image_count']}",
        f"- Hard-failed images: {aggregate['hard_failed_images']}",
        f"- Hard-failure events: {aggregate['hard_failure_count']}",
        f"- OCR misses: {aggregate['text_fn']}",
        f"- OCR false positives: {aggregate['text_fp']}",
        f"- Container misses: {aggregate['containers_fn']}",
        f"- Container false positives: {aggregate['containers_fp']}",
        f"- Repeated-group misses: {aggregate['groups_fn']}",
        f"- Repeated-group false positives: {aggregate['groups_fp']}",
        "",
        "## Classification",
        "",
        "| Image | Hard failures | Text FN | Text FP | Bbox@0.5 misses | Container FN | Group FN | Crop unusable | Crop extras |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        bbox_misses = row["text_tp"] - row["text_bbox_hits"]
        crop_unusable = row["crop_requests"] - row["crop_usable"]
        lines.append(
            f"| {row['id']} | {row['hard_failure_count']} | {row['text_fn']} | {row['text_fp']} | "
            f"{bbox_misses} | {row['containers_fn']} | {row['groups_fn']} | {crop_unusable} | {row['orphan_crop_files']} |"
        )
    hard_rows = [row for row in rows if row["hard_failures"]]
    lines.extend(["", "## Hard failures", ""])
    if not hard_rows:
        lines.append("No hard failures observed.")
    else:
        for row in hard_rows:
            lines.append(f"### {row['id']}")
            for failure in row["hard_failures"]:
                lines.append(f"- **{failure['category']}**: {failure['detail']}")
            lines.append("")
    lines.extend(["## Representative misses", ""])
    for row in rows:
        categories = []
        if row["text_misses"]:
            categories.append("OCR misses: " + "; ".join(repr(item) for item in row["text_misses"][:5]))
        if row["text_false_positives"]:
            categories.append("OCR FP: " + "; ".join(repr(item) for item in row["text_false_positives"][:5]))
        if row["label_errors"]:
            categories.append("Label errors: " + "; ".join(row["label_errors"][:3]))
        if row["orphan_crop_files"]:
            categories.append(f"Crop nondeterminism: {row['nondeterministic_crop_groups']} group(s), {row['orphan_crop_files']} stale file(s)")
        if categories:
            lines.append(f"- **{row['id']}**: " + " · ".join(categories))
    path.write_text("\n".join(lines) + "\n")


def write_summary(path: Path, rows: list[dict[str, Any]], aggregate: dict[str, Any], dataset_hash: str) -> None:
    categories = defaultdict(int)
    tags = Counter()
    for row in rows:
        categories[row["category"]] += 1
        tags.update(row["tags"])
    category_text = ", ".join(f"{name} ({count})" for name, count in sorted(categories.items()))
    tag_text = ", ".join(f"`{tag}` ({count})" for tag, count in sorted(tags.items()))
    status = "NO HARD FAILURES" if aggregate["hard_failure_count"] == 0 else "HARD FAILURES PRESENT"
    lines = [
        "# P1-C UI Evidence Quality Benchmark — immutable baseline",
        "",
        f"**Status:** baseline collected; {status}. **P1-C is not frozen by this report.**",
        "",
        "## Scope",
        "",
        f"- {aggregate['image_count']} curated, browser-rendered web UI screenshots.",
        f"- Ground truth: DOM-derived text boxes, explicit container boxes, and repeated-group boxes captured independently of `inspect_ui_image`.",
        f"- Dataset SHA-256: `{dataset_hash}`.",
        f"- Categories: {category_text}.",
        f"- Coverage tags: {tag_text}.",
        "- Production path: benchmark target links the exact repository copies of `InspectUIImageTool.swift`, `UIEvidence.swift`, `UIEvidenceVision.swift`, and `ToolWorkspace.swift`; no algorithm changes.",
        "",
        "## Headline metrics",
        "",
        "| Metric | Value |",
        "|---|---:|",
        f"| OCR precision | {aggregate['ocr_precision']:.2%} |",
        f"| OCR recall | {aggregate['ocr_recall']:.2%} |",
        f"| OCR F1 | {aggregate['ocr_f1']:.2%} |",
        f"| Text bbox IoU@0.5 (matched text) | {aggregate['text_bbox_iou50']:.2%} |",
        f"| Text bbox recall@0.5 (all GT text) | {aggregate['text_bbox_recall_at_iou50']:.2%} |",
        f"| Container precision | {aggregate['container_precision']:.2%} |",
        f"| Container recall | {aggregate['container_recall']:.2%} |",
        f"| Container F1 | {aggregate['container_f1']:.2%} |",
        f"| Repeated-group F1 | {aggregate['repeated_group_f1']:.2%} |",
        f"| Observed/inferred label accuracy | {aggregate['evidence_label_accuracy']:.2%} |",
        f"| Crop usable rate | {aggregate['crop_usable_rate']:.2%} |",
        f"| Hard failures | {aggregate['hard_failure_count']} |",
        "",
        "## Latency",
        "",
        f"- Samples: {aggregate['latency_samples']} calls (3 measured repetitions per image).",
        f"- p50: **{aggregate['latency_p50_ms']:.1f} ms**",
        f"- p95: **{aggregate['latency_p95_ms']:.1f} ms**",
        f"- Mean: {aggregate['latency_mean_ms']:.1f} ms",
        f"- First-call cold-start sample: {aggregate['cold_start_ms']:.1f} ms",
        "",
        "## Source / crop safety",
        "",
        f"- Source decodes and matches manifest dimensions/hash: {aggregate['image_count'] - aggregate['hard_failed_images']} / {aggregate['image_count']} images without hard failure (see report for exact categories).",
        f"- Crop requests: {aggregate['crop_requests']}; usable: {aggregate['crop_usable']} ({aggregate['crop_usable_rate']:.2%}).",
        f"- Repeated-call crop nondeterminism: {aggregate['orphan_crop_files']} unreferenced PNG artifacts across {aggregate['nondeterministic_crop_images']} images; use `failures.md` for classification.",
        "- Every crop was checked for workspace escape, PNG decode, expected source-derived pixel dimensions, source asset linkage, and nonblank pixels.",
        "",
        "## Interpretation",
        "",
        "- OCR precision/recall are exact normalized-text matches; punctuation and case are ignored.",
        "- Text bbox IoU@0.5 is computed on matched text pairs. Bbox recall@0.5 is additionally reported against all ground-truth text.",
        "- Container P/R/F1 uses one-to-one bbox matching at IoU 0.5 against explicit DOM containers.",
        "- Repeated-group F1 requires the same axis and bbox IoU 0.5.",
        "- Observed/inferred accuracy is evaluated only on matched text and container elements.",
        "- Hard-failure checks include schema/coordinate-space validity, all bbox bounds, source/crop decode and ancestry, crop pixel dimensions, and recommendation/layout leakage.",
        "",
        "## Known limitations",
        "",
        "- This baseline is curated web UI, not a census of native iOS/macOS applications.",
        "- DOM ground truth is exhaustive only for tagged/rendered text in the captured viewport; offscreen content is intentionally excluded.",
        "- Vision behavior can vary by macOS runtime/model version. Record the host/runtime with each future comparison.",
        "- Metrics are descriptive baseline evidence, not a freeze gate or release claim.",
        "",
        "## Artifacts",
        "",
        "- `metrics.csv` — per-image and aggregate metrics.",
        "- `ui_evidence/*.json` — exact `ui_evidence.v1` output per image.",
        "- `failures.md` — hard-failure and miss classification.",
        "- `asset_checks.json` — source/crop decode, ancestry, bounds, and usability checks.",
        "- `run_metadata.json` — tool outputs, assets, checks, and latency samples.",
        "- `environment.json` — OS/Swift/Python and exact source/evaluator hashes.",
        "",
    ]
    path.write_text("\n".join(lines))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--output", type=Path, default=DEFAULT_RUN)
    args = parser.parse_args()
    dataset = args.dataset.resolve()
    run_root = args.output.resolve()
    manifest = json.loads((dataset / "manifest.json").read_text())
    metadata = json.loads((run_root / "run_metadata.json").read_text())
    records = {record["id"]: record for record in metadata["records"]}
    rows: list[dict[str, Any]] = []
    all_latencies: list[float] = []
    for spec in manifest["images"]:
        truth_path = dataset / spec["ground_truth"]
        truth = json.loads(truth_path.read_text())
        record = records[spec["id"]]
        row = score_image(record, truth, spec, run_root)
        rows.append(row)
        all_latencies.extend(float(value) for value in record.get("latencies_ms", []))
    cold_start = float(metadata["records"][0]["latencies_ms"][0]) if metadata["records"] else 0.0
    aggregate = aggregate_metrics(rows, all_latencies, cold_start)

    run_root.mkdir(parents=True, exist_ok=True)
    write_metrics_csv(run_root / "metrics.csv", rows, aggregate)
    write_latency_csv(run_root / "latency.csv", rows)
    write_failures(run_root / "failures.md", rows, aggregate)
    write_summary(run_root / "summary.md", rows, aggregate, manifest["dataset_sha256"])

    asset_checks = {
        "schema": "ui_evidence_benchmark_asset_checks.v1",
        "dataset_sha256": manifest["dataset_sha256"],
        "images": [
            {
                "id": row["id"],
                "source_check": records[row["id"]]["source_check"],
                "crop_checks": row["crops"],
                "usable": row["crop_usable"],
                "requests": row["crop_requests"],
                "hard_failures": row["hard_failures"],
                "orphan_crops": row["orphan_crops"],
                "nondeterministic_crop_groups": row["nondeterministic_crop_group_details"],
            }
            for row in rows
        ],
    }
    (run_root / "asset_checks.json").write_text(json.dumps(asset_checks, indent=2) + "\n")
    evaluation = {
        "schema": "ui_evidence_benchmark_evaluation.v1",
        "dataset_sha256": manifest["dataset_sha256"],
        "run_dataset_sha256": metadata.get("dataset"),
        "aggregate": aggregate,
        "images": rows,
    }
    (run_root / "evaluation.json").write_text(json.dumps(evaluation, indent=2) + "\n")
    print(json.dumps(aggregate, indent=2))


if __name__ == "__main__":
    main()
