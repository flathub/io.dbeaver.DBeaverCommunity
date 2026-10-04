#!/bin/bash
# Golden-image prep (runs once per distro as root): everything the tests download that is not under test.
exec > >(tee -a /root/prep.log) 2>&1
R() { echo "RESULT $*"; echo "<1>RESULT $*" > /dev/kmsg 2>/dev/null || true; }
. /etc/os-release; R "prep distro=$ID $VERSION_ID"
for i in $(seq 1 12); do getent hosts dl.flathub.org >/dev/null && break; sleep 5; done
getent hosts dl.flathub.org >/dev/null || { rm -f /etc/resolv.conf; echo "nameserver 1.1.1.1" > /etc/resolv.conf; }
case "$ID" in
  ubuntu|debian) export DEBIAN_FRONTEND=noninteractive; apt-get update -q && apt-get install -y -q flatpak xvfb x11-utils x11-apps ;;
  arch) pacman -Syu --noconfirm flatpak xorg-server-xvfb xorg-xwininfo xorg-xwd ;;
  opensuse*) zypper -n --gpg-auto-import-keys in flatpak xorg-x11-server-Xvfb xwininfo xwd ;;
  fedora) dnf -y install --skip-unavailable flatpak xorg-x11-server-Xvfb xorg-x11-utils xwininfo xwd xorg-x11-apps ;;
esac
if [ "$ID" = fedora ]; then   # Silverblue layout: homes in /var/home, /home is a symlink
  mkdir -p /var/home; cp -a /home/. /var/home/ 2>/dev/null
  umount /home 2>/dev/null; sed -i '\| /home |d' /etc/fstab
  rm -rf /home && ln -s var/home /home
fi
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install -y --noninteractive --system flathub org.gnome.Platform//50 >/dev/null 2>&1; R "runtime_rc=$?"
R "tools flatpak=$(command -v flatpak) xvfb=$(command -v Xvfb) xwininfo=$(command -v xwininfo) xwd=$(command -v xwd) home=$(readlink -f /home)"
R "runtimes: $(flatpak list --runtime --columns=application,branch | tr '\n' ' ')"
# Refuse to bless a golden image that lacks what the tests need
if ! command -v flatpak >/dev/null || ! command -v Xvfb >/dev/null || ! command -v xwininfo >/dev/null || \
   ! flatpak list --runtime --columns=application,branch | grep -q 'org.gnome.Platform.*50'; then
  R "PREP FAILED: missing tools or runtime"; poweroff; exit 1
fi
cloud-init clean --logs --machine-id 2>/dev/null || cloud-init clean --logs; sync
R "PREP DONE"
poweroff
