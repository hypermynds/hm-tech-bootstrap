#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-}"
MODE="${2:-}"

usage() {
  echo "Uso: ./release.sh X.Y.Z [--publish]" >&2
}

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  usage
  exit 1
fi

if [[ -n "$MODE" && "$MODE" != "--publish" ]]; then
  usage
  exit 1
fi

for COMMAND in git gh shasum; do
  if ! command -v "$COMMAND" >/dev/null 2>&1; then
    echo "Comando richiesto non trovato: $COMMAND" >&2
    exit 1
  fi
done

if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "La directory non appartiene a un repository Git." >&2
  exit 1
fi

if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain)" ]]; then
  echo "Il repository contiene modifiche non committate." >&2
  exit 1
fi

gh auth status >/dev/null
git -C "$SCRIPT_DIR" fetch --quiet origin

if ! git -C "$SCRIPT_DIR" rev-parse '@{u}' >/dev/null 2>&1; then
  echo "Il branch corrente non ha un upstream configurato." >&2
  exit 1
fi

LOCAL_SHA="$(git -C "$SCRIPT_DIR" rev-parse HEAD)"
UPSTREAM_SHA="$(git -C "$SCRIPT_DIR" rev-parse '@{u}')"

if [[ "$LOCAL_SHA" != "$UPSTREAM_SHA" ]]; then
  echo "Il commit corrente non coincide con il branch remoto. Esegui push o pull." >&2
  exit 1
fi

TAG="v$VERSION"

if git -C "$SCRIPT_DIR" ls-remote --exit-code --tags origin "refs/tags/$TAG" \
  >/dev/null 2>&1; then
  echo "Il tag remoto $TAG esiste già." >&2
  exit 1
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "La release $TAG esiste già." >&2
  exit 1
fi

"$SCRIPT_DIR/build.sh" "$VERSION"

DIST_DIR="$SCRIPT_DIR/dist"
ASSET_NAME="hm-tech-bootstrap-$VERSION.pkg"
PKG_PATH="$DIST_DIR/$ASSET_NAME"
CHECKSUM_PATH="$PKG_PATH.sha256"

(
  cd "$DIST_DIR"
  shasum -a 256 "$ASSET_NAME" >"$ASSET_NAME.sha256"
)

RELEASE_ARGS=(
  release create "$TAG"
  "$PKG_PATH#macOS installer package"
  "$CHECKSUM_PATH#SHA-256 checksum"
  --target "$LOCAL_SHA"
  --title "HM Tech Bootstrap $VERSION"
  --generate-notes
  --fail-on-no-commits
)

if [[ "$MODE" != "--publish" ]]; then
  RELEASE_ARGS+=(--draft)
fi

gh "${RELEASE_ARGS[@]}"

if [[ "$MODE" == "--publish" ]]; then
  echo "Release $TAG pubblicata."
else
  echo "Release $TAG creata come bozza."
  echo "Per pubblicarla: gh release edit $TAG --draft=false --latest"
fi
