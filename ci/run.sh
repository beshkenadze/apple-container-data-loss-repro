#!/bin/bash
# Runs reproduction scripts against the installed container system and records each result.
#   ci/run.sh <code under test> <expected result> <script>...
# Writes logs/<code>-<script>.txt and appends "<script> <code> <result> <expected>" rows (tab
# separated) to results/<code>.tsv. Exits 1 when a result differs from the expected one.

set -u
code="$1"
expected="$2"
shift 2
mkdir -p logs results
status=0
for script in "$@"; do
    name="$(basename "$script" .sh)"
    log="logs/$code-$name.txt"
    echo "::group::$name"
    bash "$script" 2>&1 | tee "$log"
    echo "::endgroup::"
    got="$(tail -n 1 "$log")"
    [[ "$got" == "DEFECT REPRODUCED" || "$got" == "NO DEFECT" ]] || got="ERROR"
    printf '%s\t%s\t%s\t%s\n' "$name" "$code" "$got" "$expected" >>"results/$code.tsv"
    if [[ "$got" == "$expected" ]]; then
        echo "$name on $code: $got (expected)"
    else
        echo "::error::$name on $code: $got, expected $expected"
        status=1
    fi
done
exit $status
