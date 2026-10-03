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

# --- Keep user-installed plugins working across updates ---

# Eclipse keeps the user's configuration in ~/.eclipse/<hash>_linux_gtk_<arch>, named after
# hashCode("/app/bin"): the same for every Flatpak install. Two problems after every update:
# - Eclipse ignores the user's plugin list (bundles.info) once the base install's list looks
#   changed. Flatpak sets every mtime to 0, so Eclipse compares its ctime instead, which changes
#   on every update (and reinstall): all user-installed plugins vanished after each update.
# - Installing a plugin also writes a full config.ini there, naming that DBeaver version's OSGi
#   framework jar; after a version update the jar is gone and DBeaver doesn't start at all
#   (ClassNotFoundException: EclipseStarter).
# When the base list changes, rebuild the user's list as the new base list plus the user's own
# plugins (base entries the new version no longer ships are dropped), remove Eclipse's stale
# timestamp so it uses that list, and replace config.ini (it holds no user settings).
CONFIG_AREA="${HOME}/.eclipse/487352054_linux_gtk_$(uname -m)/configuration"
SC_DIR="${CONFIG_AREA}/org.eclipse.equinox.simpleconfigurator"
BASE_LIST=/app/bin/configuration/org.eclipse.equinox.simpleconfigurator/bundles.info
BASE_STAMP=$(stat -c %Z "$BASE_LIST" 2>/dev/null)
if [ -f "${SC_DIR}/bundles.info" ] && [ "$BASE_STAMP" != "$(cat "${STATE_DIR}/base_bundles.ctime" 2>/dev/null)" ]; then
    # User entries: not in the base list and not pointing into the base install (plugins/...)
    if { cat "$BASE_LIST"; awk -F, 'NR == FNR { base[$1] = 1; next }
             !/^#/ && !($1 in base) && $3 !~ /^plugins\// { print }' "$BASE_LIST" "${SC_DIR}/bundles.info"; } \
           > "${SC_DIR}/bundles.info.new" && mv -f "${SC_DIR}/bundles.info.new" "${SC_DIR}/bundles.info"; then
        rm -f "${SC_DIR}/.baseBundlesInfoTimestamp"
        [ -f "${CONFIG_AREA}/config.ini" ] && cp -f /app/bin/configuration/config.ini "${CONFIG_AREA}/config.ini"
        echo "$BASE_STAMP" > "${STATE_DIR}/base_bundles.ctime"
        echo "Kept user-installed plugins across the update"
    else
        rm -f "${SC_DIR}/bundles.info.new"
    fi
elif [ -n "$BASE_STAMP" ]; then
    echo "$BASE_STAMP" > "${STATE_DIR}/base_bundles.ctime"
fi

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

# --- STEP 3: Trust the host's CA certificates (issue #1) ---

# The bundled JDK only trusts its own cacerts. Flatpak forwards the host trust store
# into the sandbox via p11-kit, so merge the host's server-auth anchors into a copy of
# the JDK store. Additive only: JDK entries win on alias clashes. On any failure the
# JDK default is used, as before. A user -vmargs -Djavax.net.ssl.trustStore still wins.
TRUST_DIR="${XDG_CACHE_HOME}/dbeaver-community"
TRUSTSTORE="${TRUST_DIR}/cacerts"
mkdir -p "$TRUST_DIR"
if trust extract --overwrite --format=java-cacerts --filter=ca-anchors --purpose=server-auth "${TRUSTSTORE}.tmp" 2>/dev/null &&
   chmod u+w "${TRUSTSTORE}.tmp" &&
   /app/jre/bin/keytool -importkeystore -noprompt -srckeystore /app/jre/lib/security/cacerts -srcstorepass changeit \
       -destkeystore "${TRUSTSTORE}.tmp" -deststorepass changeit >/dev/null 2>&1; then
    mv -f "${TRUSTSTORE}.tmp" "$TRUSTSTORE"
    export JAVA_TOOL_OPTIONS="-Djavax.net.ssl.trustStore=${TRUSTSTORE} ${JAVA_TOOL_OPTIONS:-}"
else
    rm -f "${TRUSTSTORE}.tmp"
fi

# --- STEP 4: Launch ---
exec /app/bin/dbeaver "${ARGS[@]}"