# silkxotic-tunables — KSU module

Re-asserts kernel tunables that crDroid's **userspace** disables at boot. The kernel compiling a
feature in is not enough on this device — this is the third confirmed instance of the pattern,
after CPU_BOOST being dormant and the gaming thermal caps coming from `mi_thermald` rather than
the kernel's own trips.

## What it currently fixes

**The hung-task detector was inert in every build up to and including v1.2.0.**

`/proc/config.gz` reports `CONFIG_DETECT_HUNG_TASK=y` and `CONFIG_DEFAULT_HUNG_TASK_TIMEOUT=120`,
but the live sysctl reads `0`, because AOSP's `/system/etc/init/hw/init.rc:326` — inside the
`on init` block — does `write /proc/sys/kernel/hung_task_timeout_secs 0`. khungtaskd therefore
never scans, and the "self-documenting freeze" feature shipped in v1.2.0 could never have fired.

`on init` runs long before `post-fs-data`, so writing from this module sticks. Verified live
2026-09-04 across a reboot: 120 / 65535 / 0, with `[khungtaskd]` alive as pid 85.

It also raises `hung_task_warnings` from its default of **10** — after ten reports the detector
goes silent, which is useless for an overnight freeze.

Log-only by design: `hung_task_panic` is pinned to 0, so a wedged task prints its stack to dmesg →
klogd → persistent logcat (`/data/misc/logd/logcat*`) instead of panicking the phone. That is what
makes the next freeze self-documenting, per `FREEZE-HANDOFF.md`.

## Install

```bash
adb push -r silkxotic-tunables /data/local/tmp/
adb shell su -W -c "cp -r /data/local/tmp/silkxotic-tunables /data/adb/modules/ && chmod 0755 /data/adb/modules/silkxotic-tunables/post-fs-data.sh"
adb reboot
```

## Verify (never trust the config — read the runtime value)

```bash
adb shell su -W -c "cat /proc/sys/kernel/hung_task_timeout_secs"   # must be 120, not 0
adb shell su -W -c "cat /proc/sys/kernel/hung_task_warnings"       # must be 65535
adb shell su -W -c "cat /proc/sys/kernel/hung_task_panic"          # must be 0 (log-only)
```

## drafts/

`drafts/memwatch.sh` — a one-sample-per-minute reclaim logger, written to catch the memory pressure
that only appears after hours of uptime and cannot be reproduced on demand (a fresh boot running the
same game shows 910 MB available and *zero* direct reclaim; ten hours later the same phone shows
442 MB and 1.99 GB swapped).

It is deliberately **not** named `service.sh`. KSU auto-runs `service.sh` only, so nothing in
`drafts/` executes until you rename it — the logger is smoke-tested but not validated as a
long-running boot service.

The column that decides everything is `dscan`/`dsteal`/`astall` (direct reclaim + allocstall).
Direct reclaim runs in the *allocating* thread's context, so it is what actually stalls a frame;
kswapd reclaim is background and does not. Measured 2026-09-05 under real 10 h-uptime pressure,
these were **0** while kswapd still reclaimed ~3000 pages/s — so at that pressure level reclaim was
happening and stalling nobody, and the 850–1850 ms frame stalls seen earlier remain unexplained.
