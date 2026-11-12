# P1-C UI Evidence Quality Benchmark

Independent, repeatable quality benchmark for `ClientToolsKit.inspect_ui_image`.
It measures the existing `ui_evidence.v1` producer only. It does not modify UI,
does not enter `ui_layout.v1`, and does not make component or layout
recommendations.

The checked-in baseline is **not a P1-C freeze declaration**.

## Dataset

- 30 curated web UI pages rendered by headless Chromium and captured at native
  viewport resolution: 27 PNG, 3 JPEG.
- Six mobile-width states and 24 desktop/wide states, including two landscape
  layouts.
- Categories: settings, feed, editor, form, payment, dashboard, Sheet/Modal,
  complex list, search, split view, small text, low contrast, repeated toolbar,
  and scroll regions.
- Ground truth is DOM-derived after render, independently of OCR/Vision. It
  contains exhaustive visible leaf text in the viewport, explicit containers,
  and repeated-group member unions.
- `dataset/manifest.json` records per-image and per-ground-truth SHA-256 values
  plus an aggregate dataset hash. Both the generator and runner refuse changed
  inputs.
- `dataset/images/` is immutable after a baseline. Do not edit screenshots or
  ground truth to improve a score.

The dataset is intentionally curated web UI rather than a claim of native-app
coverage. Future dataset versions must use a new directory and a new baseline.

## Harness

`Runner/main.swift` calls the public `InspectUIImageTool.execute` once or more
per image with three requested crops. `RunnerCore/` contains symlinks to the
exact repository copies of:

- `Sources/ClientToolsKit/InspectUIImageTool.swift`
- `Sources/ClientToolsKit/UIEvidence.swift`
- `Sources/ClientToolsKit/UIEvidenceVision.swift`
- `Sources/ClientToolsKit/ToolWorkspace.swift`

This benchmark-only target avoids compiling unrelated CoreML resources while
still compiling and executing the same source files under test. The symlinks
are verified by `environment.json` source hashes.

The runner records:

- exact `ui_evidence.v1` JSON per image;
- three measured calls per image with no warmup;
- source decode, dimensions, and SHA-256 checks;
- crop escape, decode, pixel-dimension, ancestry, and blank-content checks;
- source/crop asset metadata and workspace-relative paths.

`evaluate.py` reads the run and ground truth and writes the reports. It never
writes back to the dataset or invokes the image inspector.

## Run

Prerequisites: macOS with Vision, Swift 6.1+, Python 3.10+, Playwright, Chromium,
and Pillow. Install the Python packages with:

```bash
python3 -m pip install -r Benchmarks/UIEvidence/requirements.txt
python3 -m playwright install chromium
```

The dataset is already checked in; Playwright is needed only to re-render a
future dataset version.

```bash
cd /Users/xiaoyuan/Documents/work/git/ClientToolsKit
PYTHON_BIN=/opt/miniconda3/bin/python3.14 \
  Benchmarks/UIEvidence/run.sh Benchmarks/UIEvidence/baseline-v2
```

The script refuses to overwrite an existing immutable baseline. Use a new output
directory for every measurement round. On hosts where SwiftPM or Chromium is
blocked by an outer sandbox, run the commands in a normal developer shell or
approve the local build/browser execution.

## Metrics

Definitions are deliberately strict and fixed for the first baseline:

- **OCR recall**: exact normalized text match (case, whitespace, and punctuation
  ignored) against visible DOM text. OCR precision and F1 are also reported,
  with false positives and misses.
- **Text bbox IoU@0.5**: among uniquely matched text pairs, share whose bbox IoU
  is at least 0.5. Bbox recall against all ground-truth text is reported
  separately.
- **Container precision/recall/F1**: one-to-one bbox matching at IoU 0.5 against
  explicit DOM container annotations.
- **Repeated-group F1**: one-to-one group matching with the same axis and bbox
  IoU 0.5.
- **Observed/inferred accuracy**: matched text must be `observed`; matched
  containers must be `inferred`.
- **Crop usable rate**: crop exists, stays inside the workspace, decodes as PNG,
  has the expected source-derived pixel dimensions, resolves to the correct
  source asset, and contains nonblank pixels.
- **Latency**: nearest-rank p50/p95 over all measured calls. Cold start is
  reported separately and is not hidden by warmup.

## Hard failures

Any of the following is a hard failure:

- invalid or missing `ui_evidence.v1` schema;
- non-top-left or out-of-bounds bbox;
- source decode/hash/dimension mismatch;
- crop escape, decode failure, wrong pixel dimensions, or invalid source/crop
  ancestry;
- forbidden layout/component recommendation keys or values.

## Baseline artifacts

The first immutable run is under `baseline/`:

- `summary.md` — scope, metrics, latency, safety, and limitations;
- `metrics.csv` — per-image and aggregate metrics;
- `ui_evidence/*.json` — exact output for each image;
- `failures.md` — hard-failure and miss classification;
- `asset_checks.json` — detailed source/crop checks;
- `latency.csv` — per-image latency;
- `run_metadata.json` — raw execution record;
- `evaluation.json` — machine-readable scored output;
- `environment.json` — host/runtime and source snapshot hashes.

## Calibration v1.1

The v1 baseline and `dataset/` are immutable. The audit layer lives separately:

- `dataset-v2/` — byte-identical v1 images plus corrected overlay-occlusion GT,
  independent visual-rectangle GT, and repeated-group member metadata.
- `audit-v1.1/` — strict leaf, many-to-one line/block, bbox geometry,
  vision-rectangle, semantic-container, repeated-group, and crop-integrity
  reports.
- `audit-v1.1/overlays/` — 12 reviewed GT/prediction overlays.
- `generator/build_dataset_v2.py` and `evaluate_v11.py` — reproducible audit
  pipeline. Neither script invokes or changes the detector.
