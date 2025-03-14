#!/usr/bin/env bash

WORKSPACE_FOLDER="$XDG_DATA_HOME/workspace"
CONFIG_FOLDER="$XDG_CONFIG_HOME/eclipse"
DRIVERS_FOLDER="$XDG_DATA_HOME/drivers"

# When the app is first lanched since the deployment of the new storage strategy (XDG DATA DIRS)
if [ ! -d "$WORKSPACE_FOLDER" ]
then
	if [ -d "$HOME/.local/share/DBeaverData/workspace6" ]
	then
		# If workspace data is in old place (the app was already installed), start the migration process
		cp -r "$HOME"/.local/share/DBeaverData/workspace6 "$WORKSPACE_FOLDER"
		cp -r "$HOME"/.local/share/DBeaverData/drivers "$DRIVERS_FOLDER" || echo "INFO: No drivers to migrate"
		/app/bin/migration-dialog m
	else
		# Otherwise, the app was freshly installed so welcome the new user with this sandboxing feature
		# We might remove this notice in the future, although this is still open for debate.
		/app/bin/migration-dialog
	fi
fi
exec /app/bin/dbeaver -data "$WORKSPACE_FOLDER" -configuration "$CONFIG_FOLDER" "$@"