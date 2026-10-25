#!/bin/sh
# Build a signed flat apt repository from .deb files. Usage:
#   tools/apt-repo.sh OUTDIR DEB...
# Signs with the default secret key in $GNUPGHOME (or ~/.gnupg). Needs only
# dpkg-deb, coreutils, gzip and gpg, so it runs without apt-utils.
# Clients use:  deb [signed-by=KEYRING] https://HOST/PATH/ ./
set -eu

[ $# -ge 2 ] || { echo "usage: $0 OUTDIR DEB..." >&2; exit 2; }
OUT=$1; shift
NAME=vscode-search-provider

rm -rf "$OUT"
mkdir -p "$OUT/pool"
cp "$@" "$OUT/pool/"
cd "$OUT"

# Packages: each package's control fields plus where to find it and hashes.
for deb in pool/*.deb; do
  dpkg-deb -f "$deb"
  echo "Filename: $deb"
  echo "Size: $(stat -c %s "$deb")"
  echo "MD5sum: $(md5sum < "$deb" | cut -d' ' -f1)"
  echo "SHA1: $(sha1sum < "$deb" | cut -d' ' -f1)"
  echo "SHA256: $(sha256sum < "$deb" | cut -d' ' -f1)"
  echo
done > Packages
gzip -9nk Packages

hashes() { # hashes <tool>: " <hash> <size> <file>" for each index file
  for f in Packages Packages.gz; do
    echo " $($1 < "$f" | cut -d' ' -f1) $(stat -c %s "$f") $f"
  done
}
{
  echo "Origin: $NAME"
  echo "Label: $NAME"
  echo "Architectures: all"
  echo "Date: $(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S UTC')"
  echo "MD5Sum:"; hashes md5sum
  echo "SHA1:"; hashes sha1sum
  echo "SHA256:"; hashes sha256sum
} > Release

gpg --batch --yes --clearsign -o InRelease Release
gpg --batch --yes --armor --detach-sign -o Release.gpg Release
gpg --batch --yes --export -o "$NAME.gpg"
gpg --batch --yes --armor --export -o "$NAME.asc"
