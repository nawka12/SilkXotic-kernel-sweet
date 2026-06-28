# SilkXotic — Roadmap

Codename scheme (silk weaves): **v1.0 Mulberry** ✅ → **v1.1 Charmeuse** → Habotai → Dupioni → Organza.

Grounded in what we learned shipping v1.0: the benchmarks were a **wash**, so chasing more peak-perf
config flags is pointless. The real levers are **efficiency (battery/thermal)** and **source-level
scheduler tuning** — plus actually *measuring* the touch-feel the kernel is branded on.

## 🥇 Highest value (do first)
- **Battery-per-fixed-workload A/B.** The one untried measurement, and the most likely place a *real*
  win exists (`core_ctl`/`msm_performance` trade throughput for efficiency). Harness is ~90% there —
  add a coulomb-counter (`charge_counter`) test to `benchload.sh`. Needs KSU root.
- **zram: lz4 → zstd** (+ keep writeback). Better ratio on 6 GB; cheap, real-world fewer-reclaim-stalls.
  Enable `CONFIG_CRYPTO_ZSTD=y`, set zram default comp to zstd. A/B refault rates + `dumpsys meminfo`.
- **TCP BBR** (`cubic → bbr` + `fq` qdisc). `CONFIG_TCP_CONG_BBR=y`, `NET_SCH_FQ=y`. Cheap latency/throughput win.
- **Source-level EAS / stune tuning** — the *real* perceived-smoothness lever on 4.14 (bigger than any
  config flag). Tune WALT `sched_*`, stune top-app boost + prefer-idle, schedutil up/down rate limits.
  This is where "feels smoother" actually comes from. Validate with the heavy latency-under-load suite.

## 🥈 Worth investigating
- **Reconsider `core_ctl`.** v1.0's heavy A/B *hinted* it may cost worst-case latency (noisy, not proven).
  Do a clean with/without-core_ctl A/B; drop it if it doesn't earn its place in a smoothness build.
- **`SPECULATIVE_PAGE_FAULT` backport** (real source work, not a config flag — it doesn't exist as a
  Kconfig symbol in this tree). Can speed app launch / multithreaded faulting. Medium effort/risk.
- **Touch-latency measurement.** The thing no headless benchmark captures (and v1.0's whole value prop).
  Ideas: a tiny touch-driven test app reading input-event → frame timestamps, or instrument the input
  boost path. If we can measure it, we can actually prove (or disprove) the smoothness claim.

## 🧪 Experimental / higher risk
- **KernelSU-Next *legacy* driver** (`setup.sh … legacy`) to support manager **v3.2.0+**. Currently we
  pin manager **v3.1.0** because the kernel ships the pre-split driver. The latest legacy branch is
  known-unstable on non-GKI ([#1133](https://github.com/KernelSU-Next/KernelSU-Next/issues/1133),
  [#1249](https://github.com/KernelSU-Next/KernelSU-Next/issues/1249)) — only if you want to test it.
- **Full LTO** (drop `buildhost-lowram.config`'s ThinLTO) — matches stock exactly, ~same runtime, but
  needs a build host with ≥12 GB RAM (the 7.5 GB host can't link it).
- **MGLRU backport** (`LRU_GEN`) — meaningful reclaim win on 6 GB, but invasive to backport to 4.14.

## 🚫 Don't bother
- More peak-perf config knobs — v1.0 proved it's a benchmark wash; the touch-boost lever is already in.
- GKI port — impractical on SM7150 (no QC 5.x BSP; full driver port; likely-broken camera/modem).
- `-O3`/Polly/compiler hacks — rarely net-positive on phones, not worth the risk.

## 🔁 Process for every release
1. `./silkxotic/sync-upstream.sh` — pull crDroid security/perf fixes, rebase SilkXotic on top.
2. Change **one** variable at a time; rebuild with `build-silkxotic.sh`.
3. A/B it with the harness (light + heavy; add battery once built). Commit numbers to `results-published/`.
4. Bump codename, package, cut a GitHub release.
