#!/bin/bash
# Self-check for run.sh's migration block ("Keep DBeaver's files in the app's own Flatpak folder").
# The plugin block has its own check: .github/test_run_plugins.sh. Runs the real code against fake
# home folders. Usage: .github/test_run_migrate.sh [run.sh]
RUN_SH=${1:-run.sh}
BLOCK=$(sed -n '/^# java_prop NAME VALUE/,/--- Keep user-installed plugins/p' "$RUN_SH")
[[ "$BLOCK" == *"Keep DBeaver's files"* ]] || { echo "migration block not found in $RUN_SH"; exit 1; }
ROOT=$(mktemp -d); trap 'chmod -R u+rwx "$ROOT"; rm -rf "$ROOT"' EXIT
fail=0; check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }
ARCH=$(uname -m); HASH=487352054; CURRENT_HASH=commit-1
notify-send() { :; }   # no desktop pop-ups from the test

setup() {  # $1 = home path; creates an "old layout" install (+ a decoy non-Flatpak Eclipse folder)
    HOME=$1; export HOME
    XDG_DATA_HOME="$HOME/.var/app/x/data"; XDG_CONFIG_HOME="$HOME/.var/app/x/config"; STATE_DIR="$XDG_DATA_HOME/dbeaver-community"
    local cfg="$HOME/.eclipse/${HASH}_linux_gtk_$ARCH" d="$HOME/.local/share/DBeaverData"
    mkdir -p "$STATE_DIR" "$d/workspace6/General" "$cfg/configuration/.settings" "$cfg/p2/profile"
    echo "RECENT_WORKSPACES=$HOME/.local/share/DBeaverData/workspace6" > "$cfg/configuration/.settings/ide.prefs"
    echo "lib=$d/drivers/x.jar" > "$d/workspace6/General/data-sources.json"
    echo "backup=$d""2/old.zip" >> "$d/workspace6/General/data-sources.json"
    echo "<bundle location='file:$cfg/plugins/vrapper.jar'/>" | gzip > "$cfg/p2/profile/1.profile.gz"
    printf 'BIN\0%s\0' "$d" > "$d/workspace6/blob.bin"
    mkdir -p "$HOME/.eclipse/999_linux_gtk_$ARCH/configuration"; touch "$HOME/.eclipse/999_linux_gtk_$ARCH/configuration/DECOY"
}
run_block() { ARGS=(); JAVA_TOOL_OPTIONS=; eval "$BLOCK" >/dev/null 2>&1; }
NEWD() { echo "$XDG_DATA_HOME/DBeaverData"; }; NEWC() { echo "$XDG_CONFIG_HOME/eclipse"; }
snapshot() { (cd "$HOME" && find -L .local .eclipse -type f -exec md5sum {} + | sort); }

for H in "$ROOT/plain" "$ROOT/we ird & home|x"; do
    echo "== HOME='$H'"
    setup "$H"; OLD=$(snapshot)
    run_block
    check "switched to new dirs"            '[ "$USE_NEW_DIRS" = yes ] && [ "${ARGS[1]}" = "$(NEWC)/configuration" ]'
    check "Java property quoted"            '[[ "$JAVA_TOOL_OPTIONS" == *"-DXDG_DATA_HOME=\"$XDG_DATA_HOME\""* ]]'
    check "data and Flatpak config copied"  '[ -f "$(NEWD)/workspace6/General/data-sources.json" ] && [ -d "$(NEWC)/configuration" ]'
    check "decoy Eclipse folder not copied" '[ ! -e "$(NEWC)/configuration/DECOY" ]'
    check "-clean after copying"            '[[ " ${ARGS[*]} " == *" -clean "* ]]'
    check "text paths rewritten"            'grep -q "lib=$(NEWD)/drivers" "$(NEWD)/workspace6/General/data-sources.json" && grep -q "=$(NEWD)/workspace6" "$(NEWC)/configuration/.settings/ide.prefs"'
    check "DBeaverData2 sibling untouched"  'grep -qF "backup=$HOME/.local/share/DBeaverData2/old.zip" "$(NEWD)/workspace6/General/data-sources.json"'
    check "gzip paths rewritten"            'zcat "$(NEWC)/p2/profile/1.profile.gz" | grep -q "file:$(NEWC)/plugins/vrapper.jar"'
    check "binary file left byte-identical" 'cmp -s "$HOME/.local/share/DBeaverData/workspace6/blob.bin" "$(NEWD)/workspace6/blob.bin"'
    check "no old paths left in text"       '! grep -rIqF -e "$HOME/.local/share/DBeaverData/" -e "$HOME/.eclipse" "$(NEWD)" "$(NEWC)"'
    check "old data untouched"              '[ "$(snapshot)" = "$OLD" ]'
    check "no .tmp left"                    '! ls -d "$(NEWD).tmp" "$(NEWC).tmp" 2>/dev/null'
    run_block
    check "second start: no copy, no clean" '[ "$USE_NEW_DIRS" = yes ] && [[ " ${ARGS[*]} " != *" -clean "* ]]'
done

echo "== fresh install (no old folders)"
HOME="$ROOT/fresh"; mkdir -p "$HOME"; XDG_DATA_HOME="$HOME/d"; XDG_CONFIG_HOME="$HOME/c"; STATE_DIR="$XDG_DATA_HOME/s"; mkdir -p "$STATE_DIR"
run_block
check "uses new dirs, copies nothing"   '[ "$USE_NEW_DIRS" = yes ] && [ ! -e "$(NEWD)" ] && [ ! -e "$(NEWC)" ] && [[ " ${ARGS[*]} " != *" -clean "* ]]'

echo "== old data folder is a symlink (moved to another disk)"
setup "$ROOT/link"; mkdir -p "$ROOT/otherdisk"; mv "$HOME/.local/share/DBeaverData" "$ROOT/otherdisk/DBeaverData"
ln -s "$ROOT/otherdisk/DBeaverData" "$HOME/.local/share/DBeaverData"
ORIG=$(cd "$ROOT/otherdisk" && find . -type f -exec md5sum {} + | sort)
run_block
check "contents copied, not the link"   '[ -d "$(NEWD)" ] && [ ! -L "$(NEWD)" ] && [ -f "$(NEWD)/workspace6/General/data-sources.json" ]'
check "link target not modified"        '[ "$(cd "$ROOT/otherdisk" && find . -type f -exec md5sum {} + | sort)" = "$ORIG" ]'
check "copy rewritten"                  'grep -q "lib=$(NEWD)/drivers" "$(NEWD)/workspace6/General/data-sources.json"'

echo "== legacy .DBeaverData only (DBeaver before 6.1.3)"
setup "$ROOT/legacy"; mv "$HOME/.local/share/DBeaverData" "$HOME/.local/share/.DBeaverData"
grep -rlF "/.local/share/DBeaverData" "$HOME/.local/share/.DBeaverData" "$HOME/.eclipse" | xargs sed -i 's|/\.local/share/DBeaverData|/.local/share/.DBeaverData|g'
run_block
check "legacy data copied"              '[ -f "$(NEWD)/workspace6/General/data-sources.json" ]'
check "legacy paths rewritten"          'grep -q "lib=$(NEWD)/drivers" "$(NEWD)/workspace6/General/data-sources.json" && ! grep -rqF ".DBeaverData/" "$(NEWD)" "$(NEWC)"'

echo "== Silverblue: /home/u is a symlink to /var/home/u, files use both spellings"
mkdir -p "$ROOT/sb/var/home/u" "$ROOT/sb/home"; ln -s "$ROOT/sb/var/home/u" "$ROOT/sb/home/u"
setup "$ROOT/sb/home/u"   # HOME given in the symlink spelling
REAL="$ROOT/sb/var/home/u"
echo "script=$REAL/.local/share/DBeaverData/workspace6/a.sql" >> "$HOME/.local/share/DBeaverData/workspace6/General/data-sources.json"
run_block
check "both spellings rewritten"        '! grep -qF -e "$HOME/.local/share/DBeaverData/" -e "$REAL/.local/share/DBeaverData/" "$(NEWD)/workspace6/General/data-sources.json"'

echo "== Silverblue inside the sandbox: home is .../var/home/u, /home is NOT resolvable"
setup "$ROOT/sb2/var/home/u"   # no /home symlink exists here, like inside the Flatpak sandbox
echo "x=$ROOT/sb2/home/u/.local/share/DBeaverData/workspace6/a.sql" >> "$HOME/.local/share/DBeaverData/workspace6/General/data-sources.json"
run_block
check "/home/u spelling rewritten"      'grep -qF "x=$(NEWD)/workspace6/a.sql" "$(NEWD)/workspace6/General/data-sources.json"'

echo "== %20-encoded paths (home with a space)"
setup "$ROOT/sp ace"; echo "uri=file:${HOME// /%20}/.local/share/DBeaverData/workspace6/x" >> "$HOME/.local/share/DBeaverData/workspace6/General/data-sources.json"
run_block
check "encoded path rewritten"          'grep -qF "uri=file:$(NEWD | sed "s/ /%20/g")/workspace6/x" "$(NEWD)/workspace6/General/data-sources.json"'

echo "== not enough free space"
setup "$ROOT/full"; df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfake 100 99 1 99%% /\n'; }
run_block
check "keeps old locations, no copy"    '[ "$USE_NEW_DIRS" = no ] && [ ! -e "$(NEWD)" ] && [ -z "$JAVA_TOOL_OPTIONS" ] && [ ${#ARGS[@]} -eq 0 ]'
check "failure remembered"              '[ "$(cat "$STATE_DIR/migrate.failed")" = "$CURRENT_HASH" ]'
unset -f df
run_block
check "no retry with the same version"  '[ "$USE_NEW_DIRS" = no ] && [ ! -e "$(NEWD)" ]'
CURRENT_HASH=commit-2; run_block
check "retried after an update"         '[ "$USE_NEW_DIRS" = yes ] && [ -d "$(NEWD)" ] && [ ! -e "$STATE_DIR/migrate.failed" ]'
CURRENT_HASH=commit-1

echo "== copy fails (unreadable file in old config)"
setup "$ROOT/fail"; P="$HOME/.eclipse/${HASH}_linux_gtk_$ARCH/configuration/.settings/ide.prefs"; chmod 000 "$P"
run_block
check "keeps old locations"             '[ "$USE_NEW_DIRS" = no ] && [ -z "$JAVA_TOOL_OPTIONS" ] && [ ${#ARGS[@]} -eq 0 ]'
check "nothing half-migrated"           '[ ! -e "$(NEWD)" ] && [ ! -e "$(NEWC)" ] && ! ls -d "$(NEWD).tmp" "$(NEWC).tmp" 2>/dev/null'
chmod 644 "$P"; CURRENT_HASH=commit-2; run_block; CURRENT_HASH=commit-1
check "next version succeeds"           '[ "$USE_NEW_DIRS" = yes ] && [ -d "$(NEWD)" ] && [ -d "$(NEWC)" ]'

echo "== leftover .tmp from an interrupted copy"
setup "$ROOT/interrupt"; mkdir -p "$(NEWD).tmp/garbage"
run_block
check "redone cleanly"                  '[ -d "$(NEWD)/workspace6" ] && [ ! -e "$(NEWD)/garbage" ] && [ ! -e "$(NEWD).tmp" ]'

echo "== old data is a symlink the sandbox can't see"
setup "$ROOT/dangling"; rm -rf "$HOME/.local/share/DBeaverData"; ln -s /nonexistent/DBeaverData "$HOME/.local/share/DBeaverData"
run_block
check "keeps old locations, nothing new" '[ "$USE_NEW_DIRS" = no ] && [ ! -e "$(NEWD)" ] && [ ! -e "$(NEWC)" ] && [ -z "$JAVA_TOOL_OPTIONS" ]'
mkdir -p "$(NEWD)" "$(NEWC)"; run_block   # already migrated earlier: a dangling old link no longer matters
check "already migrated: new dirs used" '[ "$USE_NEW_DIRS" = yes ]'

echo "== DBEAVER_DATA set by the user"
setup "$ROOT/custom"; DBEAVER_DATA=/somewhere run_block
check "left alone"                      '[ "$USE_NEW_DIRS" = no ] && [ ! -e "$(NEWD)" ] && [ -z "$JAVA_TOOL_OPTIONS" ]'

echo "== Java property values"
JAVA_TOOL_OPTIONS=-Dkeep=1; eval "$(sed -n '/^java_prop() {/,/^}/p' "$RUN_SH")"
java_prop a.b "/x y/z"
check "quoted, existing options kept"   '[ "$JAVA_TOOL_OPTIONS" = "-Da.b=\"/x y/z\" -Dkeep=1" ]'
check "value with a quote refused"      '! java_prop c "/x\"y" && [[ "$JAVA_TOOL_OPTIONS" != *"-Dc="* ]]'

[ $fail = 0 ] && echo "ALL OK" || { echo "FAILURES"; exit 1; }
