#!/bin/sh
# Build build/Berang.app and sign it. Needs Xcode, because MLX's Metal shaders don't build with `swift build`.
# Signs with SIGN_IDENTITY if set, else the Berang certificate that releases use, else a Developer ID, else an
# Apple Development certificate, else ad hoc. A certificate keeps the Accessibility permission across rebuilds;
# an ad hoc signature loses it on every build. VERSION, if set, becomes the app's version.
set -e
cd "$(dirname "$0")"

xcodebuild -scheme Berang -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .xcbuild -quiet build

app=build/Berang.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp App/Info.plist "$app/Contents/"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$app/Contents/Info.plist"
fi
cp .xcbuild/Build/Products/Release/Berang "$app/Contents/MacOS/"

identities=$(security find-identity -v -p codesigning)
# The Berang certificate is self-signed, so macOS lists it as not trusted, which codesign accepts.
berang=$(security find-identity -p codesigning | grep -m1 -o '"Berang"' | tr -d '"' || true)
identity=${SIGN_IDENTITY:-$berang}
identity=${identity:-$(echo "$identities" | grep -m1 -o '"Developer ID Application: [^"]*"' | tr -d '"')}
identity=${identity:-$(echo "$identities" | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"')}
identity=${identity:--}
case $identity in
  "Developer ID"*) timestamp=--timestamp ;;
  *) timestamp=--timestamp=none ;;
esac
codesign --force --options runtime $timestamp --sign "$identity" "$app"
codesign --verify --strict "$app"
echo "$app signed by $identity"
