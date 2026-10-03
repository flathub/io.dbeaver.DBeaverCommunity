#!/bin/bash
# prep-golden.sh [distro...]: build <distro>-golden.qcow2 = cloud image + test packages + GNOME 50
# runtime, so test runs don't download them. Re-run to refresh (always before a final pre-merge run).
H=$(dirname "$(readlink -f "$0")"); . "$H/common.sh"
genisoimage -quiet -V TESTDATA -r -J -o "$WORK/logs/prep.iso" "$H/guest" || exit 1
for d in ${@:-${DISTROS[@]}}; do
  echo "=== prep $d $(date +%T)"
  base_image "$d" || { echo "[$d] download failed"; continue; }
  rm -f "$WORK/$d-golden.qcow2"
  qemu-img create -q -f qcow2 -b "$WORK/$d.qcow2" -F qcow2 "$WORK/$d-golden.qcow2" 30G
  boot_vm "dbprep-$d" "$WORK/$d-golden.qcow2" "$WORK/logs/prep.iso" prep.sh "$WORK/logs/prep-$d.log" || continue
  res=$(results "$WORK/logs/prep-$d.log"); echo "$res" | sed "s/^/[$d] /"
  grep -q "PREP DONE" <<<"$res" || { echo "[$d] prep FAILED, golden image removed"; rm -f "$WORK/$d-golden.qcow2"; }
done
