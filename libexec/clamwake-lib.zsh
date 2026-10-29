# clamwake: what the command and the daemon share (sourced, not run).
# Paths come from the install prefix (the folder above bin/ and libexec/), or CLAMWAKE_CONF / CLAMWAKE_VAR.

CLAMWAKE_PREFIX=${CLAMWAKE_PREFIX:-${${(%):-%x}:A:h:h}}
CONF=${CLAMWAKE_CONF:-$CLAMWAKE_PREFIX/etc/clamwake.conf}
VAR=${CLAMWAKE_VAR:-$CLAMWAKE_PREFIX/var/clamwake}
MODE_FILE=$VAR/mode
HOMES_FILE=$VAR/homes
STATE_FILE=$VAR/state
LOG_FILE=${CLAMWAKE_LOG:-$CLAMWAKE_PREFIX/var/log/clamwake.log}

# Settings (clamwake.conf may override them, see read_conf)
battery_floor=20
thermal_trip=Heavy
thermal_clear=600
thermal_check=30
network_check=60
tick=10                     # seconds between looks on AC or in mode on (lid, mode file, network, heat)
idle_tick=60                # on battery in auto, or in off: only the mode file can change anything

# clamwake.conf is read as data, never run: the daemon is root, and the file belongs to the user. Only known keys
# with valid values are taken; any other line is reported and ignored
read_conf() {
  local line key value n=0
  [[ -r $CONF ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    (( n++ ))
    line=${line%%\#*}
    [[ $line == *[^[:space:]]* ]] || continue
    key=${${line%%=*}//[[:space:]]/} value=${${line#*=}//[[:space:]]/}
    if [[ $line == *=* ]] && case $key in
         battery_floor) [[ $value == <0-100> ]];;
         thermal_trip) [[ $value == (Moderate|Heavy|Trapping) ]];;
         thermal_clear|thermal_check|network_check|tick|idle_tick) [[ $value == <1-> ]];;
         *) false;;
       esac; then
      typeset -g $key=$value
    else
      print -u2 -r -- "clamwake: $CONF:$n: ignored: $line"
    fi
  done < $CONF
}
read_conf

typeset -A LEVEL=(Nominal 0 Moderate 1 Heavy 2 Trapping 3 Sleeping 4)

log() { print -r -- "$(date '+%F %T') $*" >> $LOG_FILE 2>/dev/null; }

mode() { local m=""; [[ -r $MODE_FILE ]] && m=$(<$MODE_FILE); [[ $m == (on|off|auto) ]] && print $m || print auto; }

# "AC" or "Battery", and the battery percent
power_source() { pmset -g ps | head -1 | grep -q "AC Power" && print AC || print Battery; }
battery_percent() { pmset -g ps | grep -o '[0-9]*%' | head -1 | tr -d %; }

# The default gateway's IP and MAC (lower case, two digits each), or nothing
gateway_ip() { route -n get default 2>/dev/null | awk '/gateway:/{print $2}'; }
gateway_mac() {
  local ip=$1 mac
  [[ -n $ip ]] || return
  mac=$(arp -n $ip 2>/dev/null | awk '{print $4}')
  [[ $mac == *:* ]] || return
  # arp drops leading zeros (0:25:36:d:5:de): pad each part to two digits
  print -r -- $mac | awk -F: '{for (i = 1; i <= NF; i++) {x = tolower($i); if (length(x) == 1) x = "0" x; printf "%s%s", (i > 1 ? ":" : ""), x} print ""}'
}

# 0 when the current network is a remembered home (or none is remembered), with the home's name in REPLY
at_home() {
  REPLY=""
  [[ -s $HOMES_FILE ]] || { REPLY="any network"; return 0; }
  local mac; mac=$(gateway_mac "$(gateway_ip)")
  [[ -n $mac ]] || return 1
  local line; line=$(awk -F'\t' -v m=$mac '$1 == m {print $3; exit}' $HOMES_FILE)
  [[ -n $line ]] || return 1
  REPLY=$line
}

lid_closed() { ioreg -r -k AppleClamshellState -d 1 | grep -q '"AppleClamshellState" = Yes'; }

# Current pressure level (root only); empty when it cannot be read
thermal_level() { powermetrics --samplers thermal -i 1000 -n 1 2>/dev/null | awk -F': ' '/Current pressure level/{print $2}'; }

sleep_disabled() { pmset -g | awk '/SleepDisabled/{print $2; f=1} END{if(!f) print 0}'; }
