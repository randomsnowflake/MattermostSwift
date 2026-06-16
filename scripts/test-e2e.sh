#!/bin/sh
set -eu

test_channel_id=""
cleanup_test_channel() {
    if [ -n "$test_channel_id" ]; then
        swift run MattermostSwiftCLI archive-channel "$test_channel_id" >/dev/null 2>&1 || true
    fi
}
trap cleanup_test_channel EXIT INT TERM

created_channel_output=$(swift run MattermostSwiftCLI create-test-channel)
test_channel_id=$(printf '%s\n' "$created_channel_output" | awk '/^channel: / { print $2; exit }')
if [ -z "$test_channel_id" ]; then
    echo "create-test-channel did not print a channel id" >&2
    exit 1
fi
swift run MattermostSwiftCLI rename-test-channel "$test_channel_id" >/dev/null
swift run MattermostSwiftCLI archive-channel "$test_channel_id" >/dev/null
test_channel_id=""

swift run MattermostSwiftCLI e2e-test
swift run MattermostSwiftCLI thread-test
swift run MattermostSwiftCLI timeline-test
swift run MattermostSwiftCLI since-test
swift run MattermostSwiftCLI props-test
swift run MattermostSwiftCLI reaction-test
swift run MattermostSwiftCLI preference-roundtrip-test
swift run MattermostSwiftCLI search-test
swift run MattermostSwiftCLI file-test
swift run MattermostSwiftCLI websocket-test
swift run MattermostSwiftCLI live-sync-test
swift run MattermostSwiftCLI reconnect-backfill-test
swift run MattermostSwiftCLI deletion-backfill-test
swift run MattermostSwiftCLI live-sync-reconnect-test
swift run MattermostSwiftCLI all-channel-reconnect-test
swift run MattermostSwiftCLI failure-cleanup-test
swift run MattermostSwiftCLI typing-test
swift run MattermostSwiftCLI channel-test
swift run MattermostSwiftCLI sidebar-category-test
swift run MattermostSwiftCLI sidebar-move-test
swift run MattermostSwiftCLI residue-audit
