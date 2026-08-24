#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-1.0.0}"
IDENTIFIER="com.hypermynds.hmtech.bootstrap"
SIGNING_IDENTITY="Installer Certificate (Hypermynds)"
DIST_DIR="$SCRIPT_DIR/dist"
OUTPUT_PKG="$DIST_DIR/hm-tech-bootstrap-$VERSION.pkg"
VERSION_FILE="$SCRIPT_DIR/payload/Library/Hypermynds/HMTech/VERSION"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "La versione deve avere il formato X.Y.Z" >&2
  exit 1
fi

if ! security find-identity -v | grep -Fq "$SIGNING_IDENTITY"; then
  echo "Identità di firma non trovata: $SIGNING_IDENTITY" >&2
  exit 1
fi

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "File VERSION non trovato: $VERSION_FILE" >&2
  exit 1
fi

ORIGINAL_VERSION="$(<"$VERSION_FILE")"

restore_version_file() {
  printf '%s\n' "$ORIGINAL_VERSION" >"$VERSION_FILE"
}

trap restore_version_file EXIT
printf '%s\n' "$VERSION" >"$VERSION_FILE"

mkdir -p "$DIST_DIR"
rm -f "$OUTPUT_PKG"

pkgbuild \
  --root "$SCRIPT_DIR/payload" \
  --scripts "$SCRIPT_DIR/scripts" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location / \
  --ownership recommended \
  --sign "$SIGNING_IDENTITY" \
  "$OUTPUT_PKG"

echo
pkgutil --check-signature "$OUTPUT_PKG"
echo
shasum -a 256 "$OUTPUT_PKG"
echo
echo "Pacchetto creato: $OUTPUT_PKG"
