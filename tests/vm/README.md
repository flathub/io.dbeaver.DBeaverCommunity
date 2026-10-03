# VM tests

End-to-end tests of the launcher (`run.sh`) on real distributions: each test user starts on a
**published** Flathub build, gets realistic data and Eclipse plugins, then updates to the build
under test. Distros: Ubuntu 24.04, Debian 13, Arch, openSUSE Tumbleweed, Fedora 44 (set up like
Silverblue: homes in `/var/home`, `/home` a symlink).

VMs run headless (Xvfb inside), one at a time, under `qemu:///session` (no root). Nothing in the
repo is written; everything goes to `$DBEAVER_VM_DIR` (default
`~/.local/share/libvirt/images/dbeaver-test`).

## Requirements

- libvirt with `qemu:///session`, `virt-install`, `qemu-img`, `passt`, `genisoimage`, `curl`
- `flatpak` with the `org.flatpak.Builder` Flatpak and an installed DBeaver Flatpak (for `make-cache.sh`)
- About 20 GB free disk and 3 GB free RAM per VM; network for the first setup only

## One-time setup

```sh
tests/vm/make-cache.sh     # published DBeaver bundles + Vrapper/EGit update-site mirrors (~5 min)
tests/vm/prep-golden.sh    # per-distro golden image: packages + GNOME runtime (~7 min each)
```

`make-cache.sh` takes `OLD_COMMIT` (an older published DBeaver version, default 26.1.5) and
`LATEST_COMMIT` (default: today's published build); find commits with
`flatpak remote-info --log flathub io.dbeaver.DBeaverCommunity`. Re-run `prep-golden.sh` before a
final pre-merge run so results match what users have (it refreshes packages and the runtime).

## Running

Build the change as a bundle on the `stable` branch, so it installs as an update of the published app:

```sh
flatpak run org.flatpak.Builder --user --force-clean --default-branch=stable --repo=testing-repo build-dir io.dbeaver.DBeaverCommunity.yml
flatpak build-bundle testing-repo /tmp/fix.flatpak io.dbeaver.DBeaverCommunity stable
tests/vm/run.sh phase1 /tmp/fix.flatpak              # all five distros (~12 min each)
tests/vm/run.sh plugins /tmp/fix.flatpak ubuntu      # one distro
tests/vm/progress-window.sh &                        # optional live feed (VM_TERMINAL, default foot)
```

Results land in `$DBEAVER_VM_DIR/results/<scenario>-<time>/<distro>.txt`, with `diag-<distro>/`
holding screenshots (`.xwd`, convert with `magick`), DBeaver/Eclipse logs and p2 state.

## Scenarios

- **`phase1`**: published build → build under test, for user and system installs: data and Eclipse
  configuration moved, connection/script carried over, no old paths left, old data unchanged,
  restart and redeploy; version upgrade from `OLD_COMMIT`; plugin already lost by the published
  build; home with a space; legacy `.DBeaverData`; data symlinked to a readable and to an
  unreadable place; fresh user; many plugins (13 Vrapper features + EGit, every bundle checked).
- **`plugins`**: the plugin fix on the old layout (written for #375): version update with Vrapper,
  restart, redeploy, the published crash, same-version update, p2 install/uninstall afterwards,
  no plugins. Its p2-state captures read `~/.eclipse`, so on builds with the data move they come back
  empty; use `phase1` for current builds.

## Reading a result line

`[label] started=yes|wizard|ERROR-DIALOG|TIMEOUT vrapper=ACTIVE core=26.2.1 copied=2 kept_old=0`

- `started`: `yes` = reached the workbench; `wizard` = an old build sitting at its first-run
  "Product Configuration" wizard (expected for 26.1.x); `ERROR-DIALOG` = the launcher's
  "An error has occurred" dialog; `TIMEOUT` = neither within 3 minutes.
- `vrapper` / `exchange`: plugin bundle state in the running OSGi framework (empty = not installed).
- `copied` / `kept_old`: the launcher's own messages (see the README's table).

## When the harness itself misbehaves

- A cloud image download fails: it's fetched to `.part` first, just re-run.
- `virt-install failed`: see `$DBEAVER_VM_DIR/logs/<vm>.log.err`; usually a host libvirt/qemu update
  or another VM still running (`virsh -c qemu:///session list --all`).
- `PREP FAILED` in `prep-golden.sh`: a distro renamed a package; fix `guest/prep.sh` (Fedora 44, for
  example, ships `xwininfo` and `xwd` as separate packages).
- No result lines at all: open `$DBEAVER_VM_DIR/logs/<distro>.log` (serial console, includes cloud-init).
