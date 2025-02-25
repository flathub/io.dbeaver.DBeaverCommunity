#!/usr/bin/env bash

WORKSPACE_FOLDER="$XDG_DATA_HOME/workspace"
DRIVERS_FOLDER="$XDG_DATA_HOME/drivers"

# If workspace data is still in old place, start the migration process
if [ -d "$HOME/.local/share/DBeaverData/workspace6" ] && [ ! -d "$WORKSPACE_FOLDER" ]
then
  cp -r "$HOME"/.local/share/DBeaverData/workspace6 "$WORKSPACE_FOLDER"
  cp -r "$HOME"/.local/share/DBeaverData/drivers "$DRIVERS_FOLDER"
  /app/bin/migration-dialog
fi

exec /app/bin/dbeaver -data "$WORKSPACE_FOLDER"