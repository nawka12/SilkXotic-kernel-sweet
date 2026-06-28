#!/usr/bin/env bash
# SilkXotic A/B benchmark driver. Runs a fixed, thermal-controlled, multi-iteration suite
# over adb and writes machine-readable results tagged by the running kernel.
# Flash kernel A -> run this -> flash kernel B -> run this -> compare.py the two outputs.
#
# Usage:  ./bench.sh [tag] [iterations]
#   tag         override result label (default: auto from uname: silkxotic|stock-perf)
#   iterations  recorded iterations (default 6); 1 warmup is always run and discarded
#
# Tunables (env): SCALE (cpubench size, default 1.0), COOL_C (cooldown target °C, default 42),
#   COOL_MAX_S (max cooldown wait, default 180), SWIPES (jank swipes, default 18)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/bin/cpubench-arm64"
RESDIR="$HERE/results"; mkdir -p "$RESDIR"
SCALE="${SCALE:-1.0}"; COOL_C="${COOL_C:-42}"; COOL_MAX_S="${COOL_MAX_S:-180}"
ITERS="${2:-6}"; SWIPES="${SWIPES:-18}"
JANK_PKG="com.android.settings"

A(){ adb shell "$@" 2>/dev/null | tr -d '\r'; }
die(){ echo "!! $*" >&2; exit 1; }

[ -f "$BIN" ] || die "cpubench missing: $BIN (compile cpubench.c with NDK first)"
[ "$(adb get-state 2>/dev/null)" = device ] || die "device not in 'device' state (booted + adb)."

# ---- identity / tag ----
KVER="$(A cat /proc/version)"
if   echo "$KVER" | grep -qi silkxotic; then AUTOTAG=silkxotic
elif echo "$KVER" | grep -q -- "-perf";  then AUTOTAG=stock-perf
else AUTOTAG="$(A uname -r | tr -c 'A-Za-z0-9._-' '_')"; fi
TAG="${1:-$AUTOTAG}"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$RESDIR/${TAG}-${TS}.jsonl"
echo "== SilkXotic bench == tag=$TAG iters=$ITERS scale=$SCALE -> $OUT"
echo "   kernel: $KVER"

# ---- device prep: push bench, screen on+awake, fixed brightness, get screen size ----
adb push "$BIN" /data/local/tmp/cpubench >/dev/null; A chmod 755 /data/local/tmp/cpubench
A input keyevent KEYCODE_WAKEUP >/dev/null
A svc power stayon true >/dev/null
SIZE="$(A wm size | sed -n 's/.*: \([0-9]*x[0-9]*\).*/\1/p' | head -1)"; SIZE="${SIZE:-1080x2400}"
W="${SIZE%x*}"; H="${SIZE#*x}"
X=$((W/2)); Y1=$((H*78/100)); Y2=$((H*25/100))
echo "   screen ${W}x${H}; swipe x=$X y:$Y1<->$Y2"

thermal_max(){ A 'm=0; for f in /sys/class/thermal/thermal_zone*/temp; do v=$(cat "$f" 2>/dev/null); [ -n "$v" ] && [ "$v" -gt "$m" ] 2>/dev/null && m=$v; done; echo $m'; }
battery(){ A dumpsys battery | sed -n 's/^ *\(level\|temperature\|status\): \(.*\)/\1=\2/p' | paste -sd, -; }

cooldown(){
  local target=$((COOL_C*1000)) waited=0 t
  while :; do t="$(thermal_max)"; t="${t:-0}"
    [ "$t" -le "$target" ] && break
    [ "$waited" -ge "$COOL_MAX_S" ] && { echo "   (cooldown timeout @ $((t/1000))C)"; break; }
    sleep 5; waited=$((waited+5))
  done
}

env_json(){
  local gov0 gov6 mx0 mx6 thm bat mem up boost corectl msmperf
  gov0="$(A cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"
  gov6="$(A cat /sys/devices/system/cpu/cpufreq/policy6/scaling_governor)"
  mx0="$(A cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq)"
  mx6="$(A cat /sys/devices/system/cpu/cpufreq/policy6/scaling_max_freq)"
  thm="$(thermal_max)"; bat="$(battery)"
  mem="$(A grep MemAvailable /proc/meminfo | tr -dc 0-9)"
  up="$(A cut -d. -f1 /proc/uptime)"
  boost=$([ -n "$(A ls -d /sys/module/cpu_boost 2>/dev/null)" ] && echo true || echo false)
  corectl=$([ -n "$(A ls -d /sys/devices/system/cpu/cpu6/core_ctl 2>/dev/null)" ] && echo true || echo false)
  msmperf=$([ -n "$(A ls -d /sys/module/msm_performance 2>/dev/null)" ] && echo true || echo false)
  printf '"gov":["%s","%s"],"maxfreq":[%s,%s],"thermal_mC":%s,"battery":"%s","mem_avail_kB":%s,"uptime_s":%s,"feat":{"cpu_boost":%s,"core_ctl":%s,"msm_performance":%s}' \
    "$gov0" "$gov6" "${mx0:-0}" "${mx6:-0}" "${thm:-0}" "$bat" "${mem:-0}" "${up:-0}" "$boost" "$corectl" "$msmperf"
}

# ---- individual tests ----
test_cpubench(){ A "/data/local/tmp/cpubench $SCALE"; }   # already JSON

test_launch(){  # cold-launch TotalTime(ms) for stable system apps
  local pkgs="com.android.settings com.android.deskclock com.android.calculator2 com.android.documentsui"
  local parts=() p comp t
  for p in $pkgs; do
    comp="$(A cmd package resolve-activity --brief "$p" | tail -1)"
    case "$comp" in */*) ;; *) continue;; esac          # must look like pkg/activity
    A am force-stop "$p"; sleep 1
    t="$(A am start -W -n "$comp" | sed -n 's/^TotalTime: //p' | head -1)"
    A am force-stop "$p"
    [ -n "$t" ] && parts+=("\"$p\":$t")
  done
  local IFS=,; echo "{${parts[*]}}"
}

test_jank(){  # frame stats over a fixed scroll workload in Settings
  A am force-stop "$JANK_PKG"; A am start -n "$JANK_PKG/.Settings" >/dev/null; sleep 3
  A dumpsys gfxinfo "$JANK_PKG" reset >/dev/null; sleep 1
  local i
  for i in $(seq 1 "$SWIPES"); do
    A input swipe "$X" "$Y1" "$X" "$Y2" 120 >/dev/null
    A input swipe "$X" "$Y2" "$X" "$Y1" 120 >/dev/null
  done
  sleep 1
  local g total; g="$(A dumpsys gfxinfo "$JANK_PKG")"
  total=$(echo "$g" | sed -n 's/.*Total frames rendered: \([0-9]*\).*/\1/p' | head -1); total=${total:-0}
  # guard: with <30 frames gfxinfo percentiles fall through to the max histogram bucket
  # (e.g. 4950ms) and would poison the comparison — mark invalid instead.
  if [ "$total" -lt 30 ]; then A am force-stop "$JANK_PKG"; printf '{"total":%s,"valid":false}' "$total"; return; fi
  local jline janky jankpct p50 p90 p95 p99 missed
  jline=$(echo "$g"  | grep -m1 '^Janky frames: ')                 # not the "(legacy)" line
  janky=$(echo "$jline" | sed -n 's/^Janky frames: \([0-9]*\) .*/\1/p')
  jankpct=$(echo "$jline"| sed -n 's/.*(\([0-9.]*\)%.*/\1/p')
  p50=$(echo "$g" | sed -n 's/^50th percentile: \([0-9]*\)ms.*/\1/p' | head -1)   # ^ avoids "50th gpu percentile"
  p90=$(echo "$g" | sed -n 's/^90th percentile: \([0-9]*\)ms.*/\1/p' | head -1)
  p95=$(echo "$g" | sed -n 's/^95th percentile: \([0-9]*\)ms.*/\1/p' | head -1)
  p99=$(echo "$g" | sed -n 's/^99th percentile: \([0-9]*\)ms.*/\1/p' | head -1)
  missed=$(echo "$g" | sed -n 's/.*Number Missed Vsync: \([0-9]*\).*/\1/p' | head -1)
  A am force-stop "$JANK_PKG"
  printf '{"total":%s,"valid":true,"janky":%s,"janky_pct":%s,"p50_ms":%s,"p90_ms":%s,"p95_ms":%s,"p99_ms":%s,"missed_vsync":%s}' \
    "$total" "${janky:-0}" "${jankpct:-0}" "${p50:-0}" "${p90:-0}" "${p95:-0}" "${p99:-0}" "${missed:-0}"
}

run_iter(){  # $1=iter index (0 = warmup, not written)
  local i="$1"
  cooldown
  local env cpu lau jank
  env="$(env_json)"; cpu="$(test_cpubench)"; lau="$(test_launch)"; jank="$(test_jank)"
  [ "$i" -eq 0 ] && { echo "   warmup done (discarded)"; return; }
  printf '{"tag":"%s","iter":%d,"ts":"%s","env":{%s},"cpubench":%s,"launch_ms":%s,"jank":%s}\n' \
    "$TAG" "$i" "$(date +%H:%M:%S)" "$env" "$cpu" "$lau" "$jank" >> "$OUT"
  echo "   iter $i/$ITERS recorded"
}

echo "-- warmup --"; run_iter 0
for i in $(seq 1 "$ITERS"); do echo "-- iter $i --"; run_iter "$i"; done

A svc power stayon false >/dev/null
echo "== done. $(wc -l < "$OUT") iterations -> $OUT"
echo "   compare with:  python3 $HERE/compare.py <stock.jsonl> <silkxotic.jsonl>"
