#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${1:-$ROOT/baseline}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
REPETITIONS="${REPETITIONS:-3}"

if [ -e "$OUTPUT/run_metadata.json" ]; then
  echo "Refusing to overwrite immutable baseline at $OUTPUT" >&2
  echo "Choose a new output directory; do not append measurements to a frozen run." >&2
  exit 2
fi

"$PYTHON_BIN" "$ROOT/generator/generate_dataset.py" --verify-only
swift build --product UIEvidenceBenchmarkRunner
swift run --skip-build UIEvidenceBenchmarkRunner \
  --dataset "$ROOT/dataset" \
  --output "$OUTPUT" \
  --repetitions "$REPETITIONS"
"$PYTHON_BIN" "$ROOT/evaluate.py" --dataset "$ROOT/dataset" --output "$OUTPUT"
"$PYTHON_BIN" "$ROOT/record_environment.py" "$OUTPUT"
