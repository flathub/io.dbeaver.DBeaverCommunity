# DBeaver Community Edition - Flatpak

Free multi-platform database tool for developers, SQL programmers, database administrators and analysts. Supports all popular databases: MySQL, PostgreSQL, MariaDB, SQLite, Oracle, DB2, SQL Server, Sybase, MS Access, Teradata, Firebird, Derby, etc.

## Why jdk17?

Flatpak standard version of DBeaver users jdk21. If you try to connect to Databricks with the included driver, you will get an error. This version mantains compatibility with Databricks.

## Flatpak local build test

Make sure you install the OpenJDK SDK extension first, else the system will complain that it can't find
the extension with the version of the GNOME SDK:

```sh
flatpak install org.freedesktop.Sdk.Extension.openjdk17
```

To build and install the app execute:

```sh
flatpak-builder --repo=repo --force-clean build-dir io.dbeaver.DBeaverCommunity_jdk17.yml
```
