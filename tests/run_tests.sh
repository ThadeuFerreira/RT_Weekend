#!/usr/bin/env bash
set -euo pipefail

# Usage: ./tests/run_tests.sh [debug|release|all]
# Runs the render test suite against the specified build mode.
# Idempotent: cleans tests/output/<mode>/ before each run.

MODE="${1:-debug}"

# Test entries: "name|scene|width|height|samples|threads"
TESTS=(
    "smoke|tests/scenes/smoke.json|200|113|5|4"
    "materials|tests/scenes/materials.json|200|113|10|4"
)

run_test_suite() {
    local mode="$1"
    local binary="build/$mode"
    local out_dir="tests/output/$mode"

    if [[ ! -f "$binary" ]]; then
        echo "ERROR: Binary not found: $binary" >&2
        return 1
    fi

    rm -rf "$out_dir"
    mkdir -p "$out_dir"

    local total=0
    local passed=0
    local failed=0
    local test_results=""

    for entry in "${TESTS[@]}"; do
        IFS='|' read -r name scene w h s c <<< "$entry"
        local out_ppm="$out_dir/${name}.ppm"
        local out_profile="$out_dir/${name}_profile.json"

        total=$((total + 1))
        printf "  %-16s ... " "$name"

        local t0
        t0=$(date +%s%N)

        local rc=0
        "$binary" \
            -scene "$scene" \
            -headless \
            -out "$out_ppm" \
            -profile-out "$out_profile" \
            -w "$w" -h "$h" -s "$s" -c "$c" \
            > /dev/null 2>&1 || rc=$?

        local t1
        t1=$(date +%s%N)
        local dur_s
        dur_s=$(awk "BEGIN { printf \"%.3f\", ($t1 - $t0) / 1e9 }")

        local ok=true
        local reason=""

        if [[ $rc -ne 0 ]]; then
            ok=false
            reason="non-zero exit ($rc)"
        fi

        if $ok && [[ ! -f "$out_ppm" ]]; then
            ok=false
            reason="output PPM missing"
        fi

        if $ok; then
            local sz
            sz=$(wc -c < "$out_ppm" | tr -d ' ')
            if [[ "$sz" -eq 0 ]]; then
                ok=false
                reason="output PPM is empty"
            fi
        fi

        # Validate profile JSON structure if python3 is available
        if $ok && command -v python3 &>/dev/null && [[ -f "$out_profile" ]]; then
            if ! python3 -c "
import json, sys
try:
    d = json.load(open('$out_profile'))
    assert 'total_seconds' in d, 'missing total_seconds'
    assert 'phases' in d, 'missing phases'
    sys.exit(0)
except Exception as e:
    print(e, file=sys.stderr)
    sys.exit(1)
" 2>/dev/null; then
                ok=false
                reason="profile JSON invalid"
            fi
        fi

        local sz_val=0
        if [[ -f "$out_ppm" ]]; then
            sz_val=$(wc -c < "$out_ppm" | tr -d ' ')
        fi

        local profile_val="null"
        if [[ -f "$out_profile" ]]; then
            profile_val="\"$out_profile\""
        fi

        local ok_json="false"
        if $ok; then
            passed=$((passed + 1))
            ok_json="true"
            echo "PASS (${dur_s}s)"
        else
            failed=$((failed + 1))
            echo "FAIL — $reason"
        fi

        if [[ -n "$test_results" ]]; then
            test_results="${test_results},"
        fi
        test_results="${test_results}
    {\"name\":\"$name\",\"scene\":\"$scene\",\"passed\":$ok_json,\"exit_code\":$rc,\"output_file\":\"$out_ppm\",\"output_bytes\":$sz_val,\"profile_file\":$profile_val,\"duration_seconds\":$dur_s}"
    done

    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    mkdir -p tests/output
    printf '{\n  "timestamp": "%s",\n  "build_mode": "%s",\n  "binary": "%s",\n  "tests": [%s\n  ],\n  "summary": {"total": %d, "passed": %d, "failed": %d}\n}\n' \
        "$ts" "$mode" "$binary" "$test_results" "$total" "$passed" "$failed" \
        > tests/output/report.json

    echo ""
    echo "Results: $passed/$total passed — report: tests/output/report.json"

    [[ $failed -eq 0 ]]
}

exit_code=0
case "$MODE" in
    debug)
        echo "=== Test suite: debug ==="
        run_test_suite debug || exit_code=1
        ;;
    release)
        echo "=== Test suite: release ==="
        run_test_suite release || exit_code=1
        ;;
    all)
        echo "=== Test suite: debug ==="
        run_test_suite debug || exit_code=1
        echo ""
        echo "=== Test suite: release ==="
        run_test_suite release || exit_code=1
        ;;
    *)
        echo "Usage: $0 [debug|release|all]" >&2
        exit 1
        ;;
esac

exit $exit_code
