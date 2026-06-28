#!/usr/bin/env python3
"""Compare two loadbench result files (stock vs silkxotic) — noise-aware.
Usage: compareload.py <A.jsonl> <B.jsonl>   (labels come from each file's "tag")

Metrics:
  latency p50/p95/p99/max (us)  lower better  <- responsiveness under load (the key signal)
  sustained steady (Miter/s)    higher better <- sustained throughput
  retention %                   higher better <- peak->steady (throttle behavior)
Only flags a win when the median shift exceeds combined run-to-run IQR.
"""
import sys, json, statistics as st

def load(p):
    rows=[json.loads(l) for l in open(p) if l.strip()]
    if not rows: sys.exit(f"no iterations in {p}")
    return rows
def dig(d,dotted):
    for k in dotted.split('.'):
        if not isinstance(d,dict) or k not in d: return None
        d=d[k]
    return d
def quart(xs):
    s=sorted(xs); n=len(s)
    def at(pp):
        if n==1: return s[0]
        idx=pp*(n-1); lo=int(idx); fr=idx-lo
        return s[lo] if lo+1>=n else s[lo]+(s[lo+1]-s[lo])*fr
    return at(0.25),at(0.5),at(0.75)
def iqr(xs):
    if len(xs)<2: return 0.0
    q1,_,q3=quart(xs); return q3-q1
def series(rows,dotted): return [float(v) for v in (dig(r,dotted) for r in rows) if isinstance(v,(int,float))]
def fmt(x): return f"{x:.0f}" if abs(x)>=100 else (f"{x:.1f}" if abs(x)>=10 else f"{x:.2f}")

def row(label,a,b,lower_better):
    if not a or not b: print(f"  {label:<28} (insufficient)"); return
    ma,mb=st.median(a),st.median(b); na,nb=iqr(a),iqr(b); noise=(na+nb)/2
    delta=mb-ma; pct=(delta/ma*100) if ma else 0
    better=(delta<0) if lower_better else (delta>0)
    sig=abs(delta)>noise and abs(delta)>1e-9
    arrow=("▲ better" if better else "▼ worse") if sig else "—"
    print(f"  {label:<28} A={fmt(ma):>9} (±{fmt(na)})  B={fmt(mb):>9} (±{fmt(nb)})  Δ={pct:+6.1f}%  {arrow}{'' if sig else '  (within noise)'}")

def main():
    if len(sys.argv)!=3: sys.exit(__doc__)
    A=load(sys.argv[1]); B=load(sys.argv[2])
    tA,tB=A[0].get('tag','A'),B[0].get('tag','B')
    print(f"\n=== SilkXotic HEAVY A/B (latency-under-load + sustained) ===")
    print(f"A = {tA}  ({len(A)} iters, {sys.argv[1]})")
    print(f"B = {tB}  ({len(B)} iters, {sys.argv[2]})")
    eA,eB=A[0].get('env',{}),B[0].get('env',{})
    print(f"  A.feat={eA.get('feat')}  B.feat={eB.get('feat')}")
    def endtemps(rows): return [dig(r,'thermal_end_mC')/1000 for r in rows if isinstance(dig(r,'thermal_end_mC'),(int,float))]
    ea,eb=endtemps(A),endtemps(B)
    if ea and eb: print(f"  end-of-load temp: A med={st.median(ea):.0f}C  B med={st.median(eb):.0f}C")
    print(f"\n  metric                        {tA[:9]:>9}           {tB[:9]:>9}")
    print("  "+"-"*84)
    print("  [responsiveness under load — lower better]")
    for k,lab in (("load.latency.p50_us","resp latency p50 (µs)"),("load.latency.p95_us","resp latency p95 (µs)"),
                  ("load.latency.p99_us","resp latency p99 (µs)"),("load.latency.max_us","resp latency max (µs)")):
        row(lab, series(A,k), series(B,k), True)
    print("  [sustained throughput — higher better]")
    row("steady throughput (Miter/s)", series(A,"load.sustained.steady_miter_s"), series(B,"load.sustained.steady_miter_s"), False)
    row("peak throughput (Miter/s)",   series(A,"load.sustained.peak_miter_s"),   series(B,"load.sustained.peak_miter_s"),   False)
    row("throttle retention (%)",      series(A,"load.sustained.retention_pct"),  series(B,"load.sustained.retention_pct"),  False)
    print("\n  ▲/▼ only when the median shift beats combined run-to-run noise (IQR); else 'within noise'.\n")

if __name__=="__main__": main()
