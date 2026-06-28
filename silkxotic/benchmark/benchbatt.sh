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
BATDIR="$(dirname "$CC")"; STATUS="$BATDIR/status"
rd(){ SU "cat $1" | tr -dc '0-9-'; }                                  # read int from a node (root)
rds(){ SU "cat $1"; }                                                 # read string (status)

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

verify_not_charging(){  # status is the instant, reliable signal (charge_counter is coarse/laggy)
  local st a b; st="$(rds "$STATUS")"
  echo "   battery status = '$st' (want: Discharging / Not charging)"
  case "$st" in
    *harging) ;;                                   # "Discharging" -> ok (matches via the rise check below too)
  esac
  # hard reject if framework/HW still reports active charge, or if counter is climbing
  case "$st" in Charging|Full) echo "   -> still charging"; return 1;; esac
  a="$(rd "$CC")"; sleep 6; b="$(rd "$CC")"
  if [ -n "$a" ] && [ -n "$b" ] && [ "$b" -gt "$a" ] 2>/dev/null; then
    echo "   -> charge_counter rising ($a->$b)"; return 1
  fi
  return 0
}

# ---- environment / controls ----
KVER="$(A cat /proc/version)"
if   echo "$KVER" | grep -qi silkxotic; then AUTOTAG=silkxotic
elif echo "$KVER" | grep -q -- "-perf";  then AUTOTAG=stock-perf
else AUTOTAG="$(A uname -r | tr -c 'A-Za-z0-9._-' '_')"; fi
TAG="${1:-$AUTOTAG}"; TS="$(date +%Y%m%d-%H%M%S)"; OUT="$RESDIR/batt-${TAG}-${TS}.jsonl"

[ -n "$CURR" ] || die "no current_now node — can't integrate (this BMS's charge_counter is too coarse; see below)."
adb push "$BIN" /data/local/tmp/loadbench >/dev/null; A chmod 755 /data/local/tmp/loadbench

# On-device concurrent sampler + workload. charge_counter is quantized to whole-% SoC (~50mAh)
# on this BMS, so it reads 0 for <~2min workloads. current_now updates fast, so we integrate it:
# sample (uptime current voltage) ~1Hz DURING loadbench, then integrate Q=Σi·dt on the host.
# Run as root (current_now is SELinux-gated); placement differs from a foreground app but is
# identical across A/B, so the relative efficiency comparison holds.
RUNNER="$(mktemp)"; cat > "$RUNNER" <<'DEV'
#!/system/bin/sh
LAT=$1; SUS=$2; IV=$3; CURR=$4; VOLT=$5; F=/data/local/tmp
rm -f $F/bs.txt $F/lb.json; : > $F/bs.run
( while [ -f $F/bs.run ]; do
    u=$(cut -d' ' -f1 /proc/uptime); i=$(cat "$CURR" 2>/dev/null); v=$(cat "$VOLT" 2>/dev/null)
    [ -n "$i" ] && echo "$u $i ${v:-0}"; sleep 1
  done > $F/bs.txt ) &
sp=$!
$F/loadbench $LAT $SUS $IV > $F/lb.json 2>/dev/null
rm -f $F/bs.run; wait $sp 2>/dev/null
DEV
adb push "$RUNNER" /data/local/tmp/batt_run.sh >/dev/null; A chmod 755 /data/local/tmp/batt_run.sh; rm -f "$RUNNER"

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
  stop_charge; verify_not_charging || die "charging resumed before iter $i (method '$CHG_METHOD'); refusing confounded sample."
  local cc0 cc1 t0 t1 lb samp uAh uWh nsamp imean ccdelta
  cc0="$(rd "$CC")"; t0="$(thermal_max)"
  SU "/data/local/tmp/batt_run.sh $LAT_S $SUS_S $IV_S $CURR $VOLT" >/dev/null   # sampler + workload (blocks)
  cc1="$(rd "$CC")"; t1="$(thermal_max)"
  lb="$(SU 'cat /data/local/tmp/lb.json')"
  samp="$(SU 'cat /data/local/tmp/bs.txt')"
  [ "$i" -eq 0 ] && { echo "   warmup done ($(echo "$samp" | grep -c .) samples, discarded)"; return; }
  # integrate Q=Σ|i|·dt (µAh) and E=Σ|i·v|·dt (µWh) over the sampled current/voltage trace
  set -- $(printf '%s\n' "$samp" | awk '
    NR>1 && $1>pu { dt=$1-pu; ii=(pi<0?-pi:pi); vv=(pv<0?-pv:pv); q+=ii*dt; e+=ii*vv*dt; n++ }
    { pu=$1; pi=$2; pv=$3 }
    END { printf "%d %d %d", q/3600, e/3600/1000000, n+1 }')
  uAh="${1:-0}"; uWh="${2:-0}"; nsamp="${3:-0}"
  ccdelta=$(( ${cc0:-0} - ${cc1:-0} ))                               # coarse counter delta (sanity; ~0 for short runs)
  imean=$(( nsamp>0 ? uAh*3600/(SUS_S>0?SUS_S:1) : 0 ))             # rough mean discharge current µA
  printf '{"tag":"%s","iter":%d,"ts":"%s","charge_stop":"%s","airplane":"%s","work_s":%d,"charge_uAh":%d,"energy_uWh":%d,"mean_uA":%d,"n_samp":%d,"cc_delta_uAh":%d,"thermal_mC":[%d,%d],"load":%s}\n' \
    "$TAG" "$i" "$(date +%H:%M:%S)" "$CHG_METHOD" "$AIRPLANE" "$SUS_S" "$uAh" "$uWh" "$imean" "$nsamp" "$ccdelta" "${t0:-0}" "${t1:-0}" "$lb" >> "$OUT"
  echo "   iter $i/$ITERS: ${uAh} µAh / ${uWh} µWh  (~${imean}µA, ${nsamp} samp)  $((${t0:-0}/1000))->$((${t1:-0}/1000))C"
}

echo "-- warmup --"; run_iter 0
for i in $(seq 1 "$ITERS"); do echo "-- iter $i --"; run_iter "$i"; done
echo "== done. $(wc -l < "$OUT") iters -> $OUT"
echo "   (lower µAh / µWh for the same work_s = more efficient. Compare same-temp-band iters.)"
# cleanup() runs on EXIT (restores charging + brightness mode)
