#!/bin/bash
# make-cache.sh: build $WORK/cache, everything the VM tests would otherwise download each run:
#  - published-latest.flatpak / published-old.flatpak: the exact files of two published Flathub
#    commits (LATEST_COMMIT defaults to today's; OLD_COMMIT should be an older DBeaver version,
#    pick one from `flatpak remote-info --log flathub io.dbeaver.DBeaverCommunity`)
#  - vrapper-repo, egit-repo: local mirrors of the Vrapper and EGit update sites (test plugins)
# Needs: flatpak, the org.flatpak.Builder Flatpak (for ostree), and an installed DBeaver Flatpak
# (to run Eclipse's own mirror tools). Your own installs and ~/.eclipse are not touched.
set -e
. "$(dirname "$(readlink -f "$0")")/common.sh"
APP=io.dbeaver.DBeaverCommunity; C="$WORK/cache"; mkdir -p "$C"
OLD_COMMIT=${OLD_COMMIT:-4bf9ae215d7d2f9dc4d791fdb1a3bd9a89ea87105049ba30ed463fce90aff22b}   # DBeaver 26.1.5
export FLATPAK_USER_DIR="$C/fp"   # private Flatpak installation, only for fetching commits
flatpak --user remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak --user install -y --noninteractive --no-deps --no-related flathub $APP >/dev/null
LATEST_COMMIT=${LATEST_COMMIT:-$(flatpak --user remote-info flathub $APP | sed -n 's/^ *Commit: //p')}

# Flatpak keeps only the deployed commit, so fetch and export one commit at a time
for pair in "latest:$LATEST_COMMIT" "old:$OLD_COMMIT"; do
  n=${pair%%:*}; c=${pair#*:}; echo "bundle $n = $c"
  flatpak --user update -y --noninteractive --no-deps --no-related --commit="$c" $APP >/dev/null
  rm -rf "$C/arc-$n"   # build-bundle needs an archive repo; the installation's repo exports metadata only
  env -u FLATPAK_USER_DIR flatpak run --command=ostree org.flatpak.Builder init --mode=archive --repo="$C/arc-$n"
  flatpak build-commit-from --no-update-summary --src-repo="$C/fp/repo" --src-ref="$c" "$C/arc-$n" app/$APP/x86_64/stable >/dev/null
  flatpak build-bundle "$C/arc-$n" "$C/published-$n.flatpak" $APP stable
  rm -rf "$C/arc-$n"
done

# Update-site mirrors, made with the installed DBeaver; p2 keeps data next to -configuration,
# so both live in a throwaway folder
unset FLATPAK_USER_DIR
for site in "vrapper-repo https://vrapper.sourceforge.net/update-site/stable" "egit-repo https://download.eclipse.org/egit/updates/"; do
  set -- $site; rm -rf "$C/$1" "$C/tmp"; mkdir -p "$C/tmp"
  for kind in metadata artifact; do
    flatpak run --command=/app/bin/dbeaver $APP -nosplash -configuration "$C/tmp/config" -data "$C/tmp/ws" \
      -application org.eclipse.equinox.p2.$kind.repository.mirrorApplication -source "$2" -destination "file:$C/$1" >/dev/null 2>&1
  done
  rm -rf "$C/tmp"; echo "mirror $1: $(ls "$C/$1/plugins" | wc -l) plugin jars"
done
ls -la "$C"/*.flatpak
