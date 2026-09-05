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
