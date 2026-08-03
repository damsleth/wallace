#!/bin/sh
# Ticket 205: minimal copy-on-write corruption reproducer for t6040 (Apple M4 Pro).
#
# No toolchain required -- pure busybox. Fork N children that each write to a
# large inherited heap, which forces do_wp_page/copy_page for every page.
#
# RESULTS (SD-root shell, kernel 7.1.3, idle=nop):
#   maxcpus=1 -> 0 kernel traces, loop completes            (clean, repeated)
#   maxcpus=2 -> kernel-mode page fault within ~40 s:
#                do_page_fault -> do_bad_area -> die_kernel_fault
#                -> arm64_force_sig_fault -> make_task_dead
#   maxcpus>=3 -> the victim is often PID 1 => "Attempted to kill init" panic
#
# The underlying fault, captured with the boot reproducer:
#   pc copy_page+0x48/0xc4 , lr copy_highpage+0x70/0x21c , via do_wp_page
#   x0/x1 both kernel linear-map addresses
KB=${KB:-512}
N=${N:-300}
X=$(dd if=/dev/zero bs=1024 count="$KB" 2>/dev/null | tr '\000' 'a')
echo "cow-repro: heap=${#X} forks=$N"
i=0
while [ "$i" -lt "$N" ]; do
    ( Y="${X}b"; echo "${#Y}" > /dev/null ) &
    i=$((i + 1))
done
wait
echo "cow-repro: COMPLETED without the parent dying"
