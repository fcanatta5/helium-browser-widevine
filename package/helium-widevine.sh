#!/bin/sh
# Runtime Widevine registration helper for Helium on Linux.
# This script intentionally does not download or bundle Google's proprietary
# Widevine CDM. It only registers a WidevineCdm directory that already exists
# on the user's system, e.g. from Google Chrome, distro packages, or a local
# copy supplied by the user.

helium_widevine_log() {
    if [ "${HELIUM_WIDEVINE_DEBUG:-0}" = 1 ]; then
        printf '[helium-widevine] %s\n' "$*" >&2
    fi
}

helium_widevine_escape_json_path() {
    # Escape backslashes and double quotes for the tiny JSON hint file.
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

helium_widevine_platform_dir() {
    case "$(uname -m 2>/dev/null)" in
        x86_64|amd64) printf '%s\n' 'linux_x64' ;;
        aarch64|arm64) printf '%s\n' 'linux_arm64' ;;
        armv7l|armhf) printf '%s\n' 'linux_arm' ;;
        *) printf '%s\n' "linux_$(uname -m 2>/dev/null)" ;;
    esac
}

helium_widevine_is_valid_dir() {
    _wv_dir="$1"
    _wv_platform="${2:-$(helium_widevine_platform_dir)}"

    [ -n "$_wv_dir" ] || return 1
    [ -f "$_wv_dir/manifest.json" ] || return 1
    [ -f "$_wv_dir/_platform_specific/$_wv_platform/libwidevinecdm.so" ] || return 1
}

helium_widevine_find_dir() {
    _wv_platform="$(helium_widevine_platform_dir)"

    if [ -n "${HELIUM_WIDEVINE_DIR:-}" ] && helium_widevine_is_valid_dir "$HELIUM_WIDEVINE_DIR" "$_wv_platform"; then
        printf '%s\n' "$HELIUM_WIDEVINE_DIR"
        return 0
    fi

    for _wv_dir in \
        "${HELIUM_INSTALL_DIR:-}/WidevineCdm" \
        "${XDG_DATA_HOME:-$HOME/.local/share}/helium/WidevineCdm" \
        "$HOME/.local/share/helium/WidevineCdm" \
        "/opt/google/chrome/WidevineCdm" \
        "/opt/google/chrome-beta/WidevineCdm" \
        "/opt/google/chrome-unstable/WidevineCdm" \
        "/opt/microsoft/msedge/WidevineCdm" \
        "/opt/brave.com/brave/WidevineCdm" \
        "/opt/vivaldi/WidevineCdm" \
        "/usr/lib/chromium/WidevineCdm" \
        "/usr/lib/chromium-browser/WidevineCdm" \
        "/usr/lib/ungoogled-chromium/WidevineCdm" \
        "/usr/lib64/chromium/WidevineCdm" \
        "/usr/local/lib/WidevineCdm" \
        "/usr/local/share/chromium/WidevineCdm"
    do
        if helium_widevine_is_valid_dir "$_wv_dir" "$_wv_platform"; then
            printf '%s\n' "$_wv_dir"
            return 0
        fi
    done

    return 1
}

helium_widevine_user_data_dirs() {
    _wv_next_is_user_data=0
    for _wv_arg in "$@"; do
        if [ "$_wv_next_is_user_data" = 1 ]; then
            printf '%s\n' "$_wv_arg"
            _wv_next_is_user_data=0
            continue
        fi

        case "$_wv_arg" in
            --user-data-dir=*) printf '%s\n' "${_wv_arg#--user-data-dir=}" ;;
            --user-data-dir) _wv_next_is_user_data=1 ;;
        esac
    done

    if [ -n "${HELIUM_USER_DATA_DIR:-}" ]; then
        printf '%s\n' "$HELIUM_USER_DATA_DIR"
    fi

    # Helium has changed branding/name-substitution paths across builds; write
    # harmless hints to the common candidates so the active user data dir can
    # pick it up at next browser start.
    printf '%s\n' \
        "${XDG_CONFIG_HOME:-$HOME/.config}/helium" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/Helium" \
        "${XDG_CONFIG_HOME:-$HOME/.config}/net.imput.helium"
}

helium_widevine_write_hint() {
    _wv_user_data_dir="$1"
    _wv_cdm_dir="$2"

    [ -n "$_wv_user_data_dir" ] || return 1
    [ -n "$_wv_cdm_dir" ] || return 1

    _wv_hint_dir="$_wv_user_data_dir/WidevineCdm"
    _wv_hint_file="$_wv_hint_dir/latest-component-updated-widevine-cdm"
    _wv_escaped_path="$(helium_widevine_escape_json_path "$_wv_cdm_dir")"

    mkdir -p "$_wv_hint_dir" 2>/dev/null || return 1
    printf '{"Path":"%s"}\n' "$_wv_escaped_path" > "$_wv_hint_file" 2>/dev/null || return 1
    helium_widevine_log "hint: $_wv_hint_file -> $_wv_cdm_dir"
}

helium_widevine_try_install_symlink() {
    _wv_install_dir="$1"
    _wv_cdm_dir="$2"

    [ -n "$_wv_install_dir" ] || return 1
    [ -n "$_wv_cdm_dir" ] || return 1
    [ -w "$_wv_install_dir" ] || return 1
    [ ! -e "$_wv_install_dir/WidevineCdm" ] || return 0

    ln -s "$_wv_cdm_dir" "$_wv_install_dir/WidevineCdm" 2>/dev/null || return 1
    helium_widevine_log "install symlink: $_wv_install_dir/WidevineCdm -> $_wv_cdm_dir"
}

helium_widevine_prepare() {
    if [ "${HELIUM_WIDEVINE_DISABLE:-0}" = 1 ]; then
        helium_widevine_log 'disabled by HELIUM_WIDEVINE_DISABLE=1'
        return 0
    fi

    _wv_install_dir="$1"
    shift || true

    HELIUM_INSTALL_DIR="$_wv_install_dir"
    export HELIUM_INSTALL_DIR

    _wv_cdm_dir="$(helium_widevine_find_dir 2>/dev/null || true)"
    if [ -z "$_wv_cdm_dir" ]; then
        helium_widevine_log 'no valid WidevineCdm directory found'
        return 0
    fi

    # Prefer a direct install-directory WidevineCdm symlink when possible.
    # If the install directory is read-only, the user-data hint file below is
    # enough for modern Chromium Linux builds.
    helium_widevine_try_install_symlink "$_wv_install_dir" "$_wv_cdm_dir" || true

    helium_widevine_user_data_dirs "$@" | while IFS= read -r _wv_user_data_dir; do
        helium_widevine_write_hint "$_wv_user_data_dir" "$_wv_cdm_dir" || true
    done
}
