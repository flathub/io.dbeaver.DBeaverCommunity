# DBeaver Community Edition - Flatpak

Free multi-platform database tool for developers, SQL programmers, database administrators and analysts. Supports all popular databases: MySQL, PostgreSQL, MariaDB, SQLite, Oracle, DB2, SQL Server, Sybase, MS Access, Teradata, Firebird, Derby, etc.

## Flatpak local build test

Make sure you install the OpenJDK SDK extension first, else the system will complain that it can't find
the extension with the version of the GNOME SDK:

```sh
flatpak install org.freedesktop.Sdk.Extension.openjdk/x86_64/23.08
```

To build and install the app execute:

```sh
flatpak-builder --repo=repo --force-clean build-dir io.dbeaver.DBeaverCommunity.yml
```
