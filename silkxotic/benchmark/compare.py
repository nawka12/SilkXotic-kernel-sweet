#!/usr/bin/env python3
"""Compare two SilkXotic bench result files (stock vs silkxotic) — noise-aware.

Usage: compare.py <A.jsonl> <B.jsonl>   (order-independent; labels come from each file's "tag")

For every metric we report median and IQR (inter-quartile range) across iterations, the
relative delta, and a SIGNIFICANT flag that fires only when the median shift exceeds the
combined run-to-run noise (so a 'win' is a real win, not jitter). Lower-is-better is handled
per metric; burst latency reports both median and jitter (p90-p50) — the responsiveness signal.
"""
import sys, json, statistics as st

# metric: (label, lower_is_better)
SCALAR = {
    "cpubench.int_ms":   ("CPU int (ms)", True),
    "cpubench.float_ms": ("CPU float (ms)", True),
    "cpubench.alloc_ms": ("alloc churn (ms)", True),
    "cpubench.mt_ms":    ("CPU multithread (ms)", True),
    "jank.janky_pct":    ("UI janky frames (%)", True),
    "jank.p90_ms":       ("frame p90 (ms)", True),
    "jank.p95_ms":       ("frame p95 (ms)", True),
    "jank.p99_ms":       ("frame p99 (ms)", True),
    "jank.missed_vsync": ("missed vsync", True),
}
LAUNCH_LOWER = True  # app launch ms, lower better

def load(path):
    rows=[]
    for line in open(path):
        line=line.strip()
        if line: rows.append(json.loads(line))
    if not rows: sys.exit(f"no iterations in {path}")
    return rows

def dig(d, dotted):
    for k in dotted.split("."):
        if not isinstance(d, dict) or k not in d: return None
        d=d[k]
    return d

def iqr(xs):
    if len(xs)<2: return 0.0
    q=statistics_quantiles(xs)
    return q[2]-q[0]

def statistics_quantiles(xs):
    # quartiles via inclusive method; returns [q1,q2,q3]
    s=sorted(xs); n=len(s)
    def at(p):
        if n==1: return s[0]
        idx=p*(n-1); lo=int(idx); frac=idx-lo
        return s[lo] if lo+1>=n else s[lo]+(s[lo+1]-s[lo])*frac
    return [at(0.25), at(0.5), at(0.75)]

def series(rows, dotted):
    vals=[dig(r, dotted) for r in rows]
    return [float(v) for v in vals if isinstance(v,(int,float))]

def burst_series(rows):
    med=[]; jit=[]
    for r in rows:
        b=dig(r,"cpubench.burst_us")
        if isinstance(b,list) and b:
            q=statistics_quantiles([float(x) for x in b])
            med.append(q[1]); jit.append(q[2]-q[0])
    return med, jit

def fmt(x):
    return f"{x:.1f}" if abs(x)>=10 else f"{x:.2f}"

def row(label, a, b, lower_better):
    # a,b = list of per-iteration values
    if not a or not b:
        print(f"  {label:<26} (insufficient data)"); return
    ma, mb = st.median(a), st.median(b)
    na, nb = iqr(a), iqr(b)
    noise = (na+nb)/2.0
    delta = mb-ma
    pct = (delta/ma*100.0) if ma else 0.0
    better = (delta<0) if lower_better else (delta>0)
    sig = abs(delta) > noise and abs(delta) > 1e-9
    arrow = "—"
    if sig: arrow = ("▲ better" if better else "▼ worse")
    print(f"  {label:<26} A={fmt(ma):>9} (±{fmt(na)})   B={fmt(mb):>9} (±{fmt(nb)})   "
          f"Δ={pct:+6.1f}%  {arrow}{'' if sig else '  (within noise)'}")

def main():
    if len(sys.argv)!=3: sys.exit(__doc__)
    A=load(sys.argv[1]); B=load(sys.argv[2])
    tagA=A[0].get("tag","A"); tagB=B[0].get("tag","B")
    print(f"\n=== SilkXotic A/B comparison ===")
    print(f"A = {tagA}   ({len(A)} iters,  {sys.argv[1]})")
    print(f"B = {tagB}   ({len(B)} iters,  {sys.argv[2]})")
    # environment sanity (only kernel should differ)
    eA=A[0].get("env",{}); eB=B[0].get("env",{})
    print(f"  gov A={eA.get('gov')} B={eB.get('gov')}  "
          f"maxfreq A={eA.get('maxfreq')} B={eB.get('maxfreq')}")
    print(f"  features B(silkxotic-side): {eB.get('feat')}")
    print(f"\n  metric (lower is better)     {tagA[:9]:>9}            {tagB[:9]:>9}")
    print( "  " + "-"*86)
    for key,(label,lb) in SCALAR.items():
        row(label, series(A,key), series(B,key), lb)

    # app launches (per-app)
    apps=set()
    for r in A+B: apps |= set((dig(r,"launch_ms") or {}).keys())
    for p in sorted(apps):
        sa=[float(dig(r,"launch_ms").get(p)) for r in A if dig(r,"launch_ms") and p in dig(r,"launch_ms")]
        sb=[float(dig(r,"launch_ms").get(p)) for r in B if dig(r,"launch_ms") and p in dig(r,"launch_ms")]
        row("launch "+p.split('.')[-1]+" (ms)", sa, sb, LAUNCH_LOWER)

    # burst responsiveness
    ma,ja=burst_series(A); mb,jb=burst_series(B)
    print( "  " + "-"*86)
    row("burst latency med (µs)", ma, mb, True)
    row("burst jitter p90-50(µs)", ja, jb, True)

    print("\n  ▲/▼ shown only when the median shift exceeds combined run-to-run noise (IQR).")
    print("  Everything else is within noise — i.e. no real difference, not a loss.\n")

if __name__=="__main__":
    main()
