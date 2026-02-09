#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p test-results

echo "== CI Test Runner =="

TOTAL=0
PASSED=0
FAILED=0
JUNIT_TESTS=""

run_test() {
  local name="$1"
  local cmd="$2"
  TOTAL=$((TOTAL + 1))

  START=$(date +%s%N)
  if eval "$cmd" > "/tmp/ci_test_${TOTAL}.log" 2>&1; then
    END=$(date +%s%N)
    ELAPSED=$(echo "scale=3; ($END - $START) / 1000000000" | bc)
    echo "PASS: $name (${ELAPSED}s)"
    PASSED=$((PASSED + 1))
    JUNIT_TESTS+="    <testcase classname=\"ci\" name=\"${name}\" time=\"${ELAPSED}\"/>\n"
  else
    END=$(date +%s%N)
    ELAPSED=$(echo "scale=3; ($END - $START) / 1000000000" | bc)
    echo "FAIL: $name (${ELAPSED}s)"
    FAILED=$((FAILED + 1))
    MSG=$(tail -5 "/tmp/ci_test_${TOTAL}.log" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
    JUNIT_TESTS+="    <testcase classname=\"ci\" name=\"${name}\" time=\"${ELAPSED}\">\n"
    JUNIT_TESTS+="      <failure message=\"Test failed\">${MSG}</failure>\n"
    JUNIT_TESTS+="    </testcase>\n"
  fi
}

run_test "Contract Validation" "python3 scripts/validate_contracts.py"
run_test "Darija Intent Detection" "python3 scripts/test_darja_intents.py"
run_test "Template Rendering" "python3 scripts/test_template_render.py"
run_test "L10N Script Detection" "python3 scripts/test_l10n_script_detection.py"

# Generate JUnit XML
cat > test-results/results.xml << XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="ci-python-tests" tests="${TOTAL}" failures="${FAILED}" errors="0">
$(echo -e "$JUNIT_TESTS")  </testsuite>
</testsuites>
XMLEOF

echo ""
echo "Results: ${PASSED}/${TOTAL} passed, ${FAILED} failed"
echo "JUnit XML: test-results/results.xml"

if [ $FAILED -gt 0 ]; then
  exit 1
fi
