# SilkXotic A/B benchmark

Reproducible, thermal-controlled, noise-aware comparison of **stock crDroid** vs **SilkXotic** on the
*same* device/ROM/apps — so the only variable is the kernel. No bullshit single-number claims: every
metric is multi-iteration, reported as median ± IQR, and only called a win when the shift beats the noise.

> **Already ran it?** See [`RESULTS.md`](RESULTS.md) for the honest 2026-06-28 findings (TL;DR: it's a
> measured wash — and *why* that's expected). Raw data in [`results-published/`](results-published/).

## Why these metrics
SilkXotic changes 6 knobs; the suite targets exactly what they affect:

| Metric | Tool | What it reflects | Knobs exercised |
|---|---|---|---|
| Frame jank %, p90/p95/p99 frame time | `dumpsys gfxinfo` over a fixed scroll | **UI smoothness** (the whole point) | CPU_BOOST, MSM_PERFORMANCE, AUTOGROUP |
| App cold-launch time | `am start -W` TotalTime | responsiveness | CPU_BOOST, MSM_PERFORMANCE, CORE_CTL |
| Burst latency + jitter | `cpubench` short bursts after idle | freq **ramp** responsiveness | CPU_BOOST, MSM_PERFORMANCE, governor |
| CPU int/float/multithread | `cpubench` | raw throughput / scheduling | CORE_CTL, scheduler |
| alloc churn | `cpubench` malloc/free | allocator | SLUB_CPU_PARTIAL |

`cpubench` is a dynamic bionic aarch64 binary (`cpubench.c`, built with NDK r28 — see below).

## Rigor / controls (the anti-bullshit part)
- **Only the kernel differs** — same device, ROM, apps, settings. Each result records `env` (governor,
  max freqs, thermal, battery, mem, and which SilkXotic feature-nodes are present) so you can *prove* the
  two runs were comparable and which kernel was which.
- **Thermal-controlled**: before every iteration the harness waits until the hottest thermal zone is
  ≤ `COOL_C`°C (default 42) so runs don't drift hotter and bias later numbers.
- **Multi-iteration + warmup**: 1 discarded warmup, then N recorded (default 6). Reported as median ± IQR.
- **Noise gate**: `compare.py` only marks ▲/▼ when the median shift exceeds combined run-to-run IQR.
  Anything smaller prints "within noise" — i.e. no real difference (not a loss).
- Put the phone in **Airplane mode**, fixed brightness, off-charger, screen on (the harness keeps it awake).

## Build the cpubench binary (once)
```bash
NDK=$HOME/Android/Sdk/ndk/28.2.13676358
CC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android35-clang
$CC -O2 -pthread -o bin/cpubench-arm64 cpubench.c     # dynamic (static bionic+pthread segfaults)
```
(A prebuilt `bin/cpubench-arm64` is committed; rebuild if you change the source.)

## Run an A/B
```bash
# 1) boot STOCK kernel (revert), then:
./bench.sh                       # auto-tags 'stock-perf' -> results/stock-perf-<ts>.jsonl

# 2) flash SilkXotic, boot, then:
./bench.sh                       # auto-tags 'silkxotic'  -> results/silkxotic-<ts>.jsonl

# 3) compare
python3 compare.py results/stock-perf-<ts>.jsonl results/silkxotic-<ts>.jsonl
```
Tag/iters/scale overridable: `./bench.sh <tag> <iters>`, env `SCALE=1.0 COOL_C=42 SWIPES=18`.

> Tagging note: a *true* A/B needs the genuine stock kernel (no SilkXotic features) for side A. The
> `env.feat` block in each result confirms which side actually had `cpu_boost`/`core_ctl`/`msm_performance`,
> so you can't accidentally compare two feature-enabled kernels and call it a win.

## Heavy suite — `benchload.sh` (recommended for *this* kernel's knobs)
The light suite (idle Settings scroll, cold launches) barely loads an SD732G, so it tends to read "wash."
SilkXotic's knobs act under **contention and thermal load**, so the heavy suite targets exactly that:

- **latency-under-load** — a foreground "request" thread does a small fixed task every ~50ms while a
  *separate* background process (own session/autogroup) saturates all 8 cores. Reports response-latency
  p50/p95/p99/max. This is "does the UI stay responsive while the system is busy" — the real
  SCHED_AUTOGROUP + CPU_BOOST + CORE_CTL signal. Lower + tighter tail = better.
- **sustained-throttle** — saturate all cores for N seconds, sample throughput each interval → peak,
  steady-state, and retention% (steady/peak). Reveals CORE_CTL/MSM_PERFORMANCE thermal behavior.

```bash
# build the engine (once)
$CC -O2 -pthread -o bin/loadbench-arm64 loadbench.c
# run A/B (same flash-bench-flash-bench flow)
LAT_S=20 SUS_S=120 COOL_C=48 ./benchload.sh                 # auto-tags by kernel
python3 compareload.py results/load-stock-perf-*.jsonl results/load-silkxotic-*.jsonl
```
Why not 3DMark/Geekbench/AnTuTu: 3DMark is GPU-bound (kernel-CPU changes don't touch it); Geekbench/AnTuTu
ramp straight to max freq where boost/core_ctl don't matter — all three are insensitive to these knobs and
not scriptable. PCMark Work is the only commercial app worth a manual sanity check.

## Optional: rooted instrumentation tier
With KSU root you can additionally *log* that the knobs engage under load (read `cpu_boost`/`core_ctl`
params, per-cluster freq residency). Note: for latency-under-load and sustained-throttle you should **not**
pin the governor to `performance` — that would mask the very governor/boost behavior being compared. The
default tier runs fully as shell uid 2000.

## Output
One JSON object per iteration in `results/<tag>-<timestamp>.jsonl`. `results/` is git-ignored;
commit a curated run if you want to publish numbers.
