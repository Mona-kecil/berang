#!/bin/sh
# Installs Berang from its latest GitHub release, or updates it.
# usage: curl -fsSL https://raw.githubusercontent.com/Mona-kecil/berang/main/install.sh | sh
set -eu

url=${BERANG_URL:-https://github.com/Mona-kecil/berang/releases/latest/download/Berang.zip}
# The SHA-1 of the certificate every release is signed with.
certificate=88d75215f34036c49cd26eded6b5806d782ef039

fail() { echo "$1" >&2; exit 1; }
[ "$(uname -m)" = arm64 ] || fail "Berang needs a Mac with Apple silicon."
[ "$(sw_vers -productVersion | cut -d . -f 1)" -ge 15 ] || fail "Berang needs macOS 15 or later."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "Downloading Berang..."
curl -fsSL "$url" -o "$tmp/Berang.zip" || fail "Couldn't download $url"
curl -fsSL "$url.sha256" -o "$tmp/Berang.zip.sha256" || fail "Couldn't download $url.sha256"
[ "$(shasum -a 256 "$tmp/Berang.zip" | cut -d ' ' -f 1)" = "$(cat "$tmp/Berang.zip.sha256")" ] ||
  fail "The download is damaged. Run the installer again."
ditto -x -k "$tmp/Berang.zip" "$tmp"
codesign --verify --strict "$tmp/Berang.app" 2>/dev/null &&
  codesign -d -r- "$tmp/Berang.app" 2>&1 | grep -q "certificate leaf = H\"$certificate\"" ||
  fail "This Berang isn't signed by the Berang certificate. Nothing was installed."

dest=/Applications
[ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
if pgrep -xq Berang; then osascript -e 'quit app id "io.github.mona-kecil.berang"'; sleep 1; fi
rm -rf "$dest/Berang.app"
mv "$tmp/Berang.app" "$dest/"
echo "Installed $(defaults read "$dest/Berang.app/Contents/Info" CFBundleShortVersionString) in $dest. Opening Berang..."
open "$dest/Berang.app"
