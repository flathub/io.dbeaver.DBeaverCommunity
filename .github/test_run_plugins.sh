#!/bin/bash
# Self-check for run.sh's "Keep user-installed plugins working across updates" block.
# Runs the real block against a fake home and a fake base install. Usage: .github/test_run_plugins.sh [run.sh]
RUN_SH=${1:-run.sh}
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
BLOCK=$(sed -n '/--- Keep user-installed plugins/,/--- STEP 2/p' "$RUN_SH" | sed "s|/app/bin/configuration|$ROOT/base|")
[ -n "$BLOCK" ] || { echo "plugin block not found in $RUN_SH"; exit 1; }
fail=0; check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }

HOME="$ROOT/home"; STATE_DIR="$ROOT/state"
CONFIG_AREA="$HOME/.eclipse/487352054_linux_gtk_$(uname -m)/configuration"
SCD="$CONFIG_AREA/org.eclipse.equinox.simpleconfigurator"; BSC="$ROOT/base/org.eclipse.equinox.simpleconfigurator"
run_plugins() { eval "$BLOCK" >/dev/null 2>&1; }

echo "== no user plugins (no user bundles.info)"
mkdir -p "$STATE_DIR" "$BSC"
printf '#encoding=UTF-8\n#version=1\ncore,2.0,plugins/core_2.0.jar,4,false\nnewlib,1.0,plugins/newlib_1.0.jar,4,false\n' > "$BSC/bundles.info"
echo "osgi.framework=file\:plugins/org.eclipse.osgi_2.0.jar" > "$ROOT/base/config.ini"
run_plugins
check "nothing created"                 '[ ! -e "$CONFIG_AREA" ] && [ -s "$STATE_DIR/base_bundles.ctime" ]'

echo "== user plugin installed under an older version, then an update"
mkdir -p "$SCD"
printf '#encoding=UTF-8\n#version=1\ncore,1.0,plugins/core_1.0.jar,4,false\ngone,1.0,plugins/gone_1.0.jar,4,false\nvrapper,0.74,../../home/u/.eclipse/x/plugins/vrapper.jar,4,false\n' > "$SCD/bundles.info"
echo "bundlesInfoTimestamp=123" > "$SCD/.baseBundlesInfoTimestamp"
echo "osgi.framework=file\:plugins/org.eclipse.osgi_1.0.jar" > "$CONFIG_AREA/config.ini"   # written by p2 for the old version
rm -f "$STATE_DIR/base_bundles.ctime"   # the update: the base list's ctime differs from the recorded one
run_plugins
L=$(grep -v '^#' "$SCD/bundles.info")
check "new base bundles listed"         'grep -qx "core,2.0,plugins/core_2.0.jar,4,false" <<<"$L" && grep -q "^newlib," <<<"$L"'
check "user plugin kept"                'grep -q "^vrapper,0.74,../../home/u/.eclipse/x/plugins/vrapper.jar" <<<"$L"'
check "old base entries dropped"        '! grep -q -e "^gone," -e "core_1.0" <<<"$L"'
check "no duplicates, header once"      '[ "$(cut -d, -f1 <<<"$L" | sort | uniq -d)" = "" ] && [ "$(grep -c "^#version" "$SCD/bundles.info")" = 1 ]'
check "stale Eclipse timestamp removed" '[ ! -e "$SCD/.baseBundlesInfoTimestamp" ]'
check "stale config.ini replaced"       'cmp -s "$CONFIG_AREA/config.ini" "$ROOT/base/config.ini"'

echo "== restart without an update"
cp "$SCD/bundles.info" "$ROOT/after1"; echo "bundlesInfoTimestamp=456" > "$SCD/.baseBundlesInfoTimestamp"
echo "user.edit=1" >> "$CONFIG_AREA/config.ini"
run_plugins
check "list, timestamp, config.ini left alone" 'cmp -s "$SCD/bundles.info" "$ROOT/after1" && [ -e "$SCD/.baseBundlesInfoTimestamp" ] && grep -q user.edit "$CONFIG_AREA/config.ini"'

echo "== later redeploy (new ctime on the base files)"
sleep 1.1; touch -d "@1" "$BSC/bundles.info"; chmod g+w "$BSC/bundles.info"
run_plugins
check "rebuilt again, plugin still kept" '[ ! -e "$SCD/.baseBundlesInfoTimestamp" ] && grep -q "^vrapper," "$SCD/bundles.info"'

[ $fail = 0 ] && echo "ALL OK" || { echo "FAILURES"; exit 1; }
