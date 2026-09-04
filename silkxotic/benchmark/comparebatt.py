#!/usr/bin/env python3
"""Compare two benchbatt result files (stock vs silkxotic) — noise-aware.

Usage: comparebatt.py <A.jsonl> <B.jsonl>   (order-independent; labels come from each file's "tag")

Primary metrics: charge_uAh / energy_uWh for the same fixed workload — lower = more efficient.
A SIGNIFICANT flag fires only when the median shift exceeds the combined iter-to-iter noise (IQR),
mirroring compare.py. Fairness gate: the embedded load block's sustained throughput must be ~equal
across sides (same work actually done); if it differs beyond noise, trust the normalized
µAh-per-Titer row instead of raw µAh. Sanity checks (charge_stop method, n_samp, work_s,
thermal band overlap) print as warnings, not failures.
"""
import sys, json, statistics as st

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

def quantiles(xs):
    s=sorted(xs); n=len(s)
    def at(p):
        if n==1: return s[0]
        idx=p*(n-1); lo=int(idx); frac=idx-lo
        return s[lo] if lo+1>=n else s[lo]+(s[lo+1]-s[lo])*frac
    return [at(0.25), at(0.5), at(0.75)]

def iqr(xs):
    if len(xs)<2: return 0.0
    q=quantiles(xs)
    return q[2]-q[0]

def series(rows, dotted):
    vals=[dig(r, dotted) for r in rows]
    return [float(v) for v in vals if isinstance(v,(int,float))]

def work_titer(r):
    """Total work done in the sustained window (Titer = 1e12 iterations)."""
    m=dig(r,"load.sustained.miter_s"); iv=dig(r,"load.sustained.interval_s")
    if isinstance(m,list) and m and isinstance(iv,(int,float)):
        return sum(float(x) for x in m)*float(iv)/1e6
    sm=dig(r,"load.sustained.steady_miter_s"); ws=dig(r,"work_s")
    if isinstance(sm,(int,float)) and isinstance(ws,(int,float)):
        return float(sm)*float(ws)/1e6
    return None

def fmt(x):
    return f"{x:.1f}" if abs(x)>=10 else f"{x:.3f}"

def row(label, a, b, lower_better=True):
    if not a or not b:
        print(f"  {label:<26} (insufficient data)"); return None
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
    return sig, better, pct

def main():
    if len(sys.argv)!=3: sys.exit(__doc__)
    A=load(sys.argv[1]); B=load(sys.argv[2])
    tagA=A[0].get("tag","A"); tagB=B[0].get("tag","B")
    print(f"\n=== SilkXotic battery A/B (identical {A[0].get('work_s','?')} s all-core workload) ===")
    print(f"A = {tagA}   ({len(A)} iters,  {sys.argv[1]})")
    print(f"B = {tagB}   ({len(B)} iters,  {sys.argv[2]})")

    # -- sanity gate: only kernel should differ, and the measurement must be clean --
    warn=[]
    for rows,tag in ((A,tagA),(B,tagB)):
        for r in rows:
            if r.get("charge_stop")!="input_suspend":
                warn.append(f"{tag} iter {r.get('iter')}: charge_stop={r.get('charge_stop')} (want input_suspend)")
            ws=r.get("work_s") or 0; ns=r.get("n_samp") or 0
            if ws and abs(ns-ws)>ws*0.1:
                warn.append(f"{tag} iter {r.get('iter')}: n_samp={ns} vs work_s={ws} (sampler gap?)")
    if len({r.get("work_s") for r in A+B})>1:
        warn.append(f"work_s differs across iters: {sorted({r.get('work_s') for r in A+B})}")
    # thermal band overlap: compare start temps
    tsA=[r["thermal_mC"][0]/1000 for r in A if isinstance(r.get("thermal_mC"),list)]
    tsB=[r["thermal_mC"][0]/1000 for r in B if isinstance(r.get("thermal_mC"),list)]
    if tsA and tsB:
        print(f"  start temp A={min(tsA):.0f}-{max(tsA):.0f}C  B={min(tsB):.0f}-{max(tsB):.0f}C")
        if min(max(tsA),max(tsB)) < max(min(tsA),min(tsB)) - 3:
            warn.append("thermal start bands barely overlap — compare same-temp iters by hand")
    for w in warn: print(f"  !! {w}")

    print(f"\n  metric (lower is better)   {tagA[:9]:>9}            {tagB[:9]:>9}")
    print( "  " + "-"*86)
    row("charge (µAh)",       series(A,"charge_uAh"),  series(B,"charge_uAh"))
    row("energy (µWh)",       series(A,"energy_uWh"),  series(B,"energy_uWh"))
    row("mean current (µA)",  series(A,"mean_uA"),     series(B,"mean_uA"))

    # -- fairness gate: same work actually done? --
    print( "  " + "-"*86)
    thr=row("sustained (Miter/s)", series(A,"load.sustained.steady_miter_s"),
                                   series(B,"load.sustained.steady_miter_s"), lower_better=False)
    wA=[w for w in (work_titer(r) for r in A) if w]
    wB=[w for w in (work_titer(r) for r in B) if w]
    effA=[q/w for q,w in zip(series(A,"charge_uAh"),wA) if w]
    effB=[q/w for q,w in zip(series(B,"charge_uAh"),wB) if w]
    row("charge/work (µAh/Titer)", effA, effB)
    if thr and thr[0] and abs(thr[2]) > 1.0:
        print("  !! throughput differs beyond noise — raw µAh is NOT a fair comparison here;")
        print("     the µAh/Titer row above is the honest efficiency number.")

    print("\n  ▲/▼ shown only when the median shift exceeds combined iter-to-iter noise (IQR).")
    print("  Everything else is within noise — i.e. no real difference, not a loss.\n")

if __name__=="__main__":
    main()
