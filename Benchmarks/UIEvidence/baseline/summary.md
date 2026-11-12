# P1-C UI Evidence Quality Benchmark — immutable baseline

**Status:** baseline collected; NO HARD FAILURES. **P1-C is not frozen by this report.**

## Scope

- 30 curated, browser-rendered web UI screenshots.
- Ground truth: DOM-derived text boxes, explicit container boxes, and repeated-group boxes captured independently of `inspect_ui_image`.
- Dataset SHA-256: `5433ce68c8560c86b07360ef7b74d5a33ddbdf4f012b1df5af7a6a2b937461e5`.
- Categories: dashboard (2), editor (2), feed (3), form (2), landscape (3), list (2), low_contrast (1), payment (2), repeated_toolbar (1), scroll_region (1), search (3), settings (2), sheet_modal (3), small_text (1), split_view (2).
- Coverage tags: `artifact_compression` (2), `dark` (4), `desktop` (24), `empty_state` (1), `jpeg` (3), `landscape` (2), `low_contrast` (3), `mobile` (6), `overlay` (4), `png` (27), `repeated_group` (15), `repeated_toolbar` (3), `scroll_region` (8), `small_text` (4), `split` (2).
- Production path: benchmark target links the exact repository copies of `InspectUIImageTool.swift`, `UIEvidence.swift`, `UIEvidenceVision.swift`, and `ToolWorkspace.swift`; no algorithm changes.

## Headline metrics

| Metric | Value |
|---|---:|
| OCR precision | 82.76% |
| OCR recall | 77.47% |
| OCR F1 | 80.03% |
| Text bbox IoU@0.5 (matched text) | 43.36% |
| Text bbox recall@0.5 (all GT text) | 33.59% |
| Container precision | 7.03% |
| Container recall | 32.82% |
| Container F1 | 11.57% |
| Repeated-group F1 | 3.92% |
| Observed/inferred label accuracy | 100.00% |
| Crop usable rate | 97.78% |
| Hard failures | 0 |

## Latency

- Samples: 90 calls (3 measured repetitions per image).
- p50: **231.1 ms**
- p95: **409.6 ms**
- Mean: 1513.8 ms
- First-call cold-start sample: 55392.5 ms

## Source / crop safety

- Source decodes and matches manifest dimensions/hash: 30 / 30 images without hard failure (see report for exact categories).
- Crop requests: 90; usable: 88 (97.78%).
- Repeated-call crop nondeterminism: 7 unreferenced PNG artifacts across 3 images; use `failures.md` for classification.
- Every crop was checked for workspace escape, PNG decode, expected source-derived pixel dimensions, source asset linkage, and nonblank pixels.

## Interpretation

- OCR precision/recall are exact normalized-text matches; punctuation and case are ignored.
- Text bbox IoU@0.5 is computed on matched text pairs. Bbox recall@0.5 is additionally reported against all ground-truth text.
- Container P/R/F1 uses one-to-one bbox matching at IoU 0.5 against explicit DOM containers.
- Repeated-group F1 requires the same axis and bbox IoU 0.5.
- Observed/inferred accuracy is evaluated only on matched text and container elements.
- Hard-failure checks include schema/coordinate-space validity, all bbox bounds, source/crop decode and ancestry, crop pixel dimensions, and recommendation/layout leakage.

## Known limitations

- This baseline is curated web UI, not a census of native iOS/macOS applications.
- DOM ground truth is exhaustive only for tagged/rendered text in the captured viewport; offscreen content is intentionally excluded.
- Vision behavior can vary by macOS runtime/model version. Record the host/runtime with each future comparison.
- Metrics are descriptive baseline evidence, not a freeze gate or release claim.

## Artifacts

- `metrics.csv` — per-image and aggregate metrics.
- `ui_evidence/*.json` — exact `ui_evidence.v1` output per image.
- `failures.md` — hard-failure and miss classification.
- `asset_checks.json` — source/crop decode, ancestry, bounds, and usability checks.
- `run_metadata.json` — tool outputs, assets, checks, and latency samples.
- `environment.json` — OS/Swift/Python and exact source/evaluator hashes.
