# SilkXotic vs stock crDroid — A/B benchmark results (honest writeup)

**Date:** 2026-06-28 · **Device:** Redmi Note 10 Pro `sweet` (SD732G/SM7150), crDroid 16 (12.11)
**A = stock-perf** (byte-exact stock `4.14.357-perf`, features absent) · **B = silkxotic** (same base + 6 knobs, features present)

> **TL;DR — it's a wash.** On every measurable, scriptable axis, SilkXotic is statistically
> indistinguishable from stock: no real win, no robust regression. That's not a failure of the
> kernel — it's a property of *what the knobs do* (see "Why" below). **Do not claim SilkXotic is
> "faster."** Its real case is subjective touch-feel + (unmeasured) battery/thermals.

Raw per-iteration data backing every number here is in [`results-published/`](results-published/).

## Method (anti-bullshit controls)
- **Only the kernel differs** — same device, ROM, apps, settings. Each result records `env.feat`
  (`cpu_boost`/`core_ctl`/`msm_performance`) proving A had features **off** and B had them **on**.
- True stock side was restored by `dd`-ing the byte-exact stock `boot.img` (sha256-verified).
- Thermal-gated cooldown between iterations; 1 discarded warmup; medians ± IQR.
- **Noise gate:** a metric is only called ▲/▼ when the median shift exceeds combined run-to-run IQR.

## Light suite (`bench.sh`, 6 iters, idle Settings scroll + cold launches)
| metric (lower better) | stock A | silkxotic B | Δ | verdict |
|---|---|---|---|---|
| CPU int (ms) | 809.0 ±8.7 | 812.1 ±4.8 | +0.4% | within noise |
| CPU float (ms) | 525.0 | 525.3 | +0.1% | noise (gate false-positive) |
| CPU multithread (ms) | 171.3 ±6.9 | 178.6 ±1.9 | +4.3% | nominally worse |
| alloc churn (ms) | 4.87 | 4.88 | +0.3% | within noise |
| UI janky frames (%) | 0.48 ±0.18 | 0.71 ±0.18 | +47.9% | worse on tiny absolutes (0.2 pp; both <1%) |
| frame p90 / p95 (ms) | 11 / 11 | 12 / 12 | +9% | +1 ms, both far inside budget |
| frame p99 (ms) | 14 | 14 | 0% | within noise |
| app launches (settings/clock/calc/files) | — | — | — | all **within noise** |
| burst latency med (µs) | 66,491 | 60,986 | −8.3% | better, but **within noise** |
| burst jitter p90-50 (µs) | 5,567 | 2,255 | −59.5% | better, but **within noise** |

The freq-ramp burst signal trended SilkXotic's way (−8%/−60%) but stock's variance was huge, so it
can't be called significant. Everything else: wash, with MT and idle-jank nominally worse.

## Heavy suite (`benchload.sh`, 4 iters, latency-under-load + sustained-throttle)
| metric | stock A | silkxotic B | Δ | verdict |
|---|---|---|---|---|
| resp latency p50 (µs) | 704 | 704 | 0% | identical |
| resp latency p95 (µs) | 1533 ±31 | 1518 ±186 | −1.0% | within noise |
| resp latency p99 (µs) | 1969 ±159 | 2228 ±1094 | +13.2% | within noise (huge IQR) |
| resp latency **max** (µs) | 2976 ±509 | 4722 ±818 | +58.7% | flagged worse — **don't trust** (see below) |
| sustained steady (Miter/s) | 1794 | 1784 | −0.6% | within noise |
| throttle retention (%) | 99.5 | 99.2 | −0.3% | within noise (no throttling occurred) |

**On the "max worse" flag:** `max` is the single worst of ~1,600 samples — the noisiest metric there
is. The robust p50→p99 are all within noise. There's also a fairness confound: stock was benched after
being up a while, but SilkXotic right after a flash+reboot (its iter1 ran to 61 °C vs the rest ~52 °C),
so post-boot background activity inflated its tail. **Not a real regression.**

## Why no benchmark shows a SilkXotic win (the actual insight)
1. **CPU_BOOST is touch-triggered.** Its input boost hooks the real touchscreen driver; a headless
   benchmark generates zero touch events, so the one knob most likely to deliver "smoothness" **never
   fires** here. Structurally unmeasurable by any scripted CPU/UI test.
2. **core_ctl / msm_performance are efficiency/thermal plays.** Their payoff is **battery + sustained
   thermals** — but 120 s of all-core load only reached ~52 °C (retention ~99%), so the chip never
   throttled and there was nothing for them to win against; and battery was not measured.
3. So these tests exercise the knob that can slightly *cost* latency (core_ctl) while leaving the knob
   that helps *feel* (cpu_boost) dormant.

## Honest conclusion
SilkXotic = stock, within measurement noise, across CPU throughput, app launch, frame jank, latency-
under-load, and sustained throughput. Its legitimate value lives in **subjective touch responsiveness**
(input boost) and **likely battery/thermal efficiency over long real use** — neither captured here. The
only untried path to a *measured* difference is a **battery-per-fixed-workload** A/B.

*Peak-score apps (3DMark/Geekbench/AnTuTu) were deliberately not used: 3DMark is GPU-bound; Geekbench/
AnTuTu ramp straight to max freq where these knobs don't act — all insensitive to the change.*
