#!/usr/bin/env python3
"""Compare two benchgame result files — noise-aware, with a scene-validity gate.

Usage: comparegame.py <A.jsonl> <B.jsonl>   (order-independent; labels come from each file's "tag")

Primary metrics are frame pacing: fps (higher better) and p95/p99/worst/jank (lower better).
A ▲/▼ fires only when the median shift exceeds combined iteration-to-iteration noise (IQR),
mirroring compare.py and comparebatt.py.

TWO GATES, because a live game will happily lie to you:

  SCENE GATE — frame rate in a real game is set by what is on screen. If either side's scene
  drifted, or the two sides were measured on different scenes, the comparison is void and this
  script says so instead of printing a number. This is the gate the 2026-09-04 hand probe lacked,
  where a day->night cycle alone moved the same location from 28 fps to 15 fps.

  ACTUATOR CHECK — for a thermal-clamp patch, "did fps change" is the wrong first question.
  The first question is "did the clamp actually move": cpu6_max_mhz and cdev_cpu6 are reported
  as diagnostics. A patch that raises fps without moving cdev_cpu6 did something else, and a
  patch that moves cdev_cpu6 without raising fps means you were not CPU-bound in that scene.
"""
import sys, json, statistics as st

DRIFT_MAX = 8.0      # % — above this the scene did not hold still
DRIFT_SKEW = 5.0     # % — above this the two sides were not the same scene

def load(path):
    rows = [json.loads(l) for l in open(path) if l.strip()]
    if not rows: sys.exit(f"no iterations in {path}")
    return rows

def series(rows, key):
    return [float(r[key]) for r in rows if isinstance(r.get(key), (int, float))]

def quart(xs):
    s = sorted(xs); n = len(s)
    def at(p):
        if n == 1: return s[0]
        i = p * (n - 1); lo = int(i)
        return s[lo] if lo + 1 >= n else s[lo] + (s[lo+1] - s[lo]) * (i - lo)
    return at(0.25), at(0.5), at(0.75)

def iqr(xs): return 0.0 if len(xs) < 2 else quart(xs)[2] - quart(xs)[0]

def row(label, a, b, lower_better=True, unit=""):
    if not a or not b:
        print(f"  {label:<24} (insufficient data)"); return
    ma, mb = st.median(a), st.median(b)
    na, nb = iqr(a), iqr(b)
    d = mb - ma
    sig = abs(d) > (na + nb) and abs(d) > 1e-9
    better = (d < 0) if lower_better else (d > 0)
    mark = ("  ▲" if better else "  ▼") if sig else "   ="
    pct = f"{(d / ma * 100):+.1f}%" if ma else "  n/a"
    va, vb = f"{ma:.2f}{unit}", f"{mb:.2f}{unit}"
    print(f"  {label:<24} A={va:>10} (±{na:5.2f})   B={vb:>10} (±{nb:5.2f})   {pct:>7}{mark}")

def main():
    if len(sys.argv) != 3: sys.exit(__doc__)
    A, B = load(sys.argv[1]), load(sys.argv[2])
    ta, tb = A[0].get("tag", "A"), B[0].get("tag", "B")

    print(f"\n=== SilkXotic game frame-pacing A/B ===")
    print(f"A = {ta}   ({len(A)} iters, {sys.argv[1]})")
    print(f"B = {tb}   ({len(B)} iters, {sys.argv[2]})")
    print(f"    pkg={A[0].get('pkg')}  panel={A[0].get('refresh_hz')}Hz  window={A[0].get('window_s')}s")
    print(f"    kernel A={A[0].get('kernel')}\n    kernel B={B[0].get('kernel')}")

    # ---- scene gate ----
    da, db = series(A, "scene_drift_pct"), series(B, "scene_drift_pct")
    void = False
    print("\n  scene validity")
    if not da or not db or min(da + db) < 0:
        print("   !! scene drift not recorded — cannot validate; treat result as indicative only.")
    else:
        mda, mdb = st.median(da), st.median(db)
        print(f"   drift A={mda:.2f}%  B={mdb:.2f}%  (gate: each <{DRIFT_MAX}%, skew <{DRIFT_SKEW}%)")
        if mda > DRIFT_MAX or mdb > DRIFT_MAX:
            print("   !! SCENE MOVED during sampling — the frame numbers below are not comparable.")
            void = True
        if abs(mda - mdb) > DRIFT_SKEW:
            print("   !! sides were measured on different scenes — comparison is void.")
            void = True
        if not void: print("   ok — both sides held still on a comparable scene.")

    # ---- thermal comparability ----
    ca, cb = series(A, "cpu_c"), series(B, "cpu_c")
    if ca and cb:
        print(f"\n  thermal   A={st.median(ca):.1f}C  B={st.median(cb):.1f}C"
              + ("   !! >3C apart: sides were not equally soaked" if abs(st.median(ca) - st.median(cb)) > 3 else ""))

    print(f"\n  frame pacing            {ta[:9]:>13}          {tb[:9]:>13}")
    print("  " + "-" * 78)
    row("fps", series(A, "fps"), series(B, "fps"), lower_better=False)
    row("median frame", series(A, "median_ms"), series(B, "median_ms"), unit="ms")
    row("p95 frame", series(A, "p95_ms"), series(B, "p95_ms"), unit="ms")
    row("p99 frame", series(A, "p99_ms"), series(B, "p99_ms"), unit="ms")
    row("worst frame", series(A, "worst_ms"), series(B, "worst_ms"), unit="ms")
    row("jank (>2x median)", series(A, "jank_pct"), series(B, "jank_pct"), unit="%")

    print("\n  actuator / headroom  (diagnostic — did the clamp actually move?)")
    print("  " + "-" * 78)
    row("cpu6 scaling_max", series(A, "cpu6_max_mhz"), series(B, "cpu6_max_mhz"), lower_better=False, unit="MHz")
    row("cdev cpufreq-6 state", series(A, "cdev_cpu6"), series(B, "cdev_cpu6"))
    row("gpu clock", series(A, "gpu_mhz"), series(B, "gpu_mhz"), lower_better=False, unit="MHz")
    row("gpu busy", series(A, "gpu_busy_pct"), series(B, "gpu_busy_pct"), unit="%")
    row("gpu thermal_pwrlevel", series(A, "gpu_thermal_pwrlevel"), series(B, "gpu_thermal_pwrlevel"))

    ga, gb = series(A, "gpu_busy_pct"), series(B, "gpu_busy_pct")
    print()
    if ga and gb and min(st.median(ga), st.median(gb)) > 85:
        print("  !! GPU >85% busy on both sides — this scene is GPU-bound, so a CPU-clamp change")
        print("     cannot show up here regardless of whether it worked. Check the actuator rows,")
        print("     and re-test in a lighter scene if you need to see a frame-rate effect.")
    if void:
        print("  !! SCENE GATE FAILED — do not quote the frame numbers above.")
    print("  ▲/▼ shown only when the median shift exceeds combined iteration-to-iteration noise (IQR).")
    print("  Everything else is within noise — i.e. no real difference, not a loss.\n")

main()
