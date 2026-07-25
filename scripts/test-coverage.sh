#!/bin/sh
set -eu

cd "$(git rev-parse --show-toplevel)"

command -v swift >/dev/null 2>&1 || {
    echo "error: swift is required to generate coverage" >&2
    exit 127
}
command -v xcrun >/dev/null 2>&1 || {
    echo "error: xcrun is required to export LCOV coverage" >&2
    exit 127
}

coverage_output="${COVERAGE_OUTPUT:-coverage.lcov}"
swift test --enable-code-coverage

bin_path="$(swift build --show-bin-path)"
profile_path="$bin_path/codecov/default.profdata"
test_bundle=""
for candidate in "$bin_path"/*.xctest; do
    if [ -d "$candidate" ]; then
        test_bundle="$candidate"
        break
    fi
done

if [ -z "$profile_path" ] || [ ! -f "$profile_path" ]; then
    echo "error: SwiftPM did not produce a default.profdata coverage profile" >&2
    exit 1
fi
if [ -z "$test_bundle" ] || [ ! -d "$test_bundle" ]; then
    echo "error: could not locate the SwiftPM .xctest bundle under $bin_path" >&2
    exit 1
fi

test_binary=""
for candidate in "$test_bundle"/Contents/MacOS/*; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
        test_binary="$candidate"
        break
    fi
done
if [ -z "$test_binary" ] || [ ! -x "$test_binary" ]; then
    echo "error: could not locate the executable in $test_bundle" >&2
    exit 1
fi

temporary_output="${coverage_output}.tmp"
trap 'rm -f "$temporary_output"' EXIT HUP INT TERM
xcrun llvm-cov export \
    -format=lcov \
    -instr-profile "$profile_path" \
    -ignore-filename-regex='(^|/)(Tests|\.build)/' \
    "$test_binary" >"$temporary_output"

if [ ! -s "$temporary_output" ]; then
    echo "error: llvm-cov produced an empty coverage report" >&2
    exit 1
fi

mv "$temporary_output" "$coverage_output"
trap - EXIT HUP INT TERM
echo "Coverage written to $coverage_output"
