Reviewer harness (sonnet, 2026-10-25) for `scripts/t6040-init-nvme-exfat-write`
(1d67ddc). `flow-section.sh` is the script's lines from `fsck_n()` to the final
PASS line, unchanged except `nvme0n1` in `pstat` is parameterised for the loop
device. The harness uses the 5003 initramfs's own BusyBox (`61781806…`) and
`fsck.exfat` (`d56b877d…`) on a 3 GiB loop device with 4096-byte logical blocks:
(1) GPT offset logic (slot-2 entry at `2*LBS+2*128`), (2) write, (3) write again
(must refuse), (4) verify, (5) flip one byte then verify (must STOP). The
partition pins themselves are not exercised (they are real-device values); they
were checked against the 5001 transcript by hand, see the review.
Copy `run-in-podman.sh` to `$S/w_run.sh` and `flow-section.sh` to `$S/w_flow.sh`;
run as root in the podman machine with `$S/iw` = the extracted initramfs.
