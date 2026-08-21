#!/bin/bash

set -uo pipefail

HM_DIR="/Library/Hypermynds/HMTech"
BREWFILE="$HM_DIR/Brewfile"
DONE_FILE="$HM_DIR/.completed"
LOG_FILE="/var/log/hypermynds-hmtech-bootstrap.log"
R_VERSION="4.6.1"

umask 022
exec >>"$LOG_FILE" 2>&1

echo "[$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')] Avvio HM Tech Bootstrap"

if [[ -f "$DONE_FILE" ]]; then
  echo "Bootstrap già completato."
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
  BREW_PREFIX="/opt/homebrew"
elif [[ -x /usr/local/bin/brew ]]; then
  BREW_BIN="/usr/local/bin/brew"
  BREW_PREFIX="/usr/local"
else
  echo "Homebrew non ancora disponibile; nuovo tentativo tra cinque minuti."
  exit 0
fi

echo "Utente console: $CONSOLE_USER"
echo "Homebrew: $BREW_BIN"

if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  echo "AVVISO: Xcode Command Line Tools non rilevati."
fi

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_BUNDLE_NO_UPGRADE=1

if "$BREW_BIN" as-console-user bundle --file="$BREWFILE" --no-upgrade; then
  RIG_BIN="$BREW_PREFIX/bin/rig"

  if [[ ! -x "$RIG_BIN" ]]; then
    echo "rig non trovato dopo brew bundle: $RIG_BIN"
    exit 1
  fi

  if ! "$RIG_BIN" add "$R_VERSION" --without-pak; then
    if "$RIG_BIN" list 2>/dev/null | /usr/bin/grep -Fq "$R_VERSION"; then
      echo "R $R_VERSION risulta già gestito da rig; proseguo."
    else
      echo "Installazione di R $R_VERSION tramite rig non riuscita."
      exit 1
    fi
  fi

  "$RIG_BIN" default "$R_VERSION"
  "$RIG_BIN" system setup-user-lib

  {
    echo "completed_at=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "console_user=$CONSOLE_USER"
    echo "brew=$BREW_BIN"
    echo "rig=$RIG_BIN"
    echo "r_version=$R_VERSION"
  } >"$DONE_FILE"

  /usr/sbin/chown root:wheel "$DONE_FILE"
  /bin/chmod 0644 "$DONE_FILE"
  echo "HM Tech Bootstrap completato."
  exit 0
else
  STATUS=$?
  echo "brew bundle non completato (stato $STATUS); verrà riprovato."
  exit "$STATUS"
fi
