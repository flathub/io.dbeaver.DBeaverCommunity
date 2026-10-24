#!/bin/bash
# Self-check for run.sh's "Remember SSH host keys" block.
# Runs the real block against a fake home. Usage: .github/test_run_ssh.sh [run.sh]
RUN_SH=${1:-run.sh}
ROOT=$(mktemp -d); trap 'rm -rf "$ROOT"' EXIT
BLOCK=$(sed -n '/--- Remember SSH host keys/,/--- STEP 3/p' "$RUN_SH")
[ -n "$BLOCK" ] || { echo "SSH block not found in $RUN_SH"; exit 1; }
fail=0; check() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1"; fail=1; fi; }

setup() {  # setup HOME: a fresh fake home with the Flatpak folders under it
    rm -rf "$ROOT/h"; HOME="$1"; XDG_CONFIG_HOME="$HOME/.var/app/x/config"
    CONFIG_AREA="$XDG_CONFIG_HOME/eclipse/configuration"; PREFS="$CONFIG_AREA/.settings/org.eclipse.jsch.core.prefs"
    mkdir -p "$HOME"
}
run_ssh() { eval "$BLOCK" >/dev/null 2>&1; }

echo "== fresh user, no ~/.ssh"
setup "$ROOT/h/u"; run_ssh
check "SSH home created, private"       '[ "$(stat -c %a "$XDG_CONFIG_HOME/ssh")" = 700 ]'
check "Eclipse points at it"            '[ "$(cat "$PREFS")" = "$(printf "eclipse.preferences.version=1\nSSH2HOME=%s" "$XDG_CONFIG_HOME/ssh")" ]'

echo "== existing ~/.ssh/known_hosts"
setup "$ROOT/h/u"; mkdir -p "$HOME/.ssh"; echo "host1 ssh-ed25519 AAAA" > "$HOME/.ssh/known_hosts"; run_ssh
check "known hosts copied"              'cmp -s "$HOME/.ssh/known_hosts" "$XDG_CONFIG_HOME/ssh/known_hosts"'
echo "host2 ssh-ed25519 BBBB" >> "$XDG_CONFIG_HOME/ssh/known_hosts"; cp "$PREFS" "$ROOT/prefs1"; run_ssh
check "own copy kept on restart"        'grep -q host2 "$XDG_CONFIG_HOME/ssh/known_hosts" && [ "$(wc -l < "$HOME/.ssh/known_hosts")" = 1 ]'
check "preferences left alone"          'cmp -s "$PREFS" "$ROOT/prefs1"'

echo "== preferences already there"
setup "$ROOT/h/u"; mkdir -p "$(dirname "$PREFS")"; printf 'eclipse.preferences.version=1\nSSH2HOME=/custom\n' > "$PREFS"; run_ssh
check "user's SSH2 home kept"           '[ "$(grep -c SSH2HOME "$PREFS")" = 1 ] && grep -qx "SSH2HOME=/custom" "$PREFS"'
printf 'eclipse.preferences.version=1\nPRIVATEKEY=id_rsa\n' > "$PREFS"; run_ssh
check "added next to other settings"    'grep -qx PRIVATEKEY=id_rsa "$PREFS" && grep -q "^SSH2HOME=" "$PREFS" && [ "$(grep -c version "$PREFS")" = 1 ]'

echo "== home with a space, non-ASCII and a backslash"
setup "$ROOT/h/Jé 😀\\x"; run_ssh
check "SSH home created there"          '[ -d "$XDG_CONFIG_HOME/ssh" ]'
check "value escaped for Java"          'grep -qxF "SSH2HOME=$ROOT/h/J\\u00e9 \\ud83d\\ude00\\\\x/.var/app/x/config/ssh" "$PREFS"'

[ $fail = 0 ] && echo "ALL OK" || { echo "FAILURES"; exit 1; }
