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
- **Source-level scheduler tuning that actually sticks.** ⚠️ Knob-tuning is a dead end for our
  packaging: an on-device probe (2026-06-28, running v1.0 build) showed crDroid's init rewrites *every*
  sched/stune/schedutil knob at boot — `sched_latency` 6→10ms, `min_granularity` 0.75→3ms,
  `tunable_scaling` 1→0, stune top-app `boost` 0→10 / `prefer_idle` 0→1, schedutil `down_rate_limit`
  500→20000us — so changing compiled defaults does nothing from an Image.gz-only kernel that keeps
  crDroid's ramdisk. (Proof: WALT-migrate/stune/schedutil writes are verbatim in
  `/vendor/bin/init.qcom.post_boot.sh`; the CFS latency knobs come from the perf-HAL, proven by
  elimination — the kernel compiles `tunable_scaling=1`/`latency=6ms` and nothing in scripts/cmdline/dts
  produces the live `0`/10ms, so userspace must.) The levers that DO stick (no userspace override surface):
  (a) **DT EAS energy model** — `sched-energy-costs` + capacities in `sdmmagpie.dtsi` (the base dtb),
  read once at boot with no runtime knob, so it can't be overridden. **PROVEN in v1.1 Charmeuse**: a
  little-cluster top-OPP cost tweak (130→145 / 148→175) built, diff-verified byte-clean vs stock,
  shipped as AK3's `dtb`, flashed, and read back live on-device (`0x91`/`0xaf`). This is *the* on-brand
  sticky lever. (b) `kernel/sched/features.h` SCHED_FEAT toggles — low-risk but small; (c) a BORE/CASS
  **algorithm** port (see 🧪). Validate with the heavy latency-under-load suite + subjective touch-feel
  + battery-per-workload. (Knobs were the easy path the roadmap assumed; the probe killed them — the DT
  energy model is the way.)
- **Strip debug overhead.** The shipped build still carries `DEBUG_INFO=y` / `DEBUG_KERNEL=y` /
  `SCHED_DEBUG=y` / `FTRACE=y` / `STACKTRACE=y` (inherited from `sdmsteppe-perf_defconfig`; the tree's
  `disable_dbgfs.sh` only strips `DEBUG_FS`/`PAGE_OWNER` for `user` builds, and crDroid's `perf` path
  skips it — both are already off anyway). Drop the rest (keep only what KSU/SUSFS needs) → smaller
  `Image.gz` and fewer hot-path hooks (`SCHED_DEBUG`/`FTRACE` cost cycles every event; `DEBUG_INFO` is
  mostly image size). Zero functional risk, costs one rebuild; fold into the first v1.1 build and A/B
  image size + jank. Not a "peak-perf knob" — pure overhead removal. (Confirmed pattern: Tobrut Exotic
  ships a `debugfs.config` for the same purpose.)

## 🥈 Worth investigating
- **Reconsider `core_ctl`.** v1.0's heavy A/B *hinted* it may cost worst-case latency (noisy, not proven).
  Do a clean with/without-core_ctl A/B; drop it if it doesn't earn its place in a smoothness build.
- **`SPECULATIVE_PAGE_FAULT` backport** (real source work, not a config flag — it doesn't exist as a
  Kconfig symbol in this tree). Can speed app launch / multithreaded faulting. Medium effort/risk.
- **Touch-latency measurement.** The thing no headless benchmark captures (and v1.0's whole value prop).
  Ideas: a tiny touch-driven test app reading input-event → frame timestamps, or instrument the input
  boost path. If we can measure it, we can actually prove (or disprove) the smoothness claim.
- **I/O scheduler + readahead on UFS.** Tree ships `mq-deadline` + `kyber` (BFQ off; default `cfq`).
  A/B `mq-deadline` vs `kyber` and tune `read_ahead_kb` / `nr_requests` / `rq_affinity` / `add_random=0`
  / `iostats=0` on `sda`. Pure sysfs (no rebuild) — storage stalls are a real jank source the v1.0 suite
  never isolated, and this is the cheapest lever to A/B without a flash.
- **Devfreq DDR/L3/cache-hwmon + thermal/current-limit tuning.** Tobrut Exotic (our tuning ancestor)
  explicitly targets "safe temperature and current limits" — a lever we don't exercise. The build already
  ships a rich QCOM devfreq stack (`QCOM_BW_HWMON`, `QCOM_CACHE_HWMON`, `MEMLAT`, `CDSPL3`, `ADRENO_TZ`,
  `GPUBW_MON`) — tune the DDR/L3/cache bandwidth governors + LMH-DCVS / battery-current-limit nodes so
  sustained load doesn't spike thermals. Pure sysfs (no rebuild); A/B with the throttling-suite fix below.
- **F2FS mount/GC tuning.** `userdata` is F2FS. Tune `discard_granularity` / `max_vfs_search_percent` /
  GC threads / `fsync` mode (or remount with tuned flags) so storage GC never stalls the UI thread —
  pairs with the I/O-scheduler item above as a combined storage-jank A/B. Mostly sysfs; needs KSU root.
- **VM tunables (no rebuild).** `vm.swappiness`, `vm.watermark_scale_factor`, `vm.dirty_ratio` /
  `dirty_background_ratio`, `vfs_cache_pressure` via init.d/sysfs. Pairs with the zstd-zram change (both
  move reclaim behavior); A/B refault rates + `dumpsys meminfo`. Easy to stack on the same test run.
- **Make the heavy suite actually throttle.** v1.0's heavy run only reached ~52 °C / 99% retention, so
  `core_ctl`/`msm_performance` had nothing to win. For v1.1, lengthen `SUS_S`, lower `COOL_C`, and add a
  GPU co-load (hot GLES loop) so the SoC genuinely throttles — otherwise the efficiency knobs stay
  unmeasurable. Harness work; complements the battery A/B and the core_ctl reconsideration above.

## 🧪 Experimental / higher risk
- **KernelSU-Next *legacy* driver** (`setup.sh … legacy`) to support manager **v3.2.0+**. Currently we
  pin manager **v3.1.0** because the kernel ships the pre-split driver. The latest legacy branch is
  known-unstable on non-GKI ([#1133](https://github.com/KernelSU-Next/KernelSU-Next/issues/1133),
  [#1249](https://github.com/KernelSU-Next/KernelSU-Next/issues/1249)) — only if you want to test it.
- **Full LTO** (drop `buildhost-lowram.config`'s ThinLTO) — matches stock exactly, ~same runtime, but
  needs a build host with ≥12 GB RAM (the 7.5 GB host can't link it).
- **MGLRU backport** (`LRU_GEN`) — meaningful reclaim win on 6 GB, but invasive to backport to 4.14.
- **uclamp backport** (`CONFIG_UCLAMP_TASK`, confirmed absent on this tree). Modern util-clamp on top of
  WALT. Caveat: uclamp.min/max are *also* a userspace-set surface (cgroup cpu controller + per-task
  `sched_setattr`), so like the sched knobs it's liable to be overridden by init — verify it actually
  sticks before investing. Same effort/risk tier as the MGLRU backport (real source work, not a flag).
- **BORE / CASS scheduler port** — the real source-level "feel" lever now that knob-tuning is proven
  override-dead (see 🥇). AGNI Reborn (`manipvlator/los_kernel_xiaomi_sm6150`) ships BORE + CASS on the
  *same* 4.14.357 base, so it's portable in principle — but it's a hot-path **algorithm** swap (BORE =
  CFS vruntime/pick rework, "better responsive touch"; CASS removes WALT entirely, which our v1.0 knob
  set is built around) and AGNI is sm6150 vs our sm7150/sdmsteppe — not a drop-in. Medium-high risk; do
  it as its own experimental build, validate by flash + heavy suite + subjective feel. The only
  scheduler-behavior change that init can't override.

## 🚫 Don't bother
- More peak-perf config knobs — v1.0 proved it's a benchmark wash; the touch-boost lever is already in.
- GKI port — impractical on SM7150 (no QC 5.x BSP; full driver port; likely-broken camera/modem).
- `-O3`/Polly/compiler hacks — rarely net-positive on phones, not worth the risk.
- **Feature fluff other sweet kernels ship** (KCAL/display-color, sound control, USB fastcharge,
  double-tap-to-wake, frandom). Against the "zero bloat, nothing else disturbed" brand; each is a
  driver backport + maintenance surface for no smoothness/efficiency gain. Leave them out.
- **Tuning WALT `sched_*` / stune boost / schedutil rate limits via kernel defaults** — measured dead
  (on-device probe 2026-06-28): crDroid's init overrides all of them at boot, so compiled-default changes
  never apply from our Image.gz-only packaging. To change scheduler behavior either swap the *algorithm*
  (🧪 BORE/CASS) or ship the knobs via a mechanism we don't have (init.d / vendor overlay) — which breaks
  the "nothing disturbed" brand. (`net` defaults DO stick — confirmed live on v1.1: `bbr`/`fq` active.
  But zram `comp_algorithm` does **NOT** — `init.qcom.post_boot.sh:299` writes `lz4`, caught when v1.1
  booted with a zstd compiled default yet still ran `[lz4]`; devfreq DDR/L3 bandwidth is post_boot-written
  too. So of the v1.1 changes, debug-trim + BBR/fq are real wins and zram-zstd is a no-op as shipped —
  the DT energy model (🥇) is the lever that actually moved.)

## 🔁 Process for every release
0. **Safety first** — `sweet` is A-only (no fallback slot): keep a known-good stock `boot.img` to
   `fastboot flash boot` back. After each build, verify KSU/SUSFS root + Play-Integrity (keybox) *before*
   benchmarking — a vanilla rebuild silently drops root/hiding and integrity.
1. `./silkxotic/sync-upstream.sh` — pull crDroid security/perf fixes, rebase SilkXotic on top.
2. Change **one** variable at a time; rebuild with `build-silkxotic.sh`.
3. A/B it with the harness (light + heavy; add battery once built). Commit numbers to `results-published/`.
4. Bump codename, package, cut a GitHub release.
