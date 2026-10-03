#!/bin/bash
# Hotfix test ("Keep user-installed plugins working across updates"). Runs as root in a throwaway VM
# built from a golden image (packages + GNOME runtime preinstalled). Uses only the ISO: published
# DBeaver builds as bundles, the hotfix bundle, and a Vrapper update-site mirror.
# RESULT lines go to the serial log; a diagnostics tar stream goes to the OUTDISK.
exec > >(tee -a /root/result.log) 2>&1
R() { echo "RESULT $*"; echo "<1>RESULT $*" > /dev/kmsg 2>/dev/null || true; }
APP=io.dbeaver.DBeaverCommunity; T=/mnt/t; DIAG=/root/diag; mkdir -p $DIAG
. /etc/os-release; R "distro=$ID $VERSION_ID golden=$(flatpak list --runtime --columns=application,branch | grep -c 'org.gnome.Platform.*50')"
mkdir -p $T && mount -o ro /dev/disk/by-label/TESTDATA $T || R "FATAL no test iso"
command -v Xvfb >/dev/null && command -v flatpak >/dev/null || R "FATAL golden image lacks packages"
HOMEBASE=/home; [ "$(readlink -f /home)" = /var/home ] && HOMEBASE=/var/home
(Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &); sleep 2

mkuser() { useradd -m -b "$HOMEBASE" "$1"; loginctl enable-linger "$1"
  for i in $(seq 1 20); do [ -S /run/user/$(id -u "$1")/bus ] && break; sleep 1; done
  cp -r $T/vrapper-repo "$(home "$1")/vrapper-repo"; chown -R "$1" "$(home "$1")/vrapper-repo"; }
home() { getent passwd "$1" | cut -d: -f6; }
as() { local u=$1; shift; runuser -u "$u" -- env HOME="$(home "$u")" XDG_RUNTIME_DIR=/run/user/$(id -u "$u") \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$u")/bus DISPLAY=:99 "$@"; }
# launcher first (no error dialog), then Java; wait until Java has really exited
stop_app() { pkill -u "$1" -f '/app/bin/dbeaver( |$)'; sleep 1; pkill -u "$1" -x java
  for i in $(seq 1 60); do pgrep -u "$1" -x java >/dev/null || break; sleep 1; done; sleep 1; }
# started_wait U LOG: until DBeaver finished starting, or an old build sits at its setup wizard,
# or the launcher's error dialog appeared ("An error has occurred") -> prints the outcome
started_wait() { local i w
  for i in $(seq 1 120); do
    grep -q "Finish initialization" "$2" 2>/dev/null && { echo yes; return; }
    w=$(xwininfo -root -tree -display :99 2>/dev/null)
    grep -q '"Product Configuration' <<<"$w" && { echo wizard; return; }
    grep -q '"Dbeaver"' <<<"$w" && ! pgrep -u "$1" -x java >/dev/null && { echo ERROR-DIALOG; return; }
    sleep 1.5
  done; echo TIMEOUT; }
install_bundle() {  # install_bundle U MODE FILE: first install or update (reinstall) from a bundle
  if [ "$2" = user ]; then as "$1" flatpak install -y --noninteractive --user --reinstall "$3" >/dev/null 2>&1
  else flatpak install -y --noninteractive --system --reinstall "$3" >/dev/null 2>&1; fi
  R "[$1] installed $(basename "$3") rc=$? core=$(as "$1" flatpak run --"$2" --command=sh $APP -c 'ls /app/bin/plugins | grep -o "org.jkiss.dbeaver.core_[0-9]*\.[0-9]*\.[0-9]*" | head -1 | sed s/.*_//')"
}
# probe U MODE LABEL: start DBeaver with the OSGi console, report start outcome and plugins, stop
probe() {
  local u=$1 m=$2 lbl=$3 h; h=$(home "$u"); local fifo=/tmp/fifo-$u out=$DIAG/out-$lbl.txt
  local log="$h/.local/share/DBeaverData/workspace6/.metadata/dbeaver-debug.log"
  rm -f "$fifo" "$log"; mkfifo -m 666 "$fifo"
  ( sleep 600 ) > "$fifo" &   # keeps the console's stdin open; killed below
  local keep=$!
  as "$u" flatpak run --"$m" --env=JAVA_TOOL_OPTIONS=-Dproduct.config.disable=true $APP -console < "$fifo" > "$out" 2>&1 &
  local st; st=$(started_wait "$u" "$log")
  if [ "$st" = yes ] || [ "$st" = wizard ]; then
    exec 7>"$fifo"; printf 'ss vrapper\nss org.jkiss.dbeaver.core\n' >&7
    for i in $(seq 1 20); do grep -aq 'org.jkiss.dbeaver.core_' "$out" && break; sleep 1; done; exec 7>&-
  fi
  xwd -root -display :99 -silent > "$DIAG/shot-$lbl.xwd" 2>/dev/null
  stop_app "$u"; kill $keep 2>/dev/null; rm -f "$fifo"
  R "[$lbl] started=$st vrapper=$(grep -aoE '(ACTIVE|RESOLVED|STARTING|INSTALLED) +net.sourceforge.vrapper.eclipse_' "$out" | awk '{print $1}' | head -1) exchange=$(grep -aoE '(ACTIVE|RESOLVED|STARTING|INSTALLED) +net.sourceforge.vrapper.plugin.exchange' "$out" | awk '{print $1}' | head -1) core=$(grep -aoE 'org.jkiss.dbeaver.core_[0-9]+\.[0-9]+\.[0-9]+' "$out" | head -1 | sed 's/.*_//') kept_msg=$(grep -ac 'Kept user-installed' "$out")"
}
p2() {  # p2 U MODE LABEL ARGS...: p2 director through the normal launcher (wrapper), local Vrapper mirror
  local u=$1 m=$2 lbl=$3; shift 3
  timeout 300 runuser -u "$u" -- env HOME="$(home "$u")" XDG_RUNTIME_DIR=/run/user/$(id -u "$u") DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$u")/bus DISPLAY=:99 \
    flatpak run --"$m" --env=JAVA_TOOL_OPTIONS=-Dproduct.config.disable=true $APP -nosplash -application org.eclipse.equinox.p2.director \
    -repository "file:$(home "$u")/vrapper-repo" "$@" > "$DIAG/p2-$lbl.txt" 2>&1
  local rc=$?; stop_app "$u"
  R "[$lbl] p2 $* rc=$rc completed=$(grep -c 'Operation completed' "$DIAG/p2-$lbl.txt")"
  snap_p2 "$u" "$lbl"
}
p2_old() {  # p2_old U MODE: install Vrapper with the old launcher directly (as users of that version did)
  as "$1" flatpak run --"$2" --command=/app/bin/dbeaver $APP -nosplash -application org.eclipse.equinox.p2.director \
    -repository "file:$(home "$1")/vrapper-repo" -installIU net.sourceforge.vrapper.feature.group > "$DIAG/p2-$1-vrapper.txt" 2>&1
  stop_app "$1"; R "[$1] vrapper_install=$(grep -c 'Operation completed' "$DIAG/p2-$1-vrapper.txt")"; snap_p2 "$1" "$1-after-vrapper"
}
snap_p2() {  # p2 records + user plugin list, for the uninstall diagnosis
  local d="$DIAG/p2state-$2"; mkdir -p "$d"; local c; c="$(home "$1")/.eclipse/487352054_linux_gtk_$(uname -m)"
  cp "$c/configuration/org.eclipse.equinox.simpleconfigurator/bundles.info" "$d/" 2>/dev/null
  cp -r "$c/p2/org.eclipse.equinox.p2.engine/profileRegistry" "$d/" 2>/dev/null
  cp "$c/configuration/config.ini" "$d/" 2>/dev/null
}

OLD=$T/published-old.flatpak; LATEST=$T/published-latest.flatpak; FIX=$T/fix.flatpak

# A. Version update with a plugin: published 26.1.5 + Vrapper -> hotfix (user install, then system)
for m in user system; do u=hf$m
  mkuser $u; install_bundle $u $m $OLD; probe $u $m $u-old; p2_old $u $m; probe $u $m $u-old-vrapper
  install_bundle $u $m $FIX; probe $u $m $u-fix; probe $u $m $u-fix-restart
  install_bundle $u $m $FIX; probe $u $m $u-fix-redeploy
done
# B. Live bug: same, but update to today's published build first (expect: no start), then the hotfix
mkuser hfaff; install_bundle hfaff user $OLD; probe hfaff user hfaff-old; p2_old hfaff user
install_bundle hfaff user $LATEST; probe hfaff user hfaff-published
install_bundle hfaff user $FIX; probe hfaff user hfaff-fix
# C. Same DBeaver version (26.2.1 published + Vrapper -> hotfix): plugin kept
mkuser hfsame; install_bundle hfsame user $LATEST; probe hfsame user hfsame-pub; p2_old hfsame user
install_bundle hfsame user $FIX; probe hfsame user hfsame-fix
# D. p2 after the update (uninstall diagnosis): install a 2nd plugin, then uninstall it
p2 hfuser user hfuser-p2-install -installIU net.sourceforge.vrapper.plugin.exchange.feature.group; probe hfuser user hfuser-p2-installed
p2 hfuser user hfuser-p2-uninstall -uninstallIU net.sourceforge.vrapper.plugin.exchange.feature.group; probe hfuser user hfuser-p2-uninstalled
# E. No plugins at all: hotfix changes nothing
mkuser hfplain; install_bundle hfplain user $LATEST; probe hfplain user hfplain-pub
install_bundle hfplain user $FIX; probe hfplain user hfplain-fix
R "[hfplain] user_bundles_info=$([ -f "$(home hfplain)/.eclipse/487352054_linux_gtk_$(uname -m)/configuration/org.eclipse.equinox.simpleconfigurator/bundles.info" ] && echo exists || echo none)"

OUT=$(ls /dev/disk/by-id/*OUTDISK* 2>/dev/null | head -1)
[ -n "$OUT" ] && tar cf "$OUT" -C /root diag && sync && R "diag_written=$(du -sk $DIAG | cut -f1)KiB"
R "DONE"
poweroff
