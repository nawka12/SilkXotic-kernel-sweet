#!/system/bin/sh
# Late re-assert of hung_task_panic.
#
# post-fs-data.sh sets it, and then loses it. /system/etc/init/llkd.rc clobbers it
# through a property-trigger chain that runs AFTER post-fs-data:
#
#   on property:ro.debuggable=*        -> setprop khungtask.enable ${ro.khungtask.enable:-0}
#   on property:khungtask.enable=0     -> setprop khungtask.enable false
#   on property:khungtask.enable=false -> write /proc/sys/kernel/hung_task_panic 0
#
# Verified 2026-09-07 across a reboot: timeout(120), warnings(65535) and
# panic_on_rcu_stall(1) all survived from post-fs-data, while hung_task_panic alone
# came back 0 -- it is the only one of the four that appears in that chain.
#
# This is the fourth instance of the device's recurring pattern: the kernel offers the
# capability, crDroid's userspace switches it off. Verify the runtime value, never the
# config, and never assume an early write wins.
until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done
sleep 5
echo 1     > /proc/sys/kernel/hung_task_panic
echo 120   > /proc/sys/kernel/hung_task_timeout_secs
echo 65535 > /proc/sys/kernel/hung_task_warnings
echo 1     > /proc/sys/kernel/panic_on_rcu_stall

# softlockup_panic: only exists once CONFIG_SOFTLOCKUP_DETECTOR=y is flashed (added to
# silkxotic-hungtask.config 2026-09-07). Guarded so this module stays correct on older
# kernels. A soft lockup is a CPU spinning in kernel mode >20 s (watchdog_thresh) with
# the task still in state R -- invisible to khungtaskd, which is why freeze #6 could sit
# wedged for 13 min with hung_task_panic=1 armed and never fire. Panic so the report
# reaches pstore and the phone resets itself, same reasoning as hung_task_panic.
[ -e /proc/sys/kernel/softlockup_panic ] && echo 1 > /proc/sys/kernel/softlockup_panic

# --- independent /dev/kmsg capture (freeze #5/#6 discriminator) ---
#
# Both freezes showed kernel lines vanishing from logcat while userspace lines kept
# flowing. That was read as "the kernel stopped printing", but logcat's kernel buffer
# is fed by logd's own /dev/kmsg reader thread, so a wedge in THAT thread produces an
# identical symptom with a completely different root cause. Nothing we have can tell
# the two apart.
#
# This reader is independent of logd. On the next freeze:
#   - kmsg.log also stops  -> the kernel really did stop printing
#   - kmsg.log keeps going -> logd's reader wedged; the kernel was fine, look at logd
#
# Self-bounding: head -c exits after 64 MB, the loop rotates and reopens. Opening
# /dev/kmsg restarts at the oldest retained record, so expect ~1 MB of overlap per
# rotation -- harmless. Records carry <prio>,<seq>,<monotonic_us>, so they align to
# the freeze onset directly.
KLOG=/data/local/tmp/kmsg.log
(
  while true; do
    mv -f "$KLOG" "$KLOG.1" 2>/dev/null
    head -c 67108864 /dev/kmsg > "$KLOG" 2>/dev/null
    sleep 1
  done
) &
