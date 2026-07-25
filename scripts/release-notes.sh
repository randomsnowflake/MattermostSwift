#!/bin/sh
set -eu

cd "$(git rev-parse --show-toplevel)"

tag="${1:-}"
case "$tag" in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *)
        echo "usage: $0 vMAJOR.MINOR.PATCH[-PRERELEASE]" >&2
        exit 64
        ;;
esac

if ! printf '%s\n' "$tag" | grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$'; then
    echo "error: tag must be a fully qualified semantic version prefixed with v" >&2
    exit 64
fi

version="${tag#v}"
notes="$(
    awk -v heading="## $version" '
        $0 == heading {
            found = 1
            next
        }
        found && /^## / {
            exit
        }
        found {
            print
        }
        END {
            if (!found) {
                exit 2
            }
        }
    ' CHANGELOG.md
)" || {
    echo "error: CHANGELOG.md has no '$version' release section" >&2
    exit 1
}

if ! printf '%s\n' "$notes" | grep -Eq '[^[:space:]]'; then
    echo "error: CHANGELOG.md section '$version' is empty" >&2
    exit 1
fi

printf '%s\n' "$notes"
