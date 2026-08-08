#!/usr/bin/env bash
# ws <command> [args] — route to the workspace scripts in ws.d/.
#
# `./ws feature vat` from the workspace root, or symlink this file onto PATH
# (`ln -s .../ws ~/bin/ws`) to get the `ws feature vat` spelling from
# anywhere — it resolves the symlink back to the workspace.
set -euo pipefail

SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
DIR="$(cd "$(dirname "$SELF")/ws.d" && pwd)"

usage() {
    echo "usage: ws <command> [args]"
    echo
    echo "commands:"
    for f in "$DIR"/*; do
        [ -x "$f" ] || continue
        # Each script's second line is its one-line header.
        printf '  %s\n' "$(sed -n '2s/^# *//p' "$f")"
    done
}

CMD="${1-}"
case "$CMD" in
    "" | -h | --help | help) usage; exit 0 ;;
    */*) echo "ws: unknown command '$CMD'" >&2; exit 1 ;;
esac
shift

if [ ! -x "$DIR/$CMD" ]; then
    echo "ws: unknown command '$CMD'" >&2
    usage >&2
    exit 1
fi
exec "$DIR/$CMD" "$@"
