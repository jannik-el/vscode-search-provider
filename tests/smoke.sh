#!/bin/sh
# Smoke test: run the provider on a private session bus against a fake
# workspaceStorage and check its D-Bus answers. Usage:
#   tests/smoke.sh [path/to/searchProvider.js]
# Re-executes itself under dbus-run-session, so it never touches the real bus.
set -eu

if [ -z "${SMOKE_IN_BUS:-}" ]; then
  SMOKE_IN_BUS=1 exec dbus-run-session --config-file="$(dirname "$0")/session.conf" -- "$0" "$@"
fi

SCRIPT=${1:-src/searchProvider.js}
BUS=io.github.jannik_el.VSCodeSearchProvider
OBJ=/io/github/jannik_el/VSCodeSearchProvider
IFACE=org.gnome.Shell.SearchProvider2

PID=
TMP=$(mktemp -d)
trap 'kill "$PID" 2>/dev/null || true; rm -rf "$TMP"' EXIT
export XDG_CONFIG_HOME="$TMP/config"
STORAGE="$XDG_CONFIG_HOME/Code/User/workspaceStorage"

# folder <hash> <path>: register a recent folder; mtime order = recency.
folder() {
  mkdir -p "$STORAGE/$1"
  printf '{"folder":"file://%s"}\n' "$2" > "$STORAGE/$1/workspace.json"
  touch "$STORAGE/$1/state.vscdb"
  sleep 1
}

mkdir -p "$TMP/code/seal-team" "$TMP/code/stats-course"
folder a1 "$TMP/code/stats-course"
folder b2 "$TMP/code/seal-team"
folder c3 "$TMP/code/deleted-project"

gjs -m "$SCRIPT" &
PID=$!
gdbus wait --session --timeout 10 "$BUS"

call() {
  method=$1; shift
  gdbus call --session --dest "$BUS" --object-path "$OBJ" --method "$IFACE.$method" "$@"
}

fail=0
expect() { # expect <description> <actual> <expected>
  if [ "$2" = "$3" ]; then
    echo "ok   $1"
  else
    echo "FAIL $1"; echo "  expected: $3"; echo "  actual:   $2"; fail=1
  fi
}

SEAL="file://$TMP/code/seal-team"
STATS="file://$TMP/code/stats-course"

expect "single term matches folder name" \
  "$(call GetInitialResultSet "['seal']")" "(['$SEAL'],)"
expect "case-insensitive, most recent first" \
  "$(call GetInitialResultSet "['CODE']")" "(['$SEAL', '$STATS'],)"
expect "every term must match" \
  "$(call GetInitialResultSet "['code', 'stats']")" "(['$STATS'],)"
expect "missing folders are skipped" \
  "$(call GetInitialResultSet "['deleted']")" "(@as [],)"
expect "subsearch" \
  "$(call GetSubsearchResultSet "['$SEAL', '$STATS']" "['seal']")" "(['$SEAL'],)"

META=$(call GetResultMetas "['$SEAL']")
case "$META" in
  *"'name': <'seal-team'>"*) echo "ok   result meta has folder name" ;;
  *) echo "FAIL result meta: $META"; fail=1 ;;
esac

exit $fail
