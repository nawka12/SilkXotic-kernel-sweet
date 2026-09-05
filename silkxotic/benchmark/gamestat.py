#!/usr/bin/env python3
"""Turn one benchgame.sh sample window into a single JSONL result row. Invoked via env vars.

Frame source is `dumpsys SurfaceFlinger --latency`, which only retains the last 128 frames, so
benchgame.sh polls it repeatedly and the blocks are de-duplicated here by present-timestamp.

fps is computed as (n_unique_frames - 1) / span rather than 1/mean(interval): if a poll ever did
drop frames, the resulting phantom gap would inflate mean(interval) badly, while the count/span
form degrades gracefully. Both are emitted so a disagreement between them is visible.
"""
import os, json, statistics as st

PENDING = (1 << 63) - 1

def frames(raw):
    ts, refresh = set(), None
    for line in raw.splitlines():
        p = line.split()
        if len(p) == 1 and p[0].isdigit():
            refresh = int(p[0]); continue
        if len(p) != 3: continue
        try: actual = int(p[1])
        except ValueError: continue
        if actual <= 0 or actual >= PENDING: continue   # pending/never-presented
        ts.add(actual)
    return sorted(ts), refresh

def pct(xs, q):
    if not xs: return 0.0
    s = sorted(xs); i = q * (len(s) - 1); lo = int(i)
    return s[lo] if lo + 1 >= len(s) else s[lo] + (s[lo+1] - s[lo]) * (i - lo)

def main():
    ts, refresh = frames(os.environ.get("FRAMES", ""))
    iv = [(b - a) / 1e6 for a, b in zip(ts, ts[1:])] if len(ts) > 1 else []
    span = (ts[-1] - ts[0]) / 1e9 if len(ts) > 1 else 0.0

    hw = {}
    cols = ["gpu_hz","gpu_busy","cpu0_hz","cpu6_hz","cpu6_max_hz",
            "cpu_mc","gpu_mc","cdev_gpu","cdev_cpu6","gpu_thermal_pwrlevel"]
    vals = {c: [] for c in cols}
    for line in os.environ.get("HW", "").splitlines():
        p = line.split()
        if len(p) != len(cols): continue
        for c, v in zip(cols, p):
            try: vals[c].append(float(v))
            except ValueError: pass
    for c in cols:
        hw[c] = st.mean(vals[c]) if vals[c] else 0.0

    med = st.median(iv) if iv else 0.0
    budget = refresh / 1e6 if refresh else 16.67       # one vsync at the panel's active mode
    row = {
        "tag": os.environ.get("TAGV",""), "iter": int(os.environ.get("ITER","0")),
        "pkg": os.environ.get("PKGV",""), "kernel": os.environ.get("KV",""),
        "build": os.environ.get("BLD",""), "layer": os.environ.get("LAYV",""),
        "window_s": float(os.environ.get("DURV","0")),
        "scene_drift_pct": float(os.environ.get("DRIFT","-1")),
        "refresh_hz": round(1e9 / refresh, 1) if refresh else None,
        "n_frames": len(ts), "span_s": round(span, 2),
        # primary: count/span. secondary: 1/mean(interval). They should agree within ~1%.
        "fps": round((len(ts) - 1) / span, 2) if span > 0 else 0.0,
        "fps_from_mean_iv": round(1000 / st.mean(iv), 2) if iv else 0.0,
        "mean_ms": round(st.mean(iv), 2) if iv else 0.0,
        "median_ms": round(med, 2),
        "p90_ms": round(pct(iv, 0.90), 2), "p95_ms": round(pct(iv, 0.95), 2),
        "p99_ms": round(pct(iv, 0.99), 2), "worst_ms": round(max(iv), 2) if iv else 0.0,
        # jank = interval more than 2x the run's own median: scene-independent, unlike a fixed budget
        "jank_pct": round(100 * sum(1 for x in iv if x > 2 * med) / len(iv), 2) if iv and med else 0.0,
        "over_budget_pct": round(100 * sum(1 for x in iv if x > budget * 1.5) / len(iv), 2) if iv else 0.0,
        "gpu_mhz": round(hw["gpu_hz"] / 1e6, 1), "gpu_busy_pct": round(hw["gpu_busy"], 1),
        "cpu0_mhz": round(hw["cpu0_hz"] / 1e3, 1), "cpu6_mhz": round(hw["cpu6_hz"] / 1e3, 1),
        "cpu6_max_mhz": round(hw["cpu6_max_hz"] / 1e3, 1),
        "cpu_c": round(hw["cpu_mc"] / 1e3, 1), "gpu_c": round(hw["gpu_mc"] / 1e3, 1),
        "cdev_gpu": round(hw["cdev_gpu"], 2), "cdev_cpu6": round(hw["cdev_cpu6"], 2),
        "gpu_thermal_pwrlevel": round(hw["gpu_thermal_pwrlevel"], 2),
    }
    print(json.dumps(row))

main()
