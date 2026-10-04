#!/bin/bash
# run.sh SCENARIO FIX_BUNDLE [distro...]: run scenarios/SCENARIO.sh against FIX_BUNDLE (a .flatpak of
# the build under test, built on the "stable" branch) on each distro, one VM at a time.
# Results: $WORK/results/SCENARIO-<time>/<distro>.txt (+ diag-<distro>/ with logs and screenshots).
H=$(dirname "$(readlink -f "$0")"); . "$H/common.sh"
scenario=$1 fix=$2; shift 2
[ -f "$H/scenarios/$scenario.sh" ] && [ -f "$fix" ] || { echo "usage: run.sh plugins|phase1 FIX_BUNDLE [distro...]"; exit 1; }
for f in published-old.flatpak published-latest.flatpak vrapper-repo egit-repo; do
  [ -e "$WORK/cache/$f" ] || { echo "missing $WORK/cache/$f: run make-cache.sh first"; exit 1; }
done
iso="$WORK/logs/iso-$scenario"; rm -rf "$iso"; mkdir -p "$iso"
cp "$H/scenarios/$scenario.sh" "$iso/test.sh"; cp "$fix" "$iso/fix.flatpak"
cp -rl "$WORK/cache"/{published-old.flatpak,published-latest.flatpak,vrapper-repo,egit-repo} "$iso/" 2>/dev/null ||
  cp -r "$WORK/cache"/{published-old.flatpak,published-latest.flatpak,vrapper-repo,egit-repo} "$iso/"
genisoimage -quiet -V TESTDATA -r -J -o "$WORK/logs/testdata.iso" "$iso" || exit 1
out="$WORK/results/$scenario-$(date +%Y%m%d-%H%M)"; mkdir -p "$out"
for d in ${@:-${DISTROS[@]}}; do
  echo "=== $d $(date +%T)"
  base="$WORK/$d-golden.qcow2"
  [ -s "$base" ] || { echo "[$d] no golden image (prep-golden.sh); using the plain cloud image, slower"; base_image "$d" || continue; base="$WORK/$d.qcow2"; }
  rm -f "$WORK/$d-run.qcow2" "$WORK/logs/$d-out.raw"; truncate -s 400M "$WORK/logs/$d-out.raw"
  qemu-img create -q -f qcow2 -b "$base" -F qcow2 "$WORK/$d-run.qcow2" 30G
  boot_vm "dbtest-$d" "$WORK/$d-run.qcow2" "$WORK/logs/testdata.iso" test.sh "$WORK/logs/$d.log" "$WORK/logs/$d-out.raw"
  rm -f "$WORK/$d-run.qcow2"
  results "$WORK/logs/$d.log" | tee "$out/$d.txt" | sed "s/^/[$d] /"
  mkdir -p "$out/diag-$d" && tar xf "$WORK/logs/$d-out.raw" -C "$out/diag-$d" 2>/dev/null
done
echo "=== finished $(date +%T), results in $out"
