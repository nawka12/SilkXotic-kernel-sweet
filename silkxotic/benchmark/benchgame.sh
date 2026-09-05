#!/usr/bin/env bash
# SilkXotic GAME frame-pacing A/B driver (fixed-scene, thermally-soaked).
#
# WHY THIS EXISTS: the 2026-09-04 probe tried to A/B a real game (hololive Dreams) by hand and
# every comparison was wrecked by scene variance — 28 fps in a daytime plaza, 20 fps in a 2D shop
# menu, 15 fps in the same plaza after the in-game clock rolled to night. Frame rate in a live
# game is dominated by WHAT IS ON SCREEN, not by the kernel. Any A/B that doesn't pin the scene
# is measuring the game, not the kernel.
#
# So this harness does three things the ad-hoc probe didn't:
#   1. SCENE GATE. Screenshots the framebuffer at the start and end of every sample window and
#      records the mean per-pixel drift. If the scene moved (character walked, day->night, a menu
#      opened), the iteration is flagged and comparegame.py refuses to trust it.
#   2. THERMAL SOAK, not cooldown. We are measuring the SUSTAINED clamp (mi_thermald converges the
#      golds to ~1555 MHz after ~90 s of load), so a cold-start run measures the wrong thing.
#      Iteration 1 is preceded by SOAK_S of gameplay and discarded as warmup.
#   3. DEVICE-SIDE COLLECTION. Frame + sysfs sampling runs on the phone and is pulled once, so the
#      harness works unchanged over high-latency wireless adb (tailscale ~360 ms RTT) where a
#      poll-per-sample host loop would itself perturb the measurement.
#
# OPERATOR PROTOCOL (this is not optional — it is the experiment):
#   - Park the character at a FIXED landmark. Do not walk. Do not rotate the camera.
#   - Do not touch the screen at all once the countdown starts.
#   - Keep the in-game time-of-day the same across both sides of the A/B (this game has a
#     day/night cycle and night costs ~40% of the frame rate).
#   - Same in-game graphics preset and fps cap on both sides. Record them in the tag.
#
# Usage: ./benchgame.sh [tag] [iterations]
# Env: DUR_S (sample window secs, default 30), SOAK_S (warmup soak, default 120),
#      GAP_S (gap between iters, default 10), PKG (default: auto-detect foreground),
#      ADB_SERIAL (e.g. 100.80.206.8:5555 for wireless), BRIGHT (fixed brightness, default 40)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESDIR="$HERE/results"; mkdir -p "$RESDIR"
DUR_S="${DUR_S:-30}"; SOAK_S="${SOAK_S:-120}"; GAP_S="${GAP_S:-10}"; BRIGHT="${BRIGHT:-40}"
ITERS="${2:-5}"
ADBS=(); [ -n "${ADB_SERIAL:-}" ] && ADBS=(-s "$ADB_SERIAL")

A(){ adb "${ADBS[@]}" shell "$@" 2>/dev/null | tr -d '\r'; }
SU(){ adb "${ADBS[@]}" shell "su -W -c \"$*\"" 2>/dev/null | tr -d '\r'; }
die(){ echo "!! $*" >&2; exit 1; }

[ "$(adb "${ADBS[@]}" get-state 2>/dev/null)" = device ] || die "device not reachable via adb."
[ "$(SU id -u)" = 0 ] || die "no adb-shell root. KSU: manager -> Superuser -> grant 'Shell'/ADB.
   GPU sysfs (/sys/class/kgsl) and the thermal cooling nodes are SELinux-gated without it."

# ---- foreground package + its BLAST SurfaceView layer ----
# The layer id CHANGES whenever the game recreates its surface (observed #688 -> #756 -> #843 in a
# single session), so it is re-resolved every iteration, never cached across the run.
detect_pkg(){ A 'dumpsys window' | sed -n 's/.*mCurrentFocus=Window{[^ ]* [^ ]* \([^ /]*\).*/\1/p' | head -1; }
detect_layer(){ A 'dumpsys SurfaceFlinger --list' \
  | grep "SurfaceView\[$1" | grep BLAST | sed 's/RequestedLayerState{//; s/ parentId.*//' | head -1; }

PKG="${PKG:-$(detect_pkg)}"; [ -n "$PKG" ] || die "could not detect a foreground package."
L0="$(detect_layer "$PKG")"; [ -n "$L0" ] || die "no BLAST SurfaceView layer for $PKG (is it a
   SurfaceView game? HWUI-only apps must be measured with gfxinfo instead)."

TAG="${1:-game}"; TS="$(date +%Y%m%d-%H%M%S)"; OUT="$RESDIR/game-${TAG}-${TS}.jsonl"
KVER="$(A uname -r)"; BUILD="$(A getprop ro.build.display.id)"
A "settings put system screen_brightness $BRIGHT" >/dev/null
A 'settings put system screen_off_timeout 1800000' >/dev/null

echo "== benchgame == pkg=$PKG kernel=$KVER"
echo "   layer=$L0"
echo "   window=${DUR_S}s soak=${SOAK_S}s iters=$ITERS (+1 discarded warmup) -> $OUT"

# ---- device-side collector: frames + sysfs, one pull ----
# dumpsys --latency returns only the LAST 128 frames, so it is polled every 1.5 s and de-duplicated
# on the host by present-timestamp. At 30-60 fps that is 45-90 frames per poll: no gap.
RUNNER=/data/local/tmp/benchgame-run.sh
adb "${ADBS[@]}" shell "cat > $RUNNER" <<'DEV'
LAYER="$1"; DUR="$2"
F=/data/local/tmp
: > $F/bg_frames.raw; : > $F/bg_hw.txt
END=$(( $(date +%s) + DUR ))
while [ $(date +%s) -lt $END ]; do
  dumpsys SurfaceFlinger --latency "$LAYER" >> $F/bg_frames.raw 2>/dev/null
  echo "$(cat /sys/class/kgsl/kgsl-3d0/gpuclk) \
$(cat /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage | tr -d ' %') \
$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) \
$(cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_cur_freq) \
$(cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_max_freq) \
$(cat /sys/class/thermal/thermal_zone20/temp) \
$(cat /sys/class/thermal/thermal_zone23/temp) \
$(cat /sys/class/thermal/cooling_device1/cur_state) \
$(cat /sys/class/thermal/cooling_device9/cur_state) \
$(cat /sys/class/kgsl/kgsl-3d0/thermal_pwrlevel)" >> $F/bg_hw.txt
  sleep 1.5
done
DEV
SU "chmod 755 $RUNNER"

grab(){ adb "${ADBS[@]}" exec-out screencap > "$1" 2>/dev/null; }   # raw RGBA, decoded by python

soak(){ echo "   soaking ${SOAK_S}s (reaching the sustained thermal clamp)..."; sleep "$SOAK_S"; }

run_iter(){ # $1=iter label
  local it="$1" lay f0 f1 hw fr drift
  lay="$(detect_layer "$PKG")"; [ -n "$lay" ] || { echo "   iter $it: layer vanished, skipping"; return 1; }
  f0="$(mktemp)"; f1="$(mktemp)"
  echo -n "   iter $it: hold still... "
  grab "$f0"
  SU "sh $RUNNER '$lay' $DUR_S" >/dev/null
  grab "$f1"
  fr="$(SU "cat /data/local/tmp/bg_frames.raw")"
  hw="$(SU "cat /data/local/tmp/bg_hw.txt")"
  drift="$(python3 "$HERE/scenedrift.py" "$f0" "$f1" 2>/dev/null || echo -1)"
  rm -f "$f0" "$f1"
  FRAMES="$fr" HW="$hw" DRIFT="$drift" ITER="$it" TAGV="$TAG" KV="$KVER" BLD="$BUILD" \
    PKGV="$PKG" DURV="$DUR_S" LAYV="$lay" python3 "$HERE/gamestat.py" >> "$OUT"
  tail -1 "$OUT" | python3 -c 'import sys,json; r=json.load(sys.stdin); print("%.1f fps  p95=%.1fms  worst=%.0fms  cpu6max=%.0f  cdev=%.1f  drift=%.2f%%"%(r["fps"],r["p95_ms"],r["worst_ms"],r["cpu6_max_mhz"],r["cdev_cpu6"],r["scene_drift_pct"]))'
}

trap 'echo; echo "-- interrupted; partial results in $OUT"; exit 130' INT
soak
echo "   -- warmup iteration (discarded) --"
run_iter 0 >/dev/null 2>&1 || true
: > "$OUT"   # drop warmup
for i in $(seq 1 "$ITERS"); do
  run_iter "$i" || true
  [ "$i" -lt "$ITERS" ] && sleep "$GAP_S"
done
echo
echo "== done: $OUT ($(wc -l < "$OUT") iterations)"
echo "   compare with: ./comparegame.py <A.jsonl> <B.jsonl>"
