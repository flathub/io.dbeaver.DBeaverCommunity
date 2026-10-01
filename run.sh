#!/bin/bash

# Define state files
STATE_DIR="${XDG_DATA_HOME}/dbeaver-community"
HASH_FILE="${STATE_DIR}/osgi_bundle.sha256"
VERSION_FILE="${STATE_DIR}/last_VERSION"

# Ensure the directory exists
mkdir -p "$STATE_DIR"

# --- STEP 1: Calculate Current State ---

# The decision maker: the Flatpak app commit, which changes on every update.
# Flatpak sets every file mtime in /app to 1970, so Equinox cannot see that a bundle
# changed when its version stays the same (e.g. sshj jars, issue #318) and keeps a
# stale cache. Cleaning once per app commit covers that and OSGi updates (#336).
# (State file keeps its old name so existing installs don't leave an orphan behind.)
CURRENT_HASH=$(sed -n 's/^app-commit=//p' /.flatpak-info 2>/dev/null)
if [ -z "$CURRENT_HASH" ]; then
    # Not running inside Flatpak: never matches, so we clean every start (safe, just slower)
    CURRENT_HASH="unknown-$(date +%s)"
fi

# Get the Human-Readable Version (For the log message ONLY)
# Extracts "25.3.0" from "org.jkiss.dbeaver.ce.feature_25.3.0.2025..."
VERSION_DIR=$(ls -d /app/bin/features/org.jkiss.dbeaver.ce.feature_* 2>/dev/null | head -n 1)
if [ -n "$VERSION_DIR" ]; then
    DIR_NAME=$(basename "$VERSION_DIR")
    # Extract version between "feature_" and the last dot
    CURRENT_VERSION=$(echo "$DIR_NAME" | sed -n 's/.*feature_\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p')
fi

# Cosmetic Fallback: If parsing failed, just use "unknown" so the script doesn't crash
if [ -z "$CURRENT_VERSION" ]; then
    CURRENT_VERSION="unknown"
fi

ARGS=("$@")

# --- STEP 2: Compare and Clean ---

# We check the HASH to decide if we need to clean. This is the safety mechanism.
if [ ! -f "$HASH_FILE" ] || [ "$(cat "$HASH_FILE")" != "$CURRENT_HASH" ]; then
    
    # Retrieve the OLD human version just for the log message
    if [ -f "$VERSION_FILE" ]; then
        OLD_VERSION=$(cat "$VERSION_FILE")
    else
        OLD_VERSION="fresh-install"
    fi

    echo "App update detected ($OLD_VERSION -> $CURRENT_VERSION). Cleaning OSGi cache..."
    ARGS+=("-clean")
    
    # Update state files so we don't clean next time
    echo "$CURRENT_HASH" > "$HASH_FILE"
    echo "$CURRENT_VERSION" > "$VERSION_FILE"
fi

# --- STEP 3: Launch ---
exec /app/bin/dbeaver "${ARGS[@]}"