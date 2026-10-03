# Shared settings for the VM tests (sourced). Everything written goes to $WORK, never into the repo.
WORK=${DBEAVER_VM_DIR:-$HOME/.local/share/libvirt/images/dbeaver-test}
DISTROS=(ubuntu debian arch opensuse fedora)
declare -A URL=(
  [ubuntu]=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
  [debian]=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
  [arch]=https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2
  [opensuse]=https://download.opensuse.org/tumbleweed/appliances/openSUSE-Tumbleweed-Minimal-VM.x86_64-Cloud.qcow2
  [fedora]=https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2 )
mkdir -p "$WORK/logs"
VIRSH="virsh -c qemu:///session"

# base_image DISTRO: download the cloud image once (via .part, so a broken download is never used)
base_image() {
  [ -s "$WORK/$1.qcow2" ] && return 0
  curl -fsSL --http1.1 --retry 5 --retry-all-errors -C - -o "$WORK/$1.qcow2.part" "${URL[$1]}" &&
    mv "$WORK/$1.qcow2.part" "$WORK/$1.qcow2"
}

# boot_vm NAME DISK ISO SCRIPT LOG [OUTDISK]: boot a VM that runs SCRIPT (from the ISO) via cloud-init,
# wait until it powers itself off (max 60 min), then remove its definition. One VM at a time.
boot_vm() {
  local name=$1 disk=$2 iso=$3 script=$4 log=$5 out=$6 ud="$WORK/logs/$1.user-data"
  printf '#cloud-config\nruncmd:\n  - [bash, -c, "mkdir -p /mnt/t && mount -o ro /dev/disk/by-label/TESTDATA /mnt/t && cp /mnt/t/%s /root/ && umount /mnt/t; bash /root/%s"]\n' \
    "$script" "$script" > "$ud"
  rm -f "$log"
  virt-install --connect qemu:///session --name "$name" --memory 3072 --vcpus 4 --import \
    --disk "$disk" --disk "$iso,device=cdrom" ${out:+--disk "path=$out,format=raw,bus=virtio,serial=OUTDISK"} \
    --network passt,model=virtio --osinfo detect=on,require=off --cloud-init user-data="$ud" \
    --serial file,path="$log" --graphics none --noautoconsole >/dev/null 2>"$log.err" ||
    { echo "[$name] virt-install failed: $(tail -1 "$log.err")"; return 1; }
  for i in $(seq 1 360); do [ "$($VIRSH domstate "$name" 2>/dev/null)" = "shut off" ] && break; sleep 10; done
  $VIRSH destroy "$name" >/dev/null 2>&1
  $VIRSH undefine "$name" --nvram >/dev/null 2>&1 || $VIRSH undefine "$name" >/dev/null 2>&1
}

# results LOG: the RESULT lines a VM wrote, deduplicated
results() { grep -ao 'RESULT .*' "$1" | tr -d '\r' | sed 's/\[ *[0-9.]*\] RESULT.*//; s/^RESULT //' | awk '!s[$0]++'; }
