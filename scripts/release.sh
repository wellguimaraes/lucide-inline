#!/usr/bin/env bash
# Builds a Developer ID signed, notarized DMG and publishes it as a GitHub release.
#
#   scripts/release.sh 1.0.0
#
# Signing settings are loaded from SIGNING_ENV (default ~/.floripa-signing/signing.env), which sets:
#   CSC_NAME          Developer ID Application identity
#   CSC_KEYCHAIN      keychain holding that identity
#   APPLE_API_KEY     App Store Connect API key (.p8) for notarization
#   APPLE_API_KEY_ID, APPLE_API_ISSUER
# The keychain password is read from the login keychain (service SIGNING_KEYCHAIN_SERVICE,
# default floripa-signing-keychain), never from a file.
set -euo pipefail

version="${1:?usage: scripts/release.sh <version>}"
version="${version#v}"
tag="v$version"

cd "$(dirname "$0")/.."

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must be X.Y.Z, got: $version" >&2
  exit 1
fi
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is dirty. Commit or stash first so the tag matches the build." >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "Tag $tag already exists." >&2
  exit 1
fi
gh auth status >/dev/null

set -a
# shellcheck disable=SC1090
source "${SIGNING_ENV:-$HOME/.floripa-signing/signing.env}"
set +a
security unlock-keychain \
  -p "$(security find-generic-password -s "${SIGNING_KEYCHAIN_SERVICE:-floripa-signing-keychain}" -w)" \
  "$CSC_KEYCHAIN"

notarize() {
  local result status id
  result="$(xcrun notarytool submit "$1" \
    --key "$APPLE_API_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER" \
    --wait --output-format json)"
  status="$(plutil -extract status raw -o - - <<<"$result")"
  if [[ "$status" != "Accepted" ]]; then
    id="$(plutil -extract id raw -o - - <<<"$result")"
    echo "Notarization of $1 finished with status: $status" >&2
    xcrun notarytool log "$id" --key "$APPLE_API_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER" >&2
    exit 1
  fi
  echo "Notarized $1"
}

app="build/Lucide Inline.app"
dmg_name="Lucide-Inline-$version.dmg"
dmg="build/$dmg_name"

VERSION="$version" UNIVERSAL=1 SIGN_IDENTITY="$CSC_NAME" SIGN_KEYCHAIN="$CSC_KEYCHAIN" ./scripts/build.sh

# Staple the app itself so it passes Gatekeeper offline after it's copied out of the DMG.
ditto -c -k --keepParent "$app" build/notarize.zip
notarize build/notarize.zip
rm build/notarize.zip
xcrun stapler staple "$app"

staging="build/dmg"
rm -rf "$staging" "$dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Lucide Inline" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
rm -rf "$staging"

codesign --sign "$CSC_NAME" --keychain "$CSC_KEYCHAIN" --timestamp "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"

(cd build && shasum -a 256 "$dmg_name" > SHA256SUMS)

git tag "$tag"
git push origin "$tag"
gh release create "$tag" "$dmg" build/SHA256SUMS \
  --title "Lucide Inline $tag" \
  --generate-notes \
  --verify-tag \
  --latest
