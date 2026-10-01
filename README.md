# DBeaver Community Edition - Flatpak

Free multi-platform database tool for developers, SQL programmers, database administrators and analysts. Supports all popular databases: MySQL, PostgreSQL, MariaDB, SQLite, Oracle, DB2, SQL Server, Sybase, MS Access, Teradata, Firebird, Derby, etc.

## Silverblue specific problems

The way how Eclipse, DBeaver and plug-ins work, means that alternative DXG-config is not well supported.

### Workaround

> If you are on Silverblue or other atomic version, please make sure the paths in the `~/.local/share/DBeaverData/workspace6/.metadata/.plugins/org.eclipse.core.runtime/.settings/org.jkiss.dbeaver.core.prefs` point to `/var/home` and not to `/home`. This also applies to the query export and other dialogs that work with paths. The /home symlink doesn't work in the Flatpak properly (it does not map to the host location, but files will be written to this location which will exist only inside the Flatpak environment, which is not permanent).

https://github.com/flathub/io.dbeaver.DBeaverCommunity/issues/156#issuecomment-2595002171

## Custom CA certificates

DBeaver trusts the CA certificates in your system trust store, in addition to the ones bundled with Java. Add your CA the usual way for your distribution (e.g. `sudo trust anchor ca.crt` on Fedora/Arch, or copy it to `/usr/local/share/ca-certificates/` and run `sudo update-ca-certificates` on Debian/Ubuntu), then restart DBeaver.

Flatpak can only pass your trust store to the app when the `p11-kit server` command is available on the host. Most desktop installs have it; if your CA is still not trusted, install it (package `p11-kit-server` on Fedora and openSUSE) and log out and back in.

## Flatpak local build test

To build and install the app execute:

```sh
bash build_install.sh
```
