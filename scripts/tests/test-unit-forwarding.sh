#!/bin/sh
# Proves scripts/test-unit.sh forwards its arguments verbatim to `swift test`.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
fake=$(mktemp -d)
trap 'rm -rf "$fake"' EXIT
printf '#!/bin/sh\nprintf "%%s|" "$@" > "%s/args"\n' "$fake" > "$fake/swift"
chmod +x "$fake/swift"

PATH="$fake:$PATH" "$root/scripts/test-unit.sh" --filter "Store Tests"
[ "$(cat "$fake/args")" = "test|--filter|Store Tests|" ] || { echo "forwarding failed: $(cat "$fake/args")"; exit 1; }
PATH="$fake:$PATH" "$root/scripts/test-unit.sh"
[ "$(cat "$fake/args")" = "test|" ] || { echo "no-arg gate changed: $(cat "$fake/args")"; exit 1; }
echo "test-unit.sh forwarding OK"
