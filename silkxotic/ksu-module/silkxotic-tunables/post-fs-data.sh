#!/system/bin/sh
# SilkXotic tunables -- re-assert what crDroid's userspace turns off at boot.
#
# hung-task detector: the kernel compiles CONFIG_DETECT_HUNG_TASK=y with
# CONFIG_DEFAULT_HUNG_TASK_TIMEOUT=120, but AOSP's /system/etc/init/hw/init.rc:326
# (inside "on init") does `write /proc/sys/kernel/hung_task_timeout_secs 0`, so
# khungtaskd never scans. Verified live 2026-09-04: sysctl read 0 on a kernel whose
# /proc/config.gz said 120. Every SilkXotic build up to v1.2.0 shipped it inert.
#
# "on init" runs long before post-fs-data, so writing here sticks.
#
# hung_task_warnings defaults to 10, i.e. it goes silent after ten reports -- useless
# for an overnight freeze, so raise it.
echo 120   > /proc/sys/kernel/hung_task_timeout_secs
echo 65535 > /proc/sys/kernel/hung_task_warnings

# PANIC ON HANG (changed from log-only 2026-09-07, after freeze #5).
#
# The old design was log-only: hung_task_panic=0, on the theory that a wedged task
# would print its stack to dmesg -> klogd -> persistent logcat. Freeze #5 disproved
# that. Kernel log output ceased at 09:41:39 and stayed dead for the whole 10.5-minute
# freeze (steady ~200 lines/min before, exactly 0 after, while userspace logging kept
# writing ~70 lines/min -- so logd was alive and the kernel side went silent). Any
# khungtaskd report would have gone into that same dead channel. Log-only
# instrumentation cannot capture this freeze class, so it captured nothing.
#
# Panicking instead routes the report through a path that does not involve logd:
# printk -> pstore console (a DRAM ring written directly from printk) and then
# CONFIG_QCOM_FORCE_WDOG_BITE_ON_PANIC=y resets the SoC while DRAM stays powered, so
# the record survives into /sys/fs/pstore/console-ramoops-0. A user long-press does
# NOT preserve it -- which is why freeze #5's newest console record is still the one
# from the Sep 4 clean reboot. A kernel-initiated reset is the only way we get a
# kernel-side post-mortem off this device.
#
# It also ends the freeze: today the phone sits dead until it is long-pressed.
# panic=5 is already set, so it reboots itself 5s after the panic.
#
# Trade-off: any single >120s D-state now reboots the phone, false positive included.
# At a 120s threshold on an idle handset that is rare, and a task wedged 120s has
# already cost more than the reboot does.
echo 1     > /proc/sys/kernel/hung_task_panic

# RCU stall -> panic as well. hung_task only sees TASK_UNINTERRUPTIBLE; it would miss a
# CPU spinning with a lock held or interrupts off, which is a live candidate for freeze
# #5 given that printk itself went quiet. CONFIG_SOFTLOCKUP_DETECTOR is NOT set on this
# kernel (verified 2026-09-07: /proc/sys/kernel/softlockup_panic does not exist), so RCU
# stall is the only lockup detector we currently have. Enabling SOFTLOCKUP_DETECTOR is a
# build-time item for the next kernel.
echo 1     > /proc/sys/kernel/panic_on_rcu_stall
