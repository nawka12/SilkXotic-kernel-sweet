#!/usr/bin/env bash
# SilkXotic BATTERY-per-fixed-workload A/B driver (coulomb counter).
# The roadmap's "one untried measurement": run an IDENTICAL fixed workload (loadbench
# sustained phase) and measure charge consumed (Δ charge_counter, µAh) + energy (µWh).
# Compares stock vs SilkXotic for the SAME work -> the efficiency win (if any) shows here,
# where the latency/throughput benches showed a wash.
#
# WHY THIS IS HARD (and why it hard-aborts): we run over USB, which charges the battery,
# so a raw charge_counter delta is garbage. We must STOP charge input and then VERIFY it
# stopped (charge_counter must not rise) before trusting any number. No clean stop -> abort.
#
# PREREQ: ADB-shell root. KSU does not grant su to adb by default — enable it once in the
# KernelSU-Next manager (Superuser -> grant "Shell"/ADB). Without root we can only try the
# framework-level `dumpsys battery set`, which may not stop real hardware charging.
#
# Usage: ./benchbatt.sh [tag] [iterations]
# Env: SUS_S (workload secs, default 180), IV_S (sample interval, default 10),
#      COOL_C (cooldown °C, default 40), COOL_MAX_S (max cooldown wait, default 300),
#      BRIGHT (fixed screen brightness 0-255, default 40)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/bin/loadbench-arm64"; RESDIR="$HERE/results"; mkdir -p "$RESDIR"
SUS_S="${SUS_S:-180}"; IV_S="${IV_S:-10}"; LAT_S=2
COOL_C="${COOL_C:-40}"; COOL_MAX_S="${COOL_MAX_S:-300}"; BRIGHT="${BRIGHT:-40}"; ITERS="${2:-3}"

A(){ adb shell "$@" 2>/dev/null | tr -d '\r'; }                       # unprivileged
SU(){ adb shell "su -c '$*'" 2>/dev/null | tr -d '\r'; }              # root (KSU)
die(){ echo "!! $*" >&2; exit 1; }
[ -f "$BIN" ] || die "loadbench missing: $BIN"
[ "$(adb get-state 2>/dev/null)" = device ] || die "device not booted/adb."

# ---- root check FIRST: power_supply sysfs is SELinux-gated from adb shell, so every
# battery read/write goes through KSU su. No root => can't measure cleanly => abort. ----
HAS_ROOT=false; [ "$(SU id -u)" = 0 ] && HAS_ROOT=true
$HAS_ROOT || die "no adb-shell root. KSU doesn't grant su to adb by default: open the KernelSU-Next
   manager -> Superuser -> grant root to 'Shell'/ADB, then retry. (Battery nodes are SELinux-blocked
   for plain adb shell, and we won't run under Permissive — it perturbs the power measurement.)"

# ---- discover power-supply nodes at runtime, via root (don't hardcode/guess) ----
PS=/sys/class/power_supply
CC="$(SU "for p in $PS/battery/charge_counter $PS/bms/charge_counter; do [ -f \$p ] && { echo \$p; break; }; done")"
VOLT="$(SU "for p in $PS/battery/voltage_now $PS/bms/voltage_now; do [ -f \$p ] && { echo \$p; break; }; done")"
CURR="$(SU "for p in $PS/battery/current_now $PS/bms/current_now; do [ -f \$p ] && { echo \$p; break; }; done")"
[ -n "$CC" ] || die "no charge_counter node found — can't measure coulombs on this device."
rd(){ SU "cat $1" | tr -dc '0-9-'; }                                  # read int from a node (root)

echo "== benchbatt == cc=$CC volt=${VOLT:-none} root=$HAS_ROOT selinux=$(A getenforce)"

# ---- stop charge input (try strongest first), then VERIFY ----
CHG_METHOD=none
stop_charge(){
  if $HAS_ROOT; then
    for n in $PS/battery/input_suspend $PS/usb/input_suspend; do
      [ "$(SU "[ -f $n ] && echo y")" = y ] && { SU "echo 1 > $n"; CHG_METHOD="input_suspend"; return; }
    done
    for n in $PS/battery/charging_enabled $PS/battery/battery_charging_enabled; do
      [ "$(SU "[ -f $n ] && echo y")" = y ] && { SU "echo 0 > $n"; CHG_METHOD="charging_enabled"; return; }
    done
  fi
  # framework fallback (no real-HW guarantee — verified below)
  A 'dumpsys battery set ac 0' >/dev/null; A 'dumpsys battery set usb 0' >/dev/null
  A 'dumpsys battery set wireless 0' >/dev/null; CHG_METHOD="dumpsys"
}
restore_charge(){
  if $HAS_ROOT; then
    for n in $PS/battery/input_suspend $PS/usb/input_suspend; do SU "[ -f $n ] && echo 0 > $n"; done
    for n in $PS/battery/charging_enabled $PS/battery/battery_charging_enabled; do SU "[ -f $n ] && echo 1 > $n"; done
  fi
  A 'dumpsys battery reset' >/dev/null
}
# ALWAYS restore charging + settings, even on Ctrl-C / error
cleanup(){ restore_charge; A "settings put system screen_brightness_mode 1" >/dev/null; A 'svc power stayon false' >/dev/null; echo "   (charging restored)"; }
trap cleanup EXIT INT TERM

verify_not_charging(){  # charge_counter must NOT rise over a short idle window
  local a b; a="$(rd "$CC")"; sleep 6; b="$(rd "$CC")"
  echo "   charge_counter $a -> $b over 6s (want non-increasing)"
  [ -n "$a" ] && [ -n "$b" ] && [ "$b" -le "$a" ] 2>/dev/null
}

# ---- environment / controls ----
KVER="$(A cat /proc/version)"
if   echo "$KVER" | grep -qi silkxotic; then AUTOTAG=silkxotic
elif echo "$KVER" | grep -q -- "-perf";  then AUTOTAG=stock-perf
else AUTOTAG="$(A uname -r | tr -c 'A-Za-z0-9._-' '_')"; fi
TAG="${1:-$AUTOTAG}"; TS="$(date +%Y%m%d-%H%M%S)"; OUT="$RESDIR/batt-${TAG}-${TS}.jsonl"

adb push "$BIN" /data/local/tmp/loadbench >/dev/null; A chmod 755 /data/local/tmp/loadbench
A input keyevent KEYCODE_WAKEUP >/dev/null; A svc power stayon true >/dev/null
A "settings put system screen_brightness_mode 0" >/dev/null      # auto-brightness OFF
A "settings put system screen_brightness $BRIGHT" >/dev/null     # fixed brightness (constant offset, cancels in A/B)
AIRPLANE="$(A 'cmd connectivity airplane-mode enable >/dev/null 2>&1 && echo on || echo unchanged')"

echo "   kernel: $KVER"
echo "   workload: loadbench sustained ${SUS_S}s  iters=$ITERS  brightness=$BRIGHT airplane=$AIRPLANE"
stop_charge
echo "   charge-stop method: $CHG_METHOD"
verify_not_charging || die "charging NOT stopped (charge_counter rising) via '$CHG_METHOD'. $($HAS_ROOT || echo 'No adb root — grant Shell in KSU manager, then retry.') Refusing to record a confounded battery number."

thermal_max(){ A 'm=0; for d in /sys/class/thermal/thermal_zone*; do case "$(cat "$d/type" 2>/dev/null)" in cpu-*-usr) v=$(cat "$d/temp" 2>/dev/null); [ -n "$v" ] && [ "$v" -gt "$m" ] 2>/dev/null && m=$v;; esac; done; echo $m'; }
cooldown(){ local target=$((COOL_C*1000)) waited=0 t; while :; do t="$(thermal_max)"; t="${t:-0}"; [ "$t" -le "$target" ] && break; [ "$waited" -ge "$COOL_MAX_S" ] && { echo "   (cooldown timeout @ $((t/1000))C)"; break; }; sleep 5; waited=$((waited+5)); done; }

run_iter(){
  local i="$1"; cooldown
  local cc0 cc1 v0 v1 t0 t1 up0 up1 lb dcc dwh secs
  cc0="$(rd "$CC")"; v0="$(rd "$VOLT")"; t0="$(thermal_max)"; up0="$(A cut -d. -f1 /proc/uptime)"
  lb="$(A "/data/local/tmp/loadbench $LAT_S $SUS_S $IV_S")"           # the fixed workload (emits JSON)
  cc1="$(rd "$CC")"; v1="$(rd "$VOLT")"; t1="$(thermal_max)"; up1="$(A cut -d. -f1 /proc/uptime)"
  [ "$i" -eq 0 ] && { echo "   warmup done (discarded)"; return; }
  dcc=$(( ${cc0:-0} - ${cc1:-0} ))                                   # µAh consumed (counter decreases on discharge)
  secs=$(( ${up1:-0} - ${up0:-0} ))
  # energy µWh = µAh * avg V(µV)/1e6 ; integer math, keep µWh
  local vavg=$(( (${v0:-0} + ${v1:-0}) / 2 ))
  dwh=$(( dcc * vavg / 1000000 ))
  printf '{"tag":"%s","iter":%d,"ts":"%s","charge_stop":"%s","airplane":"%s","work_s":%d,"d_charge_uAh":%d,"d_energy_uWh":%d,"v_uV":[%d,%d],"thermal_mC":[%d,%d],"load":%s}\n' \
    "$TAG" "$i" "$(date +%H:%M:%S)" "$CHG_METHOD" "$AIRPLANE" "$secs" "$dcc" "$dwh" "${v0:-0}" "${v1:-0}" "${t0:-0}" "${t1:-0}" "$lb" >> "$OUT"
  echo "   iter $i/$ITERS: ${dcc} µAh / ${dwh} µWh over ${secs}s  ($((${t0:-0}/1000))->$((${t1:-0}/1000))C)"
}

echo "-- warmup --"; run_iter 0
for i in $(seq 1 "$ITERS"); do echo "-- iter $i --"; run_iter "$i"; done
echo "== done. $(wc -l < "$OUT") iters -> $OUT"
echo "   (lower µAh / µWh for the same work_s = more efficient. Compare same-temp-band iters.)"
# cleanup() runs on EXIT (restores charging + brightness mode)
