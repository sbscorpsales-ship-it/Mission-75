#!/usr/bin/env bash
# Best-effort exporter for XCTest result bundles produced by the macOS CI runner.
# This never changes XCTest execution or the release gate; it only makes failures
# inspectable without requiring a developer to open the full .xcresult bundle.
set -uo pipefail

RESULT_PATH="\${1:-build/GATIVX.xcresult}"
OUTPUT_DIR="\${2:-build/GATIVX-XCTest-Diagnostics}"
STATUS_FILE="$OUTPUT_DIR/export-status.txt"

mkdir -p "$OUTPUT_DIR"
: > "$STATUS_FILE"

if [[ ! -f "$RESULT_PATH/Info.plist" ]]; then
  printf 'No XCTest result bundle was produced at %s.\n' "$RESULT_PATH" \
    | tee "$OUTPUT_DIR/README.txt" "$STATUS_FILE"
  exit 0
fi

run_json_export() {
  local label="$1"
  local filename="$2"
  shift 2

  if "$@" > "$OUTPUT_DIR/$filename" 2> "$OUTPUT_DIR/\${label}.stderr"; then
    printf 'PASS: %s\n' "$label" | tee -a "$STATUS_FILE"
  else
    local code=$?
    printf 'WARN: %s export failed (exit %s); see %s.stderr\n' \
      "$label" "$code" "$label" | tee -a "$STATUS_FILE"
  fi
}

run_directory_export() {
  local label="$1"
  local directory="$2"
  shift 2

  mkdir -p "$OUTPUT_DIR"
  if "$@" > "$OUTPUT_DIR/\${label}.log" 2>&1; then
    printf 'PASS: %s\n' "$label" | tee -a "$STATUS_FILE"
  else
    local code=$?
    printf 'WARN: %s export unavailable (exit %s); see %s.log\n' \
      "$label" "$code" "$label" | tee -a "$STATUS_FILE"
  fi
}

run_json_export content-availability content-availability.json \
  xcrun xcresulttool get content-availability --path "$RESULT_PATH" --compact

run_json_export test-summary summary.json \
  xcrun xcresulttool get test-results summary --path "$RESULT_PATH" --format json

run_json_export test-tree tests.json \
  xcrun xcresulttool get test-results tests --path "$RESULT_PATH" --format json

# The cumulative navigation test is the known Profile-idle failure candidate.
# If it did not execute in a particular run, these exports are recorded as warnings.
run_json_export profile-navigation-test-details profile-navigation-test-details.json \
  xcrun xcresulttool get test-results test-details --path "$RESULT_PATH" \
  --test-id "GATIVXDashboardUITests/testDashboardSectionsMetricsAndPrimaryNavigation()" --format json

run_json_export profile-navigation-test-activities profile-navigation-test-activities.json \
  xcrun xcresulttool get test-results activities --path "$RESULT_PATH" \
  --test-id "GATIVXDashboardUITests/testDashboardSectionsMetricsAndPrimaryNavigation()" --format json

run_directory_export failure-attachments attachments \
  xcrun xcresulttool export attachments --path "$RESULT_PATH" \
  --output-path "$OUTPUT_DIR/attachments" --only-failures

run_directory_export diagnostics diagnostics \
  xcrun xcresulttool export diagnostics --path "$RESULT_PATH" \
  --output-path "$OUTPUT_DIR/diagnostics"

if [[ -s "$OUTPUT_DIR/summary.json" ]]; then
  python3 - "$OUTPUT_DIR/summary.json" <<'PY' | tee "$OUTPUT_DIR/summary-counts.txt"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    summary = json.load(stream)

keys = ("totalTestCount", "passedTests", "failedTests", "skippedTests")
for key in keys:
    if key in summary:
        print(f"{key}: {summary[key]}")
PY
fi

printf 'XCTest diagnostics export completed. Test pass/fail status remains governed by the original xcodebuild test step.\n' \
  | tee -a "$STATUS_FILE"

# Deliberately return success: this exporter is diagnostic-only and must not
# hide or replace the original XCTest result or alter the release validation gate.
exit 0
