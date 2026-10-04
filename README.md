# DBeaver Community Edition - Flatpak

Free multi-platform database tool for developers, SQL programmers, database administrators and analysts. Supports all popular databases: MySQL, PostgreSQL, MariaDB, SQLite, Oracle, DB2, SQL Server, Sybase, MS Access, Teradata, Firebird, Derby, etc.

## Where DBeaver keeps its files

DBeaver's workspace, connections, scripts and drivers are stored in `~/.var/app/io.dbeaver.DBeaverCommunity/data/DBeaverData`, and Eclipse's configuration and any plugins you install in `~/.var/app/io.dbeaver.DBeaverCommunity/config/eclipse`.

Older versions of this Flatpak used `~/.local/share/DBeaverData` and `~/.eclipse`. On the first start after the update, their contents are copied to the new location; the old folders are left untouched. Once you have checked that everything is there, you can delete them:

```sh
rm -rf ~/.local/share/DBeaverData ~/.eclipse/*_linux_gtk_*
```

Only do this if you don't also use a non-Flatpak DBeaver or Eclipse, which use the same folders. If your home folder is reached through a symlink (other than Silverblue's `/home` → `/var/home`), first check that your connections and scripts still open.

## Silverblue specific problems

The way how Eclipse, DBeaver and plug-ins work, means that alternative DXG-config is not well supported.

### Workaround

> If you are on Silverblue or other atomic version, please make sure the paths in the `~/.var/app/io.dbeaver.DBeaverCommunity/data/DBeaverData/workspace6/.metadata/.plugins/org.eclipse.core.runtime/.settings/org.jkiss.dbeaver.core.prefs` (`~/.local/share/DBeaverData/...` in versions before the move described above) point to `/var/home` and not to `/home`. This also applies to the query export and other dialogs that work with paths. The /home symlink doesn't work in the Flatpak properly (it does not map to the host location, but files will be written to this location which will exist only inside the Flatpak environment, which is not permanent).

https://github.com/flathub/io.dbeaver.DBeaverCommunity/issues/156#issuecomment-2595002171

## Custom CA certificates

DBeaver trusts the CA certificates in your system trust store, in addition to the ones bundled with Java. Add your CA the usual way for your distribution (e.g. `sudo trust anchor ca.crt` on Fedora/Arch, or copy it to `/usr/local/share/ca-certificates/` and run `sudo update-ca-certificates` on Debian/Ubuntu), then restart DBeaver.

Flatpak can only pass your trust store to the app when the `p11-kit server` command is available on the host. Most desktop installs have it; if your CA is still not trusted, install it (package `p11-kit-server` on Fedora and openSUSE) and log out and back in.

## Eclipse plugins

Plugins you install with *Help > Install New Software* or the Eclipse Marketplace keep working after DBeaver updates.

After a DBeaver version update, Eclipse no longer lists plugins installed before the update as "installed by you": they don't show up for removal in *Installed Software*, and uninstalling another plugin that depends on them can remove them too. To manage such a plugin again, install it once more with *Help > Install New Software*.

## If something goes wrong

**See what happened at startup.** Start DBeaver from a terminal; the launcher prints what it did before DBeaver opens:

```sh
flatpak run io.dbeaver.DBeaverCommunity
```

| Message | Meaning |
| --- | --- |
| `Copied ~/.local/share/DBeaverData to ~/.var/app/…` | First start after the move: your files were copied (the originals are untouched) |
| `Not enough free space to copy DBeaver's files …` | The copy was skipped; DBeaver keeps using the old folders. It retries after the next update |
| `Could not copy DBeaver's files …; keeping the old locations.` | The copy failed; nothing changed, DBeaver keeps using the old folders |
| `DBeaver's old files exist but can't be read inside the Flatpak …` | Your data folder is (a symlink to) a place the Flatpak can't see; grant it with `flatpak override --user --filesystem=/that/path io.dbeaver.DBeaverCommunity` |
| `Kept user-installed plugins across the update` | Your Eclipse plugins were carried over to the new version |
| `App update detected (…). Cleaning OSGi cache...` | Normal once after every update |

**Logs.** If DBeaver shows *"An error has occurred. See the log file …"*, that file has the cause. Otherwise look in `~/.var/app/io.dbeaver.DBeaverCommunity/data/DBeaverData/workspace6/.metadata/` (`.log` and `dbeaver-debug.log`) and in `~/.var/app/io.dbeaver.DBeaverCommunity/config/eclipse/configuration/` (`*.log`). Before the move these were in `~/.local/share/DBeaverData/…` and `~/.eclipse/…`.

**Go back to the previous version** if an update breaks DBeaver for you:

```sh
flatpak remote-info --log flathub io.dbeaver.DBeaverCommunity   # pick the commit before the update
flatpak update --commit=<commit> io.dbeaver.DBeaverCommunity
flatpak mask io.dbeaver.DBeaverCommunity                        # stop updates until it's fixed
flatpak mask --remove io.dbeaver.DBeaverCommunity               # later, to receive updates again
```

Add `--user` to each command for a per-user install, or run them with `sudo` for a system install. Note that a version from before the move uses the old folders: changes you made after the move are only in the new location.

**Connections or scripts missing after the move.** Your old files are still in `~/.local/share/DBeaverData` and `~/.eclipse`. To redo the move from them, close DBeaver and set the new copy aside, then start DBeaver again:

```sh
mv ~/.var/app/io.dbeaver.DBeaverCommunity/data/DBeaverData ~/DBeaverData.after-move
mv ~/.var/app/io.dbeaver.DBeaverCommunity/config/eclipse ~/eclipse.after-move
```

The set-aside copy keeps anything you changed after the move; delete it once you no longer need it.

**Reporting a problem:** please include the terminal output from `flatpak run io.dbeaver.DBeaverCommunity`, the output of `flatpak info io.dbeaver.DBeaverCommunity`, and the log file named in any error dialog.

## Flatpak local build test

To build and install the app execute:

```sh
bash build_install.sh
```
