#!/bin/sh
set -eu

# Arguments forward to swift test, e.g. scripts/test-unit.sh --filter MattermostStoreTests
exec swift test "$@"
