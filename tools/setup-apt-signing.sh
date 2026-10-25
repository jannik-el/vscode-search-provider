#!/bin/sh
# One-time setup for the apt repository: create the signing key, store the
# private key as the APT_SIGNING_KEY repo secret, write the public key to
# vscode-search-provider.asc, and switch GitHub Pages to deploy from Actions.
# The private key exists only in a temp dir while this runs and in the secret
# afterwards. If it is ever lost, run this again and commit the new public key;
# users then re-download the keyring.
set -eu

REPO=jannik-el/vscode-search-provider
cd "$(dirname "$0")/.."

GNUPGHOME=$(mktemp -d)
export GNUPGHOME
trap 'gpgconf --kill gpg-agent 2>/dev/null || true; rm -rf "$GNUPGHOME"' EXIT

gpg --batch --quiet --pinentry-mode loopback --passphrase '' \
  --quick-generate-key "vscode-search-provider apt signing <jannik.elsaesser@gmx.net>" rsa4096 sign 5y
gpg --batch --armor --export > vscode-search-provider.asc
gpg --batch --armor --export-secret-keys | gh secret set APT_SIGNING_KEY --repo "$REPO"

gh api -X POST "repos/$REPO/pages" -f build_type=workflow >/dev/null 2>&1 ||
  gh api -X PUT "repos/$REPO/pages" -f build_type=workflow >/dev/null

# The github-pages environment only lets main deploy by default; the release
# workflow runs on v* tags.
gh api -X PUT "repos/$REPO/environments/github-pages" --input - >/dev/null <<'EOF'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
EOF
for policy in 'main branch' 'v*.*.* tag'; do
  set -- $policy
  gh api -X POST "repos/$REPO/environments/github-pages/deployment-branch-policies" \
    -f name="$1" -f type="$2" >/dev/null 2>&1 || true
done

gpg --show-keys --with-fingerprint vscode-search-provider.asc
echo "Done. Commit vscode-search-provider.asc, then push a release tag (or run the Release workflow) to publish the repo."
