#!/bin/sh
# Test tools/apt-repo.sh: build a repo signed with a throwaway key, then point
# a private, unprivileged apt at it and check it verifies and offers the
# package. Also checks that a tampered index is rejected. Usage:
#   tests/apt.sh DEB
set -eu

DEB=$1
TOOLS=$(cd "$(dirname "$0")/../tools" && pwd)
TMP=$(mktemp -d)
export GNUPGHOME="$TMP/gnupg"
trap 'gpgconf --kill gpg-agent 2>/dev/null || true; rm -rf "$TMP"' EXIT
mkdir -m 700 "$GNUPGHOME"

gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-generate-key "apt test <test@example.invalid>" ed25519 sign never
"$TOOLS/apt-repo.sh" "$TMP/repo" "$DEB"

mkdir -p "$TMP/lists/partial" "$TMP/cache/archives/partial" "$TMP/parts"
# Same deb822 shape as the README's install instructions.
cat > "$TMP/parts/test.sources" <<EOF
Types: deb
URIs: file://$TMP/repo/
Suites: ./
Signed-By: $TMP/repo/vscode-search-provider.gpg
EOF
APT="-o Dir::Etc::SourceList=/dev/null -o Dir::Etc::SourceParts=$TMP/parts
     -o Dir::State::Lists=$TMP/lists -o Dir::Cache=$TMP/cache -o Debug::NoLocking=1
     -o APT::Sandbox::User=$(id -un)"

fail=0
# shellcheck disable=SC2086
if apt-get $APT update 2>&1 | grep -q '^\(W\|E\):'; then
  echo "FAIL apt update of signed repo"; apt-get $APT update; fail=1
else
  echo "ok   apt update verifies the signed repo"
fi

VERSION=$(dpkg-deb -f "$DEB" Version)
# shellcheck disable=SC2086
if apt-cache $APT policy vscode-search-provider |
   grep -A1 "^ *\(\*\*\* \)\?$VERSION " | grep -q "file:$TMP/repo"; then
  echo "ok   repo offers vscode-search-provider $VERSION"
else
  echo "FAIL repo does not offer $VERSION"; apt-cache $APT policy vscode-search-provider; fail=1
fi

# Change the index after signing: apt must refuse it.
echo "Tampered: yes" >> "$TMP/repo/Packages"
rm -rf "$TMP/lists"; mkdir -p "$TMP/lists/partial"
# shellcheck disable=SC2086
if apt-get $APT update 2>&1 | grep -q 'Hash Sum mismatch\|File has unexpected size\|^E:'; then
  echo "ok   tampered index is rejected"
else
  echo "FAIL tampered index was accepted"; fail=1
fi

exit $fail
