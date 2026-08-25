#!/bin/bash

set -uo pipefail

HM_DIR="/Library/Hypermynds/HMTech"
BREWFILE="$HM_DIR/Brewfile"
VERSION_FILE="$HM_DIR/VERSION"
LOG_FILE="/var/log/hypermynds-hmtech-bootstrap.log"

MARKER_TEMPLATE="$HM_DIR/MarkerTemplate"
MARKER_APP="/Applications/Utilities/HM Tech Bootstrap.app"
MARKER_IDENTIFIER="com.hypermynds.hmtech.bootstrap"

BREW_RECEIPT_ID="sh.brew.homebrew"

TEMPFAIL=75

umask 022
exec >>"$LOG_FILE" 2>&1

echo "[$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')] Avvio HM Tech Bootstrap"

if [[ ! -r "$VERSION_FILE" ]]; then
  echo "File VERSION non disponibile: $VERSION_FILE"
  exit 1
fi

if [[ ! -r "$BREWFILE" ]]; then
  echo "Brewfile non disponibile: $BREWFILE"
  exit 1
fi

BOOTSTRAP_VERSION="$(
  /usr/bin/tr -d '[:space:]' <"$VERSION_FILE"
)"

if [[ ! "$BOOTSTRAP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Versione bootstrap non valida: $BOOTSTRAP_VERSION"
  exit 1
fi

DONE_FILE="$HM_DIR/.completed-$BOOTSTRAP_VERSION"

marker_is_current() {
  local marker_info="$MARKER_APP/Contents/Info.plist"
  local marker_identifier
  local marker_version

  [[ -f "$marker_info" ]] || return 1

  marker_identifier="$(
    /usr/bin/plutil \
      -extract CFBundleIdentifier raw \
      "$marker_info" 2>/dev/null ||
      true
  )"

  marker_version="$(
    /usr/bin/plutil \
      -extract CFBundleShortVersionString raw \
      "$marker_info" 2>/dev/null ||
      true
  )"

  [[ "$marker_identifier" == "$MARKER_IDENTIFIER" ]] &&
    [[ "$marker_version" == "$BOOTSTRAP_VERSION" ]]
}

if [[ -f "$DONE_FILE" ]] && marker_is_current; then
  echo "Bootstrap $BOOTSTRAP_VERSION già completato."
  exit 0
fi

if [[ -f "$DONE_FILE" ]]; then
  echo "Completamento presente ma app-marker assente o obsoleta; verrà ripristinata."
fi

CONSOLE_USER="$(
  /usr/bin/stat -f '%Su' /dev/console 2>/dev/null ||
    true
)"

case "$CONSOLE_USER" in
  ""|root|loginwindow|_mbsetupuser)
    echo "Nessun utente console disponibile; nuovo tentativo tra cinque minuti."
    exit "$TEMPFAIL"
    ;;
esac

CONSOLE_HOME="$(
  /usr/bin/dscl . \
    -read "/Users/$CONSOLE_USER" NFSHomeDirectory 2>/dev/null |
    /usr/bin/cut -d ' ' -f 2-
)"

if [[ -z "$CONSOLE_HOME" || ! -d "$CONSOLE_HOME" ]]; then
  echo "Home directory non disponibile per $CONSOLE_USER; nuovo tentativo tra cinque minuti."
  exit "$TEMPFAIL"
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW_BIN="/opt/homebrew/bin/brew"
elif [[ -x /usr/local/bin/brew ]]; then
  BREW_BIN="/usr/local/bin/brew"
else
  echo "Homebrew non ancora disponibile; nuovo tentativo tra cinque minuti."
  exit "$TEMPFAIL"
fi

echo "Versione bootstrap: $BOOTSTRAP_VERSION"
echo "Utente console: $CONSOLE_USER"
echo "Homebrew: $BREW_BIN"

if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  echo "AVVISO: Xcode Command Line Tools non rilevati."
fi

export HOME="$CONSOLE_HOME"
export USER="$CONSOLE_USER"
export LOGNAME="$CONSOLE_USER"
export PATH="$(/usr/bin/dirname "$BREW_BIN"):/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_UPGRADE=1

brew_user() {
  "$BREW_BIN" as-console-user "$@"
}

if ! /usr/sbin/pkgutil \
  --pkg-info "$BREW_RECEIPT_ID" >/dev/null 2>&1; then
  echo "Receipt $BREW_RECEIPT_ID non ancora disponibile; nuovo tentativo tra cinque minuti."
  exit "$TEMPFAIL"
fi

BREW_RECEIPT_VERSION="$(
  /usr/sbin/pkgutil \
    --pkg-info-plist "$BREW_RECEIPT_ID" 2>/dev/null |
    /usr/bin/plutil -extract pkg-version raw - 2>/dev/null ||
    true
)"

if [[ -z "$BREW_RECEIPT_VERSION" ]]; then
  echo "Impossibile determinare la versione del receipt Homebrew."
  exit "$TEMPFAIL"
fi

case "$(/usr/bin/uname -m)" in
  arm64)
    EXPECTED_BREW_PREFIX="/opt/homebrew"
    ;;
  x86_64)
    EXPECTED_BREW_PREFIX="/usr/local"
    ;;
  *)
    echo "Architettura Mac non supportata: $(/usr/bin/uname -m)"
    exit 1
    ;;
esac

BREW_PREFIX="$(
  brew_user --prefix 2>/dev/null ||
    true
)"

if [[ "$BREW_PREFIX" != "$EXPECTED_BREW_PREFIX" ]]; then
  echo "Prefisso Homebrew inatteso: '$BREW_PREFIX'; atteso: '$EXPECTED_BREW_PREFIX'."
  exit 1
fi

BREW_RUNTIME_VERSION="$(
  brew_user --version 2>/dev/null |
    /usr/bin/head -n 1 ||
    true
)"

if [[ -z "$BREW_RUNTIME_VERSION" ]]; then
  echo "Homebrew non risponde correttamente; nuovo tentativo tra cinque minuti."
  exit "$TEMPFAIL"
fi

echo "Receipt Homebrew: $BREW_RECEIPT_VERSION"
echo "Versione Homebrew: $BREW_RUNTIME_VERSION"
echo "Prefisso Homebrew: $BREW_PREFIX"

install_marker() {
  local marker_info_source="$MARKER_TEMPLATE/Info.plist"
  local marker_executable_source="$MARKER_TEMPLATE/HMTechBootstrap"
  local marker_tmp="/Applications/Utilities/.HM Tech Bootstrap.app.$$.tmp"
  local marker_contents="$marker_tmp/Contents"
  local copied_identifier

  if [[ ! -f "$marker_info_source" ||
        ! -f "$marker_executable_source" ]]; then
    echo "Template dell’app-marker incompleto."
    return 1
  fi

  /bin/rm -rf "$marker_tmp"
  /bin/mkdir -p "$marker_contents/MacOS"

  if ! /usr/bin/install \
      -m 0644 \
      "$marker_info_source" \
      "$marker_contents/Info.plist" ||
    ! /usr/bin/install \
      -m 0755 \
      "$marker_executable_source" \
      "$marker_contents/MacOS/HMTechBootstrap"; then
    /bin/rm -rf "$marker_tmp"
    return 1
  fi

  if ! /usr/bin/plutil \
      -replace CFBundleShortVersionString \
      -string "$BOOTSTRAP_VERSION" \
      "$marker_contents/Info.plist" ||
    ! /usr/bin/plutil \
      -replace CFBundleVersion \
      -string "$BOOTSTRAP_VERSION" \
      "$marker_contents/Info.plist"; then
    /bin/rm -rf "$marker_tmp"
    return 1
  fi

  copied_identifier="$(
    /usr/bin/plutil \
      -extract CFBundleIdentifier raw \
      "$marker_contents/Info.plist" 2>/dev/null ||
      true
  )"

  if [[ "$copied_identifier" != "$MARKER_IDENTIFIER" ]]; then
    echo "Bundle ID dell’app-marker non valido: $copied_identifier"
    /bin/rm -rf "$marker_tmp"
    return 1
  fi

  if ! /usr/bin/plutil -lint \
      "$marker_contents/Info.plist" ||
    ! /usr/sbin/chown -R root:wheel "$marker_tmp"; then
    /bin/rm -rf "$marker_tmp"
    return 1
  fi

  if [[ -e "$MARKER_APP" || -L "$MARKER_APP" ]]; then
    /bin/rm -rf "$MARKER_APP"
  fi

  if ! /bin/mv "$marker_tmp" "$MARKER_APP"; then
    /bin/rm -rf "$marker_tmp"
    return 1
  fi

  return 0
}

cask_artifact_present() {
  case "$1" in
    cyberduck)
      [[ -d /Applications/Cyberduck.app ]]
      ;;
    docker-desktop)
      [[ -d /Applications/Docker.app ]]
      ;;
    font-fira-code)
      [[ -f "$CONSOLE_HOME/Library/Fonts/FiraCode-Bold.ttf" ||
         -f "$CONSOLE_HOME/Library/Fonts/FiraCode-Light.ttf" ||
         -f "$CONSOLE_HOME/Library/Fonts/FiraCode-Medium.ttf" ||
         -f "$CONSOLE_HOME/Library/Fonts/FiraCode-Regular.ttf" ||
         -f "$CONSOLE_HOME/Library/Fonts/FiraCode-Retina.ttf" ||
         -f "$CONSOLE_HOME/Library/Fonts/FiraCode-SemiBold.ttf" ||
         -f "$CONSOLE_HOME/Library/Fonts/FiraCode-VF.ttf" ]]
      ;;
    obsidian)
      [[ -d "/Applications/Obsidian.app" ]]
      ;;
    pgadmin4)
      [[ -d "/Applications/pgAdmin 4.app" ]]
      ;;
    rstudio)
      [[ -d /Applications/RStudio.app ]]
      ;;
    visual-studio-code)
      [[ -d "/Applications/Visual Studio Code.app" ]]
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
done < <(
  /usr/bin/sed -nE \
    's/^[[:space:]]*brew[[:space:]]+"([^"]+)".*/\1/p' \
    "$BREWFILE"
)

while IFS= read -r CASK; do
  [[ -z "$CASK" ]] && continue

  if ! ensure_cask "$CASK"; then
    echo "Installazione del cask $CASK non riuscita; verrà riprovata."
    exit 1
  fi
done < <(
  /usr/bin/sed -nE \
    's/^[[:space:]]*cask[[:space:]]+"([^"]+)".*/\1/p' \
    "$BREWFILE"
)

DONE_TMP="$DONE_FILE.tmp.$$"

if ! {
  echo "version=$BOOTSTRAP_VERSION"
  echo "completed_at=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "console_user=$CONSOLE_USER"
  echo "brew=$BREW_BIN"
  echo "brew_prefix=$BREW_PREFIX"
  echo "brew_receipt=$BREW_RECEIPT_ID"
  echo "brew_receipt_version=$BREW_RECEIPT_VERSION"
  echo "brew_runtime_version=$BREW_RUNTIME_VERSION"
} >"$DONE_TMP"; then
  echo "Impossibile creare il file di completamento."
  /bin/rm -f "$DONE_TMP"
  exit 1
fi

if ! /usr/sbin/chown root:wheel "$DONE_TMP" ||
  ! /bin/chmod 0644 "$DONE_TMP" ||
  ! /bin/mv -f "$DONE_TMP" "$DONE_FILE"; then
  echo "Impossibile finalizzare il file di completamento."
  /bin/rm -f "$DONE_TMP"
  exit 1
fi

if ! install_marker; then
  echo "Creazione dell’app-marker non riuscita; verrà riprovata."
  /bin/rm -f "$DONE_FILE"
  exit 1
fi

echo "HM Tech Bootstrap $BOOTSTRAP_VERSION completato."
exit 0
