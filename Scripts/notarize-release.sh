#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${AIPULSE_BUILD_DIR:-${TMPDIR:-/tmp}/aipulse-release}"
app_bundle="$build_dir/Build/Products/Release/AI Pulse.app"
release_stage="${AIPULSE_RELEASE_STAGE:-${TMPDIR:-/tmp}/aipulse-notarized-release}"
mkdir -p "$release_stage" "$project_root/dist"
# Credentials are supplied locally; never copy them into the repository or archive.
if [[ -n "${AIPULSE_NOTARY_ENV:-}" ]]; then source "$AIPULSE_NOTARY_ENV"; fi
if [[ -n "${AIPULSE_NOTARY_PROFILE:-}" ]]; then
    notary_auth=(--keychain-profile "$AIPULSE_NOTARY_PROFILE")
else
    : "${APPLE_ID:?Set AIPULSE_NOTARY_PROFILE or provide local Apple notarization credentials}"
    : "${APPLE_APP_SPECIFIC_PASSWORD:?Missing Apple app-specific password}"
    : "${APPLE_TEAM_ID:?Missing Apple team ID}"
    notary_auth=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
fi
identity="${AIPULSE_SIGN_IDENTITY:-Developer ID Application: Martijn Bosschaart (EJ77LX9A8T)}"
version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["display"])' "$project_root/Config/version.json")"
submit() {
    local package="$1" report="$2"
    xcrun notarytool submit "$package" "${notary_auth[@]}" --wait --output-format json > "$report"
    python3 - "$report" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
print('Apple notarization:',result.get('status'),'Submission:',result.get('id'))
if result.get('status') != 'Accepted': raise SystemExit('Notarization was not accepted; inspect the submission log before publishing.')
PY
}
codesign --verify --deep --strict "$app_bundle"
python3 - "$app_bundle" <<'PYCODE'
from pathlib import Path
import plistlib,subprocess,sys
app=Path(sys.argv[1])
for path in [app, app/'Contents/PlugIns/AIPulseWidget.appex']:
    output=subprocess.run(['codesign','-d','--entitlements',':-',str(path)],capture_output=True,check=True).stdout
    entitlements=plistlib.loads(output)
    if entitlements.get('com.apple.security.get-task-allow'):
        raise SystemExit('Refusing notarization: debug entitlement on '+str(path))
PYCODE
ditto -c -k --keepParent --norsrc --noextattr "$app_bundle" "$release_stage/AI-Pulse-submit.zip"
submit "$release_stage/AI-Pulse-submit.zip" "$release_stage/app-notarization.json"
xcrun stapler staple "$app_bundle"
xcrun stapler validate "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
spctl --assess --type execute --verbose=4 "$app_bundle"
# The updater signature must be generated from these final stapled bytes.
ditto -c -k --keepParent --norsrc --noextattr "$app_bundle" "$project_root/dist/AI-Pulse-macOS.zip"
dmg_root="$(mktemp -d "$release_stage/dmg-root.XXXXXX")"
ditto --noextattr --norsrc "$app_bundle" "$dmg_root/AI Pulse.app"
ln -s /Applications "$dmg_root/Applications"
cat > "$dmg_root/Install AI Pulse.txt" <<'INSTALL'
AI Pulse

Drag AI Pulse.app to Applications, then open it.

Right-click the menu-bar icon and choose Settings to connect your providers.
Move the Settings window beside the cards to preview appearance changes.

Existing users: quit AI Pulse before replacing it, or use Check for updates
inside Settings. Your connections and preferences are retained.

Designed by Martijn Bosschaart, 2026
https://github.com/mbosschaart/AI-Pulse
INSTALL
cp "$project_root/LICENSE" "$dmg_root/LICENSE.txt"
dmg="$release_stage/AI-Pulse-$version.dmg"
hdiutil create -volname "AI Pulse $version" -srcfolder "$dmg_root" -ov -format UDZO "$dmg"
codesign --force --sign "$identity" --timestamp "$dmg"
submit "$dmg" "$release_stage/dmg-notarization.json"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"
cp "$dmg" "$project_root/dist/AI-Pulse-$version.dmg"
python3 "$project_root/Scripts/make-appcast.py"
python3 - "$project_root" "$version" <<'PY'
from pathlib import Path
import hashlib,sys
root=Path(sys.argv[1])/'dist'
files=['AI-Pulse-macOS.zip','AI-Pulse-'+sys.argv[2]+'.dmg']
(root/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256((root/f).read_bytes()).hexdigest()+'  '+f+'\n' for f in files))
PY
echo "Notarized, stapled ZIP and DMG ready in dist/"
