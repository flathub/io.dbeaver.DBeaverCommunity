# DBeaver Community Edition - Flatpak

Free multi-platform database tool for developers, SQL programmers, database administrators and analysts. Supports all popular databases: MySQL, PostgreSQL, MariaDB, SQLite, Oracle, DB2, SQL Server, Sybase, MS Access, Teradata, Firebird, Derby, etc.

## Silverblue specific problems

The way how Eclipse, DBeaver and plug-ins work, means that alternative DXG-config is not well supported. 

### Workaround

> If you are on Silverblue or other atomic version, please make sure the paths in the `~/.local/share/DBeaverData/workspace6/.metadata/.plugins/org.eclipse.core.runtime/.settings/org.jkiss.dbeaver.core.prefs` point to `/var/home` and not to `/home`. This also applies to the query export and other dialogs that work with paths. The /home symlink doesn't work in the Flatpak properly (it does not map to the host location, but files will be written to this location which will exist only inside the Flatpak environment, which is not permanent).

https://github.com/flathub/io.dbeaver.DBeaverCommunity/issues/156#issuecomment-2595002171

## Flatpak local build test

Make sure you install the OpenJDK SDK extension first, else the system will complain that it can't find
the extension with the version of the GNOME SDK:

```sh
flatpak install org.freedesktop.Sdk.Extension.openjdk/x86_64/24.08
```

To build and install the app execute:

```sh
flatpak-builder --repo=repo --force-clean build-dir io.dbeaver.DBeaverCommunity.yml
```
