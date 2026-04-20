#!/bin/sh
set -eu

usage() {
    cat <<'USAGE'
Usage: scripts/install-widevine.sh [options]

Registers an existing WidevineCdm directory for Helium. It does not download,
decrypt, patch, or bypass DRM.

Options:
  --from DIR             Use a specific WidevineCdm directory.
  --user-data-dir DIR    Helium/Chromium user data dir to receive the hint file.
                         Can be passed more than once.
  --install-dir DIR      Also symlink WidevineCdm into this Helium install dir
                         when writable.
  --copy-to DIR          Copy WidevineCdm into DIR/WidevineCdm instead of symlink.
  --help                 Show this help.

Examples:
  scripts/install-widevine.sh --from /opt/google/chrome/WidevineCdm
  scripts/install-widevine.sh --user-data-dir "$HOME/.config/helium"
  scripts/install-widevine.sh --install-dir /opt/helium

On Arch Linux, install a Widevine provider first, for example Google Chrome or
an AUR package that provides a valid WidevineCdm directory, then run this script.
USAGE
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
HELPER="$ROOT_DIR/package/helium-widevine.sh"

if [ ! -r "$HELPER" ]; then
    echo "error: cannot find $HELPER" >&2
    exit 1
fi

. "$HELPER"

FROM_DIR=""
INSTALL_DIR=""
COPY_TO=""
USER_DATA_DIRS=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --from)
            [ "$#" -gt 1 ] || { echo 'error: --from needs DIR' >&2; exit 1; }
            FROM_DIR="$2"; shift 2 ;;
        --from=*) FROM_DIR="${1#--from=}"; shift ;;
        --user-data-dir)
            [ "$#" -gt 1 ] || { echo 'error: --user-data-dir needs DIR' >&2; exit 1; }
            USER_DATA_DIRS="$USER_DATA_DIRS
$2"; shift 2 ;;
        --user-data-dir=*) USER_DATA_DIRS="$USER_DATA_DIRS
${1#--user-data-dir=}"; shift ;;
        --install-dir)
            [ "$#" -gt 1 ] || { echo 'error: --install-dir needs DIR' >&2; exit 1; }
            INSTALL_DIR="$2"; shift 2 ;;
        --install-dir=*) INSTALL_DIR="${1#--install-dir=}"; shift ;;
        --copy-to)
            [ "$#" -gt 1 ] || { echo 'error: --copy-to needs DIR' >&2; exit 1; }
            COPY_TO="$2"; shift 2 ;;
        --copy-to=*) COPY_TO="${1#--copy-to=}"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [ -n "$FROM_DIR" ]; then
    HELIUM_WIDEVINE_DIR="$FROM_DIR"
    export HELIUM_WIDEVINE_DIR
fi

CDM_DIR="$(helium_widevine_find_dir 2>/dev/null || true)"
if [ -z "$CDM_DIR" ]; then
    cat >&2 <<'EOFERR'
error: no valid WidevineCdm directory found.

Expected layout:
  WidevineCdm/manifest.json
  WidevineCdm/_platform_specific/linux_x64/libwidevinecdm.so

Install Google Chrome or another legitimate Widevine provider, then rerun with:
  scripts/install-widevine.sh --from /path/to/WidevineCdm
EOFERR
    exit 1
fi

if [ -n "$COPY_TO" ]; then
    mkdir -p "$COPY_TO"
    rm -rf "$COPY_TO/WidevineCdm"
    cp -a "$CDM_DIR" "$COPY_TO/WidevineCdm"
    CDM_DIR="$COPY_TO/WidevineCdm"
    echo "Copied WidevineCdm to: $CDM_DIR"
fi

if [ -n "$INSTALL_DIR" ]; then
    if [ -e "$INSTALL_DIR/WidevineCdm" ]; then
        echo "Install-dir already has: $INSTALL_DIR/WidevineCdm"
    else
        ln -s "$CDM_DIR" "$INSTALL_DIR/WidevineCdm"
        echo "Linked: $INSTALL_DIR/WidevineCdm -> $CDM_DIR"
    fi
fi

if [ -z "$USER_DATA_DIRS" ]; then
    USER_DATA_DIRS="$(helium_widevine_user_data_dirs)"
fi

printf '%s
' "$USER_DATA_DIRS" | while IFS= read -r DIR; do
    [ -n "$DIR" ] || continue
    if helium_widevine_write_hint "$DIR" "$CDM_DIR"; then
        echo "Registered hint: $DIR/WidevineCdm/latest-component-updated-widevine-cdm"
    fi
done

cat <<EOFOK

Widevine registered for Helium.
Restart the browser completely, then test:
  chrome://components
  https://bitmovin.com/demos/drm
  https://www.netflix.com
EOFOK
