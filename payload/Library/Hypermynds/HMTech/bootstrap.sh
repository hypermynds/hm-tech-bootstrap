#!/bin/bash

set -uo pipefail

HM_DIR="/Library/Hypermynds/HMTech"
BREWFILE="$HM_DIR/Brewfile"
VERSION_FILE="$HM_DIR/VERSION"
LOG_FILE="/var/log/hypermynds-hmtech-bootstrap.log"

umask 022
exec >>"$LOG_FILE" 2>&1

echo "[$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')] Avvio HM Tech Bootstrap"

if [[ ! -r "$VERSION_FILE" ]]; then
  echo "File VERSION non disponibile: $VERSION_FILE"
  exit 1
fi

BOOTSTRAP_VERSION="$(/usr/bin/tr -d '[:space:]' <"$VERSION_FILE")"

if [[ ! "$BOOTSTRAP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Versione bootstrap non valida: $BOOTSTRAP_VERSION"
  exit 1
fi

DONE_FILE="$HM_DIR/.completed-$BOOTSTRAP_VERSION"

if [[ -f "$DONE_FILE" ]]; then
  echo "Bootstrap $BOOTSTRAP_VERSION già completato."
  exit 0
fi

CONSOLE_USER="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true)"

case "$CONSOLE_USER" in
  ""|root|loginwindow|_mbsetupuser)
    echo "Nessun utente console disponibile; nuovo tentativo tra cinque minuti."
    exit 0
    ;;
esac

if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW_BIN="/opt/homebrew/bin/brew"
elif [[ -x /usr/local/bin/brew ]]; then
  BREW_BIN="/usr/local/bin/brew"
else
  echo "Homebrew non ancora disponibile; nuovo tentativo tra cinque minuti."
  exit 0
fi

echo "Versione bootstrap: $BOOTSTRAP_VERSION"
echo "Utente console: $CONSOLE_USER"
echo "Homebrew: $BREW_BIN"

if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  echo "AVVISO: Xcode Command Line Tools non rilevati."
fi

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_UPGRADE=1

brew_user() {
  "$BREW_BIN" as-console-user "$@"
}

cask_artifact_present() {
  case "$1" in
    rstudio)
      [[ -d /Applications/RStudio.app ]]
      ;;
    visual-studio-code)
      [[ -d "/Applications/Visual Studio Code.app" ]]
      ;;
    docker-desktop)
      [[ -d /Applications/Docker.app ]]
      ;;
    cyberduck)
      [[ -d /Applications/Cyberduck.app ]]
      ;;
    *)
      echo "Nessuna regola conservativa definita per il cask: $1"
      return 2
      ;;
  esac
}

ensure_formula() {
  local formula="$1"

  if brew_user list --formula "$formula" >/dev/null 2>&1; then
    echo "Formula già gestita da Homebrew: $formula"
    return 0
  fi

  echo "Installazione formula: $formula"
  brew_user install "$formula"
}

ensure_cask() {
  local cask="$1"

  if brew_user list --cask "$cask" >/dev/null 2>&1; then
    echo "Cask già gestito da Homebrew: $cask"
    return 0
  fi

  cask_artifact_present "$cask"
  local artifact_status=$?

  if [[ "$artifact_status" -eq 2 ]]; then
    return 1
  fi

  if [[ "$artifact_status" -eq 0 ]]; then
    echo "Applicazione già presente per $cask; tento l'adozione conservativa."

    if brew_user install --cask --adopt "$cask"; then
      echo "Cask adottato da Homebrew: $cask"
    else
      echo "AVVISO: $cask non è adottabile; applicazione esistente lasciata intatta."
    fi

    return 0
  fi

  echo "Installazione cask: $cask"
  brew_user install --cask "$cask"
}

while IFS= read -r FORMULA; do
  [[ -z "$FORMULA" ]] && continue

  if ! ensure_formula "$FORMULA"; then
    echo "Installazione della formula $FORMULA non riuscita; verrà riprovata."
    exit 1
  fi
done < <(/usr/bin/sed -nE 's/^[[:space:]]*brew[[:space:]]+"([^"]+)".*/\1/p' "$BREWFILE")

while IFS= read -r CASK; do
  [[ -z "$CASK" ]] && continue

  if ! ensure_cask "$CASK"; then
    echo "Installazione del cask $CASK non riuscita; verrà riprovata."
    exit 1
  fi
done < <(/usr/bin/sed -nE 's/^[[:space:]]*cask[[:space:]]+"([^"]+)".*/\1/p' "$BREWFILE")

{
  echo "version=$BOOTSTRAP_VERSION"
  echo "completed_at=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "console_user=$CONSOLE_USER"
  echo "brew=$BREW_BIN"
} >"$DONE_FILE"

/usr/sbin/chown root:wheel "$DONE_FILE"
/bin/chmod 0644 "$DONE_FILE"

echo "HM Tech Bootstrap $BOOTSTRAP_VERSION completato."
exit 0
