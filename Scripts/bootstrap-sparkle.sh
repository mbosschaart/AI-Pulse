#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
# Pinned official Sparkle distribution; no signing keys are stored in the repository.
if [[ -f "$project_root/Vendor/.sparkle-2.10.0" ]]; then exit 0; fi
sparkle_tmp="$(mktemp -d)"
trap 'rm -rf "$sparkle_tmp"' EXIT
curl --fail --location --proto '=https' --tlsv1.2 'https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz' -o "$sparkle_tmp/Sparkle.tar.xz"
python3 - "$sparkle_tmp/Sparkle.tar.xz" <<'PY'
import hashlib,sys
assert hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest() == 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c', 'Sparkle checksum mismatch'
PY
tar -xf "$sparkle_tmp/Sparkle.tar.xz" -C "$sparkle_tmp"
mkdir -p "$project_root/Vendor"
ditto --noextattr --norsrc "$sparkle_tmp/Sparkle.framework" "$project_root/Vendor/Sparkle.framework"
ditto --noextattr --norsrc "$sparkle_tmp/bin" "$project_root/Vendor/bin"
cp "$sparkle_tmp/LICENSE" "$project_root/Vendor/LICENSE"
touch "$project_root/Vendor/.sparkle-2.10.0"
