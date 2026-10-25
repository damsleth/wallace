# 5003b write-init regression (claude, 2026-10-25, offline)

This is Sonnet's 5003 loop harness (`evidence/2026-10-25-review-5003-exfat-write-test/`)
run on the revised init's flow section (`w_flow.sh`, extracted unchanged with
`nvme0n1` replaced by the loop device). It uses the 5003b initramfs `42a5e48f`
(built twice, identical), with its own BusyBox and `fsck.exfat`. p3 is a 2.8 GiB
exFAT partition on a 4 KiB-sector GPT loop.

Results (`output.txt`):
- write r2 with `nvmewc=through`: PASS.
- write r2 again: refuses (`already exists`).
- verify r2: PASS, with 0 sectors written.
- write r3, write-back: PASS. Loop devices always report `write through`, so the
  write-back path itself is only exercised on hardware.
- r3 with one byte flipped, then verify: `STOP: data mismatch`.

An earlier run in the same directory found two problems, both since fixed. The
PASS line printed `write_cache=write`, which was a script bug (`${WCNOW% *}`,
now `${WCNOW#write }`). The 1.2 GiB test partition could not hold two 1 GiB
files, which was a harness artifact; the partition is now larger.

The pins are real-device values and are not exercised here. The field-wise
boot-sector constants were checked byte for byte against the 5001 dump
(bytes 64..119) with a script.
