#!/usr/bin/env bash

WORKSPACE_FOLDER="$XDG_DATA_HOME/workspace"
CONFIG_FOLDER="$XDG_CONFIG_HOME/eclipse"
DRIVERS_FOLDER="$XDG_DATA_HOME/drivers"

# New users are informed of the improved sandboxing options.
# We might remove this notice in the future, although this is still open for debate.
if [ ! -d "$WORKSPACE_FOLDER" ]
then
  cp -r "$HOME"/.local/share/DBeaverData/workspace6 "$WORKSPACE_FOLDER"
  cp -r "$HOME"/.local/share/DBeaverData/drivers "$DRIVERS_FOLDER"

  zenity --info --title="DBeaver sandboxing" --text="If you want to, you can now improve DBeaver' sandboxing by remove Home-access. To do so, you can use an application like Flatseal."
fi


# If workspace data is still in old place, start the migration process
if [ -d "$HOME/.local/share/DBeaverData/workspace6" ] && [ ! -d "$WORKSPACE_FOLDER" ]
then
  cp -r "$HOME"/.local/share/DBeaverData/workspace6 "$WORKSPACE_FOLDER"
  cp -r "$HOME"/.local/share/DBeaverData/drivers "$DRIVERS_FOLDER"

  zenity --info --title="DBeaver improved sandboxing" --text="The default location for storing DBeaver's files has changed. They are now stored in the \"/.var/app/io.dbeaver.DBeaverCommunity\" folder. \n\nIf you want to, you can now improve DBeaver' sandboxing by remove Home-access. To do so, you can use an application like Flatseal."
fi

exec /app/bin/dbeaver -data "$WORKSPACE_FOLDER" -configuration "$CONFIG_FOLDER" "$@"
