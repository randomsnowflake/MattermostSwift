#!/bin/sh
set -eu

if ! command -v jq >/dev/null 2>&1; then
    echo "scripts/test-e2e.sh requires jq for MattermostSwiftCLI --json output." >&2
    exit 1
fi

test_channel_id=""
cleanup_test_channel() {
    if [ -n "$test_channel_id" ]; then
        swift run MattermostSwiftCLI diag archive-channel "$test_channel_id" >/dev/null 2>&1 || true
    fi
}
trap cleanup_test_channel EXIT INT TERM

created_channel_output=$(swift run MattermostSwiftCLI --json diag create-test-channel)
test_channel_id=$(printf '%s\n' "$created_channel_output" | jq -er '.id')
if [ -z "$test_channel_id" ]; then
    echo "create-test-channel did not print a channel id" >&2
    exit 1
fi
swift run MattermostSwiftCLI diag rename-test-channel "$test_channel_id" >/dev/null
swift run MattermostSwiftCLI diag archive-channel "$test_channel_id" >/dev/null
test_channel_id=""

swift run MattermostSwiftCLI diag e2e-test
swift run MattermostSwiftCLI diag thread-test
swift run MattermostSwiftCLI diag timeline-test
swift run MattermostSwiftCLI diag since-test
swift run MattermostSwiftCLI diag props-test
swift run MattermostSwiftCLI diag reaction-test
swift run MattermostSwiftCLI diag preference-roundtrip-test
swift run MattermostSwiftCLI diag search-test
swift run MattermostSwiftCLI diag file-test
swift run MattermostSwiftCLI diag websocket-test
swift run MattermostSwiftCLI diag live-sync-test
swift run MattermostSwiftCLI diag reconnect-backfill-test
swift run MattermostSwiftCLI diag deletion-backfill-test
swift run MattermostSwiftCLI diag live-sync-reconnect-test
swift run MattermostSwiftCLI diag all-channel-reconnect-test
swift run MattermostSwiftCLI diag failure-cleanup-test
swift run MattermostSwiftCLI diag typing-test
swift run MattermostSwiftCLI diag channel-test
swift run MattermostSwiftCLI diag sidebar-category-test
swift run MattermostSwiftCLI diag sidebar-move-test
swift run MattermostSwiftCLI diag residue-audit
