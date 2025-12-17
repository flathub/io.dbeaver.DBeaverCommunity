#!/bin/bash

# Define state files
STATE_DIR="${XDG_DATA_HOME}/dbeaver-community"
HASH_FILE="${STATE_DIR}/osgi_bundle.sha256"
VERSION_FILE="${STATE_DIR}/last_VERSION"

# Ensure the directory exists
mkdir -p "$STATE_DIR"

# --- STEP 1: Calculate Current State ---

# Get the robust Hash (The decision maker)
# We specifically target the OSGi kernel jar because its change triggers the error.
SYSTEM_BUNDLE=$(ls /app/bin/plugins/org.eclipse.osgi_*.jar 2>/dev/null | head -n 1)
if [ -f "$SYSTEM_BUNDLE" ]; then
    CURRENT_HASH=$(sha256sum "$SYSTEM_BUNDLE" | cut -d " " -f 1)
else
    # Fallback only if the file structure changes drastically in the future
    CURRENT_HASH="unknown"
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

    echo "System Bundle change detected ($OLD_VERSION -> $CURRENT_VERSION). Cleaning OSGi cache..."
    ARGS+=("-clean")
    
    # Update state files so we don't clean next time
    echo "$CURRENT_HASH" > "$HASH_FILE"
    echo "$CURRENT_VERSION" > "$VERSION_FILE"
fi

# --- STEP 3: Launch ---
exec /app/bin/dbeaver "${ARGS[@]}"