#!/usr/bin/env bash
# build.sh — Build the fed2-tools package.
#
# Derives version from git tags, reads muxlet_version from mfile, patches
# mfile and init.lua temporarily, runs muddle, then restores everything so
# committed values stay clean.
#
# Local builds always use the Muxlet prerelease URL (bare tag, no "v" prefix).
# Production builds (exact v* tag at HEAD, normally a CI scenario) use the
# v-prefixed production Muxlet URL.
#
# The Muxlet version is controlled solely by "muxlet_version" in mfile.
# To test against a different Muxlet build, change muxlet_version in mfile.
#
# When --profile is given, the Mudlet profile's connection files (url, port,
# login) are written in Mudlet's binary format so the profile connects to Fed2
# without any manual configuration. Pass --username to pre-fill the login field.
#
# Usage:
#   ./build.sh [--profile PROFILE] [--username NAME] [--mudlet-config PATH]
#
# Examples:
#   ./build.sh
#   ./build.sh --profile fed2-dev --username jackrungh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MFILE="$SCRIPT_DIR/mfile"
INIT_LUA="$SCRIPT_DIR/src/scripts/init.lua"
SRC_PACKAGE="$SCRIPT_DIR/build/fed2-tools.mpackage"

PROFILE="fed2-dev"
USERNAME=""
MUDLET_CONFIG=""
GAME_HOST="play.federation2.com"
GAME_PORT="30003"

# ── Parse arguments ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)       PROFILE="$2";       shift 2 ;;
        --username)      USERNAME="$2";      shift 2 ;;
        --mudlet-config) MUDLET_CONFIG="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

echo ""
echo "=== fed2-tools build ==="

# ── Read mfile ────────────────────────────────────────────────────────────────

BASE_VERSION="$(jq -r '.version' "$MFILE")"
if [[ -z "$BASE_VERSION" || "$BASE_VERSION" == "null" ]]; then
    echo "ERROR: mfile is missing 'version' field." >&2
    exit 1
fi

MUXLET_VERSION="$(jq -r '.muxlet_version' "$MFILE")"
if [[ -z "$MUXLET_VERSION" || "$MUXLET_VERSION" == "null" ]]; then
    echo "ERROR: mfile is missing 'muxlet_version' field." >&2
    exit 1
fi

# ── Derive version from mfile ─────────────────────────────────────────────────

EXACT_TAG="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
if [[ "$EXACT_TAG" == "v$BASE_VERSION" ]]; then
    VERSION="$BASE_VERSION"
    IS_RELEASE=true
else
    SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo "local")"
    VERSION="$BASE_VERSION-$SHORT_SHA"
    IS_RELEASE=false
fi

echo "Version       : $VERSION"

# ── Build Muxlet URL ──────────────────────────────────────────────────────────
# Local builds target the prerelease Muxlet (bare tag = no "v").
# IS_RELEASE=true only for an exact v* tag at HEAD; use the production URL.

if [[ "$IS_RELEASE" == true ]]; then
    MUXLET_TAG="v$MUXLET_VERSION"
else
    MUXLET_TAG="$MUXLET_VERSION"
fi
MUXLET_URL="https://github.com/tmtocloud/Muxlet/releases/download/$MUXLET_TAG/Muxlet.mpackage"

echo "Muxlet        : $MUXLET_VERSION  ($MUXLET_URL)"

# ── Patch mfile temporarily ───────────────────────────────────────────────────

ORIGINAL_MFILE="$(cat "$MFILE")"
PATCHED_MFILE="$(echo "$ORIGINAL_MFILE" | sed 's/"version":[[:space:]]*"[^"]*"/"version": "'"$VERSION"'"/')"
echo "$PATCHED_MFILE" > "$MFILE"
echo "mfile         : version set to $VERSION"

# ── Inject into init.lua temporarily ─────────────────────────────────────────

ORIGINAL_INIT="$(cat "$INIT_LUA")"

sed -i.bak \
    -e "s|local F2T_REQUIRED_MUXLET = nil|local F2T_REQUIRED_MUXLET = \"$MUXLET_VERSION\"|" \
    -e "s|local MUXLET_URL = nil|local MUXLET_URL = \"$MUXLET_URL\"|" \
    "$INIT_LUA"
echo "init.lua      : injected F2T_REQUIRED_MUXLET=$MUXLET_VERSION, MUXLET_URL"

# ── Run muddle ────────────────────────────────────────────────────────────────

restore_all() {
    echo "$ORIGINAL_MFILE" > "$MFILE"
    echo "mfile         : restored"
    echo "$ORIGINAL_INIT" > "$INIT_LUA"
    rm -f "$INIT_LUA.bak"
    echo "init.lua      : restored"
}
trap restore_all EXIT

muddle
echo "Output        : $SRC_PACKAGE"

restore_all
trap - EXIT

# ── Deploy to profile (optional) ─────────────────────────────────────────────

if [[ -z "$PROFILE" ]]; then
    echo ""
    exit 0
fi

echo ""
echo "=== Deploying to profile: $PROFILE ==="

# Write a value in Mudlet's binary profile format:
#   4-byte big-endian byte-length + UTF-16 BE string body.
write_mudlet_string() {
    local path="$1"
    local value="$2"
    python3 -c "
import sys, struct
v = sys.argv[1]
b = v.encode('utf-16-be') if v else b''
sys.stdout.buffer.write(struct.pack('>I', len(b)) + b)
" "$value" > "$path"
}

find_mudlet_config() {
    local xdg_path="${XDG_CONFIG_HOME:-$HOME/.config}/mudlet"
    [[ -d "$xdg_path/profiles" ]] && { echo "$xdg_path"; return; }

    local mac_path="$HOME/Library/Application Support/Mudlet"
    [[ -d "$mac_path/profiles" ]] && { echo "$mac_path"; return; }

    for user_dir in /mnt/c/Users/*/; do
        [[ -d "$user_dir" ]] || continue
        [[ -d "${user_dir}.config/mudlet/profiles" ]] && { echo "${user_dir}.config/mudlet"; return; }
        [[ -d "${user_dir}AppData/Roaming/Mudlet/profiles" ]] && { echo "${user_dir}AppData/Roaming/Mudlet"; return; }
    done
}

if [[ -z "$MUDLET_CONFIG" ]]; then
    MUDLET_CONFIG="$(find_mudlet_config || true)"
fi

if [[ -z "$MUDLET_CONFIG" ]]; then
    echo "ERROR: Could not find Mudlet config directory." >&2
    echo "Launch Mudlet at least once, or pass --mudlet-config explicitly." >&2
    exit 1
fi

echo "Mudlet config : $MUDLET_CONFIG"

PROFILE_DIR="$MUDLET_CONFIG/profiles/$PROFILE"
FIRST_TIME=0

if [[ ! -d "$PROFILE_DIR" ]]; then
    mkdir -p "$PROFILE_DIR"
    echo "Created profile: $PROFILE"
    FIRST_TIME=1
else
    echo "Profile       : $PROFILE"
fi

write_mudlet_string "$PROFILE_DIR/url"         "$GAME_HOST"
write_mudlet_string "$PROFILE_DIR/port"        "$GAME_PORT"
write_mudlet_string "$PROFILE_DIR/description" ""
if [[ -n "$USERNAME" ]]; then
    write_mudlet_string "$PROFILE_DIR/login" "$USERNAME"
fi
echo "Connection    : $GAME_HOST:$GAME_PORT${USERNAME:+ ($USERNAME)}"

if [[ ! -f "$SRC_PACKAGE" ]]; then
    echo "ERROR: build/fed2-tools.mpackage not found after build step." >&2
    exit 1
fi

DEST_PACKAGE="$PROFILE_DIR/fed2-tools.mpackage"
cp "$SRC_PACKAGE" "$DEST_PACKAGE"
echo "Deployed      : $DEST_PACKAGE"

STAMP_PATH="$PROFILE_DIR/fed2-tools-rebuild.stamp"
date +%s > "$STAMP_PATH"
echo "Stamp written : $STAMP_PATH"

echo ""

if [[ $FIRST_TIME -eq 1 ]]; then
    echo "FIRST-TIME SETUP:"
    echo "  1. Open Mudlet"
    echo "  2. Select profile: '$PROFILE'"
    if [[ -n "$USERNAME" ]]; then
        echo "  3. Enter password (username '$USERNAME' pre-filled), connect"
    else
        echo "  3. Enter username + password, connect"
    fi
    echo "  4. Toolbox -> Package Manager -> Install from file:"
    echo "     $DEST_PACKAGE"
    echo ""
    echo "After this one-time install, fed2-tools reloads automatically on each build."
    echo ""
fi

echo "WORKFLOW:"
echo "  ./build.sh --profile $PROFILE"
echo "  fed2-tools auto-reloads within ~30 seconds via the dev stamp watcher."
echo ""
