# clamwake — specification

Keep a MacBook awake with the lid closed while it is plugged in (and, optionally, only on the home network), and let
it sleep again as soon as it is unplugged or runs hot. Written in zsh; installed with Homebrew (a cask) or install.sh.

Status: 2026-10-29. Runs as a root LaunchDaemon on a MacBook Air (see "Checked").

## Why

A MacBook used as a small server (for example an Ollama node that another machine sends requests to) goes to sleep
when its lid is closed, even with `pmset sleep 0` and the charger in. Requests sent to it then hang for minutes:
the network can wake it only into DarkWake, which does not keep services answering, and it falls asleep again
after about 40 seconds. The only setting that keeps a Mac awake with the lid closed is `pmset disablesleep 1`. It
is global (not per power source), so something has to switch it on and off by the conditions below.

## Behaviour

clamwake runs as a root LaunchDaemon (`clamwaked`) and sets `disablesleep` to 1 ("awake") or 0 ("normal").

| Mode | Awake when |
|---|---|
| `auto` (default) | on AC power, **and** on a home network (if any are configured), **and** not tripped by heat |
| `on` | always, unless tripped by heat or the battery is at or below `battery_floor` |
| `off` | never (clamwake leaves sleep to macOS) |

- The mode is kept across restarts (state file). `clamwake on|off|auto` changes it; `clamwake status` prints one
  line (mode and decision), `clamwake doctor` the full picture (see "Diagnosis").
- Whenever clamwake stops, is uninstalled, or cannot decide (an input fails), it sets `disablesleep 0`. It never
  leaves a Mac unable to sleep by accident. (`disablesleep` is stored in
  /Library/Preferences/com.apple.PowerManagement.plist as `SleepDisabled`, so a 1 left behind outlives a reboot.)
  The LaunchDaemon starts clamwaked only if it is there and sets `disablesleep 0` otherwise, so a clamwake removed
  while its LaunchDaemon stays still lets the Mac sleep; `clamwake doctor` warns when sleep is disabled but no daemon
  is deciding.

### Inputs

| Input | How it is read | When |
|---|---|---|
| Power source (AC / battery, battery %) | `pmset -g pslog` as the trigger (the daemon blocks on it), then `pmset -g ps` for the state: a change may come as a bare `com.apple.system.powersources` line with no details | at once, on every change |
| Home network | the default gateway (`route -n get default`) and its MAC address (`arp -n`), compared with the remembered home networks | in `auto` on AC: when the power changes, then every `network_check` seconds (60); every tick while there is no gateway (right after a wake) |
| Heat | the line `Current pressure level: Nominal` of `powermetrics --samplers thermal -i 1000 -n 1` (root; without `-i` it samples 5 s): Nominal / Moderate / Heavy / Trapping / Sleeping | every `thermal_check` seconds (30) while awake |
| Lid | `ioreg -r -k AppleClamshellState` | with every decision (for heat and display handling) |

Without a line from `pmset -g pslog`, the daemon looks again every `tick` seconds (10) on AC or in `on`, and every
`idle_tick` seconds (60) on battery in `auto` or in `off`, where only the mode file can change the decision.

Wi-Fi names (SSIDs) are not used: recent macOS versions redact them unless the asking process has Location
permission, which a root daemon does not get. A gateway MAC address identifies the home network without it.

### Home networks

Nobody types a MAC address. On the network to remember:

```
clamwake home add [name]     # remember the current network (its gateway MAC) as home, e.g. "clamwake home add home"
clamwake home list           # number, name, gateway IP and MAC, when added
clamwake home remove <n>     # forget one
```

- Any number can be remembered (home, office). With none, every network counts as home (AC alone decides).
- A new router has a new MAC: `doctor` then says the network is not home and suggests `clamwake home add`.
- Stored in `/usr/local/var/clamwake/homes` (one line each: MAC, IP, name, date).

### Heat guard (always on)

- Trip when the thermal pressure is `thermal_trip` (Heavy) or higher: set `disablesleep 0`, and if the lid is
  closed, put the Mac to sleep (`pmset sleepnow`).
- Stay tripped until the pressure has been Nominal for `thermal_clear` seconds (600); then decide again.
- Every trip and clear is logged.

### Display

`disablesleep` does not turn the built-in display off when the lid closes; it stays lit until `displaysleep` runs
out. When the lid closes while awake, clamwake runs `pmset displaysleepnow`.

## Diagnosis

`clamwake doctor` prints each input, whether it allows staying awake, and the decision, with the reason and what to
do when it says no:

```
mode        auto
power       AC (100%)                          ok
network     gateway 192.168.1.1 aa:bb:cc:…     home ("home")
heat        Nominal                            ok
lid         closed
daemon      running (pid 123), last decision 12 s ago
decision    awake (disablesleep 1)
```

e.g. `network  gateway 10.0.0.1 11:22:…  not home: run "clamwake home add" here if it is`, or
`daemon  not running: run install.sh again (from the clone)`.

## Settings

`/usr/local/etc/clamwake.conf` (owned by root): `key=value` lines, read as data and never run (the daemon is root). Unknown keys and invalid values are reported (in the error log or on the terminal) and ignored.

```
battery_floor=20      # mode on: sleep at or below this battery %
thermal_trip=Heavy    # Moderate | Heavy | Trapping
thermal_clear=600     # seconds of Nominal before awake again
thermal_check=30
network_check=60
tick=10               # seconds between looks on AC or in mode on
idle_tick=60          # on battery in auto, or in off
```

## Files

| Path | What |
|---|---|
| `/usr/local/bin/clamwake` | the command: `on`, `off`, `auto`, `status`, `doctor`, `log`, `home add/list/remove` |
| `/usr/local/libexec/clamwaked` | the daemon loop (with `clamwake-lib.zsh`, shared with the command) |
| `/usr/local/etc/clamwake.conf` | settings |
| `/usr/local/var/clamwake/mode` | the mode |
| `/usr/local/var/clamwake/homes` | the remembered home networks |
| `/usr/local/var/log/clamwake.log` | decisions, trips, errors |
| `/Library/LaunchDaemons/io.github.otaqq.clamwake.plist` | the LaunchDaemon (root) |

Everything is owned by root, except `/usr/local/var/clamwake/`, which belongs to the user so that the command needs
no sudo. The daemon runs as root, so it must not run files the user can change.

## Install

```
brew install otaqq/tap/clamwake                  # or, from a clone: ./install.sh (as the normal user)
clamwake home add home    # once, on the home network
clamwake doctor           # check every input and the decision
```

`install.sh` makes only the folders under `/usr/local` that are missing (on an Intel Mac, Homebrew owns some of
them), copies the files, installs the plist and starts the daemon; it keeps the settings and home networks of an
earlier install. `uninstall.sh` stops the daemon, sets `disablesleep 0`, removes every file above (settings and home
networks too) and the folders left empty; `--keep-data` keeps the settings, home networks and log. Both refuse a
plain root shell; under sudo they give var/clamwake to the user behind sudo.

Homebrew: a cask in the tap [otaqq/homebrew-tap](https://github.com/otaqq/homebrew-tap) (`Casks/clamwake.rb`), not a
formula, because a formula installs into the Homebrew prefix, owned by the user, and the root daemon must not run
files the user can change. The cask downloads the tagged source tarball and runs the same scripts with sudo (a cask's
installer must not be interactive): `install.sh` to install, `uninstall.sh --keep-data` to uninstall (Homebrew
upgrades by uninstalling first, so the settings and home networks must stay), and with `--zap` then `uninstall.sh`.

`clamwake on|off|auto` changes the mode without sudo (a file the daemon watches); only the daemon runs `pmset`.

## Requirements

macOS 14 or later, Apple Silicon (tested on a MacBook Air). zsh and the tools above ship with macOS.

## Not in the first version

- Menu bar icon: later, as a SwiftBar plugin (SwiftBar is open source and installs with Homebrew) that calls
  `clamwake status` and `on|off|auto`.
- Exact temperatures (IOHID, needs Swift or C): only if thermal pressure proves too coarse.

## Checked (2026-10-29, MacBook Air Mac17,3, macOS 26.6 25G72)

- `powermetrics --samplers thermal -n 1` (root) prints `Current pressure level: Nominal`, after sampling 5 s.
- `pmset -g pslog` runs without root; it starts with the current source (`Now drawing from 'AC Power'`). It also
  printed a bare `com.apple.system.powersources` line while the charger stayed in: such lines are not always a change
  of source, so the daemon reads `pmset -g ps` and acts only when the source differs.
- Pulling the charger out and back in: `pmset -g pslog` printed `Now drawing from 'Battery Power'` / `'AC Power'`
  with `com.apple.system.powersources.source` lines, and kept printing across the sleeps in between.
- With the lid open, on AC and `pmset sleep 0`, the Mac still slept: after the charger woke it (FullWake), it went
  back to sleep 4 s later (`Notification Wake Back to Sleep`), and earlier by `Maintenance Sleep`. On battery it
  went to `Idle Sleep` 5 s after the charger was pulled. So an open lid is not enough either; `disablesleep` is.
- `pmset displaysleepnow` works without root. A `caffeinate -u` assertion still active turns the display on again.
- `route -n get default` and `arp -n <gateway>` give the gateway IP and MAC without root.
- Homebrew is at /opt/homebrew and not on the PATH of a non-login shell: call it by its full path.

Running clamwaked as a root LaunchDaemon (the plist in share/, `launchctl bootstrap system`), same day and Mac:

- `sudo launchctl submit` runs the job as the calling user, not root (pmset then fails); `launchctl bootstrap system`
  with a root-owned plist in /Library/LaunchDaemons runs it as root, also over ssh.
- Lid closed on AC, `disablesleep 1`: the Mac stayed awake and reachable over the network for 4.5 h.
- Lid closed, charger pulled: `disablesleep 0` within a second, and the Mac slept 9 s later (Idle Sleep). Another
  time it slept only after about 2 min, while an app held a `PreventUserIdleSystemSleep` assertion.
- Lid closed, charger plugged in: the Mac woke and was awake again (`disablesleep 1`) within 1-2 s, twice. Once the
  network was not up yet at the wake, the daemon saw no home network, and the Mac went back to sleep 45 s later.
- `pmset -g pslog` kept reporting across sleeps and wakes (not checked across a reboot).
- pslog's output reaches a pipe in pieces, so zsh's `read -t` does not time out while waiting for the rest of a line;
  `sysread -t` (zsh/system) does.
- `pmset` run without root prints `'pmset' must be run as root...` and still exits 0.
- `SleepDisabled` is stored in /Library/Preferences/com.apple.PowerManagement.plist.
- `powermetrics --samplers thermal -i 1000 -n 1` from the daemon read `Nominal`.
- A plist pointing at a missing clamwaked set `disablesleep` back to 0.

Installed with install.sh into /usr/local, same day and Mac:

- install.sh, then install.sh again over the running daemon, then uninstall.sh: /usr/local was as before the
  install (no files or folders left), no plist, job or process, `SleepDisabled` 0.
- The display: with the lid closed, clamwake ran `pmset displaysleepnow` and pmset's log said `Display is turned off`
  in the same second; the display stayed dark, and lit again when the lid was opened a little.
- Reboot: the daemon got TERM and set 0 before the shutdown; after the boot it started without anyone logged in, first
  saw no network (not home, 0), and found the home network at the next tick, 10 s later (1). pslog ran again.
  (A LaunchAgent, such as a user's Ollama, does not start until someone logs in.)
- Heat, with `thermal_trip=Moderate` and `thermal_clear=60` for the test: about 4 min of LLM generation on the
  fanless MacBook Air brought the pressure to `Moderate`; the daemon tripped and set 0 in the same second. After the
  load stopped, the pressure was Nominal within a minute, and the daemon cleared and set 1 after 60 s of Nominal.

Homebrew 7.0.9, same Mac:

- `brew install otaqq/tap/clamwake` tapped otaqq/tap, ran install.sh with sudo (one password prompt) and used the home
  networks kept by an earlier `--keep-data`.
- `brew uninstall clamwake` left only etc/, var/clamwake and var/log; `brew uninstall --zap clamwake` ran
  `uninstall.sh --keep-data` first, then `uninstall.sh` (the staged scripts were still there), and left /usr/local
  as before the install, no plist, `SleepDisabled` 0.

## To check

- The level names above Moderate (`Heavy`, `Trapping`, `Sleeping`: not seen yet), and a trip at the default
  `thermal_trip=Heavy`.
- A heat trip with the lid closed (the daemon then runs `pmset sleepnow`).
- `brew upgrade clamwake` (needs a second release).

## Prior art

- [fainir/mac-keepawake](https://github.com/fainir/mac-keepawake) (MIT): shell, root LaunchDaemon following
  `pmset -g pslog` to keep the lid-closed Mac awake on AC. clamwake takes this approach.
- [acastro2/lid-awake](https://github.com/acastro2/lid-awake) (MIT): Swift menu bar app with a thermal guard
  (trip at 90 °C, clear below 75 °C).
- [karmahacker/battguard](https://github.com/karmahacker/battguard): low-battery sleep and turning the display off
  when the lid closes.
- [Aboudjem/Sleepless](https://github.com/Aboudjem/Sleepless) (MIT): menu bar app with a battery floor, Homebrew cask.

## License

MIT.
