#!/usr/bin/env bash
# SilkXotic HEAVY A/B driver: latency-under-load + sustained-throttle (loadbench).
# Same controls as bench.sh (thermal cooldown, multi-iteration, env capture, kernel-tagged).
#
# Usage: ./benchload.sh [tag] [iterations]
# Env: LAT_S (latency phase secs, default 20), SUS_S (sustained secs, default 150),
#      IV_S (sample interval, default 10), COOL_C (cooldown °C, default 46),
#      COOL_MAX_S (max cooldown wait, default 240)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HERE/bin/loadbench-arm64"; RESDIR="$HERE/results"; mkdir -p "$RESDIR"
LAT_S="${LAT_S:-20}"; SUS_S="${SUS_S:-150}"; IV_S="${IV_S:-10}"
COOL_C="${COOL_C:-46}"; COOL_MAX_S="${COOL_MAX_S:-240}"; ITERS="${2:-5}"

A(){ adb shell "$@" 2>/dev/null | tr -d '\r'; }
die(){ echo "!! $*" >&2; exit 1; }
[ -f "$BIN" ] || die "loadbench missing: $BIN"
[ "$(adb get-state 2>/dev/null)" = device ] || die "device not booted/adb."

KVER="$(A cat /proc/version)"
if   echo "$KVER" | grep -qi silkxotic; then AUTOTAG=silkxotic
elif echo "$KVER" | grep -q -- "-perf";  then AUTOTAG=stock-perf
else AUTOTAG="$(A uname -r | tr -c 'A-Za-z0-9._-' '_')"; fi
TAG="${1:-$AUTOTAG}"; TS="$(date +%Y%m%d-%H%M%S)"; OUT="$RESDIR/load-${TAG}-${TS}.jsonl"
echo "== loadbench == tag=$TAG iters=$ITERS  lat=${LAT_S}s sus=${SUS_S}s  -> $OUT"
echo "   kernel: $KVER"
adb push "$BIN" /data/local/tmp/loadbench >/dev/null; A chmod 755 /data/local/tmp/loadbench
A input keyevent KEYCODE_WAKEUP >/dev/null; A svc power stayon true >/dev/null

# real CPU die sensors only (exclude lmh-dcvs constant zones)
thermal_max(){ A 'm=0; for d in /sys/class/thermal/thermal_zone*; do case "$(cat "$d/type" 2>/dev/null)" in cpu-*-usr) v=$(cat "$d/temp" 2>/dev/null); [ -n "$v" ] && [ "$v" -gt "$m" ] 2>/dev/null && m=$v;; esac; done; echo $m'; }
cooldown(){ local target=$((COOL_C*1000)) waited=0 t; while :; do t="$(thermal_max)"; t="${t:-0}"; [ "$t" -le "$target" ] && break; [ "$waited" -ge "$COOL_MAX_S" ] && { echo "   (cooldown timeout @ $((t/1000))C)"; break; }; sleep 5; waited=$((waited+5)); done; }
env_json(){
  local g0 g6 thm bat mem up boost corectl msmperf
  g0="$(A cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor)"; g6="$(A cat /sys/devices/system/cpu/cpufreq/policy6/scaling_governor)"
  thm="$(thermal_max)"; bat="$(A dumpsys battery | sed -n 's/^ *\(level\|temperature\|status\): \(.*\)/\1=\2/p' | paste -sd, -)"
  mem="$(A grep MemAvailable /proc/meminfo | tr -dc 0-9)"; up="$(A cut -d. -f1 /proc/uptime)"
  boost=$([ -n "$(A ls -d /sys/module/cpu_boost 2>/dev/null)" ] && echo true || echo false)
  corectl=$([ -n "$(A ls -d /sys/devices/system/cpu/cpu6/core_ctl 2>/dev/null)" ] && echo true || echo false)
  msmperf=$([ -n "$(A ls -d /sys/module/msm_performance 2>/dev/null)" ] && echo true || echo false)
  printf '"gov":["%s","%s"],"thermal_start_mC":%s,"battery":"%s","mem_avail_kB":%s,"uptime_s":%s,"feat":{"cpu_boost":%s,"core_ctl":%s,"msm_performance":%s}' \
    "$g0" "$g6" "${thm:-0}" "$bat" "${mem:-0}" "${up:-0}" "$boost" "$corectl" "$msmperf"
}

run_iter(){
  local i="$1"; cooldown
  local env lb thm_after
  env="$(env_json)"
  lb="$(A "/data/local/tmp/loadbench $LAT_S $SUS_S $IV_S")"
  thm_after="$(thermal_max)"
  [ "$i" -eq 0 ] && { echo "   warmup done (discarded)"; return; }
  printf '{"tag":"%s","iter":%d,"ts":"%s","env":{%s},"thermal_end_mC":%s,"load":%s}\n' \
    "$TAG" "$i" "$(date +%H:%M:%S)" "$env" "${thm_after:-0}" "$lb" >> "$OUT"
  echo "   iter $i/$ITERS recorded  (end $((${thm_after:-0}/1000))C)"
}

echo "-- warmup --"; run_iter 0
for i in $(seq 1 "$ITERS"); do echo "-- iter $i --"; run_iter "$i"; done
A svc power stayon false >/dev/null
echo "== done. $(wc -l < "$OUT") iters -> $OUT"
echo "   compare:  python3 $HERE/compareload.py <stock load.jsonl> <silkxotic load.jsonl>"
