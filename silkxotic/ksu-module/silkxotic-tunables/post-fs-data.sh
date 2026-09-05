#!/system/bin/sh
# SilkXotic tunables -- re-assert what crDroid's userspace turns off at boot.
#
# hung-task detector: the kernel compiles CONFIG_DETECT_HUNG_TASK=y with
# CONFIG_DEFAULT_HUNG_TASK_TIMEOUT=120, but AOSP's /system/etc/init/hw/init.rc:326
# (inside "on init") does `write /proc/sys/kernel/hung_task_timeout_secs 0`, so
# khungtaskd never scans. Verified live 2026-09-04: sysctl read 0 on a kernel whose
# /proc/config.gz said 120. Every SilkXotic build up to v1.2.0 shipped it inert.
#
# "on init" runs long before post-fs-data, so writing here sticks. Log-only by design:
# hung_task_panic stays 0 so a wedged task prints its stack to dmesg -> klogd ->
# persistent logcat (/data/misc/logd/logcat*) instead of panicking the phone.
#
# hung_task_warnings defaults to 10, i.e. it goes silent after ten reports -- useless
# for an overnight freeze, so raise it.
echo 120   > /proc/sys/kernel/hung_task_timeout_secs
echo 65535 > /proc/sys/kernel/hung_task_warnings
echo 0     > /proc/sys/kernel/hung_task_panic
