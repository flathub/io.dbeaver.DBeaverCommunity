#!/bin/bash
# Phase 1 test ("Keep DBeaver's files in the app's Flatpak folder"), on top of the plugin hotfix.
# Runs as root in a throwaway VM built from a golden image; uses only the ISO (published bundles,
# fix bundle, Vrapper mirror). RESULT lines -> serial log; diagnostics tar -> OUTDISK.
exec > >(tee -a /root/result.log) 2>&1
R() { echo "RESULT $*"; echo "<1>RESULT $*" > /dev/kmsg 2>/dev/null || true; }
APP=io.dbeaver.DBeaverCommunity; T=/mnt/t; DIAG=/root/diag; mkdir -p $DIAG
. /etc/os-release; R "distro=$ID $VERSION_ID golden=$(flatpak list --runtime --columns=application,branch | grep -c 'org.gnome.Platform.*50')"
mkdir -p $T && mount -o ro /dev/disk/by-label/TESTDATA $T || R "FATAL no test iso"
command -v Xvfb >/dev/null && command -v flatpak >/dev/null || R "FATAL golden image lacks packages"
HOMEBASE=/home; [ "$(readlink -f /home)" = /var/home ] && HOMEBASE=/var/home
(Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &); sleep 2
OLD=$T/published-old.flatpak; LATEST=$T/published-latest.flatpak; FIX=$T/fix.flatpak
NEWD() { echo "$(home "$1")/.var/app/$APP/data/DBeaverData"; }; NEWC() { echo "$(home "$1")/.var/app/$APP/config/eclipse"; }

home() { getent passwd "$1" | cut -d: -f6; }
mkuser() { if [ -n "$2" ]; then useradd -m -d "$HOMEBASE/$2" "$1"; else useradd -m -b "$HOMEBASE" "$1"; fi
  loginctl enable-linger "$1"; for i in $(seq 1 20); do [ -S /run/user/$(id -u "$1")/bus ] && break; sleep 1; done
  cp -r $T/vrapper-repo "$(home "$1")/vrapper-repo"; chown -R "$1" "$(home "$1")/vrapper-repo"; }
as() { local u=$1; shift; runuser -u "$u" -- env HOME="$(home "$u")" XDG_RUNTIME_DIR=/run/user/$(id -u "$u") \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$u")/bus DISPLAY=:99 "$@"; }
stop_app() { pkill -u "$1" -f '/app/bin/dbeaver( |$)'; sleep 1; pkill -u "$1" -x java
  for i in $(seq 1 60); do pgrep -u "$1" -x java >/dev/null || break; sleep 1; done; sleep 1; }
started_wait() { local u=$1 i w; shift   # remaining args: debug logs to watch
  for i in $(seq 1 120); do
    for l in "$@"; do grep -q "Finish initialization" "$l" 2>/dev/null && { echo yes; return; }; done
    w=$(xwininfo -root -tree -display :99 2>/dev/null)
    grep -q '"Product Configuration' <<<"$w" && { echo wizard; return; }
    grep -q '"Dbeaver"' <<<"$w" && ! pgrep -u "$u" -x java >/dev/null && { echo ERROR-DIALOG; return; }
    sleep 1.5
  done; echo TIMEOUT; }
install_bundle() {
  if [ "$2" = user ]; then as "$1" flatpak install -y --noninteractive --user --reinstall "$3" >/dev/null 2>&1
  else flatpak install -y --noninteractive --system --reinstall "$3" >/dev/null 2>&1; fi
  R "[$1] installed $(basename "$3") rc=$?"
}
probe() {  # probe U MODE LABEL
  local u=$1 m=$2 lbl=$3 h; h=$(home "$u"); local fifo=/tmp/fifo-$u out=$DIAG/out-$lbl.txt
  local l1="$h/.local/share/DBeaverData/workspace6/.metadata/dbeaver-debug.log" l2; l2="$(NEWD "$u")/workspace6/.metadata/dbeaver-debug.log"
  rm -f "$fifo" "$l1" "$l2"; mkfifo -m 666 "$fifo"; ( sleep 600 ) > "$fifo" & local keep=$!
  as "$u" flatpak run --"$m" --env=JAVA_TOOL_OPTIONS=-Dproduct.config.disable=true $APP -console < "$fifo" > "$out" 2>&1 &
  local st; st=$(started_wait "$u" "$l1" "$l2")
  if [ "$st" = yes ] || [ "$st" = wizard ]; then
    exec 7>"$fifo"; printf 'ss vrapper\nss org.jkiss.dbeaver.core\nss\ngetprop osgi.configuration.area\ngetprop osgi.instance.area\ngetprop javax.net.ssl.trustStore\n' >&7
    for i in $(seq 1 25); do grep -av 'Picked up' "$out" | grep -aq 'javax.net.ssl.trustStore=' && grep -aq 'osgi.instance.area=' "$out" && break; sleep 1; done; exec 7>&-
  fi
  xwd -root -display :99 -silent > "$DIAG/shot-$lbl.xwd" 2>/dev/null
  stop_app "$u"; kill $keep 2>/dev/null; rm -f "$fifo"
  local cfg inst ts
  cfg=$(grep -ao 'osgi.configuration.area=.*' "$out" | head -1 | sed "s|osgi.configuration.area=file:||; s|$h|~|")
  inst=$(grep -ao 'osgi.instance.area=.*' "$out" | head -1 | sed "s|osgi.instance.area=file:||; s|$h|~|")
  ts=$(grep -av 'Picked up' "$out" | grep -ao 'javax.net.ssl.trustStore=.*' | head -1 | sed "s|javax.net.ssl.trustStore=||; s|$h|~|")
  R "[$lbl] started=$st vrapper=$(grep -aoE '(ACTIVE|RESOLVED|STARTING|INSTALLED) +net.sourceforge.vrapper.eclipse_' "$out" | awk '{print $1}' | head -1) core=$(grep -aoE 'org.jkiss.dbeaver.core_[0-9]+\.[0-9]+\.[0-9]+' "$out" | head -1 | sed 's/.*_//') copied=$(grep -ac '^Copied' "$out") kept_old=$(grep -acE 'keeping the old locations' "$out")"
  R "[$lbl] areas: config=${cfg:-?} instance=${inst:-?} truststore=${ts:-?}"
}
p2_old() {  # install Vrapper with the currently installed (old-layout) launcher
  as "$1" flatpak run --"$2" --command=/app/bin/dbeaver $APP -nosplash -application org.eclipse.equinox.p2.director \
    -repository "file:$(home "$1")/vrapper-repo" -installIU net.sourceforge.vrapper.feature.group > "$DIAG/p2-$1.txt" 2>&1
  stop_app "$1"; R "[$1] vrapper_install=$(grep -c 'Operation completed' "$DIAG/p2-$1.txt")"
}
add_data() {  # a connection, a script, a /home-spelled path, a decoy non-Flatpak Eclipse folder
  local u=$1 h; h=$(home "$u"); local g="$h/.local/share/DBeaverData/workspace6/General" alias=""
  # Another spelling of the same home (Silverblue: /home/u -> /var/home/u), only where it really is one
  [ "$(readlink -f "/home/$u")" = "$(readlink -f "$h")" ] && [ "/home/$u" != "$h" ] && alias=",\\\"x\\\":\\\"/home/$u/.local/share/DBeaverData/workspace6/x\\\""
  as "$u" mkdir -p "$g/.dbeaver" "$g/Scripts" "$h/Documents" "$h/.eclipse/999_linux_gtk_$(uname -m)/configuration"
  as "$u" touch "$h/.eclipse/999_linux_gtk_$(uname -m)/configuration/DECOY"
  as "$u" sh -c "printf '{\"folders\":{},\"connections\":{\"sqlite-vmtest\":{\"provider\":\"generic\",\"driver\":\"sqlite_jdbc\",\"name\":\"VM test\",\"configuration\":{\"database\":\"%s/Documents/t.db\",\"url\":\"jdbc:sqlite:%s/Documents/t.db\",\"type\":\"dev\"}}}$alias}' '$h' '$h' > '$g/.dbeaver/data-sources.json'; echo 'select 1;' > '$g/Scripts/Script.sql'"
}
snap_old() { (cd "$(home "$1")" && find -L .local/share/DBeaverData .local/share/.DBeaverData .eclipse -type f ! -name dbeaver-debug.log -exec md5sum {} + 2>/dev/null | sort | md5sum); }
checks() {  # checks U: migrated data and paths
  local u=$1 nd nc; nd=$(NEWD "$u"); nc=$(NEWC "$u")
  R "[$u] connection_in_new=$(grep -c sqlite-vmtest "$nd/workspace6/General/.dbeaver/data-sources.json" 2>/dev/null) script_in_new=$([ -f "$nd/workspace6/General/Scripts/Script.sql" ] && echo yes || echo no) new_is_link=$([ -L "$nd" ] && echo YES || echo no) decoy_copied=$([ -e "$nc/configuration/DECOY" ] && echo YES || echo no)"
  R "[$u] old_paths_left=$(grep -rlIF -e '.local/share/DBeaverData/' -e '.local/share/.DBeaverData/' -e '/.eclipse/487352054' "$nd" "$nc" 2>/dev/null | wc -l)"
}
setup_old() {  # setup_old U MODE BUNDLE: old-layout install with Vrapper and user data
  install_bundle "$1" "$2" "$3"; probe "$1" "$2" "$1-old"; p2_old "$1" "$2"; add_data "$1"
}

SCLIST=".eclipse/487352054_linux_gtk_$(uname -m)/configuration/org.eclipse.equinox.simpleconfigurator/bundles.info"
user_bundles() { grep -v '^#' "$(home "$1")/$SCLIST" 2>/dev/null | grep -v ',plugins/' | cut -d, -f1 | sort -u; }
loaded_check() {  # loaded_check U LABEL NAMEFILE: every user bundle loaded in the run whose output is out-LABEL
  local out=$DIAG/out-$2.txt n=0 ok=0 miss=""
  while read -r b; do n=$((n+1))
    if grep -aqE "(ACTIVE|RESOLVED|STARTING|LAZY) +${b//./\\.}_" "$out"; then ok=$((ok+1)); else miss="$miss $b"; fi
  done < "$3"
  R "[$2] user_bundles=$n loaded=$ok missing:${miss:- none}" | cut -c1-400
}
# M. Many plugins: 13 Vrapper features + EGit (113 jars) installed on 26.1.5, then version upgrade to the fix
mkuser p1many; cp -r $T/egit-repo "$(home p1many)/egit-repo"; chown -R p1many "$(home p1many)/egit-repo"
install_bundle p1many user $OLD; probe p1many user p1many-old
VR=$(ls $T/vrapper-repo/features | sed 's/_[0-9].*//' | sort -u | grep -vE 'cdt|jdt|pydev' | sed 's/$/.feature.group/' | paste -sd,)
as p1many flatpak run --user --command=/app/bin/dbeaver $APP -nosplash -application org.eclipse.equinox.p2.director \
  -repository "file:$(home p1many)/vrapper-repo,file:$(home p1many)/egit-repo" -installIU "$VR,org.eclipse.egit.feature.group" > "$DIAG/p2-p1many.txt" 2>&1
stop_app p1many; R "[p1many] install_completed=$(grep -c 'Operation completed' "$DIAG/p2-p1many.txt") $(grep -aiE 'cannot|missing' "$DIAG/p2-p1many.txt" | head -1 | cut -c1-150)"
user_bundles p1many > /tmp/p1many-bundles; R "[p1many] user_bundles_before_update=$(wc -l < /tmp/p1many-bundles)"
add_data p1many; probe p1many user p1many-old-plugins; loaded_check p1many p1many-old-plugins /tmp/p1many-bundles
install_bundle p1many user $FIX; probe p1many user p1many-fix; checks p1many; loaded_check p1many p1many-fix /tmp/p1many-bundles
probe p1many user p1many-restart; loaded_check p1many p1many-restart /tmp/p1many-bundles
install_bundle p1many user $FIX; probe p1many user p1many-redeploy; loaded_check p1many p1many-redeploy /tmp/p1many-bundles

# A. Published -> fix, user and system installs (data, plugin, decoy, /home spelling, restarts, redeploy)
for m in user system; do u=p1$m
  mkuser $u; setup_old $u $m $LATEST; s0=$(snap_old $u)
  install_bundle $u $m $FIX; probe $u $m $u-fix; checks $u
  R "[$u] old_data_unchanged=$([ "$(snap_old $u)" = "$s0" ] && echo yes || echo NO)"
  probe $u $m $u-restart; install_bundle $u $m $FIX; probe $u $m $u-redeploy
done
# B. Version upgrade 26.1.5 -> fix
mkuser p1ver; setup_old p1ver user $OLD; install_bundle p1ver user $FIX; probe p1ver user p1ver-fix; checks p1ver
# C. Already affected: 26.1.5 + plugin -> published 26.2.1 (no start) -> fix
mkuser p1aff; setup_old p1aff user $OLD; install_bundle p1aff user $LATEST; probe p1aff user p1aff-published
install_bundle p1aff user $FIX; probe p1aff user p1aff-fix; checks p1aff
# D. Home with a space
mkuser p1sp "space user"; setup_old p1sp user $LATEST; install_bundle p1sp user $FIX; probe p1sp user p1sp-fix; checks p1sp
# E. Legacy ~/.local/share/.DBeaverData
mkuser p1leg; setup_old p1leg user $LATEST; hl=$(home p1leg)
as p1leg mv "$hl/.local/share/DBeaverData" "$hl/.local/share/.DBeaverData"
as p1leg sh -c "grep -rlF '/.local/share/DBeaverData' '$hl/.local/share/.DBeaverData' '$hl/.eclipse' | xargs -r sed -i 's|/\\.local/share/DBeaverData|/.local/share/.DBeaverData|g'"
install_bundle p1leg user $FIX; probe p1leg user p1leg-fix; checks p1leg
# F. Data symlinked to /srv, readable by the Flatpak (override): copied by content, target untouched
mkuser p1lnk; setup_old p1lnk user $LATEST; hk=$(home p1lnk); mkdir -p /srv/p1lnk; chown p1lnk /srv/p1lnk
as p1lnk mv "$hk/.local/share/DBeaverData" /srv/p1lnk/DBeaverData; as p1lnk ln -s /srv/p1lnk/DBeaverData "$hk/.local/share/DBeaverData"
as p1lnk flatpak override --user --filesystem=/srv/p1lnk $APP; t0=$(cd /srv/p1lnk && find . -type f ! -name dbeaver-debug.log -exec md5sum {} + | sort | md5sum)
install_bundle p1lnk user $FIX; probe p1lnk user p1lnk-fix; checks p1lnk
R "[p1lnk] target_unchanged=$([ "$(cd /srv/p1lnk && find . -type f ! -name dbeaver-debug.log -exec md5sum {} + | sort | md5sum)" = "$t0" ] && echo yes || echo NO)"
# G. Data symlinked to a place the Flatpak can't see (H13): old locations kept, no empty new folder
mkuser p1dng; setup_old p1dng user $LATEST; hd=$(home p1dng); mkdir -p /srv/p1dng; chown p1dng /srv/p1dng
as p1dng mv "$hd/.local/share/DBeaverData" /srv/p1dng/DBeaverData; as p1dng ln -s /srv/p1dng/DBeaverData "$hd/.local/share/DBeaverData"
install_bundle p1dng user $FIX; probe p1dng user p1dng-fix
R "[p1dng] new_data_created=$([ -e "$(NEWD p1dng)" ] && echo YES || echo no)"
# H. Fresh user on the fix build: nothing in the old places
mkuser p1new; install_bundle p1new user $FIX; probe p1new user p1new-fix; hn=$(home p1new)
R "[p1new] old_dirs_created=$(ls -d "$hn/.local/share/DBeaverData" "$hn/.eclipse" 2>/dev/null | wc -l) new_dirs=$(ls -d "$(NEWD p1new)" "$(NEWC p1new)" 2>/dev/null | wc -l)"

OUT=$(ls /dev/disk/by-id/*OUTDISK* 2>/dev/null | head -1)
[ -n "$OUT" ] && tar cf "$OUT" -C /root diag && sync && R "diag_written=$(du -sk $DIAG | cut -f1)KiB"
R "DONE"
poweroff
