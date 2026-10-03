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

# java_prop NAME VALUE: add -DNAME=VALUE to JAVA_TOOL_OPTIONS. The JVM splits that variable on
# spaces, so the value is quoted (the JVM strips the quotes); a value containing a double quote
# can't be passed safely, so it is refused (returns 1).
java_prop() {
    [[ "$2" == *\"* ]] && return 1
    export JAVA_TOOL_OPTIONS="-D$1=\"$2\" ${JAVA_TOOL_OPTIONS:-}"
}

# --- Keep DBeaver's files in the app's own Flatpak folder (issue #316, phase 1) ---

# DBeaver reads XDG_DATA_HOME as a Java property (not the env var), so its data ends up in
# ~/.local/share/DBeaverData; Eclipse puts its configuration and user-installed plugins in
# ~/.eclipse because /app/bin is read-only. Point both into ~/.var/app instead. Existing data
# is copied (never moved, so older builds keep working) with absolute paths rewritten. If the
# copy can't be done we keep using the old locations: never start on an empty folder.
NEW_DATA="${XDG_DATA_HOME}/DBeaverData"
NEW_CONFIG="${XDG_CONFIG_HOME}/eclipse"
OLD_DATA="${HOME}/.local/share/DBeaverData"
# DBeaver before 6.1.3 used .DBeaverData and still falls back to it (dbeaver#6316)
[ ! -e "$OLD_DATA" ] && [ -d "${HOME}/.local/share/.DBeaverData" ] && OLD_DATA="${HOME}/.local/share/.DBeaverData"
# Eclipse names this folder after hashCode("/app/bin"): the same for every Flatpak install, and
# different from any non-Flatpak Eclipse or DBeaver, whose folders must not be picked up.
OLD_CONFIG="${HOME}/.eclipse/487352054_linux_gtk_$(uname -m)"
FAIL_FILE="${STATE_DIR}/migrate.failed"

OLDS=("$OLD_DATA" "$OLD_CONFIG")
NEWS=("$NEW_DATA" "$NEW_CONFIG")

# rewrite_paths DIR: in DIR's text and gzip'ed files, replace every old location with its new
# one (Eclipse and p2 store absolute paths, and the configuration refers to the data folder).
# Every spelling of the home folder is covered (Silverblue: /home/u is a symlink to /var/home/u),
# also %20-encoded, and only whole path names match (DBeaverData2 is left alone).
rewrite_paths() {
    # sed delimiter: a control character, so "|" keeps its meaning (alternation) in the pattern
    local dir="$1" script="" patterns=() homes=("$HOME") real i h old new f D=$'\001'
    real=$(readlink -f "$HOME"); [ "$real" != "$HOME" ] && homes+=("$real")
    # Silverblue & co.: /home is a symlink to /var/home and files may use either spelling. The
    # sandbox can't resolve that link, so map the prefix by convention.
    for h in "$HOME" "$real"; do
        case "$h" in */var/home/*) homes+=("${h%%/var/home/*}/home/${h#*/var/home/}") ;; esac
    done
    for i in "${!OLDS[@]}"; do
        for h in "${homes[@]}"; do
            old="${h}${OLDS[$i]#"$HOME"}"; new="${NEWS[$i]}"
            for enc in no yes; do
                if [ "$enc" = yes ]; then
                    [[ "$old$new" == *" "* ]] || continue
                    old="${old// /%20}"; new="${new// /%20}"
                fi
                patterns+=(-e "$old/")
                script+="s${D}$(printf '%s' "$old" | sed 's/[]\/$*.^[]/\\&/g')\\([^A-Za-z0-9._-]\\|\$\\)${D}$(printf '%s' "$new" | sed 's/[\/&]/\\&/g')\\1${D}g;"
            done
        done
    done
    grep -rlIZF "${patterns[@]}" -- "$dir" | xargs -0r sed -i "$script" || return 1
    while IFS= read -r -d '' f; do
        zcat "$f" | sed "$script" | gzip > "${f}.new" && mv -f "${f}.new" "$f" || return 1
    done < <(find "$dir" -name '*.gz' -print0)
    # Never use a copy that still points into the old folders (a spelling we don't know)
    if grep -rlIF "${patterns[@]}" -- "$dir" >&2; then
        echo "Old paths left in the files above." >&2
        return 1
    fi
}

USE_NEW_DIRS=yes
if [ -n "${DBEAVER_DATA:-}" ] || [[ "$XDG_DATA_HOME" == *\"* ]]; then
    USE_NEW_DIRS=no  # the user chose their own data folder, or the path can't be passed to Java
else {
    flock 9  # two windows started at once must not copy twice
    # Copy only what exists in the old place and was not migrated yet (fresh installs skip this)
    PENDING=(); UNREADABLE=no
    for i in "${!OLDS[@]}"; do
        [ -e "${NEWS[$i]}" ] && continue
        # An old folder that exists but can't be read here (e.g. a symlink to a place the sandbox
        # can't see) must not be replaced by an empty new one
        if { [ -L "${OLDS[$i]}" ] && [ ! -d "${OLDS[$i]}" ]; } || { [ -d "${OLDS[$i]}" ] && [ ! -r "${OLDS[$i]}" ]; }; then
            UNREADABLE=yes
        elif [ -d "${OLDS[$i]}" ]; then
            PENDING+=("$i")
        fi
    done
    SRCS=(); for i in "${PENDING[@]}"; do SRCS+=("${OLDS[$i]}/."); done
    if [ "$UNREADABLE" = yes ]; then
        echo "DBeaver's old files exist but can't be read inside the Flatpak; keeping the old locations." >&2
        USE_NEW_DIRS=no
    elif [ ${#PENDING[@]} -gt 0 ] && [ "$(cat "$FAIL_FILE" 2>/dev/null)" = "$CURRENT_HASH" ]; then
        USE_NEW_DIRS=no  # failed with this version already; try again after the next update
    elif [ ${#PENDING[@]} -gt 0 ]; then
        # Never fill the disk: need the size of the old folders plus 10% free
        need=$(du -sk "${SRCS[@]}" | awk '{ s += $1 } END { print int(s * 1.1) }')
        avail=$(df -Pk "$XDG_DATA_HOME" | awk 'NR == 2 { print $4 }')
        ok=yes
        if [ "$need" -gt "${avail:-0}" ]; then
            echo "Not enough free space to copy DBeaver's files (${need} KiB needed, ${avail} KiB free)." >&2
            ok=no
        else
            [ "$need" -gt 102400 ] && notify-send --app-name="DBeaver" "DBeaver" \
                "Moving DBeaver's files into its Flatpak folder. This first start may take a while." 2>/dev/null
            # All or nothing: rename the copies into place only if every copy succeeded, so
            # DBeaver never runs on a mix of old and new folders. "OLD/." copies the folder's
            # contents, also when OLD is a symlink (the link's target is never modified).
            for i in "${PENDING[@]}"; do
                rm -rf "${NEWS[$i]}.tmp"
                mkdir -p "$(dirname "${NEWS[$i]}")" &&
                    cp -a --reflink=auto "${OLDS[$i]}/." "${NEWS[$i]}.tmp" &&
                    rewrite_paths "${NEWS[$i]}.tmp" || { ok=no; break; }
            done
        fi
        for i in "${PENDING[@]}"; do
            if [ "$ok" = yes ]; then
                mv "${NEWS[$i]}.tmp" "${NEWS[$i]}" && echo "Copied ${OLDS[$i]} to ${NEWS[$i]}"
            else
                rm -rf "${NEWS[$i]}.tmp"
            fi
        done
        if [ "$ok" = yes ]; then
            rm -f "$FAIL_FILE"
            ARGS+=("-clean")  # cached bundle locations point at the old copy
        else
            echo "Could not copy DBeaver's files into the Flatpak folder; keeping the old locations." >&2
            echo "$CURRENT_HASH" > "$FAIL_FILE"
            USE_NEW_DIRS=no
        fi
    fi
} 9>"${STATE_DIR}/migrate.lock"
fi

if [ "$USE_NEW_DIRS" = yes ]; then
    java_prop XDG_DATA_HOME "$XDG_DATA_HOME"
    ARGS=("-configuration" "${NEW_CONFIG}/configuration" "${ARGS[@]}")
    CONFIG_AREA="${NEW_CONFIG}/configuration"
else
    CONFIG_AREA="${OLD_CONFIG}/configuration"
fi

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
CONFIG_AREA="${CONFIG_AREA:-${HOME}/.eclipse/487352054_linux_gtk_$(uname -m)/configuration}"  # Phase 1 sets the moved one
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
    java_prop javax.net.ssl.trustStore "$TRUSTSTORE"
else
    rm -f "${TRUSTSTORE}.tmp"
fi

# --- STEP 4: Launch ---
exec /app/bin/dbeaver "${ARGS[@]}"