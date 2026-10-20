#!/usr/bin/env bash
# Build Pocket and install it on a connected iPhone.
#
#   ./scripts/install-device.sh
#
# Environment overrides:
#   DEVICE_ID          device UDID (default: auto-detect the first paired device)
#   TEAM               Apple team id (default: the team of the first development cert)
#   POCKET_BUNDLE_ID   bundle id to sign (default: com.example.pocket.dev)
#   POCKET_BASE_URL    server root baked into the app (required)
#   POCKET_TOKEN       pairing token (default: read from ~/.dsh/pocket/state.json)
#
# Machine-local values can live in scripts/local.env (git-ignored), for example:
#   POCKET_BUNDLE_ID=com.yourname.pocket.dev
#   POCKET_BASE_URL=https://your-mac.your-tailnet.ts.net/pocket
#   TEAM=YOURTEAMID
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f scripts/local.env ]; then
  set -a
  . scripts/local.env
  set +a
fi

if [ -z "${DEVICE_ID:-}" ]; then
  DEVICE_ID="$(xcrun devicectl list devices 2>/dev/null | awk '/available|paired/ {print $3; exit}')"
fi
[ -n "$DEVICE_ID" ] || { echo "no paired iPhone found"; exit 1; }

BUNDLE_ID="${POCKET_BUNDLE_ID:-com.example.pocket.dev}"
BASE_URL="${POCKET_BASE_URL:-}"
if [ -z "$BASE_URL" ]; then
  echo "POCKET_BASE_URL is required (or put it in scripts/local.env)" >&2
  exit 1
fi
TOKEN="${POCKET_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  TOKEN="$(python3 -c 'import json,os;print(json.load(open(os.path.expanduser("~/.dsh/pocket/state.json")))["token"])')"
fi

# --- pick a signing identity (and its team) from the keychain -------------
identity_hash() {
  local team="$1" line hash name ou
  security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Development' | while IFS= read -r line; do
    hash="$(echo "$line" | awk '{print $2}')"
    name="$(echo "$line" | sed -E 's/.*"(.*)".*/\1/')"
    ou="$(security find-certificate -c "$name" -p 2>/dev/null \
      | openssl x509 -noout -subject -nameopt sep_multiline 2>/dev/null \
      | awk -F= '/OU=/{print $2; exit}' | tr -d ' ')"
    if [ -z "$team" ] || [ "$ou" = "$team" ]; then
      echo "$hash|$ou"
      return
    fi
  done | head -1
}

PICK="$(identity_hash "${TEAM:-}")"
HASH="${PICK%%|*}"
TEAM_ID="${TEAM:-${PICK##*|}}"
[ -n "$HASH" ] || { echo "no Apple Development certificate found"; exit 1; }

echo "device:   $DEVICE_ID"
echo "team:     $TEAM_ID"
echo "identity: $HASH"
echo "bundle:   $BUNDLE_ID"

cd ios
set +e
xcodebuild \
  -project Pocket.xcodeproj \
  -scheme Pocket \
  -configuration Release \
  -destination "id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  -derivedDataPath build-device \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  POCKET_BASE_URL="$BASE_URL" \
  POCKET_TOKEN="$TOKEN" \
  build
STATUS=$?
set -e

APP="build-device/Build/Products/Release-iphoneos/Pocket.app"
ENT="build-device/Build/Intermediates.noindex/Pocket.build/Release-iphoneos/Pocket.build/Pocket.app.xcent"
if [ ! -d "$APP" ]; then
  echo "build failed (exit $STATUS)"; exit "$STATUS"
fi

# macOS adds com.apple.provenance / FinderInfo to freshly written bundles and
# codesign refuses them: strip the xattrs and sign the finished product.
xattr -cr "$APP"
if [ -f "$ENT" ]; then
  codesign --force --sign "$HASH" --entitlements "$ENT" --timestamp=none --generate-entitlement-der "$APP"
else
  codesign --force --sign "$HASH" --timestamp=none --generate-entitlement-der "$APP"
fi

xcrun devicectl device uninstall app --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" || true
