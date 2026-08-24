#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-1.0.0}"
IDENTIFIER="com.hypermynds.hmtech.bootstrap"
SIGNING_IDENTITY="Installer Certificate (Hypermynds)"

DIST_DIR="$SCRIPT_DIR/dist"
OUTPUT_PKG="$DIST_DIR/hm-tech-bootstrap-$VERSION.pkg"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "La versione deve avere il formato X.Y.Z" >&2
  exit 1
fi

for COMMAND in security pkgbuild productbuild pkgutil shasum ditto plutil; do
  if ! command -v "$COMMAND" >/dev/null 2>&1; then
    echo "Comando richiesto non trovato: $COMMAND" >&2
    exit 1
  fi
done

if ! security find-identity -v | grep -Fq "$SIGNING_IDENTITY"; then
  echo "Identità di firma non trovata: $SIGNING_IDENTITY" >&2
  exit 1
fi

BUILD_DIR="$(
  mktemp -d "${TMPDIR:-/tmp}/hm-tech-bootstrap.XXXXXX"
)"
STAGING_ROOT="$BUILD_DIR/root"
STAGING_SCRIPTS="$BUILD_DIR/scripts"

COMPONENT_PKG="$BUILD_DIR/hm-tech-bootstrap-component.pkg"
PRODUCT_EXPANDED="$BUILD_DIR/product-expanded"

cleanup() {
  if [[ -n "${BUILD_DIR:-}" && -d "$BUILD_DIR" ]]; then
    rm -rf "$BUILD_DIR"
  fi
}

trap cleanup EXIT

COPYFILE_DISABLE=1 /usr/bin/ditto \
  --norsrc --noextattr --noqtn \
  "$SCRIPT_DIR/payload" \
  "$STAGING_ROOT"

COPYFILE_DISABLE=1 /usr/bin/ditto \
  --norsrc --noextattr --noqtn \
  "$SCRIPT_DIR/scripts" \
  "$STAGING_SCRIPTS"

VERSION_FILE="$STAGING_ROOT/Library/Hypermynds/HMTech/VERSION"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "File VERSION non trovato nel payload." >&2
  exit 1
fi

printf '%s\n' "$VERSION" >"$VERSION_FILE"

MARKER_APP="$STAGING_ROOT/Applications/Utilities/HM Tech Bootstrap.app"
MARKER_INFO="$MARKER_APP/Contents/Info.plist"
MARKER_EXECUTABLE="$MARKER_APP/Contents/MacOS/HMTechBootstrap"

if [[ ! -f "$MARKER_INFO" || ! -f "$MARKER_EXECUTABLE" ]]; then
  echo "App-marker incompleta nel payload." >&2
  exit 1
fi

/usr/bin/plutil \
  -replace CFBundleShortVersionString \
  -string "$VERSION" \
  "$MARKER_INFO"

/usr/bin/plutil \
  -replace CFBundleVersion \
  -string "$VERSION" \
  "$MARKER_INFO"

/bin/chmod 0755 "$MARKER_EXECUTABLE"
/bin/chmod 0644 "$MARKER_INFO"

/usr/bin/plutil -lint "$MARKER_INFO"

/usr/bin/find "$BUILD_DIR" \
  \( -name '._*' -o -name '.DS_Store' \) \
  -delete

/usr/bin/xattr -cr "$BUILD_DIR" 2>/dev/null || true

mkdir -p "$DIST_DIR"
rm -f "$OUTPUT_PKG"

pkgbuild \
  --root "$STAGING_ROOT" \
  --scripts "$STAGING_SCRIPTS" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location / \
  --ownership recommended \
  "$COMPONENT_PKG"

if pkgutil --payload-files "$COMPONENT_PKG" |
  grep -Eq '(^|/)\._|(^|/)\.DS_Store'; then
  echo "Il component package contiene metadati indesiderati." >&2
  exit 1
fi

productbuild \
  --package "$COMPONENT_PKG" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --sign "$SIGNING_IDENTITY" \
  "$OUTPUT_PKG"

pkgutil --expand "$OUTPUT_PKG" "$PRODUCT_EXPANDED"

if [[ ! -f "$PRODUCT_EXPANDED/Distribution" ]]; then
  echo "Il product archive non contiene Distribution." >&2
  exit 1
fi

echo
pkgutil --check-signature "$OUTPUT_PKG"
echo
shasum -a 256 "$OUTPUT_PKG"
echo
echo "Pacchetto creato: $OUTPUT_PKG"
