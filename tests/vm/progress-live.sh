#!/bin/bash
# Live feed of the DBeaver Flatpak VM tests: every result line appears the moment a VM writes it.
# Read-only (follows the serial logs). Usage: progress-live.sh [LOG_DIR]; Ctrl+C or close to stop.
V=${1:-${DBEAVER_VM_DIR:-$HOME/.local/share/libvirt/images/dbeaver-test}/logs}
running=$(virsh -c qemu:///session list --name 2>/dev/null | grep . | sed 's/^dbtest-//; s/^dbprep-/prep-/')
echo "DBeaver Flatpak VM tests — live feed since $(date '+%H:%M:%S'). Running VM: ${running:-none}"
echo "Green = worked, red = problem. Older runs' lines are not shown."
echo

follow() {  # follow NAME FILE: its result lines, prefixed with time and name, deduplicated, coloured
    local d=$1 f=$2 from=0
    [ "$d" = "$running" ] && from=+1   # the running VM: show what it already wrote, too
    tail -n "$from" -F "$f" 2>/dev/null \
        | grep -a --line-buffered -o 'RESULT .*' \
        | sed -u 's/\r//g; s/\[ *[0-9.]*\] RESULT.*//; s/^RESULT //' \
        | awk -v d="$d" '
            !seen[$0]++ {
                c = ""
                if ($0 ~ /started=NO|started=ERROR|started=TIMEOUT|FATAL|WARN|Could not|Not enough|Old paths|=NO|vrapper= |rc=[1-9]/) c = "\033[31m"
                else if ($0 ~ /started=yes|started=wizard|ACTIVE|DONE|=yes/) c = "\033[32m"
                printf "%s %s%-13s %s\033[0m\n", strftime("%H:%M:%S"), c, d, $0; fflush()
            }'
}
for d in ubuntu debian arch opensuse fedora; do
    follow "$d" "$V/$d.log" &                      # test runs
    follow "prep-$d" "$V/prep-$d.log" &   # golden-image prep
done
wait
