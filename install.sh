#!/bin/zsh
# clamwake installer. Run it from the clone as your normal user (not with sudo): it asks for your password when it
# needs root. Safe to run again, also to update after `git pull`.
# Copies everything into /usr/local, owned by root (the daemon runs as root, so it must not run files the user can
# change), except var/clamwake, which `clamwake on|off|auto` and `clamwake home add` write without sudo.
set -eu

[[ $(uname) == Darwin ]] || { print -u2 "clamwake runs on macOS only"; exit 1; }
(( EUID != 0 )) || { print -u2 "run it as your normal user (no sudo): it asks for your password when needed"; exit 1; }

HERE=${0:A:h}
PREFIX=/usr/local
LABEL=io.github.otaqq.clamwake
PLIST=/Library/LaunchDaemons/$LABEL.plist

print "==> Installing into $PREFIX"
# Make only the folders that are missing: on an Intel Mac, Homebrew owns /usr/local/bin and others, leave them be
for d in bin libexec etc var var/log; do
  [[ -d $PREFIX/$d ]] || sudo install -d -o root -g wheel -m 755 $PREFIX/$d
done
sudo install -o root -g wheel -m 755 $HERE/bin/clamwake $PREFIX/bin/clamwake
sudo install -o root -g wheel -m 755 $HERE/libexec/clamwaked $PREFIX/libexec/clamwaked
sudo install -o root -g wheel -m 644 $HERE/libexec/clamwake-lib.zsh $PREFIX/libexec/clamwake-lib.zsh
# Keep the settings and the remembered home networks of an earlier install
[[ -e $PREFIX/etc/clamwake.conf ]] || sudo install -o root -g wheel -m 644 $HERE/share/clamwake.conf $PREFIX/etc/clamwake.conf
[[ -d $PREFIX/var/clamwake ]] || sudo install -d -o $(id -un) -g $(id -gn) -m 755 $PREFIX/var/clamwake

print "==> Installing the LaunchDaemon $PLIST"
tmp=$(mktemp)
sed "s|PREFIX|$PREFIX|g" $HERE/share/$LABEL.plist > $tmp
plutil -lint -s $tmp
sudo install -o root -g wheel -m 644 $tmp $PLIST
rm -f $tmp

print "==> Starting clamwaked"
sudo launchctl bootout system/$LABEL 2>/dev/null || true
# bootout returns before the old daemon is gone, and bootstrap fails until then (37: Operation already in progress)
for i in {1..20}; do
  sudo launchctl print system/$LABEL >/dev/null 2>&1 || break
  sleep 0.5
done
sudo launchctl bootstrap system $PLIST
sleep 3

print
$PREFIX/bin/clamwake doctor
print
[[ -s $PREFIX/var/clamwake/homes ]] ||
  print "No home network remembered: every network counts as home. On the home network, run: clamwake home add home"
if [[ $HERE == */Caskroom/* ]]; then print "To remove clamwake: brew uninstall clamwake (--zap: settings and home networks too)"
else print "To remove clamwake: $HERE/uninstall.sh"; fi
