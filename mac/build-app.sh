#!/bin/sh
# Build build/Berang.app and sign it. Needs Xcode, because MLX's Metal shaders don't build with `swift build`.
# Signs with SIGN_IDENTITY if set, else the Berang certificate that releases use, else a Developer ID, else an
# Apple Development certificate, else ad hoc. A certificate keeps the Accessibility permission across rebuilds;
# an ad hoc signature loses it on every build. VERSION, if set, becomes the app's version.
set -e
cd "$(dirname "$0")"

# Xcode builds a package's scheme with code coverage on, which adds counters to every function.
xcodebuild -scheme Berang -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .xcbuild -quiet CLANG_COVERAGE_MAPPING=NO build

app=build/Berang.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp App/Info.plist "$app/Contents/"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
    -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$app/Contents/Info.plist"
fi
cp .xcbuild/Build/Products/Release/Berang "$app/Contents/MacOS/"
# Symbols for crash reports stay in .xcbuild/Build/Products/Release/Berang.dSYM.
strip -S -x "$app/Contents/MacOS/Berang"
# Package resources, such as MLX's Metal shaders, which the app finds in Contents/Resources.
mkdir -p "$app/Contents/Resources"
for bundle in .xcbuild/Build/Products/Release/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$app/Contents/Resources/"
done
# Sparkle, which updates the app. Berang isn't sandboxed, so it needs none of Sparkle's XPC services.
sparkle=$app/Contents/Frameworks/Sparkle.framework
mkdir -p "$app/Contents/Frameworks"
ditto .xcbuild/Build/Products/Release/Sparkle.framework "$sparkle"
rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/Berang"
# The app icon, the menu bar icon, and the mascot's poses.
cp -R App/Brand "$app/Contents/Resources/"
cp App/Brand/AppIcon.icns "$app/Contents/Resources/"
# Each voice's recorded preview, made by `berang-say previews App/Previews <Pocket's model folder>`.
cp -R App/Previews "$app/Contents/Resources/"

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
# Sparkle's helpers first, then Sparkle, then the app, as Sparkle's documentation does it, without --deep.
for part in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle"; do
  codesign --force --options runtime $timestamp --sign "$identity" "$part"
done
# Library validation loads only frameworks from the app's own Apple team. The Berang certificate has no team, so
# it would refuse Sparkle, signed by the same certificate.
codesign --force --options runtime $timestamp --entitlements App/Berang.entitlements --sign "$identity" "$app"
codesign --verify --strict "$app"
echo "$app signed by $identity"
