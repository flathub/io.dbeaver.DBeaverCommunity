#!/bin/bash
# Opens a terminal window with the live VM test feed (it only reads logs; close it any time).
# Terminal: $VM_TERMINAL (default: foot); it must accept the command to run as trailing arguments.
H=$(dirname "$(readlink -f "$0")")
exec ${VM_TERMINAL:-foot} "$H/progress-live.sh" "$@"
