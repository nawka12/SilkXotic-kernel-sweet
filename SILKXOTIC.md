<div align="center">

# SilkXotic — kernel for `sweet`

**exotic tuning, silk finish** · *“BruthXotic was brutal — this is silk.”*

A smooth-tuned **crDroid** kernel for the Xiaomi Redmi Note 10 Pro (`sweet`, SM7150).
The refined sibling of **BruthXotic / Tobrut Exotic** — the genuinely useful Exotic tuning,
grafted onto crDroid's own kernel with **zero bloat** and **nothing else disturbed**.

</div>

## What this is
This is a **private fork** of [`crdroidandroid/android_kernel_xiaomi_sm6150`](https://github.com/crdroidandroid/android_kernel_xiaomi_sm6150)
(branch `16.0`). It is **not** a GitHub network-fork (those can't be private) — upstream is wired in as the
`upstream` remote so crDroid changes can be pulled in (see `silkxotic/sync-upstream.sh`).

Base: a **re-rooted, tree-identical snapshot** of crDroid `16.0` at upstream commit `731658b235df` (the tree
that builds crDroid 12.11's stock `4.14.357-perf` kernel). Re-rooted (parentless) so this private repo is a
small, self-contained single-snapshot. Because the base is a fresh root, the **first** upstream sync uses
`--allow-unrelated-histories` (handled by `silkxotic/sync-upstream.sh`); after that, syncs are normal.

## What's changed vs stock (the entire diff)
Six config knobs, verified to exist in this tree, added via `arch/arm64/configs/vendor/silkxotic-opts.config`:

| Knob | Effect |
|---|---|
| `CONFIG_CPU_BOOST` | QTI input/CPU boost — touch-to-render latency |
| `CONFIG_SCHED_CORE_CTL` | smart online/offline of the gold cluster under load |
| `CONFIG_MSM_PERFORMANCE` | perfd cpufreq min/max hints |
| `CONFIG_SCHED_AUTOGROUP` | favors the foreground app |
| `CONFIG_BALANCE_ANON_FILE_RECLAIM` | reclaim balancing |
| `CONFIG_SLUB_CPU_PARTIAL` | allocator throughput |

Everything else is **stock crDroid**: full LTO kept on, KSU + SUSFS intact, sweet drivers, WireGuard, EROFS.
Built from crDroid's own tree (overlay-dtb model, dtbo untouched) → it **can't** reproduce the dtbo/DT
bootloop that the standalone BruthXotic prebuilt hit on a crDroid base.

`silkxotic-brand.config` sets `uname` to `4.14.357-silkxotic`. `buildhost-lowram.config` switches full-LTO →
ThinLTO so the link fits a low-RAM build host (LTO stays on; runtime ~equivalent).

## Build
```bash
# needs: AOSP clang-r563880c, bc, make, zip, python3
TC_DIR=/path/to/clang-r563880c JOBS=6 ./silkxotic/build-silkxotic.sh
# -> out/arch/arm64/boot/Image.gz   (then package: keep crDroid dtb/dtbo, no dtbo.img in the zip)
```

## Benchmarking (stock vs SilkXotic)
A reproducible A/B harness lives in [`silkxotic/benchmark/`](silkxotic/benchmark/) — real metrics
(frame jank, app-launch latency, CPU microbench), thermal-controlled, multi-iteration, with a noise-aware
comparison so the numbers aren't bullshit. See `silkxotic/benchmark/README.md`.

## Credits
- **Tuning DNA:** BruthXotic / *Tobrut Exotic* — **Morat Engine**, by **@MasMasBertelur**.
- **Base / upstream:** crDroid (`android_kernel_xiaomi_sm6150`, `16.0`).
- **Built & maintained by:** **nawka12** (kayfahaarukku).

> Full brand identity, palette, and logo: [`silkxotic/branding/BRANDING.md`](silkxotic/branding/BRANDING.md).
