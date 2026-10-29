#!/bin/zsh
# Remove clamwake and let the Mac sleep as usual. Run it as your normal user (not with sudo). Safe to run again.
# No `set -e` on purpose: go on and remove as much as possible.
set -u

(( EUID != 0 )) || { print -u2 "run it as your normal user (no sudo): it asks for your password when needed"; exit 1; }

PREFIX=/usr/local
LABEL=io.github.otaqq.clamwake
PLIST=/Library/LaunchDaemons/$LABEL.plist

print "==> Stopping clamwaked (it sets disablesleep 0 as it stops)"
sudo launchctl bootout system/$LABEL 2>/dev/null
sudo rm -f $PLIST
# Also when the daemon could not do it
sudo pmset -a disablesleep 0

print "==> Removing the files in $PREFIX (settings and remembered home networks too)"
sudo rm -f $PREFIX/bin/clamwake $PREFIX/libexec/clamwaked $PREFIX/libexec/clamwake-lib.zsh \
  $PREFIX/etc/clamwake.conf $PREFIX/var/log/clamwake.log $PREFIX/var/log/clamwake.err
sudo rm -rf $PREFIX/var/clamwake
# Folders only when nothing else is left in them
for d in var/log var etc libexec bin; do
  sudo rmdir $PREFIX/$d 2>/dev/null
done

print
print "Done. SleepDisabled is $(pmset -g | awk '/SleepDisabled/{print $2; f=1} END{if(!f) print 0}')."
print "This folder (${0:A:h}) is left; delete it if you no longer need it."
