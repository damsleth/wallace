# ANS2 IOQ-size read-only candidate — ticket 6000

Prepared at CJ's request following the August 19–September 20 IRC review.
Hardware baseline is unchanged since August 19. No hardware result is claimed;
CJ will signal when the M4 is waiting for the payload.

## Scope and rationale

`patches/t6040-nvme-ans2-ioq-size.patch` ports the queue-size contract from
Yuka's ANS2 commit 42839287f85c8c36b63579371af533fcd1b8c970 onto Linux
4f2429104009e3964ddcc326d8490ac25bfb1a5c. On `need_ioq_register` hardware,
0x1210 is a zero-based SQ/CQ size, not the older pending-command limit.
Program 0x003f003f after the existing CQ/SQ base registrations; preserve the
older variant behavior, separate NVMMU base and all firmware compatibility gates.
No threaded IRQ, queue-depth, WFxT, SMP, firmware, or MMIO-base experiment is mixed in.

The known force-clean ANS boot patch remains. The modern crash-log decoder was
reviewed but excluded: its local checks do not correct the legacy outer
parser's bounds checks. Its existing ticket 201 remains independent.

The diagnostic profile includes the mandatory PCIe/SMC/HID kernel markers,
16 KiB pages, NVMe/SART/RTKit and watchdog. DT disables unrelated SPMI, SMC,
USB and PCIe endpoints. The DT is the existing ADT-derived NVMe-only fixture,
not the daily SD-root DT. This is a focused hypothesis test, not a claim of
zero-other-delta against an old daily artifact.

## Build record

Artifacts: `/Users/damsleth/code/linux-build-out/nvme-ioq-20260920/`.
Payload: `payload/`; machine-readable `manifest.json` pins the payload and host boot code.
The successful A/E builds and the final initramfs pair are byte-identical.

The existing container overlay had only 781 MiB free. A 24 GiB case-sensitive
APFS sparse image provides separate build storage without deleting prior work.
The initial shallow local clone ignored `--shared`; it was stopped before
building. Fresh repositories use source-object alternates to `/src/.git/objects`
with the source shallow boundary copied. No compiled objects are shared.

Build A: `build-volume/clean-a`, log `clean-a.log`, stage `stage/`.
Build B: fresh `clean-b`; APT refresh first failed on a future-dated repository
release, so verified installed dependencies were reused. Compilation then
failed with shared-filesystem `Too many open files`. It does not count as a
successful reproducibility build. The idle build VM was restarted to clear
its filesystem state and correct its clock. Fresh build C also failed with
the same shared-filesystem error. The VM disk was grown from 60 to 80 GiB;
the first native checkout D ran out of space because the existing root
partition had not auto-grown. After growing the build VM partition/XFS, fresh
verification build E uses native storage at `/build/nvme-ioq-clean-e`.
Canonical and relocated build scripts are retained in each staging directory.

The test executables/archives produced during review are distinctly named;
only `*-final-*` and `payload/` are candidates. No `$OUT/Image` or enrolled
object was replaced.

## Read test

The initramfs mounts only proc, sysfs, devtmpfs and RAM tmpfs. It loads the
Norwegian keymap before any shell, runs the existing 30 s / 10 s watchdog keeper,
checks the single APPLE namespace on `apple-nvme`, sets the namespace and its
partitions block-read-only, and invokes the static AArch64 tester.

The tester opens `/dev/nvme0n1` with `O_RDONLY|O_DIRECT`, verifies block-read-only,
and performs four passes over the first 64 MiB in 16 KiB synchronous reads.
Pass 1 retains its reference in RAM; passes 2–4 compare every byte. This makes
16,384 requests and at least 256 complete 64-entry CQ cycles. It prints no disk
data. Kernel-log fault/timeout detection runs between reads. There are no
block-device filesystem mounts, disk-write calls, retries or automatic reboots in the test.
A 240 s alarm bounds userspace only; a kernel-blocked read can outlive the signal.
The operator must enforce the same stop/recovery deadline on the host.

Tester PASS alone is insufficient. The host checker requires one complete test,
≥16,384 completed block reads and 524,288 sectors, unchanged write/discard/flush
counters, no in-flight I/O, and no recognized fault. Preserve and inspect the
whole kernel transcript. A clean pass validates only this bounded read workload;
it does not establish write safety, durability, cold-boot reliability or a daily
NVMe root.

## Run gate and recovery

Only after CJ reports the M4 ready: approve/ready the exact rig ticket, acquire
Astra's lease, establish the DebugUSB link with the existing sanctioned script,
verify the proxy is waiting, and run the pinned launcher once. Cable uses the
left-back DFU/DebugUSB port. Do not substitute a daily DT or initramfs.

The launcher defaults to verification only. `--run` checks ticket/hash state,
uses the existing lease-enforced boot script, disables the second chainload
attempt, and gives chainload/boot/Linux logs a unique directory. Stop on hash
mismatch, absent clean Linux/init start, timeout, ANS assert/crash, SError,
DART fault, data mismatch or storage activity outside this scope. Never retry
the read test in a failed boot. Preserve/hash the complete log before recovery.
Recover through the sanctioned DebugUSB reboot/proxy path; release healthy only
at quiescent `Running proxy`, otherwise release wedged. No enrollment or writes.

## Final offline validation (2026-09-22)

Successful clean builds A and E match byte-for-byte for Image, System.map,
config and the NVMe DTB. The two final initramfs archives also match.
All image-preflight checks pass, including Norwegian keymap, mandatory driver
markers, console ordering, single CPU and explicit tethered-proxy scope.
The verification-only launcher passes without accessing the target.

| Payload member | SHA-256 |
|---|---|
| Image | `6eef9eef130d805d71e2800f63c58813979041ee7589eb5d90116340bcd3bb7d` |
| DTB | `a96d04a7c37355ed13ac6e4ac90ec319ecc3e755d584ea2b414a7ad80498845b` |
| Initramfs | `38a7d90ad8dd58e703eec56437fff486f842b95ecd20fe2605b1658d9cafe707` |
| System.map | `fd662fe932025bb153e7419f679f14b709cb8ccf19be13ecc3284f234bdc385e` |
| Config | `02f1f1343c03878ef1de0d29c3c7a7b00be9abc3c470f13bb3f9e9561ad0ed6f` |
| m1n1 | `7de07c714ebe8b26a408ab0a4719d10d2d208eb120eaac7d3aea03f0e36daf2a` |
| Matching raw ELF | `5bee616c39fb745393cc4d961fe148189b1c084ef722b51d25c07941cc2a396f` |

Final manifest SHA-256:
`d9ae6072eafb1791aedb270289c87f155a7e9d104fe1c13c553c6d56662c18c0`.
The manifest pins 241 files, including host launcher/preflight/guard/checker,
proxyclient Python sources and the independent build outputs. A later change
requires a new manifest and review, not a hash-check bypass.

Verification only:

```sh
python3 scripts/t6040-run-nvme-ioq.py \
  /Users/damsleth/code/linux-build-out/nvme-ioq-20260920/manifest.json
```

After CJ's ready signal, ticket 6001 approval/readiness and Astra's lease,
add `--run` to that exact invocation. Do not run it now. A result is evaluated
with `scripts/t6040-check-nvme-ioq-transcript.py <unique-console-log>` and a full
manual transcript review. Hash and retain chainload, upload and console logs.

Offline checks also covered C compilation with `-Wall -Wextra -Werror`, static
AArch64 executable identity, script syntax, rejected invalid preflight mode
combinations, and synthetic transcript cases (success, ANS crash, timeout,
DART fault, write-counter change and incomplete boot). None is a hardware test.

Independent reviewer `/root/nvme_review` gave final **PASS** after checking all
241 pinned files and the A/E byte comparisons. Review is recorded in
`2026-09-21-nvme-ans2-ioq-candidate/independent-review.json`. Ticket 6000 is
complete; ticket 6001 remains proposed and non-runnable until CJ's ready signal.
