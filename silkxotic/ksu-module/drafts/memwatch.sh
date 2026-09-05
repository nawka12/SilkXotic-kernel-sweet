#!/system/bin/sh
# SilkXotic memwatch -- low-rate reclaim logger.
#
# WHY: the memory thrash that matters on this device (kswapd burning 30-67% of a gold core beside
# UnityMain, 850-1850 ms frame stalls) only appears after HOURS of uptime with background apps
# accumulated. It cannot be reproduced on demand: measured 2026-09-04, a fresh boot with the same
# game running showed MemAvailable 910 MB, zram 722 MB, and *zero* direct reclaim, versus 515 MB /
# 1.97 GB / kswapd at 30-67% after a long uptime. Tuning against the wrong state is guessing.
#
# So: one sample per minute, deltas per interval, until the pressure comes back on its own.
#
# THE FIELD THAT DECIDES EVERYTHING is dscan/dsteal/astall (direct reclaim + allocstall). Direct
# reclaim runs in the *allocating* thread's context, so it is what actually stalls a frame; kswapd
# reclaim is background and does not. On a fresh boot these are 0 while kswapd still reclaims
# ~1200 pages/s, i.e. reclaim was happening and hurting nobody. If a freeze or a stall window shows
# dscan/astall > 0, the stall is memory; if they stay 0, look elsewhere.
#
# STATUS 2026-09-05: smoke-tested live for 20 s with shortened intervals -- header and all 14
# columns populate correctly, and a sample during the run caught real direct reclaim
# (dscan=902 dsteal=538 astall=5), confirming the decisive field registers when it fires.
# NOT yet validated as a boot service over a long run: unproven are log rotation at the 4 MB
# threshold and behaviour across a full day. This is why it lives in drafts/ and is NOT named
# service.sh -- KSU only auto-runs service.sh, so nothing here executes until you rename it.
#
# To promote: cp drafts/memwatch.sh silkxotic-tunables/service.sh && chmod 0755, reinstall, reboot.
#
# Disable: touch /data/adb/modules/silkxotic-tunables/disable_memwatch  (or remove the module)
LOG=/data/adb/silkxotic-memwatch.log
FLAG=/data/adb/modules/silkxotic-tunables/disable_memwatch
[ -f "$FLAG" ] && exit 0
sleep 120                                     # let boot settle before first sample

v(){ grep -w "^$1" /proc/vmstat | awk '{print $2}'; }
# kswapd0's pid is not stable across boots -- resolve it once, at start.
# `ps` renders kernel threads as "[kswapd0]" (brackets), so an exact-name match silently
# fails and every kswapd_ticks column comes out 0. Scan /proc/*/comm instead -- definitive.
KPID=$(grep -l '^kswapd0$' /proc/[0-9]*/comm 2>/dev/null | head -1 | sed 's|/proc/||; s|/comm||')
ktime(){ [ -n "$KPID" ] && awk '{print $14+$15}' /proc/$KPID/stat 2>/dev/null || echo 0; }

pd=$(v pgscan_direct); ps_=$(v pgsteal_direct); pk=$(v pgscan_kswapd)
si=$(v pswpin); so=$(v pswpout); wr=$(v workingset_refault)
an=$(v allocstall_normal); am=$(v allocstall_movable); kt=$(ktime)

echo "# ts avail_mb swap_mb dscan dsteal kscan swpin swpout refault astall kswapd_ticks psi_some60 psi_full60 top_rss_mb top_proc" >> "$LOG"
while true; do
  sleep 60
  [ -f "$FLAG" ] && exit 0
  # rotate at ~4 MB
  SZ=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
  [ "$SZ" -gt 4194304 ] && mv "$LOG" "$LOG.1" && : > "$LOG"

  npd=$(v pgscan_direct); nps=$(v pgsteal_direct); npk=$(v pgscan_kswapd)
  nsi=$(v pswpin); nso=$(v pswpout); nwr=$(v workingset_refault)
  nan=$(v allocstall_normal); nam=$(v allocstall_movable); nkt=$(ktime)

  AV=$(( $(grep -w ^MemAvailable /proc/meminfo | awk '{print $2}') / 1024 ))
  SW=$(( ($(grep -w ^SwapTotal /proc/meminfo | awk '{print $2}') - $(grep -w ^SwapFree /proc/meminfo | awk '{print $2}')) / 1024 ))
  PS6=$(awk '/^some/{print $3}' /proc/pressure/memory | cut -d= -f2)
  PF6=$(awk '/^full/{print $3}' /proc/pressure/memory | cut -d= -f2)
  set -- $(ps -A -o RSS,NAME --sort=-RSS 2>/dev/null | sed -n 2p)
  TR=$(( ${1:-0} / 1024 )); TN=${2:-none}

  echo "$(date +%H:%M:%S) $AV $SW $((npd-pd)) $((nps-ps_)) $((npk-pk)) $((nsi-si)) $((nso-so)) $((nwr-wr)) $(( (nan-an)+(nam-am) )) $((nkt-kt)) $PS6 $PF6 $TR $TN" >> "$LOG"

  pd=$npd; ps_=$nps; pk=$npk; si=$nsi; so=$nso; wr=$nwr; an=$nan; am=$nam; kt=$nkt
done
