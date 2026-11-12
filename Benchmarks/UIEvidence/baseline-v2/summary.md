# P1-C Evidence Detector v2 — baseline-v2

**Status:** checkpoint collected. P1-C is not frozen.

## Headline

| Metric | Before (audit-v1.1) | After (baseline-v2) |
|---|---:|---:|
| strict_dom_leaf_content_f1 | 0.8136009832036052 | 0.8136009832036052 |
| strict_text_bbox_iou50 | 0.4340382678751259 | 0.4340382678751259 |
| many_to_one_leaf_recall | 0.8685483870967742 | 0.8627394605980956 |
| visual_line_bbox_iou50 | n/a | 0.7610619469026548 |
| visual_line_bbox_recall_iou50 | n/a | 0.44559585492227977 |
| repeated_group_precision | 0.030303030303030304 | 0.8461538461538461 |
| repeated_group_recall | 0.05555555555555555 | 0.6111111111111112 |
| repeated_group_f1 | 0.0392156862745098 | 0.7096774193548387 |
| vision_rectangle_precision | 0.19538968166849616 | 0.19538968166849616 |
| vision_rectangle_recall | 0.4472361809045226 | 0.4472361809045226 |
| vision_rectangle_f1 | 0.2719633307868602 | 0.2719633307868602 |
| stale_crop_artifacts | 7 | 0 |
| crop_integrity_rate | 1.0 | 1.0 |
| hard_failures | 0 | 0 |

- Strict DOM-leaf content F1 is preserved and unchanged by structural changes.
- Visual-line bbox IoU@0.5 is reported on content-covered visual lines without splitting OCR blocks.
- Repeated groups are **ENABLED** by the precision/recall gate.
- Vision rectangles are weak geometry only (`role=vision_rectangle`) and never semantic containers.
- Crop integrity: 90/90 (100.00%); stale crop artifacts: 0.
- Hard failures: 0.
- Latency: p50 221.2 ms, p95 358.2 ms over 90 calls.

## Enablement gates

| Gate | Result |
|---|---|
| Hard failures = 0 | PASS |
| Crop integrity = 100% | PASS |
| Stale crops = 0 | PASS |
| Vision rectangle role enforced | PASS |
| Repeated-group precision ≥ 80% | PASS |
| Repeated-group recall ≥ 50% | PASS |

When a repeated-group candidate does not pass the per-image precision threshold, it is omitted rather than emitted as a speculative group. Repeated groups as a structural capability remain guarded when the aggregate gate does not pass.

## Outputs

- `metrics.csv` — per-image detector metrics.
- `groups.csv` — emitted repeated-group candidates.
- `before_after.csv` — direct comparison with audit-v1.1.
- `gate.json` — machine-readable enablement gate.
- `evaluation.json` — full evaluation and hard-failure audit.
- `environment.json` — host/runtime and source snapshot hashes.
- `checkpoint.json` — non-frozen detector-v2 enablement checkpoint.
