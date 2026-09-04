# SilkXotic vs stock crDroid — A/B benchmark results (honest writeup)

**Date:** 2026-06-28 (light/heavy, v1.0) + 2026-07-04 (battery, v1.1) · **Device:** Redmi Note 10 Pro `sweet` (SD732G/SM7150), crDroid 16 (12.11)
**A = stock-perf** (byte-exact stock `4.14.357-perf`, features absent) · **B = silkxotic** (same base + 6 knobs, features present)

> **TL;DR — perf is a wash; battery under sustained load is a measured LOSS.** On every scriptable
> perf axis, SilkXotic is statistically indistinguishable from stock: no real win, no robust
> regression. That's not a failure of the kernel — it's a property of *what the knobs do* (see "Why"
> below). **Do not claim SilkXotic is "faster."** The battery A/B (below, v1.1) then produced the
> first *measured* difference — in stock's favor: **+37% charge for +4% throughput** on a fixed
> sustained workload. SilkXotic's real case is subjective touch-feel; the battery/thermal-efficiency
> hope is now measured and, for sustained load, dead.

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

## Battery suite (`benchbatt.sh`, 2026-07-04, 3 iters, 180 s all-core fixed workload, SUS_S=180)

**⚠️ Version note:** this suite benched **v1.1 Charmeuse** (6 knobs + debug-trim + BBR/fq + the DT
energy-model edit), not the v1.0 build the suites above used. Same byte-exact stock on the A side.
Method: charge input verifiably suspended (`input_suspend`, checked every iter), airplane on,
brightness fixed, µAh/µWh integrated from a 1 Hz `current_now`/`voltage_now` trace during the
identical 180 s saturating `loadbench` run; discarded warmup + thermal-gated cooldown; kernels
swapped by root `dd` of md5-verified boot images. Comparison: `comparebatt.py` (median ± IQR, same
noise gate as `compare.py`).

| metric (lower better) | stock A | silkxotic B (v1.1) | Δ | verdict |
|---|---|---|---|---|
| charge (µAh) | 23,703 ±606 | 32,588 ±188 | **+37.5%** | **worse — far beyond noise** |
| energy (µWh) | 101,194 ±2,690 | 139,330 ±1,035 | **+37.7%** | **worse — far beyond noise** |
| mean current (mA) | 474 ±12 | 652 ±4 | +37.5% | (same signal) |
| sustained steady (Miter/s) | 1,694.5 ±0.6 | 1,768.2 ±0.7 | +4.3% | silkxotic does more work |
| **charge per work (µAh/Titer)** | **75,277 ±1,310** | **103,401 ±501** | **+37.4%** | **worse — the honest number** |
| burst latency p50 (µs) | 703 | 705 | ~0% | identical |
| end temp (°C) | 47–50 | 49–54 | — | silkxotic runs hotter |

**What the traces show (the mechanism):** stock bursts to ~1,813 Miter/s then **steps down** within
~30 s to a rock-stable 1,694 (93.4% retention, ±1 Miter/s for the rest of the run) — a clock policy
settling at a sustainable OPP. SilkXotic **holds ~1,768 flat the whole 180 s** (99.5% retention; only
iter 3's tail shows the first throttle dips). So SilkXotic buys +74 Miter/s (+4.3%) for +178 mA
(+37.5%): the marginal work from holding the top OPPs costs roughly **8× the average perf/W** of
stock's steady point. That's the SD732G's top-OPP power curve doing exactly what it does.

**Which lever causes it — not resolved by this data.** Candidates: the v1.1 DT energy-model edit
(shifts placement toward golds), `core_ctl`/`msm_performance` keeping cores/clocks up, or a
mitigation-path difference. Isolation runs that would answer it: stock-dtb + SilkXotic-Image hybrid
(AK3 makes this easy) and a with/without-`core_ctl` build, each re-run through this same harness.

**Honest caveats:** (1) This is a *saturating* all-core workload — it measures sustained-load clock
policy, not light/mixed daily drain; do NOT read "37% worse battery life" from it. Light-use drain
remains unmeasured. (2) Side B ran post-reboot in `RUNNING_LOCKED` state (fewer background services
than side A's long-uptime session) — direction favors stock, but background idle draw is tens of mA
at most against a 178 mA gap, and the clean throughput step-down is a clock policy, not noise.
(3) Iter-to-iter spread was ~1–2.5% per side; the 37% shift is ~15–50× the combined IQR. This is the
least ambiguous result the harness has ever produced.

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
under-load, and sustained throughput. **Update 2026-07-04:** the battery-per-fixed-workload A/B — the
one untried measurement — came back decisive and *against* v1.1: **+37% charge/energy for +4%
sustained throughput** (µAh-per-work +37%), running hotter. The "likely battery/thermal efficiency"
hypothesis is dead for sustained load; light-use drain is still unmeasured. SilkXotic's remaining
legitimate value is **subjective touch responsiveness** (input boost) — plus, if you want to spin the
same number the other way, it *is* the higher-sustained-throughput, no-step-down kernel; but that
trade costs ~8× marginal perf/W and nobody should pretend it's "efficiency." v1.2 should attack this
directly: battery-direction DT energy-model edit ("sipping" profile), and a with/without-`core_ctl`
isolation A/B through this same harness.

*Peak-score apps (3DMark/Geekbench/AnTuTu) were deliberately not used: 3DMark is GPU-bound; Geekbench/
AnTuTu ramp straight to max freq where these knobs don't act — all insensitive to the change.*
