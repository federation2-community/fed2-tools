#!/usr/bin/env bash
# build.sh — Build the fed2-tools package.
#
# Derives version from git tags, patches mfile, runs muddle, then restores
# mfile so the committed value stays clean.
#
#   Release build (exact git tag at HEAD): version = "0.2.0"
#   Dev build (no exact tag):             version = "0.2.0-a3f91cd"
#
# Pass --muxlet-tag to override where Muxlet is installed from.  The override
# is injected into the build copy of init.lua only — the source file is never
# modified.  Omit --muxlet-tag to use the Mudlet Package Repository (default).
#
# Works in WSL, native Linux, and macOS.
#
# Usage:
#   ./build.sh [--profile PROFILE] [--muxlet-tag TAG] [--mudlet-config PATH]
#
# Examples:
#   ./build.sh
#   ./build.sh --profile fed2-dev
#   ./build.sh --muxlet-tag 1.0.6 --profile fed2-dev

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MFILE="$SCRIPT_DIR/mfile"
INIT_LUA="$SCRIPT_DIR/src/scripts/init.lua"
SRC_PACKAGE="$SCRIPT_DIR/build/fed2-tools.mpackage"

PROFILE=""
MUXLET_TAG=""
MUDLET_CONFIG=""

# ── Parse arguments ───────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile)       PROFILE="$2";       shift 2 ;;
        --muxlet-tag)    MUXLET_TAG="$2";    shift 2 ;;
        --mudlet-config) MUDLET_CONFIG="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

echo ""
echo "=== fed2-tools build ==="

# ── Derive version from git ───────────────────────────────────────────────────

EXACT_TAG="$(git describe --tags --exact-match HEAD 2>/dev/null || true)"
if [[ "$EXACT_TAG" =~ ^v(.+)$ ]]; then
    VERSION="${BASH_REMATCH[1]}"
else
    LAST_TAG="$(git describe --tags --match "v*" --abbrev=0 2>/dev/null || echo "v0.0.0")"
    BASE_VERSION="${LAST_TAG#v}"
    SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
    VERSION="$BASE_VERSION-$SHORT_SHA"
fi

echo "Version       : $VERSION"

# ── Patch mfile temporarily ───────────────────────────────────────────────────

ORIGINAL_MFILE="$(cat "$MFILE")"
PATCHED_MFILE="$(echo "$ORIGINAL_MFILE" | sed 's/"version":[[:space:]]*"[^"]*"/"version": "'"$VERSION"'"/')"
echo "$PATCHED_MFILE" > "$MFILE"
echo "mfile         : version set to $VERSION"

# ── Optionally inject Muxlet dev URL into init.lua ───────────────────────────

ORIGINAL_INIT="$(cat "$INIT_LUA")"
INIT_PATCHED=0

if [[ -n "$MUXLET_TAG" ]]; then
    DEV_URL="https://github.com/tmtocloud/Muxlet/releases/download/$MUXLET_TAG/Muxlet.mpackage"
    sed -i.bak "s|local MUXLET_DEV_URL = nil|local MUXLET_DEV_URL = \"$DEV_URL\"|" "$INIT_LUA"
    INIT_PATCHED=1
    echo "Muxlet URL    : $DEV_URL"
else
    echo "Muxlet source : MPR (default)"
fi

# ── Run muddle ────────────────────────────────────────────────────────────────

restore_all() {
    echo "$ORIGINAL_MFILE" > "$MFILE"
    echo "mfile         : restored"
    if [[ $INIT_PATCHED -eq 1 ]]; then
        echo "$ORIGINAL_INIT" > "$INIT_LUA"
        rm -f "$INIT_LUA.bak"
        echo "init.lua      : restored"
    fi
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
    echo "  3. Toolbox -> Package Manager -> Install from file:"
    echo "     $DEST_PACKAGE"
    echo ""
    echo "After this one-time install, fed2-tools loads automatically."
    echo ""
fi

echo "WORKFLOW:"
echo "  ./build.sh --profile $PROFILE"
echo "  Reinstall the package in Mudlet to pick up changes."
echo ""
