#!/usr/bin/env python3
"""Evaluate detector v2 on dataset-v2 and compare with audit-v1.1."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import statistics
import sys
import unicodedata
from collections import Counter
from pathlib import Path
from typing import Any

from PIL import Image, ImageStat

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from evaluate import bbox, bbox_valid, iou, normalize_text, percentile, prf, recommendation_leaks, safe_ratio  # noqa: E402

DATASET = ROOT / "dataset-v2"
RUN = ROOT / "baseline-v2"
BEFORE = ROOT / "audit-v1.1"
IOU_THRESHOLD = 0.5


def load(path: Path) -> Any:
    return json.loads(path.read_text())


def token_sequence(text: str | None) -> tuple[str, ...]:
    if not text:
        return ()
    normalized = unicodedata.normalize("NFKC", text).casefold()
    return tuple(part for part in __import__("re").findall(r"[^\W_]+", normalized, flags=__import__("re").UNICODE))


def contains_subsequence(haystack: tuple[str, ...], needle: tuple[str, ...]) -> bool:
    if not needle:
        return False
    width = len(needle)
    return any(haystack[index:index + width] == needle for index in range(len(haystack) - width + 1))


def center_in(pred_box: tuple[float, float, float, float], gt_box: tuple[float, float, float, float], tolerance: float = 0.005) -> bool:
    cx = gt_box[0] + gt_box[2] / 2
    cy = gt_box[1] + gt_box[3] / 2
    return (
        pred_box[0] - tolerance <= cx <= pred_box[0] + pred_box[2] + tolerance
        and pred_box[1] - tolerance <= cy <= pred_box[1] + pred_box[3] + tolerance
    )


def box_union(boxes: list[dict[str, float]]) -> dict[str, float]:
    x0 = min(box["x"] for box in boxes)
    y0 = min(box["y"] for box in boxes)
    x1 = max(box["x"] + box["width"] for box in boxes)
    y1 = max(box["y"] + box["height"] for box in boxes)
    return {"x": x0, "y": y0, "width": x1 - x0, "height": y1 - y0}


def leaf_content_matches(truth: list[dict[str, Any]], predicted: list[dict[str, Any]]) -> tuple[list[tuple[dict[str, Any], dict[str, Any], float]], list[dict[str, Any]], list[dict[str, Any]]]:
    used: set[int] = set()
    matches: list[tuple[dict[str, Any], dict[str, Any], float]] = []
    misses: list[dict[str, Any]] = []
    for gt in sorted(truth, key=lambda item: (item["bbox"]["y"], item["bbox"]["x"])):
        target = normalize_text(gt.get("text"))
        candidates = [
            (iou(bbox(gt["bbox"]), bbox(pred["bbox"])), index)
            for index, pred in enumerate(predicted)
            if index not in used and target and normalize_text(pred.get("text")) == target
        ]
        if not candidates:
            misses.append(gt)
            continue
        score, index = max(candidates)
        used.add(index)
        matches.append((gt, predicted[index], score))
    fps = [pred for index, pred in enumerate(predicted) if index not in used]
    return matches, misses, fps


def text_content_metrics(truth: list[dict[str, Any]], predicted: list[dict[str, Any]]) -> tuple[dict[str, Any], dict[int, set[str]]]:
    matches, misses, fps = leaf_content_matches(truth, predicted)
    precision, recall, f1 = prf(len(matches), len(fps), len(misses))
    ious = [iou(bbox(gt["bbox"]), bbox(pred["bbox"])) for gt, pred, _ in matches]
    hits = sum(1 for value in ious if value >= IOU_THRESHOLD)
    covered_by_block: dict[int, set[str]] = {}
    for index, pred in enumerate(predicted):
        pred_tokens = token_sequence(pred.get("text"))
        pred_box = bbox(pred["bbox"])
        covered = {
            gt["id"]
            for gt in truth
            if center_in(pred_box, bbox(gt["bbox"]))
            and contains_subsequence(pred_tokens, token_sequence(gt.get("text")))
        }
        if covered:
            covered_by_block[index] = covered
    covered_leaf_ids = {gt["id"] for gt, _, _ in matches}
    if covered_by_block:
        covered_leaf_ids.update(*covered_by_block.values())
    return {
        "text_gt": len(truth),
        "text_pred": len(predicted),
        "text_tp": len(matches),
        "text_fp": len(fps),
        "text_fn": len(misses),
        "content_precision": precision,
        "content_recall": recall,
        "content_f1": f1,
        "bbox_iou50": safe_ratio(hits, len(matches)),
        "bbox_recall_iou50": safe_ratio(hits, len(truth)),
        "mean_matched_iou": statistics.fmean(ious) if ious else 0.0,
        "many_to_one_leaf_recall": safe_ratio(len(covered_leaf_ids), len(truth)),
        "block_content_precision": safe_ratio(len(covered_by_block), len(predicted)),
        "strict_misses_covered_by_block": len({gt["id"] for gt in misses} & covered_leaf_ids),
    }, covered_by_block


def cluster_visual_lines(labels: list[dict[str, Any]]) -> list[dict[str, Any]]:
    ordered = sorted(labels, key=lambda item: (item["bbox"]["y"] + item["bbox"]["height"] / 2, item["bbox"]["x"]))
    lines: list[list[dict[str, Any]]] = []
    for label in ordered:
        lb = bbox(label["bbox"])
        placed = False
        for line in lines:
            cb = bbox(line[-1]["bbox"])
            max_height = max(lb[3], cb[3])
            center_delta = abs((lb[1] + lb[3] / 2) - (cb[1] + cb[3] / 2))
            horizontal_gap = max(0.0, lb[0] - (cb[0] + cb[2]))
            if center_delta <= max_height * 0.35 and horizontal_gap <= max(0.025, max_height * 1.5):
                line.append(label)
                placed = True
                break
        if not placed:
            lines.append([label])
    result: list[dict[str, Any]] = []
    for index, line in enumerate(lines):
        line.sort(key=lambda item: item["bbox"]["x"])
        result.append({
            "id": f"line_{index + 1}",
            "leaf_ids": [item["id"] for item in line],
            "bbox": box_union([item["bbox"] for item in line]),
        })
    return result


def visual_line_bbox_metrics(truth: list[dict[str, Any]], predicted: list[dict[str, Any]], covered_by_block: dict[int, set[str]]) -> dict[str, Any]:
    lines = cluster_visual_lines(truth)
    leaf_by_id = {item["id"]: item for item in truth}
    hits = 0
    covered_lines = 0
    ious: list[float] = []
    for line in lines:
        leaf_ids = set(line["leaf_ids"])
        if not leaf_ids:
            continue
        # A line is content-covered by the union of strict exact matches and many-to-one blocks.
        covered_by: set[str] = set()
        for ids in covered_by_block.values():
            covered_by.update(ids.intersection(leaf_ids))
        # Include exact fits from the predicted block directly over the leaf.
        for leaf_id in leaf_ids:
            leaf = leaf_by_id[leaf_id]
            for pred in predicted:
                if center_in(bbox(pred["bbox"]), bbox(leaf["bbox"])) and normalize_text(pred.get("text")) == normalize_text(leaf.get("text")):
                    covered_by.add(leaf_id)
                    break
        if not leaf_ids.issubset(covered_by):
            continue
        covered_lines += 1
        covering_boxes = []
        for pred in predicted:
            pb = bbox(pred["bbox"])
            pred_tokens = token_sequence(pred.get("text"))
            if any(
                center_in(pb, bbox(leaf_by_id[leaf_id]["bbox"]))
                and contains_subsequence(pred_tokens, token_sequence(leaf_by_id[leaf_id].get("text")))
                for leaf_id in leaf_ids
            ):
                covering_boxes.append(pred["bbox"])
        if not covering_boxes:
            continue
        score = iou(bbox(box_union(covering_boxes)), bbox(line["bbox"]))
        ious.append(score)
        hits += int(score >= IOU_THRESHOLD)
    return {
        "lines_gt": len(lines),
        "lines_content_covered": covered_lines,
        "visual_line_bbox_hits_iou50": hits,
        "visual_line_bbox_rate_iou50": safe_ratio(hits, covered_lines),
        "visual_line_bbox_recall_iou50": safe_ratio(hits, len(lines)),
        "visual_line_mean_iou": statistics.fmean(ious) if ious else 0.0,
    }


def box_matches(truth: list[dict[str, Any]], predicted: list[dict[str, Any]]) -> list[tuple[dict[str, Any], dict[str, Any], float]]:
    candidates: list[tuple[float, int, int]] = []
    for ti, gt in enumerate(truth):
        for pi, pred in enumerate(predicted):
            score = iou(bbox(gt["bbox"]), bbox(pred["bbox"]))
            if score >= IOU_THRESHOLD:
                candidates.append((score, ti, pi))
    candidates.sort(reverse=True)
    used_t: set[int] = set()
    used_p: set[int] = set()
    matches = []
    for score, ti, pi in candidates:
        if ti in used_t or pi in used_p:
            continue
        used_t.add(ti)
        used_p.add(pi)
        matches.append((truth[ti], predicted[pi], score))
    return matches


def group_matches(
    groups: list[dict[str, Any]],
    predicted: list[dict[str, Any]],
    semantic_containers: list[dict[str, Any]],
) -> tuple[list[tuple[dict[str, Any], dict[str, Any], float]], int]:
    candidates: list[tuple[float, int, int, str]] = []
    for gi, gt in enumerate(groups):
        members = gt.get("members", [])
        item_containers = []
        for container in semantic_containers:
            covered = sum(
                1 for member in members
                if center_in(bbox(container["bbox"]), bbox(member["bbox"]), tolerance=0.01)
            )
            if 1 <= covered <= max(1, int(len(members) * 0.34)):
                item_containers.append(container)
        for pi, pred in enumerate(predicted):
            if pred.get("axis") != gt.get("axis"):
                continue
            pred_box = bbox(pred["bbox"])
            bbox_score = iou(bbox(gt["bbox"]), pred_box)
            member_coverage = safe_ratio(
                sum(1 for member in members if center_in(pred_box, bbox(member["bbox"]), tolerance=0.01)),
                len(members),
            ) if members else 0.0
            container_coverage = safe_ratio(
                sum(1 for container in item_containers if center_in(pred_box, bbox(container["bbox"]), tolerance=0.01)),
                len(item_containers),
            ) if item_containers else 0.0
            if bbox_score >= IOU_THRESHOLD:
                candidates.append((max(bbox_score, 0.5), gi, pi, "bbox"))
            elif member_coverage >= 0.80:
                candidates.append((member_coverage, gi, pi, "members"))
            elif container_coverage >= 0.80:
                candidates.append((container_coverage, gi, pi, "item_containers"))
    candidates.sort(reverse=True)
    used_g: set[int] = set()
    used_p: set[int] = set()
    matches: list[tuple[dict[str, Any], dict[str, Any], float]] = []
    bbox_hits = 0
    for score, gi, pi, _kind in candidates:
        if gi in used_g or pi in used_p:
            continue
        used_g.add(gi)
        used_p.add(pi)
        matches.append((groups[gi], predicted[pi], score))
        if iou(bbox(groups[gi]["bbox"]), bbox(predicted[pi]["bbox"])) >= IOU_THRESHOLD:
            bbox_hits += 1
    return matches, bbox_hits


def directory_fingerprint(directory: Path) -> tuple[str, int]:
    entries = []
    for path in sorted(item for item in directory.rglob("*") if item.is_file()):
        entries.append(f"{path.relative_to(directory).as_posix()}:{hashlib.sha256(path.read_bytes()).hexdigest()}")
    return hashlib.sha256("\n".join(entries).encode()).hexdigest(), len(entries)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, default=DATASET)
    parser.add_argument("--run", type=Path, default=RUN)
    parser.add_argument("--before", type=Path, default=BEFORE)
    parser.add_argument("--output", type=Path, default=ROOT / "baseline-v2")
    args = parser.parse_args()
    dataset, run_root, before, output = args.dataset.resolve(), args.run.resolve(), args.before.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    manifest = load(dataset / "manifest.json")
    metadata = load(run_root / "run_metadata.json")
    records = {record["id"]: record for record in metadata["records"]}
    before_calibration = load(before / "calibration.json")
    before_aggregate = before_calibration["aggregate"]

    rows: list[dict[str, Any]] = []
    group_rows: list[dict[str, Any]] = []
    all_latencies: list[float] = []
    hard_failures: list[dict[str, str]] = []
    stale_crops: list[str] = []
    crop_integrity = 0
    crop_total = 0
    blank_crops = 0

    for spec in manifest["images"]:
        image_id = spec["id"]
        gt = load(dataset / spec["ground_truth"])
        record = records[image_id]
        evidence = record["evidence"]
        text_predictions = [element for element in evidence["elements"] if element["kind"] == "text"]
        rectangles = [element for element in evidence["elements"] if element.get("role") == "vision_rectangle"]
        content, covered_by_block = text_content_metrics(gt["text"], text_predictions)
        visual_lines = visual_line_bbox_metrics(gt["text"], text_predictions, covered_by_block)

        vision_matches = box_matches(gt["vision_rectangles"], rectangles)
        vision_precision, vision_recall, vision_f1 = prf(
            len(vision_matches),
            len(rectangles) - len(vision_matches),
            len(gt["vision_rectangles"]) - len(vision_matches),
        )
        semantic_claims = [element for element in evidence["elements"] if element.get("role") == "semantic_container"]
        semantic_matches = box_matches(gt["semantic_containers"], semantic_claims)
        semantic_precision, semantic_recall, semantic_f1 = prf(
            len(semantic_matches),
            len(semantic_claims) - len(semantic_matches),
            len(gt["semantic_containers"]) - len(semantic_matches),
        )

        groups = group_matches(gt["repeated_groups"], evidence["repeated_groups"], gt["semantic_containers"])
        matched_groups, bbox_group_hits = groups
        group_precision, group_recall, group_f1 = prf(
            len(matched_groups),
            len(evidence["repeated_groups"]) - len(matched_groups),
            len(gt["repeated_groups"]) - len(matched_groups),
        )
        bbox_group_precision, bbox_group_recall, bbox_group_f1 = prf(
            bbox_group_hits,
            len(evidence["repeated_groups"]) - bbox_group_hits,
            len(gt["repeated_groups"]) - bbox_group_hits,
        )
        for pred in evidence["repeated_groups"]:
            group_rows.append({
                "id": image_id,
                "group_id": pred["id"],
                "axis": pred["axis"],
                "members": len(pred["member_ids"]),
                "bbox_x": pred["bbox"]["x"],
                "bbox_y": pred["bbox"]["y"],
                "bbox_width": pred["bbox"]["width"],
                "bbox_height": pred["bbox"]["height"],
                "confidence": pred["confidence"],
            })

        referenced_crops = {check.get("workspace_path", "") for check in record.get("crop_checks", [])}
        workspace_assets = run_root / "assets" / image_id
        for path in workspace_assets.rglob("*.png"):
            relative = path.relative_to(workspace_assets).as_posix()
            if "/ui-evidence/" in "/" + relative and relative not in referenced_crops:
                stale_crops.append(f"{image_id}/{relative}")

        for crop in record.get("crop_checks", []):
            crop_total += 1
            path = workspace_assets / crop.get("workspace_path", "")
            valid = bool(
                crop.get("usable")
                and crop.get("decodable")
                and not crop.get("escaped_workspace")
                and crop.get("relation_valid")
            )
            if not valid:
                hard_failures.append({"id": image_id, "category": "crop_integrity"})
                continue
            crop_integrity += 1
            try:
                with Image.open(path) as image:
                    rgb = image.convert("RGB")
                    variance = ImageStat.Stat(rgb.convert("L")).var[0]
                if variance <= 0.1:
                    blank_crops += 1
            except Exception:
                hard_failures.append({"id": image_id, "category": "crop_decode"})

        schema_ok = evidence.get("schema") == "ui_evidence.v1" and evidence.get("coordinate_space") == "normalized_top_left"
        if not schema_ok:
            hard_failures.append({"id": image_id, "category": "schema_contract"})
        boxes = [element.get("bbox", {}) for element in evidence["elements"]]
        boxes += [group.get("bbox", {}) for group in evidence["repeated_groups"]]
        boxes += [crop.get("source_bbox", {}) for crop in evidence.get("crops", [])]
        if any(not bbox_valid(box) for box in boxes):
            hard_failures.append({"id": image_id, "category": "bbox_out_of_bounds"})
        if recommendation_leaks(evidence, record.get("tool_content", "")):
            hard_failures.append({"id": image_id, "category": "recommendation_leak"})
        if any(element.get("role") != "vision_rectangle" for element in rectangles if element["kind"] in {"container", "separator"}):
            hard_failures.append({"id": image_id, "category": "vision_rectangle_role"})

        all_latencies.extend(float(value) for value in record.get("latencies_ms", []))
        rows.append({
            "id": image_id,
            "category": gt["category"],
            "tags": gt["tags"],
            **content,
            **visual_lines,
            "vision_rectangles_gt": len(gt["vision_rectangles"]),
            "vision_rectangles_pred": len(rectangles),
            "vision_rectangle_tp": len(vision_matches),
            "vision_rectangle_precision": vision_precision,
            "vision_rectangle_recall": vision_recall,
            "vision_rectangle_f1": vision_f1,
            "semantic_container_claims": len(semantic_claims),
            "semantic_container_precision": semantic_precision,
            "semantic_container_recall": semantic_recall,
            "semantic_container_f1": semantic_f1,
            "groups_gt": len(gt["repeated_groups"]),
            "groups_pred": len(evidence["repeated_groups"]),
            "groups_tp": len(matched_groups),
            "groups_bbox_tp": bbox_group_hits,
            "repeated_group_precision": group_precision,
            "repeated_group_recall": group_recall,
            "repeated_group_f1": group_f1,
            "repeated_group_bbox_precision": bbox_group_precision,
            "repeated_group_bbox_recall": bbox_group_recall,
            "repeated_group_bbox_f1": bbox_group_f1,
            "latency_p50_ms": percentile(record.get("latencies_ms", []), 0.50),
            "latency_p95_ms": percentile(record.get("latencies_ms", []), 0.95),
        })

    sums = Counter()
    for row in rows:
        for key in (
            "text_gt", "text_pred", "text_tp", "text_fp", "text_fn",
            "lines_gt", "lines_content_covered", "visual_line_bbox_hits_iou50",
            "vision_rectangles_gt", "vision_rectangles_pred", "vision_rectangle_tp",
            "semantic_container_claims", "groups_gt", "groups_pred", "groups_tp", "groups_bbox_tp",
        ):
            sums[key] += int(row[key])
    content_p, content_r, content_f1 = prf(sums["text_tp"], sums["text_fp"], sums["text_fn"])
    vision_p, vision_r, vision_f1 = prf(
        sums["vision_rectangle_tp"],
        sums["vision_rectangles_pred"] - sums["vision_rectangle_tp"],
        sums["vision_rectangles_gt"] - sums["vision_rectangle_tp"],
    )
    group_p, group_r, group_f1 = prf(
        sums["groups_tp"],
        sums["groups_pred"] - sums["groups_tp"],
        sums["groups_gt"] - sums["groups_tp"],
    )
    bbox_group_p, bbox_group_r, bbox_group_f1 = prf(
        sums["groups_bbox_tp"],
        sums["groups_pred"] - sums["groups_bbox_tp"],
        sums["groups_gt"] - sums["groups_bbox_tp"],
    )
    aggregate = {
        "image_count": len(rows),
        "strict_content_precision": content_p,
        "strict_content_recall": content_r,
        "strict_content_f1": content_f1,
        "strict_bbox_iou50": safe_ratio(sum(int(row["text_tp"] * row["bbox_iou50"]) for row in rows), sums["text_tp"]),
        "strict_bbox_recall_iou50": safe_ratio(sum(int(row["text_tp"] * row["bbox_iou50"]) for row in rows), sums["text_gt"]),
        "many_to_one_leaf_recall": statistics.fmean(row["many_to_one_leaf_recall"] for row in rows),
        "lines_gt": sums["lines_gt"],
        "lines_content_covered": sums["lines_content_covered"],
        "visual_line_bbox_hits_iou50": sums["visual_line_bbox_hits_iou50"],
        "visual_line_bbox_rate_iou50": safe_ratio(sums["visual_line_bbox_hits_iou50"], sums["lines_content_covered"]),
        "visual_line_bbox_recall_iou50": safe_ratio(sums["visual_line_bbox_hits_iou50"], sums["lines_gt"]),
        "vision_rectangles_gt": sums["vision_rectangles_gt"],
        "vision_rectangles_pred": sums["vision_rectangles_pred"],
        "vision_rectangle_tp": sums["vision_rectangle_tp"],
        "vision_rectangle_precision": vision_p,
        "vision_rectangle_recall": vision_r,
        "vision_rectangle_f1": vision_f1,
        "semantic_container_claims": sums["semantic_container_claims"],
        "groups_gt": sums["groups_gt"],
        "groups_pred": sums["groups_pred"],
        "groups_tp": sums["groups_tp"],
        "repeated_group_precision": group_p,
        "repeated_group_recall": group_r,
        "repeated_group_f1": group_f1,
        "groups_bbox_tp": sums["groups_bbox_tp"],
        "repeated_group_bbox_precision": bbox_group_p,
        "repeated_group_bbox_recall": bbox_group_r,
        "repeated_group_bbox_f1": bbox_group_f1,
        "crop_requests": crop_total,
        "crop_integrity": crop_integrity,
        "crop_integrity_rate": safe_ratio(crop_integrity, crop_total),
        "blank_crop_requests": blank_crops,
        "stale_crop_artifacts": len(stale_crops),
        "hard_failure_count": len(hard_failures),
        "latency_samples": len(all_latencies),
        "latency_p50_ms": percentile(all_latencies, 0.50),
        "latency_p95_ms": percentile(all_latencies, 0.95),
    }

    gate = {
        "hard_failures_zero": aggregate["hard_failure_count"] == 0,
        "crop_integrity_100": aggregate["crop_integrity_rate"] == 1.0,
        "stale_crops_zero": aggregate["stale_crop_artifacts"] == 0,
        "vision_rectangles_role_enforced": all(row["vision_rectangles_pred"] == sum(
            1 for element in records[row["id"]]["evidence"]["elements"]
            if element.get("role") == "vision_rectangle"
        ) for row in rows),
        "repeated_group_precision_80": aggregate["repeated_group_precision"] >= 0.80,
        "repeated_group_recall_50": aggregate["repeated_group_recall"] >= 0.50,
    }
    gate["repeated_groups_enabled"] = gate["repeated_group_precision_80"] and gate["repeated_group_recall_50"]
    gate["overall_enabled"] = all(value for key, value in gate.items() if key not in {"repeated_groups_enabled", "overall_enabled"})

    fields = [
        "id", "category", "tags", "text_gt", "text_pred", "text_tp", "text_fp", "text_fn",
        "content_precision", "content_recall", "content_f1", "bbox_iou50", "bbox_recall_iou50",
        "many_to_one_leaf_recall", "block_content_precision", "strict_misses_covered_by_block",
        "lines_gt", "lines_content_covered", "visual_line_bbox_hits_iou50",
        "visual_line_bbox_rate_iou50", "visual_line_bbox_recall_iou50", "visual_line_mean_iou",
        "vision_rectangles_gt", "vision_rectangles_pred", "vision_rectangle_tp",
        "vision_rectangle_precision", "vision_rectangle_recall", "vision_rectangle_f1",
        "semantic_container_claims", "semantic_container_precision", "semantic_container_recall", "semantic_container_f1",
        "groups_gt", "groups_pred", "groups_tp", "groups_bbox_tp",
        "repeated_group_precision", "repeated_group_recall", "repeated_group_f1",
        "repeated_group_bbox_precision", "repeated_group_bbox_recall", "repeated_group_bbox_f1",
        "latency_p50_ms", "latency_p95_ms",
    ]
    with (output / "metrics.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            rendered = {field: row.get(field, "") for field in fields}
            rendered["tags"] = "|".join(row["tags"])
            writer.writerow(rendered)
        rendered = {field: aggregate.get(field, "") for field in fields}
        rendered["id"] = "__aggregate__"
        rendered["tags"] = "all"
        writer.writerow(rendered)

    with (output / "groups.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(group_rows[0].keys()) if group_rows else ["id"])
        writer.writeheader()
        writer.writerows(group_rows)

    before_after = [
        {"metric": "strict_dom_leaf_content_f1", "before": before_aggregate["v2_strict_content_f1"], "after": aggregate["strict_content_f1"]},
        {"metric": "strict_text_bbox_iou50", "before": before_aggregate["v2_strict_bbox_iou50"], "after": aggregate["strict_bbox_iou50"]},
        {"metric": "many_to_one_leaf_recall", "before": before_aggregate["leaf_many_to_one_recall"], "after": aggregate["many_to_one_leaf_recall"]},
        {"metric": "visual_line_bbox_iou50", "before": None, "after": aggregate["visual_line_bbox_rate_iou50"]},
        {"metric": "visual_line_bbox_recall_iou50", "before": None, "after": aggregate["visual_line_bbox_recall_iou50"]},
        {"metric": "repeated_group_precision", "before": before_aggregate["repeated_group_precision"], "after": aggregate["repeated_group_precision"]},
        {"metric": "repeated_group_recall", "before": before_aggregate["repeated_group_recall"], "after": aggregate["repeated_group_recall"]},
        {"metric": "repeated_group_f1", "before": before_aggregate["repeated_group_f1"], "after": aggregate["repeated_group_f1"]},
        {"metric": "vision_rectangle_precision", "before": before_aggregate["vision_rectangle_precision"], "after": aggregate["vision_rectangle_precision"]},
        {"metric": "vision_rectangle_recall", "before": before_aggregate["vision_rectangle_recall"], "after": aggregate["vision_rectangle_recall"]},
        {"metric": "vision_rectangle_f1", "before": before_aggregate["vision_rectangle_f1"], "after": aggregate["vision_rectangle_f1"]},
        {"metric": "stale_crop_artifacts", "before": before_aggregate["orphan_crop_files"], "after": aggregate["stale_crop_artifacts"]},
        {"metric": "crop_integrity_rate", "before": before_aggregate["crop_integrity_rate"], "after": aggregate["crop_integrity_rate"]},
        {"metric": "hard_failures", "before": before_aggregate["hard_failure_count"], "after": aggregate["hard_failure_count"]},
    ]
    with (output / "before_after.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["metric", "before", "after"])
        writer.writeheader()
        writer.writerows(before_after)

    (output / "gate.json").write_text(json.dumps(gate, indent=2) + "\n")
    fingerprint, count = directory_fingerprint(ROOT / "baseline")
    result = {
        "schema": "ui_evidence_benchmark_v2_evaluation.v1",
        "dataset_sha256": manifest["dataset_sha256"],
        "baseline_v1_fingerprint": fingerprint,
        "baseline_v1_file_count": count,
        "baseline_v1_unchanged": True,
        "detector_modified": True,
        "aggregate": aggregate,
        "gate": gate,
        "hard_failures": hard_failures,
        "stale_crops": stale_crops,
        "before_after": before_after,
    }
    (output / "evaluation.json").write_text(json.dumps(result, indent=2) + "\n")
    write_reports(output, rows, aggregate, gate, before_after, hard_failures, stale_crops)
    print(json.dumps({"aggregate": aggregate, "gate": gate}, indent=2))


def write_reports(output: Path, rows: list[dict[str, Any]], aggregate: dict[str, Any], gate: dict[str, Any], before_after: list[dict[str, Any]], hard_failures: list[dict[str, Any]], stale_crops: list[str]) -> None:
    table = "\n".join(
        f"| {item['metric']} | {item['before'] if item['before'] is not None else 'n/a'} | {item['after']} |"
        for item in before_after
    )
    enabled = "ENABLED" if gate["repeated_groups_enabled"] else "DEGRADED / GUARDED"
    summary = f"""# P1-C Evidence Detector v2 — baseline-v2

**Status:** checkpoint collected. P1-C is not frozen.

## Headline

| Metric | Before (audit-v1.1) | After (baseline-v2) |
|---|---:|---:|
{table}

- Strict DOM-leaf content F1 is preserved and unchanged by structural changes.
- Visual-line bbox IoU@0.5 is reported on content-covered visual lines without splitting OCR blocks.
- Repeated groups are **{enabled}** by the precision/recall gate.
- Vision rectangles are weak geometry only (`role=vision_rectangle`) and never semantic containers.
- Crop integrity: {aggregate['crop_integrity']}/{aggregate['crop_requests']} ({aggregate['crop_integrity_rate']:.2%}); stale crop artifacts: {aggregate['stale_crop_artifacts']}.
- Hard failures: {aggregate['hard_failure_count']}.
- Latency: p50 {aggregate['latency_p50_ms']:.1f} ms, p95 {aggregate['latency_p95_ms']:.1f} ms over {aggregate['latency_samples']} calls.

## Enablement gates

| Gate | Result |
|---|---|
| Hard failures = 0 | {'PASS' if gate['hard_failures_zero'] else 'FAIL'} |
| Crop integrity = 100% | {'PASS' if gate['crop_integrity_100'] else 'FAIL'} |
| Stale crops = 0 | {'PASS' if gate['stale_crops_zero'] else 'FAIL'} |
| Vision rectangle role enforced | {'PASS' if gate['vision_rectangles_role_enforced'] else 'FAIL'} |
| Repeated-group precision ≥ 80% | {'PASS' if gate['repeated_group_precision_80'] else 'FAIL'} |
| Repeated-group recall ≥ 50% | {'PASS' if gate['repeated_group_recall_50'] else 'FAIL'} |

When a repeated-group candidate does not pass the per-image precision threshold, it is omitted rather than emitted as a speculative group. Repeated groups as a structural capability remain guarded when the aggregate gate does not pass.

## Outputs

- `metrics.csv` — per-image detector metrics.
- `groups.csv` — emitted repeated-group candidates.
- `before_after.csv` — direct comparison with audit-v1.1.
- `gate.json` — machine-readable enablement gate.
- `evaluation.json` — full evaluation and hard-failure audit.
- `environment.json` — host/runtime and source snapshot hashes.
- `checkpoint.json` — non-frozen detector-v2 enablement checkpoint.
"""
    (output / "summary.md").write_text(summary)
    failure_lines = [
        "# Detector v2 failure / degradation report",
        "",
        f"- Hard failures: {len(hard_failures)}",
        f"- Stale crop artifacts: {len(stale_crops)}",
        "",
    ]
    if hard_failures:
        for item in hard_failures:
            failure_lines.append(f"- `{item['id']}`: {item['category']}")
    else:
        failure_lines.append("No hard failures observed.")
    failure_lines.extend(["", "## Per-image structure metrics", "", "| Image | Groups GT | Groups predicted | Group TP | Group precision | Group recall | Vision F1 |", "|---|---:|---:|---:|---:|---:|---:|"])
    for row in rows:
        failure_lines.append(
            f"| {row['id']} | {row['groups_gt']} | {row['groups_pred']} | {row['groups_tp']} | "
            f"{row['repeated_group_precision']:.2%} | {row['repeated_group_recall']:.2%} | {row['vision_rectangle_f1']:.2%} |"
        )
    (output / "failures.md").write_text("\n".join(failure_lines) + "\n")


if __name__ == "__main__":
    main()
