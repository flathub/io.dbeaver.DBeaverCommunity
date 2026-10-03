# Maintaining the DBeaver Community Flatpak

Runbook for this repository: what the launcher does, how each part fails, what to do when a
release goes wrong, and how to test changes. User-facing recovery steps are in the README
("If something goes wrong").

## How the app starts

`io.dbeaver.DBeaverCommunity.yml` packages the upstream tarball and installs `run.sh` as
`/app/bin/dbeaver-wrapper`, the app's command. The wrapper prepares a few things, then `exec`s
`/app/bin/dbeaver` (Eclipse's native launcher). It runs on every start, in this order:

| Step in `run.sh` | Why | If it fails | Issue / PR |
| --- | --- | --- | --- |
| Compute the app commit (`/.flatpak-info`) and version | Detect updates | Falls back to cleaning every start (slower, harmless) | #318, #373 |
| **Keep DBeaver's files in the app's Flatpak folder** | Data in `~/.var/app/…/data/DBeaverData`, Eclipse configuration and plugins in `~/.var/app/…/config/eclipse` | Old locations kept (copy failed, not enough space, old folder unreadable in the sandbox); retried after the next update only | #316 phase 1, #376 |
| **Keep user-installed plugins working across updates** | Rebuild the user's `bundles.info`, drop Eclipse's stale timestamp, replace the user's `config.ini` | List not rebuilt → plugins missing after the update (startup unaffected unless `config.ini` is stale) | #375 |
| Compare and clean | `-clean` once per app commit (stale OSGi cache: Flatpak mtimes are all 0) | — | #318, #336, #373 |
| Trust the host's CA certificates | Merge the host trust store (p11-kit) into a copy of the JDK `cacerts` | JDK default store used, as before | #1, #374 |
| Launch | `exec /app/bin/dbeaver` | — | — |

Two settings live in the manifest instead: `-Dpolicy.software.update.disabled=true` is appended to
`dbeaver.ini` (DBeaver's own update check is off; Flatpak delivers updates, #328), and paths
passed through `JAVA_TOOL_OPTIONS` are quoted by `run.sh` (the JVM splits that variable on spaces).

### State files (per user)

| File | Written by | Purpose |
| --- | --- | --- |
| `~/.var/app/io.dbeaver.DBeaverCommunity/data/dbeaver-community/osgi_bundle.sha256` | compare-and-clean | App commit of the last start (name kept from an older version) |
| `…/data/dbeaver-community/last_VERSION` | compare-and-clean | DBeaver version, for the log message only |
| `…/data/dbeaver-community/base_bundles.ctime` | plugins | ctime of the base `bundles.info` at the last rebuild |
| `…/data/dbeaver-community/migrate.failed` | data move | App commit of a failed copy; no retry until the commit changes |
| `…/data/dbeaver-community/migrate.lock` | data move | Lock so two starts don't copy at once |
| `~/.var/app/io.dbeaver.DBeaverCommunity/cache/dbeaver-community/cacerts` | trust store | Rebuilt on every start |

Deleting `data/dbeaver-community/` is safe: it only causes one extra `-clean` and plugin rebuild.

### Key facts behind the design

- Flatpak sets every file's mtime in `/app` to 0. Eclipse then compares **ctime**, which changes on
  every update and reinstall (`SimpleConfiguratorUtils.getFileLastModified`), so Eclipse thinks the
  base install changed on every update.
- Eclipse names the user configuration folder after `hashCode("/app/bin")` → `487352054`, the same
  for every Flatpak install and different from any other Eclipse or DBeaver.
- DBeaver reads `XDG_DATA_HOME` as a Java **property**, not the environment variable.
- p2 (Eclipse's installer) writes a full `config.ini` into the user configuration when a plugin is
  installed; it names that version's OSGi framework jar.
- After a DBeaver version update p2 starts the user's profile afresh (Eclipse shared-install
  behaviour), so earlier plugins keep working but no longer count as user-installed (README).
- The sandbox can't resolve host symlinks such as Silverblue's `/home` → `/var/home`.

## When a release goes wrong

1. **Confirm and scope it.** Ask for the terminal output of `flatpak run io.dbeaver.DBeaverCommunity`,
   `flatpak info io.dbeaver.DBeaverCommunity` and the log named in any error dialog (README).
   Reproduce with the VM tests (below) against the published build:
   `tests/vm/run.sh phase1 <bundle>` for each relevant distro.
2. **Unblock users right away.** Point them to the README's rollback (`flatpak update --commit=…`
   plus `flatpak mask`). Find the last good commit with
   `flatpak remote-info --log flathub io.dbeaver.DBeaverCommunity`; each commit's subject names the PR.
3. **Prefer fixing forward over reverting:**
   - **Data move (#376):** reverting does **not** undo it for users. After the move DBeaver writes only
     to `~/.var/app/…`; a revert sends them back to the old, now stale folders, and their recent changes
     seem lost (they are still in `~/.var/app/…/data/DBeaverData`). Fix forward instead. If a revert is
     unavoidable, tell users to copy the new folder back first (`cp -a ~/.var/app/io.dbeaver.DBeaverCommunity/data/DBeaverData/. ~/.local/share/DBeaverData/`,
     after backing up the old one) and expect paths inside it to point at `~/.var/app/…`.
   - **Plugins (#375):** reverting brings back the crash for everyone with Eclipse plugins on their
     next DBeaver version update (`ClassNotFoundException: org.eclipse.core.runtime.adaptor.EclipseStarter`).
   - Everything else (#372–#374) is safe to revert.
4. **Revert** if needed: `git revert -m 1 <merge commit>` on a branch, PR, wait for the Flathub test
   build, merge. Flathub publishes the next build to everyone.
5. **Afterwards:** add the failing case to `.github/test_run_*.sh` and/or `tests/vm/scenarios/`.

## Testing a change

- **Self-checks** (seconds, no Flatpak needed): `.github/test_run_migrate.sh` and
  `.github/test_run_plugins.sh` run the real `run.sh` blocks against fake homes.
  `python3 .github/release_notes.py io.dbeaver.DBeaverCommunity.appdata.xml --check` checks the
  release-notes converter.
- **Local build:** `bash build_install.sh`.
- **VM tests** on Ubuntu, Debian, Arch, openSUSE and Fedora (Silverblue layout), starting from the
  published builds: see [tests/vm/README.md](tests/vm/README.md). Run them before merging anything
  that touches `run.sh` or the manifest's startup, and refresh the golden images first for the final run.

## Automation

- **flathubbot** opens update PRs (new upstream version) and adds a `<release>` entry to the appdata.
- **`.github/workflows/validate-update.yml`** checks those PRs' sources, builds and smoke-tests them,
  and its `release-notes` job fills the empty release description from the upstream GitHub release
  (`.github/release_notes.py`); it never blocks an update.
- **Flathub** builds every PR (`builds/x86_64` check, with a test-install command in its comment)
  and publishes `master` after merge.

## Known limitations and open work

- aarch64 is built by Flathub but not tested here.
- Homes reached through a symlink other than `/var/home`: paths stored in that other spelling keep
  pointing at the old folder (README warns before deleting it).
- Eclipse plugins after a version update: see "Key facts" above.
- Dropping home access (#316 phase 2) needs: `~/.java/.userPrefs` (EULA, `DeploymentId`), `~/.ssh`
  keys, **certificate and key files that connections reference by path** (e.g. `~/certificates/ca.pem`;
  host CA trust itself is already independent of home access), user scripts/exports/SQLite files, host database clients (e.g. `mysqldump`), project
  `.location` files outside the workspace, and the file-chooser portal's paths.
- Phase 2 must keep read-only access to the two old folders (`~/.local/share/DBeaverData`,
  `~/.eclipse`) so users who skip every phase 1 build still get migrated; otherwise wait 6+ months.
- Upstream-blocked: #203 (Flathub verification needs the dbeaver.io domain owner);
  WebKit/runtime crashes like #371 come from the GNOME runtime, not this repo.
