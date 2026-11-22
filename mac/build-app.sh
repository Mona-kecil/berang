#!/bin/sh
# Build build/Berang.app and sign it. Needs Xcode, because MLX's Metal shaders don't build with `swift build`.
# Signs with SIGN_IDENTITY if set, else a Developer ID, else an Apple Development certificate, else ad hoc.
# A certificate keeps the Accessibility permission across rebuilds; an ad hoc signature loses it on every build.
set -e
cd "$(dirname "$0")"

xcodebuild -scheme Berang -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .xcbuild -quiet build

app=build/Berang.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp App/Info.plist "$app/Contents/"
cp .xcbuild/Build/Products/Release/Berang "$app/Contents/MacOS/"

identities=$(security find-identity -v -p codesigning)
identity=${SIGN_IDENTITY:-$(echo "$identities" | grep -m1 -o '"Developer ID Application: [^"]*"' | tr -d '"')}
identity=${identity:-$(echo "$identities" | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"')}
identity=${identity:--}
case $identity in
  "Developer ID"*) timestamp=--timestamp ;;
  *) timestamp=--timestamp=none ;;
esac
codesign --force --options runtime $timestamp --sign "$identity" "$app"
codesign --verify --strict "$app"
echo "$app signed by $identity"
