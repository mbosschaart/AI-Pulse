#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
"$project_root/Scripts/bootstrap-sparkle.sh"
python3 "$project_root/Scripts/generate-project.py"
build_dir="${AIPULSE_BUILD_DIR:-${TMPDIR:-/tmp}/aipulse-release}"
xcodebuild -project "$project_root/AIPulse.xcodeproj" -scheme AIPulse -configuration Release -derivedDataPath "$build_dir" "$@" build
app_bundle="$build_dir/Build/Products/Release/AI Pulse.app"
framework="$app_bundle/Contents/Frameworks/Sparkle.framework"
identity="${AIPULSE_SIGN_IDENTITY:-Developer ID Application: Martijn Bosschaart (EJ77LX9A8T)}"
# Outside Archive/Export, Xcode does not re-sign Sparkle's nested installer tools.
for component in 'Versions/B/XPCServices/Installer.xpc' 'Versions/B/XPCServices/Downloader.xpc' 'Versions/B/Autoupdate' 'Versions/B/Updater.app'; do
    codesign --force --sign "$identity" --options runtime --timestamp --preserve-metadata=entitlements "$framework/$component"
done
codesign --force --sign "$identity" --options runtime --timestamp "$framework"
codesign --force --sign "$identity" --options runtime --timestamp --preserve-metadata=entitlements "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
mkdir -p "$project_root/dist"
# Produce the archive directly from non-cloud build storage to preserve signed contents.
ditto -c -k --keepParent --norsrc --noextattr "$app_bundle" "$project_root/dist/AI-Pulse-macOS.zip"
echo "Signed app: $app_bundle"
echo "Archive: $project_root/dist/AI-Pulse-macOS.zip"
