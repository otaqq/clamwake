# clamwake

Keep a MacBook awake with the lid closed while it is plugged in (and, optionally, only on the home network), and let
it sleep again as soon as it is unplugged or runs hot. Written in zsh; nothing to compile.

For a MacBook used as a small server, for example an Ollama node that other machines send requests to. With the lid
closed, macOS sleeps even on AC with `pmset sleep 0`; the network can wake it only into DarkWake, and requests hang.
`pmset disablesleep 1` is the only setting that keeps it awake, and it is global: clamwake switches it on and off by
the conditions below, and always back off when it stops.

Status: first version, not yet tested on a Mac. See [docs/SPEC.md](docs/SPEC.md) for the design and what was checked.

## Install

```sh
brew install otaqq/tap/clamwake
sudo brew services start clamwake
clamwake home add home    # once, on the home network (optional)
clamwake doctor           # check every input and the decision
```

## Use

```
clamwake auto           # default: awake on AC, on a home network, not too hot
clamwake on             # awake on battery too (until battery_floor)
clamwake off            # leave sleep to macOS
clamwake status         # one line: mode and decision
clamwake doctor         # every input, the decision and what to do about it
clamwake home add [name] | home list | home remove <n>
clamwake log [n]
```

No sudo: the command writes files the daemon reads within `tick` seconds (10; 60 on battery); only the daemon (root) runs `pmset`.

```
mode       auto
power      AC (100%)                                ok
network    gateway 192.168.1.1 aa:bb:cc:dd:ee:ff    home (home)
heat       Nominal                                  ok
lid        closed
daemon     running (pid 123)                        last decision 3s ago
decision   awake (AC, home home)                    pmset disablesleep is 1
```

## How it decides

| Mode | Awake when |
|---|---|
| `auto` | on AC, **and** on a home network (any network if none is remembered), **and** not tripped by heat |
| `on` | always, unless tripped by heat or the battery is at or below `battery_floor` |
| `off` | never |

- **Power**: follows `pmset -g pslog`, so pulling the charger takes effect at once.
- **Home network**: the default gateway's MAC address, remembered with `clamwake home add`. Wi-Fi names are not
  used (macOS hides them from a root daemon).
- **Heat**: the thermal pressure from `powermetrics`. At `thermal_trip` (Heavy) clamwake lets the Mac sleep (and
  sleeps it at once if the lid is closed) until the pressure has been Nominal for `thermal_clear` seconds.
- **Display**: when the lid closes while awake, `pmset displaysleepnow` turns the built-in display off.
- When the daemon stops or an input cannot be read, `disablesleep` goes back to 0.

## Settings

`$(brew --prefix)/etc/clamwake.conf` ([share/clamwake.conf](share/clamwake.conf)); restart the daemon after a change.

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
| `$(brew --prefix)/etc/clamwake.conf` | settings |
| `$(brew --prefix)/var/clamwake/` | `mode`, `homes`, `state` (the daemon's last decision) |
| `$(brew --prefix)/var/log/clamwake.log` | decisions, trips, errors |

## Without Homebrew

Clone the repository anywhere; `etc/` and `var/` are then made inside it. Try the daemon without root first: it
decides and logs, but changes nothing (heat is unknown without root).

```sh
libexec/clamwaked --dry-run &
bin/clamwake doctor
tail -f var/log/clamwake.log
```

To run it for real, replace `PREFIX` in [share/io.github.otaqq.clamwake.plist](share/io.github.otaqq.clamwake.plist)
with the clone's path, then:

```sh
sudo cp share/io.github.otaqq.clamwake.plist /Library/LaunchDaemons/
sudo launchctl bootstrap system /Library/LaunchDaemons/io.github.otaqq.clamwake.plist
# stop and remove: sudo launchctl bootout system/io.github.otaqq.clamwake (sets disablesleep 0)
```

## Requirements

macOS 14 or later, Apple Silicon. zsh and every tool used ship with macOS.

## License

MIT
