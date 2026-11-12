# P1-C benchmark audit and calibration — v1.1

This is an audit of measurement semantics over the immutable baseline evidence. The detector, AgentKit, Talkify, code-agent, and frozen contracts were not modified. IoU remains 0.5 in every geometry match; no threshold was relaxed.

## Executive conclusion

- The first-round number conflated several different things. v1.1 keeps strict DOM-leaf OCR metrics and adds separate line/block content, bbox geometry, vision-rectangle, semantic-container, repeated-group, and crop-integrity views.
- Occlusion was a real benchmark defect: dimmed/blurred underlay DOM text was counted as OCR obligations. dataset-v2 removes it using the active-overlay center-inside rule.
- Many leaf misses are not necessarily OCR omissions; they are representation mismatches where one Vision line/block covers multiple DOM leaves.
- Raw Vision rectangles and semantic DOM containers are not the same class. v1.1 reports them separately at IoU 0.5.
- Fixed blank crops are request-design observations, not crop-contract failures. Crop integrity and crop content utility are now separate.
- Repeated-group misses have both definition mismatch and genuine algorithm limitations. Equal-width is not an absolute requirement, but the code enforces a 1.8 width-ratio cap and a 0.02 lead-edge tolerance.

## Audit samples

| Image | Strict recall | Many-to-one recall | Bbox IoU@0.5 | Full-line coverage | Semantic F1 | Vision rect F1 | Group F1 |
|---|---:|---:|---:|---:|---:|---:|---:|
| sheet_delete_modal | 50.00% | 66.67% | 0.00% | 50.00% | 8.00% | 14.29% | 0.00% |
| sheet_filters_mobile | 100.00% | 100.00% | 15.79% | 100.00% | 0.00% | 21.28% | 0.00% |
| modal_payment_mobile | 100.00% | 100.00% | 77.78% | 100.00% | 25.00% | 32.00% | 0.00% |
| search_command_dark | 22.22% | 61.11% | 75.00% | 46.15% | 7.41% | 11.11% | 0.00% |
| feed_news_compact | 73.17% | 75.61% | 70.00% | 72.73% | 24.24% | 53.66% | 0.00% |
| small_text_legal | 72.22% | 75.00% | 30.77% | 67.86% | 7.69% | 16.67% | 0.00% |
| split_mail_desktop | 79.03% | 80.65% | 48.98% | 72.09% | 12.90% | 32.56% | 0.00% |
| settings_general_light | 86.96% | 93.48% | 52.50% | 90.00% | 5.13% | 13.95% | 0.00% |
| dashboard_analytics_light | 91.23% | 92.98% | 32.69% | 90.48% | 16.67% | 25.00% | 0.00% |
| list_orders_desktop | 94.83% | 98.28% | 47.27% | 97.14% | 4.65% | 19.05% | 0.00% |
| payment_confirm_mobile | 93.75% | 93.75% | 66.67% | 93.75% | 19.05% | 25.00% | 0.00% |
| landscape_table_finance | 91.55% | 97.18% | 23.08% | 95.35% | 8.16% | 21.82% | 0.00% |

## 1. Occluded / blurred DOM text

- Four overlay pages supplied 43 underlay DOM labels that were not valid OCR targets.
- 41 of those labels had no content-equal OCR prediction; they were counted as misses in v1 solely because they remained in GT.
- Strict content recall on the four overlay pages changes from 37.89% (v1 GT) to 67.31% (dataset-v2 GT).
- dataset-v2 policy: a text/container center must be inside the topmost active overlay (`modal`, `sheet`, or command palette). Excluded labels remain recorded in `excluded_text` for audit.

## 2. DOM-leaf versus line/block many-to-one

- Strict leaf exact-content recall (v2): 80.08%.
- Many-to-one leaf content recall, allowing one OCR block to cover multiple leaves: 86.85%.
- Block content precision (an OCR block must contain at least one leaf's ordered tokens and cover its center): 65.61%.
- Multi-leaf OCR blocks: 16; leaves covered by those blocks: 35.
- Visual lines fully covered by one or more OCR blocks: 719/864 (83.22%).
- Visual lines covered by one single OCR block: 47.57%.
- Strict leaf misses covered by a many-to-one block match: 84.
- Multi-leaf block bbox IoU@0.5: 62.50%.
- This separates representation from recognition: many-to-one coverage can improve content recall, while bbox geometry remains measured independently at IoU 0.5.

## 3. Vision rectangle versus semantic container

- v1 combined container view is retired in the v1.1 analysis.
- Raw container predictions: 911.
- Against vision-rectangle GT: precision 19.54%, recall 44.72%, F1 27.20%.
- Against semantic-container GT: precision 7.03%, recall 34.22%, F1 11.66%.
- Both use one-to-one IoU@0.5. The gap demonstrates a definition mismatch: a detected geometric rectangle is not automatically a semantic UI container, and vice versa.

## 4. Repeated-group width and definition

- GT groups: 18 across 18 rows; matched: 1; F1: 3.92%.
- Group definitions: visual-item union 11 (matched 0); text-geometry union 7 (matched 1).
- Width ratio exceeds detector cap 1.8: 2 groups (setting_rows, notification_rows).
- Lead-edge span exceeds 0.02: 1 groups.
- Width equality is not required by the detector; it allows a 1.8 ratio. Two GT groups exceed that cap, but most misses are not explained by width alone. The larger measurement issue is that some v1 groups were visual-item unions while the detector consumes text/container elements and their union geometry.

## 5. Fixed blank crops

- Crop integrity (exists, decodable, source-linked, dimensions correct, no escape): 90/90 (100.00%).
- Crop content utility (nonblank pixels): 88/90 (97.78%).
- Blank fixed requests: 2. These are classified as request-quality observations, not tool failures.

## Real algorithm issues retained

- Strict text bbox IoU@0.5 (v2): 43.40%; bbox recall against all GT leaves: 34.76%. Content and geometry remain separate concerns.
- Vision rectangle F1 remains 27.20% even under the independent geometric GT, so rectangle over/under-detection is not just a semantic-label artifact.
- Repeated-group F1 remains 3.92%; width is a partial contributor, not the sole explanation.
- The original repeat-run workspace issue remains: 7 unreferenced crop files were produced across 3 images. Referenced crop integrity is still 100%; this is a tool-runtime issue, not an OCR/rectangle detector result.

## Hard failures

No hard failures were found.

## Measurement limitations

- Visual-rectangle GT is a curated set of visible DOM boxes. It is independent of Vision but remains an axis-aligned proxy for borders, fills, shadows, and rounded geometry.
- Many-to-one content coverage uses ordered-token containment plus the leaf center falling inside the OCR block. It is a content/representation metric, not a substitute for bbox IoU.
- Full-line clustering is a deterministic spatial heuristic; it does not assign semantic reading order across distant columns.
- Repeated-group GT still includes both text-geometry unions and visual-item unions. The two are reported separately in `repeated_group_audit.csv`; one combined F1 should not be interpreted as a pure detector score.
- Overlay correction uses the center-inside-active-overlay policy. Excluded labels remain auditable in `dataset-v2/ground_truth/*.json`.
