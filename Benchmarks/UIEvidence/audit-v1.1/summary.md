# P1-C Benchmark v1.1 — Audit Summary

**Scope:** measurement calibration over the immutable `baseline/`. Detector unchanged. P1-C is not frozen.

## Calibrated metrics

| Metric | Value |
|---|---:|
| Strict DOM-leaf content F1 (v1 GT, preserved) | 80.03% |
| Strict DOM-leaf content precision (v2 GT) | 82.68% |
| Strict DOM-leaf content recall (v2 GT) | 80.08% |
| Strict DOM-leaf content F1 (v2 GT) | 81.36% |
| Strict text bbox IoU@0.5 (v1 GT) | 43.36% |
| Strict text bbox IoU@0.5 (v2 GT) | 43.40% |
| Strict text bbox recall@0.5 (v2 GT) | 34.76% |
| Many-to-one leaf content recall | 86.85% |
| Block content precision | 65.61% |
| Full-line coverage recall | 83.22% |
| Single-block full-line recall | 47.57% |
| Multi-leaf block bbox IoU@0.5 | 62.50% |
| Semantic-container F1 | 11.66% |
| Vision-rectangle F1 | 27.20% |
| Repeated-group F1 | 3.92% |
| Crop integrity | 100.00% |
| Crop content utility | 97.78% |

## Calibration highlights

- dataset-v2 applies 43 overlay-occlusion text corrections and leaves v1 untouched.
- `['sheet_delete_modal', 'sheet_filters_mobile', 'modal_payment_mobile', 'search_command_dark']` are the audited overlay pages.
- 84 strict leaf misses are covered by a many-to-one OCR block.
- 11 repeated-group GT rows are visual-item unions; 0 matched. 7 are text-geometry unions; 1 matched.
- 2 groups exceed the detector's 1.8 width-ratio cap; this does not explain most group misses.
- 2 fixed crop requests target blank regions. Crop integrity is 100%; blank content is a request-quality observation, not a tool failure.
- Hard failures: 0.

## Artifacts

- `metrics.csv` — strict v1/v2, line/block, geometry, container, and group metrics per image.
- `container_metrics.csv` — separate vision-rectangle and semantic-container metrics.
- `repeated_group_audit.csv` — width/lead-edge/definition diagnostics for every GT group.
- `findings.md` — audit conclusions and measurement-versus-algorithm classification.
- `failures.md` — hard failures and per-image residual misses.
- `overlays/` — 12 annotated GT/prediction audits.
- `calibration.json` — machine-readable calibration record.
