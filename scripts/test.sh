#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
test_dir="$(mktemp -d /tmp/trackpadflow-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -D PORTABLE_TESTS \
  "$project_dir/Sources/TrackpadFlow/GestureEngine.swift" \
  "$project_dir/Tests/TrackpadFlowTests/GestureEngineTests.swift" \
  "$project_dir/scripts/TestRunner.swift" \
  -o "$test_dir/tests"
"$test_dir/tests"
